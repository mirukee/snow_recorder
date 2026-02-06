const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentDeleted, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { setGlobalOptions } = require("firebase-functions/v2");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

setGlobalOptions({ region: "asia-northeast3" });
admin.initializeApp();

const db = admin.firestore();

// 소스/타겟 컬렉션
const SOURCE_COLLECTION = "rankings";
const LEADERBOARD_COLLECTION = "leaderboards";
const QUEUE_COLLECTION = "leaderboard_queue";

// 배치 기본 설정
const COUNTRY_CODE = "KR";
const PAGE_SIZE = 100;
const LIMIT = 1000;
const MAX_PAGES = Math.ceil(LIMIT / PAGE_SIZE);
const MAX_WEEKLY_DISTANCE_M = 500000;
const MAX_SEASON_DISTANCE_M = 2000000;
const MAX_WEEKLY_RUNCOUNT = 300;
const MAX_SEASON_RUNCOUNT = 2000;
const MAX_SCORE = 1000;

// 리조트 키 (슬로프 데이터 기준)
const RESORT_KEYS = [
  "high1",
  "yongpyong",
  "phoenix",
  "vivaldi",
  "alpensia",
  "oakvalley",
  "gangchon",
  "wellihilli",
  "muju",
  "o2",
  "konjiam",
  "jisan",
  "edenvalley"
];

const SEASON_RUNCOUNT_FIELDS = ["season_runCount", ...RESORT_KEYS.map((key) => `season_runCount_${key}`)];
const SEASON_DISTANCE_FIELDS = ["season_distance_m", ...RESORT_KEYS.map((key) => `season_distance_m_${key}`)];
const WEEKLY_RUNCOUNT_FIELDS = ["weekly_runCount", ...RESORT_KEYS.map((key) => `weekly_runCount_${key}`)];
const WEEKLY_DISTANCE_FIELDS = ["weekly_distance_m", ...RESORT_KEYS.map((key) => `weekly_distance_m_${key}`)];

// 메트릭 정의
const METRICS = ["runCount", "distance_m", "edge", "flow"];
const CYCLES = ["season", "weekly"];

exports.buildLeaderboardsOnRankingChange = onDocumentWritten(`${SOURCE_COLLECTION}/{userId}`, async (event) => {
  const after = event.data?.after;
  if (!after || !after.exists) {
    return;
  }

  const afterData = after.data() || {};
  const before = event.data?.before;
  const beforeData = before && before.exists ? before.data() : null;

  const isCreate = !beforeData;
  const countryChanged = !!beforeData && beforeData.country !== afterData.country;
  const seasonIdChanged = !!beforeData && beforeData.seasonId && beforeData.seasonId !== afterData.seasonId;
  const weekIdChanged = !!beforeData && beforeData.weekly_weekId && beforeData.weekly_weekId !== afterData.weekly_weekId;

  const seasonMetricsChanged = getChangedMetrics(beforeData, afterData, {
    runCount: SEASON_RUNCOUNT_FIELDS,
    distance_m: SEASON_DISTANCE_FIELDS,
    edge: ["season_edge"],
    flow: ["season_flow"]
  });
  const weeklyMetricsChanged = getChangedMetrics(beforeData, afterData, {
    runCount: WEEKLY_RUNCOUNT_FIELDS,
    distance_m: WEEKLY_DISTANCE_FIELDS,
    edge: ["weekly_edge"],
    flow: ["weekly_flow"]
  });

  const seasonMetricsToBuild = isCreate || seasonIdChanged || countryChanged
    ? METRICS
    : seasonMetricsChanged;
  const weeklyMetricsToBuild = isCreate || weekIdChanged || countryChanged
    ? METRICS
    : weeklyMetricsChanged;

  const seasonIdsToBuild = new Set();
  if (seasonMetricsToBuild.length > 0) {
    if (afterData.seasonId) {
      seasonIdsToBuild.add(afterData.seasonId);
    }
    if ((seasonIdChanged || countryChanged) && beforeData?.seasonId) {
      seasonIdsToBuild.add(beforeData.seasonId);
    }
  }

  const weekIdsToBuild = new Set();
  if (weeklyMetricsToBuild.length > 0) {
    if (afterData.weekly_weekId) {
      weekIdsToBuild.add(afterData.weekly_weekId);
    }
    if ((weekIdChanged || countryChanged) && beforeData?.weekly_weekId) {
      weekIdsToBuild.add(beforeData.weekly_weekId);
    }
  }

  if (seasonIdsToBuild.size === 0 && weekIdsToBuild.size === 0) {
    return;
  }

  const enqueueTasks = [];

  for (const seasonId of seasonIdsToBuild) {
    enqueueTasks.push(enqueueLeaderboardBuild("season", seasonId, seasonMetricsToBuild));
  }

  for (const weekId of weekIdsToBuild) {
    enqueueTasks.push(enqueueLeaderboardBuild("weekly", weekId, weeklyMetricsToBuild));
  }

  await Promise.all(enqueueTasks);
});

exports.processLeaderboardQueue = onSchedule("*/10 * * * *", async () => {
  const queueSnapshot = await db.collection(QUEUE_COLLECTION).orderBy("updatedAt").limit(20).get();
  if (queueSnapshot.empty) {
    return;
  }

  for (const doc of queueSnapshot.docs) {
    const locked = await tryLockQueueDoc(doc.ref);
    if (!locked) {
      continue;
    }
    try {
      await processQueueDoc(doc.ref);
      await doc.ref.delete();
    } catch (error) {
      await doc.ref.set({
        processing: false,
        lastError: error?.message || "unknown_error",
        errorAt: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });
      logger.error("리더보드 큐 처리 실패", { error });
    }
  }
});

exports.removeFromLeaderboardsOnOptOut = onDocumentDeleted(`${SOURCE_COLLECTION}/{userId}`, async (event) => {
  const userId = event.params.userId;
  if (!userId) {
    logger.warn("opt-out 삭제 이벤트 누락", { eventId: event.id });
    return;
  }

  const deletedData = event.data?.data() || null;
  if (!deletedData) {
    logger.warn("opt-out 삭제 데이터 누락", { userId, eventId: event.id });
    return;
  }

  const seasonId = deletedData.seasonId;
  const weekId = deletedData.weekly_weekId;
  const tasks = [];

  if (seasonId) {
    for (const board of buildBoardsForMetrics("season", METRICS)) {
      tasks.push({ board, filters: { seasonId } });
    }
  }

  if (weekId) {
    for (const board of buildBoardsForMetrics("weekly", METRICS)) {
      tasks.push({ board, filters: { weekId } });
    }
  }

  for (const task of tasks) {
    try {
      const boardId = makeBoardId(task.board, task.filters);
      await removeUserFromBoard(boardId, userId);
    } catch (error) {
      logger.error("opt-out 리더보드 제거 실패", { userId, error });
    }
  }
});

function buildBoards() {
  return buildBoardsForMetrics();
}

async function enqueueLeaderboardBuild(cycle, id, metrics) {
  const normalizedMetrics = normalizeMetrics(metrics);
  if (normalizedMetrics.length === 0) {
    return;
  }
  const docId = cycle === "season" ? `season_${id}` : `weekly_${id}`;
  const ref = db.collection(QUEUE_COLLECTION).doc(docId);
  const update = {
    cycle,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  };
  if (cycle === "season") {
    update.seasonId = id;
  } else {
    update.weekId = id;
  }
  for (const metric of normalizedMetrics) {
    update[`metrics.${metric}`] = true;
  }
  await ref.set(update, { merge: true });
}

function normalizeMetrics(metrics) {
  if (!metrics || metrics.length === 0) {
    return [];
  }
  const filtered = metrics.filter((metric) => METRICS.includes(metric));
  return Array.from(new Set(filtered));
}

async function tryLockQueueDoc(ref) {
  try {
    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) {
        return false;
      }
      const data = snap.data() || {};
      if (data.processing === true) {
        return false;
      }
      tx.update(ref, {
        processing: true,
        processingAt: admin.firestore.FieldValue.serverTimestamp()
      });
      return true;
    });
  } catch (error) {
    logger.warn("큐 잠금 실패", { error });
    return false;
  }
}

async function processQueueDoc(ref) {
  const snapshot = await ref.get();
  if (!snapshot.exists) {
    return;
  }
  const data = snapshot.data() || {};
  const cycle = data.cycle;
  const metrics = Object.keys(data.metrics || {}).filter((metric) => METRICS.includes(metric));
  if (!cycle || metrics.length === 0) {
    return;
  }

  if (cycle === "season") {
    const seasonId = data.seasonId;
    if (!seasonId) {
      return;
    }
    for (const board of buildBoardsForMetrics("season", metrics)) {
      await buildLeaderboard(board, { seasonId });
    }
    return;
  }

  const weekId = data.weekId;
  if (!weekId) {
    return;
  }
  for (const board of buildBoardsForMetrics("weekly", metrics)) {
    await buildLeaderboard(board, { weekId });
  }
}

function buildBoardsForMetrics(targetCycle, targetMetrics) {
  const boards = [];
  const cycles = targetCycle ? [targetCycle] : CYCLES;
  const metrics = targetMetrics && targetMetrics.length > 0 ? targetMetrics : METRICS;

  for (const cycle of cycles) {
    for (const metric of metrics) {
      const scopes = metric === "edge" || metric === "flow"
        ? ["all"]
        : ["all", ...RESORT_KEYS];
      for (const scope of scopes) {
        boards.push({ cycle, metric, scope });
      }
    }
  }
  return boards;
}

function getChangedMetrics(beforeData, afterData, metricFields) {
  if (!beforeData) {
    return Object.keys(metricFields);
  }
  const changed = [];
  for (const [metric, fields] of Object.entries(metricFields)) {
    if (hasAnyFieldChanged(beforeData, afterData, fields)) {
      changed.push(metric);
    }
  }
  return changed;
}

function hasAnyFieldChanged(beforeData, afterData, fields) {
  for (const field of fields) {
    const beforeValue = beforeData ? beforeData[field] : undefined;
    const afterValue = afterData ? afterData[field] : undefined;
    if (beforeValue !== afterValue) {
      return true;
    }
  }
  return false;
}

function makeBoardId(board, filters) {
  if (board.cycle === "season") {
    return `${board.cycle}_${board.metric}_${board.scope}_${filters.seasonId}`;
  }
  return `${board.cycle}_${board.metric}_${board.scope}_${filters.weekId}`;
}

async function buildLeaderboard(board, filters) {
  const fieldName = getFieldName(board);
  const boardId = makeBoardId(board, filters);

  let query = db.collection(SOURCE_COLLECTION)
    .where("country", "==", COUNTRY_CODE);

  if (board.cycle === "season") {
    if (!filters?.seasonId) {
      return;
    }
    query = query.where("seasonId", "==", filters.seasonId);
  } else {
    if (!filters?.weekId) {
      return;
    }
    query = query.where("weekly_weekId", "==", filters.weekId);
  }

  query = query.orderBy(fieldName, "desc").limit(LIMIT);

  const snapshot = await query.get();
  const entries = [];
  let rank = 1;

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const value = typeof data[fieldName] === "number" ? data[fieldName] : 0;
    if (!isSaneValue(board, value)) {
      continue;
    }
    entries.push({
      uid: doc.id,
      rank,
      nickname: data.nickname || "Unknown",
      value
    });
    rank += 1;
  }

  await writeLeaderboard(boardId, entries);
}

function getFieldName(board) {
  const prefix = board.cycle === "season" ? "season_" : "weekly_";

  if (board.metric === "runCount") {
    if (board.scope !== "all") {
      return `${prefix}runCount_${board.scope}`;
    }
    return `${prefix}runCount`;
  }

  if (board.metric === "distance_m") {
    if (board.scope !== "all") {
      return `${prefix}distance_m_${board.scope}`;
    }
    return `${prefix}distance_m`;
  }

  if (board.metric === "edge") {
    return `${prefix}edge`;
  }

  return `${prefix}flow`;
}

function isSaneValue(board, value) {
  if (typeof value !== "number" || value <= 0) {
    return false;
  }
  if (board.metric === "edge" || board.metric === "flow") {
    return value >= 0 && value <= MAX_SCORE;
  }
  if (board.metric === "distance_m") {
    const max = board.cycle === "weekly" ? MAX_WEEKLY_DISTANCE_M : MAX_SEASON_DISTANCE_M;
    return value <= max;
  }
  if (board.metric === "runCount") {
    const max = board.cycle === "weekly" ? MAX_WEEKLY_RUNCOUNT : MAX_SEASON_RUNCOUNT;
    return value <= max;
  }
  return true;
}

async function writeLeaderboard(boardId, entries) {
  const boardRef = db.collection(LEADERBOARD_COLLECTION).doc(boardId);
  const pageCount = Math.ceil(entries.length / PAGE_SIZE);
  let previousPageCount = 0;
  const boardSnapshot = await boardRef.get();
  if (boardSnapshot.exists) {
    const data = boardSnapshot.data() || {};
    if (typeof data.pageCount === "number") {
      previousPageCount = data.pageCount;
    }
  }
  const batch = db.batch();

  for (let page = 0; page < pageCount; page += 1) {
    const start = page * PAGE_SIZE;
    const end = start + PAGE_SIZE;
    const chunk = entries.slice(start, end);
    const shardRef = boardRef.collection("shards").doc(`page_${page + 1}`);
    batch.set(shardRef, { entries: chunk }, { merge: false });
  }

  if (pageCount === 0) {
    const maxDeletePages = previousPageCount > 0 ? previousPageCount : MAX_PAGES;
    for (let page = 1; page <= maxDeletePages; page += 1) {
      const shardRef = boardRef.collection("shards").doc(`page_${page}`);
      batch.delete(shardRef);
    }
  } else if (previousPageCount > pageCount) {
    for (let page = pageCount + 1; page <= previousPageCount; page += 1) {
      const shardRef = boardRef.collection("shards").doc(`page_${page}`);
      batch.delete(shardRef);
    }
  }

  batch.set(boardRef, {
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    total: entries.length,
    pageSize: PAGE_SIZE,
    pageCount
  }, { merge: true });

  await batch.commit();
  logger.info("리더보드 갱신 완료", { boardId, total: entries.length });
}

async function removeUserFromBoard(boardId, userId) {
  const boardRef = db.collection(LEADERBOARD_COLLECTION).doc(boardId);
  const boardDoc = await boardRef.get();
  const boardData = boardDoc.exists ? (boardDoc.data() || {}) : {};
  const pageCount = typeof boardData.pageCount === "number" && boardData.pageCount > 0
    ? boardData.pageCount
    : MAX_PAGES;

  const shardRefs = [];
  for (let page = 1; page <= pageCount; page += 1) {
    shardRefs.push(boardRef.collection("shards").doc(`page_${page}`));
  }

  const shardDocs = await Promise.all(shardRefs.map((ref) => ref.get()));
  const updates = [];
  let removedCount = 0;

  shardDocs.forEach((shardDoc, index) => {
    if (!shardDoc.exists) {
      return;
    }
    const data = shardDoc.data() || {};
    const entries = Array.isArray(data.entries) ? data.entries : [];
    const filtered = entries.filter((entry) => {
      const entryId = entry.uid || entry.userId;
      return entryId !== userId;
    });
    if (filtered.length !== entries.length) {
      removedCount += (entries.length - filtered.length);
      updates.push({ ref: shardRefs[index], entries: filtered });
    }
  });

  if (updates.length === 0) {
    return;
  }

  const batch = db.batch();
  for (const update of updates) {
    batch.set(update.ref, { entries: update.entries }, { merge: false });
  }
  await batch.commit();
  logger.info("opt-out 리더보드 제거 완료", { boardId, userId, removedCount });
}

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { setGlobalOptions } = require("firebase-functions/v2");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

setGlobalOptions({ region: "asia-northeast3" });
admin.initializeApp();

const db = admin.firestore();

// 소스/타겟 컬렉션
const SOURCE_COLLECTION = "rankings";
const LEADERBOARD_COLLECTION = "leaderboards";

// 배치 기본 설정
const COUNTRY_CODE = "KR";
const SEASON_ID = "25_26";
const PAGE_SIZE = 100;
const LIMIT = 1000;
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

// 메트릭 정의
const METRICS = ["runCount", "distance_m", "edge", "flow"];
const CYCLES = ["season", "weekly"];

exports.buildLeaderboardsHourly = onSchedule("0 * * * *", async () => {
  const weekId = getISOWeekIdKST(new Date());
  const boards = buildBoards();

  for (const board of boards) {
    try {
      await buildLeaderboard(board, weekId);
    } catch (error) {
      logger.error("리더보드 배치 실패", { board, error });
    }
  }
});

function buildBoards() {
  const boards = [];
  for (const cycle of CYCLES) {
    for (const metric of METRICS) {
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

async function buildLeaderboard(board, weekId) {
  const fieldName = getFieldName(board);
  const boardId = `${board.cycle}_${board.metric}_${board.scope}`;

  let query = db.collection(SOURCE_COLLECTION)
    .where("country", "==", COUNTRY_CODE);

  if (board.cycle === "season") {
    query = query.where("seasonId", "==", SEASON_ID);
  } else {
    query = query.where("weekly_weekId", "==", weekId);
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
  const batch = db.batch();

  for (let page = 0; page < pageCount; page += 1) {
    const start = page * PAGE_SIZE;
    const end = start + PAGE_SIZE;
    const chunk = entries.slice(start, end);
    const shardRef = boardRef.collection("shards").doc(`page_${page + 1}`);
    batch.set(shardRef, { entries: chunk }, { merge: false });
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

function getISOWeekIdKST(date) {
  const kst = toKSTDate(date);
  const iso = getISOWeek(kst);
  return `${iso.year}-W${String(iso.week).padStart(2, "0")}`;
}

function toKSTDate(date) {
  const KST_OFFSET_MS = 9 * 60 * 60 * 1000;
  return new Date(date.getTime() + KST_OFFSET_MS);
}

function getISOWeek(date) {
  const utcDate = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const day = utcDate.getUTCDay() || 7;
  utcDate.setUTCDate(utcDate.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(utcDate.getUTCFullYear(), 0, 1));
  const week = Math.ceil((((utcDate - yearStart) / 86400000) + 1) / 7);
  return { year: utcDate.getUTCFullYear(), week };
}

# Leaderboard 아키텍처 (스노우 레코드)

## 목적
- **Write 비용 최소화**: 의미 있는 변화만 업로드
- **Read 비용 고정화**: 유저는 “정답지” 1개만 읽기
- **서버 계산 고정화**: 매시 1회 배치로 랭킹 산정

---

## 전체 흐름

1. **Client Upload**
   - 세션 저장 직후 업로드 판단
   - TECHNICAL: top3 평균이 바뀔 때만 업로드
   - MILEAGE: 항상 업로드

2. **Server Batch (Cloud Functions)**
   - 매시 정각에 `user_rankings` 전체에서 Top N 생성
   - 결과를 `leaderboards`에 샤딩 저장

3. **Client Read**
   - 랭킹은 `leaderboards`의 정답지만 읽음
   - 내 점수는 로컬 계산값으로 즉시 표시

---

## Firestore 데이터 구조

### 1) 유저 업로드 문서
`user_rankings/{uid}`

**공통**
- `nickname`: String
- `country`: "KR"
- `seasonId`: "25_26"
- `weekly_weekId`: "2026-W05"
- `updatedAt`: serverTimestamp

**MILEAGE (항상 업로드)**
- `season_runCount`: Int
- `season_distance_m`: Double
- `weekly_runCount`: Int
- `weekly_distance_m`: Double

**TECHNICAL (top3 평균 변경 시 업로드)**
- `season_edge`: Double
- `season_flow`: Double
- `weekly_edge`: Double
- `weekly_flow`: Double

**리조트별 MILEAGE (Meters 기준)**
- `season_runCount_{resortKey}`
- `season_distance_m_{resortKey}`
- `weekly_runCount_{resortKey}`
- `weekly_distance_m_{resortKey}`

---

### 2) 리더보드 정답지

**메타 (문서)**
`leaderboards/{boardId}`
- `updatedAt`: timestamp
- `total`: Int
- `pageSize`: Int (예: 100)
- `pageCount`: Int

**샤드**
`leaderboards/{boardId}/shards/{page}`
- `entries`: [ { uid, rank, nickname, value } ]

**boardId 규칙**
`{cycle}_{metric}_{scope}`
- cycle: `season | weekly`
- metric: `runCount | distance_m | edge | flow`
- scope: `all | {resortKey}`

예시:
- `season_distance_m_all`
- `weekly_runCount_high1`

---

## 업로드 로직 (Client)

### TECHNICAL
- 기준: **top3 평균 변경**
- 저장 위치: `UserDefaults`
- 예시 키:
  - `last_uploaded_season_edge`
  - `last_uploaded_season_flow`
  - `last_uploaded_weekly_edge`
  - `last_uploaded_weekly_flow`

### MILEAGE
- 거리/횟수는 누적이므로 **항상 업로드**

---

## 서버 배치 로직 (Cloud Functions)

### 스케줄
- 매시 정각: `"0 * * * *"`

### 처리 순서 (보드 1개 기준)
1. `rankings`(현재) 또는 `user_rankings`에서 필터 (`country`, `seasonId` or `weekly_weekId`)
2. `orderBy(metricField, desc)`
3. `limit(N)` (예: 1000)
4. 랭킹 계산 후 100개 단위로 샤딩 저장
5. `meta` 갱신

### 비용 주의
- `limit(N)` 기반이라 비용은 **보드 수 × N**으로 고정
- 리조트가 늘면 보드 수가 증가함

---

## 리조트 확장 가이드

리조트는 앞으로 추가될 예정이므로 **키 관리 규칙**을 반드시 고정한다.

---

## 단계별 적용: 1단계 (스키마/레지스트리 고정)

**목표:** 데이터 구조와 키 규칙을 먼저 고정해서 이후 확장 비용을 최소화한다.

- 컬렉션/문서 경로 확정  
  - `user_rankings/{uid}`  
  - `leaderboards/{boardId}/meta`  
  - `leaderboards/{boardId}/shards/{page}`
- `boardId` 규칙 확정  
  - `{cycle}_{metric}_{scope}`
- 리조트 레지스트리 확정  
  - 키 목록과 표시명 매핑을 문서화
- 인덱스 생성 규칙 확정  
  - 신규 리조트 추가 시 필요한 인덱스 패턴 정리

---

## 리조트 레지스트리 (Source of Truth)

리조트가 추가될 때 **가장 먼저 여기부터** 갱신한다.

| resortKey | displayName | note |
| --- | --- | --- |
| high1 | 하이원 | 기존 |
| yongpyong | 용평 | 기존 |
| phoenix | 휘닉스 | 기존 |
| vivaldi | 비발디 | 기존 |
| TBD | TBD | 신규 추가 예정 |

---

### 1) 리조트 키 규칙
- 소문자 영문 + 숫자만 사용
- 공백/특수문자 금지
- 예시: `high1`, `yongpyong`, `phoenix`, `vivaldi`

### 2) 추가 시 수정해야 할 곳
- **클라이언트**
  - 리조트 리스트 (UI 필터)
  - `resortKey` 매핑
  - 리조트 감지 로직 (좌표 기반)
- **서버 배치**
  - 생성할 `boardId` 리스트에 추가
- **Firestore 인덱스**
  - 신규 리조트 필드에 대한 인덱스 추가 필요

### 인덱스 생성 규칙 (리조트 추가 시)

각 리조트 키마다 아래 4개 인덱스 필요:
- `season_runCount_{resortKey}`
- `season_distance_m_{resortKey}`
- `weekly_runCount_{resortKey}`
- `weekly_distance_m_{resortKey}`

---

## 구현 메모 (현재 단계)

- 서버 배치 소스 컬렉션은 **현재 `rankings`** 기준
- 추후 `user_rankings`로 분리 시, **클라이언트 업로드 컬렉션 이동 후** 서버 배치의 소스만 변경

### 3) 향후 확장 옵션
- 리조트 수가 많아지면:
  - 보드 생성 범위를 “활성 리조트만”으로 제한
  - 리조트별 보드를 별도 컬렉션으로 분리
  - 또는 리조트별 문서 샤딩 전략 고도화

---

## UI 표시 정책
- 정답지는 서버 기준
- **내 점수는 로컬 계산값으로 즉시 표시**
- “마지막 갱신 시각” 표기 권장 (정확도 지연 안내)

---

## 리스크/주의
- **정답지 단일 문서 1MB 제한**: 반드시 샤딩
- **데이터 신뢰성**: 클라이언트 업로드 값은 조작 가능
  - 이상치 필터(속도/거리/시간) 고려
- **리조트 인덱스 폭증**: 리조트 확장 시 비용 증가

---

## 비정상 값 방어 (A+B 적용)

### A) 클라이언트 업로드 필터
- 세션 업로드 전 최소 sanity 체크
- 예시 기준 (현재 적용값):
  - 평균 속도 > 120km/h → 업로드 스킵
  - 최고 속도 > 180km/h → 업로드 스킵
  - 거리 > 200km (단일 세션) → 업로드 스킵
  - 런 횟수 > 200 → 업로드 스킵
  - 점수 범위(0~1000) 밖 → 업로드 스킵

### B) 서버 배치 필터
- 리더보드 생성 시 이상치 제거
- 기준 (현재 적용값):
  - weekly distance > 500km → 제외
  - season distance > 2000km → 제외
  - weekly runCount > 300 → 제외
  - season runCount > 2000 → 제외
  - edge/flow > 1000 → 제외

---
description: 측정 엔진 로직 및 슬로프 인식 시스템 설명 (코드 기준)
---

# Snow Recorder 측정 엔진 (코드 기준)

## 상태 모델

- **RIDING**: 활강 중 (측정 활성)
- **ON_LIFT**: 리프트 탑승 중
- **RESTING**: 대기/휴식 (슬로프 외부 포함)

> 참고: 과거의 **PAUSED** 상태는 제거되었고, UI/세션 일시정지는 `RecordManager`에서 별도로 처리됩니다.

### 서브 상태 개념
- **Pending Riding**: RESTING에서 RIDING 확정 전 5초 프리롤 구간
- **Pending Rest**: RIDING에서 RESTING 확정 전 보류 구간 (UI 표기는 RESTING)

## 상태 전환 로직 (핵심 조건)

### RESTING → RIDING (프리롤 확정)
- 조건: **속도 > 5km/h + 하강 감지**
- 5초 동안 `avgSpeed ≥ 5km/h`, `distance ≥ 5m`, `drop ≥ 3m` 만족 시 **RIDING 확정**

### RESTING → ON_LIFT
- 최근 10초 기준 **상승 ≥ 5m** 감지 시 리프트로 전환

### RIDING → ON_LIFT
- 최근 10초 기준 **상승 ≥ 7m** 감지 시 리프트로 전환
- 전환 시점에 **Pending Rest**가 있었다면 해당 시점으로 런 종료 처리

### RIDING → RESTING (Pending Rest)
- **최근 20초 최대속도 ≤ 6km/h** + **최근 순하강 ≤ 10m** → Pending Rest 진입
- Pending Rest 중:
  - **재개 조건:** `speed ≥ 10km/h` + `순하강 ≥ 3m` 또는 하강 트렌드  
  - **타임아웃:** 180초 지속 시 RESTING 확정

### ON_LIFT → RIDING
아래 조건을 모두 만족하면 활강으로 복귀:
- **속도 > 5km/h**
- 최근 10초 **하강 ≥ 5m** (Strong Descent)
- 리프트 직선 이동 패턴이 **아님**
  - 직진성 비율 < 0.95 **또는** 방향 분산 > 5°

### ON_LIFT → RESTING
- `speed < 1.5km/h` + 상승/하강 트렌드 없음 상태가 **60초 이상** 지속

### 고도 신호 선택
상태 전환의 상승/하강 판단은 **바리오(기압계)**가 활성화되면 바리오 데이터를, 그렇지 않으면 **GPS 스무딩 고도**를 사용합니다.

## 슬로프 인식

- **폴리곤 매칭**: `SlopeDatabase.findSlope(at:)` 내부 Ray Casting
- **상태 판정에는 사용하지 않고 태깅/표시용으로만 사용**
- **체크 주기:** 50m 이상 이동 시에만 수행
- **Start/Finish 감지:** 반경 50m
  - Start는 RIDING/RESTING 모두 허용
  - Finish는 RIDING 상태에서만 허용
- **ON_LIFT 부스트:** 하차 감지 직후 정밀도 상승 구간에서 Start 후보만 수집 → RIDING 진입 시 검증 반영

### 런 종료 시 슬로프 확정 우선순위
1. Start & Finish 모두 통과한 슬로프 우선
2. 난이도 높은 슬로프 우선
3. 위 조건이 없으면 **폴리곤 면적 작은 슬로프** 우선 (상세 슬로프 우선)

## 메트릭 계산

| 메트릭 | 조건 |
|------|------|
| **거리** | RIDING 상태에서만 누적 |
| **수직 낙차** | RIDING 상태에서만 누적 (바리오 사용 시 바리오 기반, 아니면 GPS 스무딩) |
| **평균 속도** | RIDING 상태에서 속도 > 5km/h 샘플 평균 |
| **최고 속도** | RIDING + `speedAccuracy ≤ 2.0 m/s` 샘플만 사용 |
| **경로 기록** | RIDING: 5m 간격, ON_LIFT/RESTING: 20m 간격 |

### 런 그래프/메트릭 속도 시리즈
- `routeSpeeds`와 `routeSpeedAccuracies`를 사용
- **속도 정확도 ≤ 2.0m/s**만 런 그래프/메트릭에 사용

### 런 확정/제외
- 런 종료 조건: **RIDING → RESTING 또는 RIDING → ON_LIFT**
- **런 종료 시점(RESTING/ON_LIFT)마다 Edge/Flow 결과 확정 및 RunMetric 저장**
- 노이즈 런 필터: **40초 이하 + 하강 30m 이하**면 런 제외

## 라이딩 스타일 점수

### Edge Score (카빙 파워)
- **데이터 소스:** `CMDeviceMotion` total acceleration
- **샘플링:** 60Hz (`updateInterval = 1/60`)
- **속도 게이트:** `4.2 m/s` 미만은 계산 제외
- **델타 체크:** `|ΔG| >= 0.5G` 프레임 무시
- **스무딩:** 10프레임 SMA

#### 가중치
- **Tier1:** 1.2G ~ 1.4G → 0.2x
- **Tier2:** 1.4G ~ 1.7G → 2.5x
- **Tier3:** 1.7G 이상 → 6.0x

#### 정규화 (1000점)
```
edgeRaw += (G * tierWeight) * dt
edgeScore = log(1 + edgeRaw) / log(1 + 260) * 1000
```

#### 캡
- `maxG < 1.7G` → **최대 940점**
- `tier2PlusTime / tieredTimeTotal < 0.25` → **최대 790점**

### Flow Score (주행 리듬 / 안정성)
- **데이터 소스:** `CLLocation.speed`
- **정확도 필터:** `horizontalAccuracy ≤ 80m`, `speedAccuracy ≤ 10.0m/s` (speedAccuracy < 0는 허용)
- **Stability Window:** 최근 5샘플 기준 변동성 평가
- **Base Score:** `300 + (700 * Average Stability)`
- **무효 조건:** `activeTime < 5s` 또는 `movingTime < 5s` 또는 샘플 부족 시 0점

#### 패널티/보너스
- **정지 패널티:** `-5점/초` (최대 -300점) — **Pending Rest 중에는 누적하지 않음**
- **급제동:** `a ≤ -2.0 m/s²` → `-40점/회`
- **채터링:** Jerk ≥ 15.0, 0.2초 윈도우, 2.5초 쿨다운, 속도 ≥ 5.5m/s → `-10점/회` (최대 -450점)
- **Quiet 보너스:** |G-1.0| ≤ 0.05, 0.5초 이상, 속도 ≥ 5.5m/s → `+5점/회`

#### 최종 점수
```
if score <= 0: 0
else: clamp(score, min=200, max=1000)
```

## 배터리 최적화 / GPS 정확도

| 상태 | 기본 정확도 | 특이사항 |
|------|-----------|---------|
| RIDING | bestForNavigation | Pending Rest 중에는 10m로 낮춤 (부스트 시 일시 상향) |
| ON_LIFT | nearestTenMeters | 하차 감지 부스트 시 bestForNavigation (20초) |
| RESTING | nearestTenMeters | 리프트 탑승 대기 인식 목적 |

## 관련 파일

- `snow_recorder/LocationManager.swift` - 상태 기계, 경로/메트릭/슬로프 인식
- `snow_recorder/Utilities/RidingMetricAnalyzer.swift` - Edge Score
- `snow_recorder/Utilities/FlowScoreAnalyzer.swift` - Flow Score
- `snow_recorder/Models/RidingState.swift` - 상태 enum

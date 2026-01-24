---
description: 측정 엔진 로직 및 슬로프 인식 시스템 설명
---

# Snow Recorder 측정 엔진

## 상태 기계 (State Machine)

4가지 상태로 사용자 활동 분류:
- **RIDING**: 활강 중 (측정 활성)
- **PAUSED**: 슬로프 내 일시 정지
- **ON_LIFT**: 리프트 탑승 중
- **RESTING**: 슬로프 외부 / 휴식

## 상태 전환 조건

| 전환 | 조건 |
|------|------|
| RESTING → RIDING | 슬로프 내 + 속도 > 5km/h + 고도 하강 |
| RIDING → PAUSED | 슬로프 내 + 속도 < 3km/h (5초 유지) |
| RIDING → RESTING | 슬로프 이탈 + 정지 → **runCount +1** |
| PAUSED → RIDING | 속도 증가 |
| RESTING → ON_LIFT | 리프트 근처 OR **확실한 고도 상승 (isClimbing)** |
| ON_LIFT → RIDING | **확실한 하강(Strong Descent)** + 속도 > 5km/h |
| ON_LIFT → RESTING | 저속(< 1.5km/h) + 평지 유지 **60초 이상** |

**※ 리프트 상태 유지 (Sticky OnLift):** 리프트 탑승 중 멈추거나 완만한 구간이 있어도, 위 탈출 조건(활강/장기정지)을 만족하지 않으면 계속 ON_LIFT 상태를 유지함.

## 슬로프 인식

1. **폴리곤 매칭**: Ray Casting 알고리즘
2. **우선순위**: 난이도 높은 슬로프 우선 (겹침 해결)
3. **방문 기록**: `visitedSlopes`에 런 중 방문한 슬로프 기록
4. **확정**: 런 종료 시 가장 높은 우선순위 슬로프 선택

## 메트릭 계산

| 메트릭 | 조건 |
|--------|------|
| 거리 | **모든 상태 기록** (RIDING: 5m, 기타: 20m 필터) |
| 수직 낙차 | RIDING + 속도 > 5km/h + 고도차 > 1m |
| 평균 속도 | RIDING 상태 샘플 평균 |
| 런 카운트 | RIDING → RESTING 전환 시 +1 |

## 라이딩 스타일 점수 (Edge / Flow)

라이딩 세션 종료 시 **Edge Score**와 **Flow Score**를 계산합니다. 별도의 실측 캘리브레이션 데이터가 없기 때문에, **세션 내부 통계(자체 정규화)**를 기반으로 점수를 산출합니다.

### Edge Score (카빙 파워)
- **데이터 소스:** `CMDeviceMotion`의 **total acceleration** (userAcceleration + gravity)
- **속도 게이트:** `4.2 m/s` 미만은 계산 제외 (리프트/정지 구간 제거)
- **델타 체크:** `|ΔG| >= 0.5G` 프레임은 범프(충격)로 간주하여 무시
- **스무딩:** 10프레임 단순 이동 평균(SMA)

#### 점수 산식 (지수 가중치 + 로그 정규화)
- **Tier 1 (Entry):** `1.2G ~ 1.4G` → `0.2x`
- **Tier 2 (Carving):** `1.4G ~ 1.7G` → `2.5x`
- **Tier 3 (Pro):** `1.7G 이상` → `6.0x`

```
edgeRaw += (G * tierWeight) * dt
edgeScore = log(1 + edgeRaw) / log(1 + target) * 1000
```

#### HELL MODE 캡
- `maxG < 1.7G`이면 **950~1000점 불가**
- 현재 캡: `maxG < 1.7G` → `max 940점`

#### Tier2 비율 조건 (고득점 제한)
- `tier2PlusTime / tieredTimeTotal < 0.25`이면 고득점 제한
- 현재 캡: 비율 미달 시 `max 790점` (Edge Score도 1000점 만점 예정)

> 참고: `target`(로그 정규화 기준)은 난이도 밸런싱용 튜닝 상수 (현재 260)

### Flow Score (주행 리듬 / 안정성)
- **데이터 소스:** `CLLocation.speed` (1Hz)
- **정확도 필터:** `horizontalAccuracy <= 50m`, `speedAccuracy <= 2.0 m/s`
- **스무딩:** 3샘플 이동 평균(SMA)

#### 기본 개념 (Local Stability Model)
기존의 감점 방식이 아닌 **지역적 속도 안정성(Local Window Stability)** 기반으로 기본 점수를 산출합니다.
- **Stability:** **5초 이동 구간(Window)** 내의 속도 표준편차(Deviation)를 측정.
  - **Natural Deceleration:** 슬로프 경사 변화로 인한 자연스러운 가감속은 5초 윈도우 내에서는 변화폭이 작아 **안정적(High Stability)**으로 평가됨.
  - **Instability:** 짧은 시간(5초) 내에 급가속/급감속이 반복되면 **불안정(Low Stability)**으로 평가됨.
#### 기본 개념 (Local Stability Model)
- **Base Score:** `300 + (700 * Average Stability)` (Spicy Mode - 1000 Scale)
  - 안정성 비중 대폭 확대: 작은 흔들림에도 점수가 크게 변동됨.
- **Variance Tuning:** `Denominator 3.5` (Sliding Friendly)
  - 슬라이딩 턴 특유의 리듬감(±3~4km/h 변동)은 **안정적(High Stability)**으로 인정.
  - 불규칙한 급가속/급감속만 불안정으로 간주.

#### 감점 로직 (Spicy Tuning)
- **정지 시간(Time-based Stop):** **정지 시간**에 비례하여 감점.
  - 감점: `-5점 / 초` (1분 정지 시 -300점)
  - **Cap**: 최대 `-300점`까지만 감점 (오래 쉬어도 0점 방지)
- **급제동(Hard Brake):** `a <= -2.0 m/s²` (슬라이딩 감속 허용)
  - `-40점` / 회 (감점 2배 강화)
  - 일반적인 슬라이딩 턴 감속은 허용하고, **위험 회피성 급정거**만 감지.
- **채터링(Chattering):** `0.1초` 내 Jerk 급변동 감지
  - `-20점` / 회 (감점 2배 강화)

#### 최종 점수
```
final = max(0, BaseScore - Penalties)
```

## 배터리 최적화 정책 (2026-01-24 업데이트)

리프트 탑승 인식률 향상을 위해 **대기 중 정밀도 상향**:

| 상태 | GPS 정확도 | 비고 |
|------|-----------|------|
| RIDING | bestForNavigation | 최고 성능 |
| PAUSED | nearestTenMeters | |
| ON_LIFT | nearestHundredMeters | 경로 기록용 |
| RESTING | **nearestTenMeters** | 빠른 리프트/이동 감지 |

슬로프 체크는 50m 이상 이동 시에만 수행

## 관련 파일

- `Models/RidingState.swift` - 상태 enum
- `Models/SlopeDatabase.swift` - 슬로프 데이터
- `LocationManager.swift` - 상태 기계 + 측정 로직

## 2026-01-24 필드 테스트 및 개선 (Field Test Log)

### 1. 리프트 탑승 미인식 (S1, S2)
- **증상:** 리프트 탑승 구간이 '휴식(Resting)'으로 기록되거나 아예 경로 데이터가 누락됨.
- **원인:**
  1. 휴식(Resting) 상태의 GPS 정확도(100m)가 너무 낮아, 탑승 초기의 미세한 이동/상승을 감지하지 못함.
  2. 위치 업데이트가 멈추면서 Speed 0km/h로 인식되어 상태 전환이 지연됨.
- **해결:** **휴식(RESTING) 상태의 GPS 정확도를 `nearestTenMeters`로 상향 고정.** (보행/대기 중 미세 이동 즉각 감지)

### 2. 리프트 상태 끊김/깜빡임 (S3)
- **증상:** 리프트 탑승 중 '이동'과 '휴식'이 빈번하게 전환됨 (Flickering).
- **원인:** 리프트 서행/정지 시 `isClimbing`(상승 감지) 조건이 깨지면서 즉시 휴식으로 이탈.
- **해결:** **Sticky On-Lift 로직 도입.**
  - 리프트는 한번 타면 **'확실한 하강(활강)'**이나 **'장시간 정지(60초 이상 평지 대기)'**가 아니면 절대 상태를 해제하지 않음.
  - 좌표 데이터 없이 물리적 패턴만으로 전 세계 모든 리프트 대응 가능.

### 3. 전체 경로 기록
- **개선:** 기존에는 '활강(Riding)'만 기록했으나, 이제는 **리프트, 휴식(이동 시) 전체 경로를 GPX에 저장**하도록 변경.
  - 배터리 절약을 위해 활강 외 구간은 20m 간격으로 기록.

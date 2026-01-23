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
| RESTING → ON_LIFT | 리프트 근처 + 고도 상승 |

## 슬로프 인식

1. **폴리곤 매칭**: Ray Casting 알고리즘
2. **우선순위**: 난이도 높은 슬로프 우선 (겹침 해결)
3. **방문 기록**: `visitedSlopes`에 런 중 방문한 슬로프 기록
4. **확정**: 런 종료 시 가장 높은 우선순위 슬로프 선택

## 메트릭 계산

| 메트릭 | 조건 |
|--------|------|
| 거리 | RIDING 상태에서만 누적 |
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
edgeScore = log(1 + edgeRaw) / log(1 + target) * 100
```

#### HELL MODE 캡
- `maxG < 1.7G`이면 **95~100점 불가**
- 현재 캡: `maxG < 1.7G` → `max 94점`

#### Tier2 비율 조건 (고득점 제한)
- `tier2PlusTime / tieredTimeTotal < 0.25`이면 고득점 제한
- 현재 캡: 비율 미달 시 `max 79점`

> 참고: `target`(로그 정규화 기준)은 난이도 밸런싱용 튜닝 상수 (현재 260)

### Flow Score (주행 리듬 / 안정성)
- **데이터 소스:** `CLLocation.speed` (1Hz)
- **정확도 필터:** `horizontalAccuracy <= 50m`, `speedAccuracy <= 2.0 m/s`
- **스무딩:** 3샘플 이동 평균(SMA)

#### 기본 개념
- **Base Score:** `100점`에서 시작
- **Cruising Ratio:** `cruisingTime / activeTime`

#### 감점 로직
- **급제동(Hard Brake):** `a <= -2.0 m/s²` 구간이 **2초 미만**이면 급제동으로 감점
  - `-3점` / 회
  - `2초 이상` 유지된 감속은 **Speed Control**로 간주하여 감점하지 않음
- **정지(Micro-Stop):** `v <= 5km/h`가 **2샘플 이상 연속**일 때 1회로 카운트
  - `-5점` / 회
  - `v >= 1.6 m/s`에서 정지 상태 해제
- **채터링(Chattering) 감지 (가정값):**
  - `0.1초` 내에 **Jerk가 +/- 방향으로 급격히 요동**하면 감점
  - 임계치: `|Jerk| >= 7.0 m/s³`
  - `-2점` / 회
  - **쿨다운:** 1초 (연속 감점 방지)
  - **속도 게이트:** `>= 4.2 m/s`에서만 감지
  - **턴 전환 보호:** Quiet Phase 직후 0.3초 감지 제외

#### Cruising Penalty (저속 주행 페널티)
- `cruisingRatio < 0.5`면 비율에 따라 추가 감점
- 최대 감점: `20점`

#### 리듬 보정 (Quiet Phase)
- **언웨이팅 구간:** `|G - 1.0| <= 0.08G` (total G 기준)이 `0.2초` 이상 지속되면 `+2점`

#### 최종 점수
```
final = max(0, 100 - penalties + quietBonus)
```

## 배터리 최적화

| 상태 | GPS 정확도 |
|------|-----------|
| RIDING | bestForNavigation |
| PAUSED | nearestTenMeters |
| ON_LIFT | hundredMeters |
| RESTING | threeKilometers |

슬로프 체크는 50m 이상 이동 시에만 수행

## 관련 파일

- `Models/RidingState.swift` - 상태 enum
- `Models/SlopeDatabase.swift` - 슬로프 데이터
- `LocationManager.swift` - 상태 기계 + 측정 로직

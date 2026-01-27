# 상태 전환 플로우 (Riding / OnLift / Resting)

본 문서는 `LocationManager.determineState()` 기준으로 **상태 전환 조건**을 정리한 요약이다. (iOS 앱 내부 로직 기준)

## 핵심 파라미터 (코드 기준)
- ridingSpeedThreshold: **5.0 km/h**
- ridingRestSpeedThreshold: **6.0 km/h** (저속 휴식 전환용)
- ridingRestDropThreshold: **10m / 20초** (하강량 제한)
- stateChangeDebounce: **5초**
- OnLift 하차 판정: **속도 < 1.5 km/h & 상승/하강 없음 상태가 60초 지속**
- OnLift 하차 감지 보조: **최근 20초 누적 하강 5m 이상 → GPS 정확도 20초 임시 상승 (쿨다운 20초)**  
  - 기본 정확도: `kCLLocationAccuracyNearestTenMeters`
- 상태 전이용 속도: **최근 위치 샘플 평균 속도(스무딩) 사용**
- Pending Rest 해제 조건: **속도 ≥ 10km/h & 순하강 ≥ 3m**
- Pending Rest 타임아웃: **180초(3분)** → Resting 확정
- Pending Rest 정확도 정책:
  - 기본: `kCLLocationAccuracyNearestTenMeters`
  - 바리오 감지: **최근 5초 누적 하강 ≥ 2m → BestForNavigation 10초 유지, 쿨다운 10초**

## 보조 판정 로직 (고도 기반)
- **Barometer 우선**, 미지원/샘플 없음 시 GPS 고도 폴백
- `altitudeChange = prev.altitude - current.altitude` (양수 = 하강)
- isDescending
  - 최근 샘플(>=3) 기준 고도 누적 하강 1.5m 이상 **또는** 현재 프레임 하강 0.5m 이상
- isClimbing
  - 최근 10샘플 기준 누적 상승 5m 이상
- isStrongDescent
  - 최근 10샘플 기준 누적 하강 5m 이상

## 상태 전환 플로우 (ASCII)

```
[RESTING]
  | 조건: speed > 5 && isDescending (Trigger)
  v
[PENDING]
  | 5초 관찰 후
  | 평균 속도 >= 5km/h
  | 변위 >= 5m
  | 순하강 >= 3m
  v
[Riding]

[RESTING]
  | 조건: isClimbing
  v
[OnLift]

[Riding]
  | 조건: 최근 20초 속도 <= 6km/h + 순하강 <= 10m
  v
[PENDING_REST]
  | 조건: 속도 >= 10km/h + 순하강 >= 3m
  v
[Riding]

[PENDING_REST]
  | 조건: isClimbingStrict
  v
[OnLift]

[PENDING_REST]
  | 조건: 5분 타임아웃
  v
[Resting]

[Riding]
  | 조건: isClimbing
  v
[OnLift]

[OnLift]
  | 조건: speed > 5 && isStrongDescent
  | + (직진성 < 0.95 OR 방향 분산 > 5°)
  v
[Riding]

[OnLift]
  | 조건: speed < 1.5 && !isClimbing && !isStrongDescent 가 60초 지속
  v
[Resting]
```

## 상태별 상세 조건

### RESTING → RIDING
- 1단계(트리거): `currentSpeedKmH > ridingSpeedThreshold && isDescending`
- 2단계(Pending 5초 확인):
  - 평균 속도 ≥ 5km/h
  - 수평 이동 거리(변위) ≥ 5m
  - 순하강(시작-현재) ≥ 3m
- 확정 시 `RIDING` 전환 (Pre-roll 적용: Pending 시작 시점부터 런으로 기록)

### RESTING → ON_LIFT
- `isClimbing == true`

### RIDING → RESTING
- 최근 20초 동안 **최대 속도 ≤ 6km/h**
- 최근 20초 동안 **순하강(시작-현재) ≤ 10m**
- **즉시 Resting 전환하지 않고 Pending Rest로 보류**
  - Pending 시작 시점: 최근 20초 윈도우의 시작 시각을 idleStartTime으로 저장
  - Pending 해제(라이딩 재개): **속도 ≥ 10km/h & 순하강 ≥ 3m**
  - Pending 중 리프트 탑승 감지: `isClimbingStrict == true` → `OnLift` 전환  
    - 이때 런 종료 시각은 **idleStartTime** 기준으로 보정
  - Pending 타임아웃(3분): `Resting` 확정  
    - 런 종료 시각은 **idleStartTime** 기준으로 보정
  - Pending 동안 정확도 정책:
    - 기본은 `NearestTenMeters` 유지 (배터리 절약)
    - 바리오 하강 감지 시 `BestForNavigation`으로 10초 임시 격상 (쿨다운 10초)

### RIDING → ON_LIFT
- `isClimbingStrict == true` (최근 10샘플 기준 **상승 7m 이상**)

### ON_LIFT → RIDING
- `currentSpeedKmH > ridingSpeedThreshold && isStrongDescent`
- **추가 필터(직진성/방향 분산):**
  - 최근 **20초 위치 샘플**로 직진성(Linearity) 계산  
    - `직선거리 / 누적거리`  
    - **60m 이상 이동한 경우에만** 적용  
    - 비율 **≥ 0.95**면 **리프트 가능성 높음**
  - 최근 위치의 `CLLocation.course` 표준편차 계산  
    - `speed ≥ 1.5 m/s`인 샘플만 사용  
    - 표준편차 **≤ 5°**면 **방향 고정 = 리프트 가능성 높음**
  - 위 두 조건을 **동시에 만족하면** `RIDING` 전환 **차단(ON_LIFT 유지)**

### ON_LIFT → RIDING (정확도 부스트: Barometer 기반 보조)
- 목적: OnLift 상태에서 **GPS 정확도 저하로 인한 Riding 전환 지연**을 줄이기 위한 보조 로직
- 조건:
  - `currentState == .onLift`
  - **Barometer 사용 가능**
  - 최근 **20초 바리오 샘플의 누적 하강 ≥ 5m**
- 동작:
  - 조건 만족 시 **GPS 정확도를 20초 동안 `BestForNavigation`으로 임시 상승**
  - 이후 **20초 쿨다운** 동안 재상승 방지
  - OnLift 상태가 종료되면 부스트/쿨다운 정보 초기화
- 주의:
  - 상태 전환 자체는 기존 조건(`speed + isStrongDescent + 필터`)을 그대로 사용
  - 이 로직은 **정확도 보정용**이며 전이 판정에는 직접 영향 없음

### ON_LIFT → RESTING
- `currentSpeedKmH < 1.5 && !isClimbing && !isStrongDescent` 상태가 **60초 이상 지속**

## Debounce 동작 요약
- `canChangeState()`
  - `stateChangeTime == nil`이면 **현재 시각 기록 후 false 반환**
  - 이후 **5초 경과 시 true 반환**
- riding에서 속도가 다시 올라가면 `stateChangeTime`을 리셋함

## 참고
- 상태 전환 시 타임라인 이벤트가 기록됨 (`handleStateChange`)
- 상태 전환은 GPS/Barometer 신호 품질에 따라 실제와 차이가 날 수 있음
- `stopTracking()` 시 **상태와 무관하게** `currentRunStartTime != nil`이면 마지막 런을 확정 저장함
- `riding → onLift` 전환 시 **런을 종료로 간주하여 확정 저장**함
- 노이즈 런 필터: `duration <= 40s` **and** `verticalDrop <= 30m` 인 런은 **RunMetric 저장에서 제외**
- 기존 데이터의 `pause` 이벤트는 UI에서 `rest`로 표시됨

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

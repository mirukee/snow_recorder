# 상태 전환 로직 점검 노트

문서(`docs/status_flow.md`)와 코드(`snow_recorder/LocationManager.swift`, `snow_recorder/RecordManager.swift`)를 기준으로 불일치 항목과 잠재 엣지 케이스를 정리한 메모이다.

## 범위
- 상태 전환 핵심: `LocationManager.determineState()`
- 런 종료/저장: `LocationManager.finalizeCurrentRun()`, `RecordManager.recordRunMetric()`

## 불일치/주의 사항 (문서 vs 코드)
- **디바운스 미적용**
  - 문서에는 `stateChangeDebounce = 5초`가 있으나, `canChangeState()`가 호출되지 않아 실제로는 전이에 디바운스가 걸리지 않는다.
  - 결과적으로 임계값 근처에서 상태가 빠르게 플립될 수 있다.
- **(해결됨)노이즈 런 필터 적용 범위**
  - 문서에 “40초 이하 + 30m 이하 런 제외”가 있으나, 이는 `RunMetric` 저장에서만 제외된다.
  - `runCount`, `totalDistance`, `verticalDrop` 등 세션 총계는 `LocationManager.finalizeCurrentRun()`에서 이미 확정되어 반영된다.
- **(해결됨) Pending 하강 조건**
  - 기존에는 pending 하강이 `verticalRange(max-min)`로 계산되어 흔들림만으로도 통과 가능했으나,
  - 현재는 **순하강(시작-현재)** 계산으로 변경되어 문서와 일치한다.

## 잠재 엣지 케이스
- **(해결)OnLift → Riding 지연 (리프트 궤적 잔존)**
  - `recentLocations`가 상태 전환 시 리셋되지 않아 리프트 궤적이 20초 윈도우에 남을 수 있다.
  - `linearityRatio`·`courseStdDev`가 “리프트 가능성 높음”으로 판정되면 실제 활강 시작이 지연될 수 있다.
- **(해결)OnLift → Riding 지연 (정확도 저하)**
  - OnLift 구간은 위치 정확도를 100m로 낮추므로 속도/고도 신뢰성이 떨어질 수 있다.
  - `speed > 5` 및 `isStrongDescent` 조건을 늦게 만족해 전이가 지연될 수 있다.
- **OnLift → Resting 지연**
  - “60초 지속” 타이머는 위치 업데이트가 들어올 때만 진행된다.
  - 업데이트가 뜸하면 실제 정지 시간이 60초를 넘겨도 전이가 늦어질 수 있다.
- **isClimbing / isClimbingStrict 샘플 의존**
  - 최근 샘플 개수(>=10) 조건에 따라 초기 구간에서 리프트 상승 감지가 늦을 수 있다.
  - 반대로 샘플 간격이 짧으면 작은 상승에도 과민 반응할 수 있다.
- **(해결)Riding → Resting 조건의 고도 범위 사용**
  - 최근 20초의 `verticalRange(max-min)`만 본다.
  - 고도 흔들림이 크면 저속이라도 Resting 전환이 지연될 수 있다.
- **속도 정확도 미반영**
  - 최대속도 갱신에는 정확도 필터가 있으나, 상태 전이에는 적용되지 않는다.
  - GPS 품질이 낮을 때 전이 판단이 흔들릴 수 있다.

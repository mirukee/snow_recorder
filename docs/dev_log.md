# 개발 일지 (Field Test / Bugfix)

## 2026-02-06
- 파이어스토어 보안 규칙 강화: `rankings/{uid}` 본인 문서만 쓰기/삭제 허용, `leaderboards` 읽기만 허용, 그 외 경로 차단.
- 시즌/주차 ID 반구 분리: `NH_25_26`, `SH_2026`, `NH_YYYY-Www` 형식으로 생성 및 서버/클라이언트 반영.
- 리더보드 보드 ID에 시즌/주차 suffix 포함: `season_distance_m_all_NH_25_26` 같은 구조로 분리.
- 리더보드 갱신 방식 변경: 변경 이벤트 → 큐 적재 → 스케줄러(10분 간격) 배치 처리로 전환.
- 랭킹 도움말 문구 업데이트: “정각 배치” → “몇 분 단위 배치”로 UX 안내 문구 갱신.
- 랭킹 UI: “UPDATED HH:mm” 표시를 보드/필터 영역에 복원(스크롤 헤더에서 보이도록).
- 해외 리더보드 표시 UX 추가: HOME/OVERSEAS 토글로 시즌 표기만 교체, 북반구 기본 노출 유지.

### 분포 요약(히스토그램) 계획
- 목표: 상위 1000 밖 유저에게 **정확 순위 대신 상위 % 근사치** 제공.
- 저장 구조: `leaderboard_stats/{boardId}` 문서에 `total`, `buckets`, `updatedAt` 저장.
- 생성 타이밍: 리더보드 큐 처리 시 `rankings` 전체를 스캔하여 버킷 카운트 산출 후 함께 업데이트.
- 버킷 설계(1차):
  - `edge/flow`: 0~1000 고정 40~50버킷.
  - `distance/runCount`: 로그 스케일 버킷(분포 쏠림 완화).
- UI 사용: TOP 1000 안이면 정확 랭크, 밖이면 `TOP XX%` 표기.
- 향후 개선: 분포 변화가 큰 구간은 **quantile 버킷**으로 정밀도 향상.

## 2026-01-31
- StoreKit 로컬 테스트 이슈: 실기기/시뮬레이터 모두 `StoreKit config path: nil`로 로컬 StoreKit 주입 실패, `Product.products(for:)` 결과 빈 배열.
- 확인 로그: `Env keys (filtered)`에 StoreKit 관련 키 없음, 번들 ID는 `com.mirukee.snow-recorder` 정상 출력.
- 결과: Paywall에서 제품 미노출, `StoreManager`가 "No products found" 출력. 현재 원인 추적 중.
- iCloud 백업(CloudKit) 기능은 컨테이너 이슈로 MVP 이후로 보류. Settings 내 백업/복원 버튼 비활성화 처리.
- 인앱 언어 변경 시 일부 화면에서 로컬라이즈가 반영되지 않는 문제 확인: `Text(String)`/`NSLocalizedString`처럼 문자열을 String으로 만들어 넣는 방식은 `.environment(\.locale, ...)` 변경을 따라가지 못함. `LocalizedStringKey` 기반 `Text("key")`/`Button("key")` 형태로 전환 필요.
- 리더보드 비용 최적화: YOU 바는 로컬 스탯 우선 표시로 즉시 반영.
- 삭제/변경 시 즉시 업로드 대신 `pending` 플래그 + 지연 업로드(쿨다운/지터) 적용, 일일 자동 업로드 제한 추가.
- 리더보드 fetch를 메타→변경 시 샤드 읽기 방식으로 변경, 정각 동시 read 분산 지터 적용.

## 2026-02-01
- 런 디테일 로컬라이즈 이슈 수정: 점수 도움말/타임라인/런 비교 문구가 영어 환경에서도 한국어로 표시되던 문제 해결.
- 원인: `NSLocalizedString`/`String(localized:)`가 앱 내 `preferred_language` 설정을 반영하지 못해 시스템 로케일과 혼재됨.
- 해결: 런 디테일 전용 로컬라이즈 함수에서 ko/en 번들을 명시적으로 선택해 로딩하도록 변경.
- 타임라인 상세 보정: 기존 세션에 저장된 “휴식/리프트 탑승” 등 한국어 detail이 영어 환경에서 그대로 노출되는 문제를 기본값 패턴 매칭으로 강제 치환.

## 2026-01-30
- 뱅크각(Bank Angle) 구현: Edge Analysis 탭에 고도화된 메트릭 카드 추가.
- 지도 스냅샷 수정: 공유 이미지 생성 시 리프트 라인(점선) 렌더링 누락 수정.
- 리더보드 프로필 버그: 타 유저 프로필 조회 시 Edge/Flow Score 0점 표시 문제 해결.

## 2026-01-29
- 리프트 감지 보강: GPS 업데이트 지연 시 바리오 기반 보조 판정으로 `OnLift` 전환(연속 3초 + 최근 10초 상승량 기준).
- 오늘 이슈 정리: 첫 런 후 리프트 탑승 구간에서 GPS 업데이트 공백으로 상태 판정이 지연되어 `riding` 유지 가능성 확인.
- 히스토리 삭제 직후 먹통/크래시 원인 분석: `flowBreakdown` 타입 캐스팅 실패(`Optional<Any>` → `FlowScoreBreakdown`)로 SIGABRT 발생.
- 해결: `flowBreakdown`/`edgeBreakdown`을 Optional로 전환하고 사용처에서 `.empty` 폴백 적용.

## 2026-01-28
- 타임라인 & 지도 고도화: 지도 경로에 타임스탬프를 매핑하여 라이딩/리프트 구간을 시각적으로 분리(실선/점선).
- 메트릭 신뢰도 개선: Flow Score 0점 버그 수정(최소 점수 보장), Chatter 감점 로직 완화, 속도 그래프 런 간 간섭 제거.

## 2026-01-27
- SwiftData 안정화: 스키마 변경 시 마이그레이션 전략 수립(Optional 필드 활용).

## 2026-01-24
- 점수 스케일 업: 변별력을 위해 100점 -> 1000점 만점으로 변경.

# 개발 일지 (Field Test / Bugfix)

## 2026-01-31
- StoreKit 로컬 테스트 이슈: 실기기/시뮬레이터 모두 `StoreKit config path: nil`로 로컬 StoreKit 주입 실패, `Product.products(for:)` 결과 빈 배열.
- 확인 로그: `Env keys (filtered)`에 StoreKit 관련 키 없음, 번들 ID는 `com.mirukee.snow-recorder` 정상 출력.
- 결과: Paywall에서 제품 미노출, `StoreManager`가 "No products found" 출력. 현재 원인 추적 중.
- iCloud 백업(CloudKit) 기능은 컨테이너 이슈로 MVP 이후로 보류. Settings 내 백업/복원 버튼 비활성화 처리.
- 인앱 언어 변경 시 일부 화면에서 로컬라이즈가 반영되지 않는 문제 확인: `Text(String)`/`NSLocalizedString`처럼 문자열을 String으로 만들어 넣는 방식은 `.environment(\.locale, ...)` 변경을 따라가지 못함. `LocalizedStringKey` 기반 `Text("key")`/`Button("key")` 형태로 전환 필요.
- 리더보드 비용 최적화: YOU 바는 로컬 스탯 우선 표시로 즉시 반영.
- 삭제/변경 시 즉시 업로드 대신 `pending` 플래그 + 지연 업로드(쿨다운/지터) 적용, 일일 자동 업로드 제한 추가.
- 리더보드 fetch를 메타→변경 시 샤드 읽기 방식으로 변경, 정각 동시 read 분산 지터 적용.

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

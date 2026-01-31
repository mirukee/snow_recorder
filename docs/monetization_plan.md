# Snow Record 구독 모델 정리 (초안)

## 결론 요약
- **개별 런 기본 스탯은 무료 유지**가 맞다.
- **유료는 “해석/비교/리플레이/고급 공유”**에 집중한다.
- 전환 중심은 **Run Detail 60% + Share 40%** 가중치로 설계한다.

## 배경 및 목표
- 목표: **구독 중심 수익 모델**, 광고는 필요 시 **최소 노출**.
- 경쟁 상황: Slopes 등 선점 앱 존재 → 진입 장벽을 낮춰야 함.
- Snow Record 정체성: **감성(Vibe) + Flex**.

## 무료/유료 범위 원칙
### 무료로 유지해야 할 것
- 기본 기록 확인: 거리/시간/최대·평균속도/버티컬/런 수
- 기본 런 맵 및 기본 속도 프로파일(간단 차트)
- 기본 공유 템플릿 1~2개(워터마크 포함)
 - **타임라인 기본 기능:** 타임라인 스크럽 + 현재 위치 마커 + 상태(riding/lift/rest) 표시 + 기본 경로 라인

### 유료로 잠글 것 (Pro)
- 런 비교(이전 런/시즌 평균/친구)
- 고급 분석(Edge/Flow 분해, G-Force 분포, 안정 구간)
- 리플레이/히트맵/3D/오프라인 맵
- 고급 공유(템플릿 확장, 애니메이션, 워터마크 제거, 고해상도)
 - **타임라인 고급 레이어:** 속도 히트맵, 최고속도 지점, G-Force 변화, Flow/Edge 변화, 점수 이벤트 마커

## 전환 설계 (가중치 60/40)
### Run Detail (전환 60%)
- 기본 스탯은 무료 → **“내 기록 확인” 습관 유지**
- Pro 카드 배치 → **“해석/비교/리플레이” 욕구 자극**
- 잠금 방식: 프리뷰 노출 후 탭 시 구독 유도

### Share (전환 40%)
- 기본 템플릿 무료
- Pro에서 커스텀/애니메이션/워터마크 제거

## 미구독 진입 UX 설계 (구독 유도 플로우)
### 핵심 원칙
- **Soft Lock + 프리뷰 + CTA**: 막기보다 궁금하게 만들기
- 라벨은 영어, 설명은 한국어
- Paywall은 세션당 1회 노출, 이후는 토스트/CTA 버튼으로 전환

### 1) Run Detail 진입 (전환 60%)
- **Pro Insights 카드**
  - 위치: 기본 스탯 바로 아래 또는 Bento 2열 중 1칸
  - 상태: 블러 프리뷰 + `LOCKED` 칩
  - 탭: Paywall 시트
  - 카피 예시: `PRO INSIGHTS` / “이번 런의 Edge·Flow 분해, 최고 속도 지점, G-Force 피크를 확인하세요”
- **타임라인 레이어 토글**
  - 무료: `STATUS`, `ROUTE`
  - Pro: `SPEED HEATMAP`, `TOP SPEED PIN`, `G-FORCE`, `EDGE/FLOW`
  - 잠금 토글 탭: 블러 프리뷰 + 하단 CTA
  - 첫 진입 1회 툴팁: `PRO LAYER`
- **Run 비교 카드**
  - `COMPARE RUNS` 잠금 카드
  - 탭 시 스켈레톤/미리보기 1~2초 후 Paywall

### 2) Share 진입 (전환 40%)
- **템플릿 선택**
  - 무료 템플릿 1~2개 정상 사용
  - Pro 템플릿: 썸네일 `PRO` 네온 배지
  - 탭: 워터마크/저해상도 프리뷰 → `UNLOCK PRO`
- **고급 공유 옵션**
  - `ANIMATED`, `NO WATERMARK`, `4K EXPORT` 토글 잠금
  - 탭 시 하단 시트: “이 옵션은 Pro에서만 가능”

### 3) Map/Replay/3D 진입
- 버튼은 보이되 흐림 + Lock 아이콘
- 탭: 1초 미리보기 후 Paywall
- 카피 예시: `REPLAY YOUR RUN` / “라인이 살아 움직이는 리플레이를 경험하세요”

### 4) Paywall 구조
- 헤더: `UNLOCK PRO` + 네온 글로우
- 혜택 요약(4줄):
  1) `ADVANCED ANALYSIS` — Edge/Flow 분해
  2) `REPLAY & HEATMAP` — 최고속도/구간별 라인
  3) `SHARE+` — 워터마크 제거/애니메이션
  4) `COMPARE` — 기록 비교
- 가격: 월/연(연간 강조)
- CTA: `START PRO` (Neon Green)
- 보조: `Not now`, `Restore`

### 5) 마이크로 카피 예시
- 잠금 상태: `PRO ONLY` / “자세한 분석은 Pro에서 확인 가능”
- Paywall 서브: “이번 런의 숨겨진 점수를 확인해보세요”
- 구독 완료: `PRO UNLOCKED` + “이제 히트맵이 활성화됩니다”

### 6) 피로도 컨트롤
- 동일 화면 내 Paywall은 세션당 1회
- 연속 탭은 토스트 + CTA 버튼으로 전환
- 공유 진입 시 Pro 템플릿 1회만 자동 강조

## UI 배치도 (Run Detail / Share)
### Run Detail 화면 배치
- Top: 헤더 + 기본 스탯 카드(무료)
- Bento Grid:
  - 1행: MAX SPEED / AVG SPEED (무료)
  - 2행: DISTANCE / RUN COUNT (무료)
  - 3행: VERTICAL DROP (무료, 2칸 스팬)
  - 4행: DURATION (무료, 2칸 스팬)
- 타임라인 영역:
  - 상단: 레이어 토글 바 (무료 2개 + Pro 4개)
  - 본문: 기본 경로/상태(무료) + 잠금 레이어는 블러 프리뷰
  - 하단: `COMPARE RUNS` 카드(잠금)
- 잠금 카드 규칙:
  - 카드 높이/그리드 규격은 무료 카드와 동일
  - `LOCKED` 칩 + 얕은 블러 + 1~2줄 설명 문구

### Share 화면 배치
- 상단: 템플릿 캐러셀
  - 무료 템플릿 1~2개는 정상
  - Pro 템플릿은 `PRO` 배지 + 잠금 오버레이 + 블러 프리뷰
- 옵션 섹션:
  - (옵션 토글 잠금은 구현 전)
- 하단:
  - 기본 공유 CTA는 활성
  - Pro 템플릿 선택 시 `UNLOCK PRO` CTA로 전환
  - 잠금 템플릿 상태에서 다운로드/배경사진 선택 비활성화

## 런 상세 화면 락 설계 예시
- 무료 카드: MAX SPEED / AVG SPEED / DISTANCE / VERT DROP / TIME
- Pro 카드: RUN 비교, 구간별 리플레이, 히트맵, Edge/Flow 세부 분석
 - 타임라인: **무료는 위치/상태**, **Pro는 히트맵/최고속도/G-Force/Flow/Edge** 토글

## 현재 적용된 UX (실제 구현 반영)
### Run Detail
- **타임라인 레이어 토글**: Pro 레이어 탭 시 Paywall 연동
- **Compare Runs 카드**: 잠금 카드 + Paywall 연결
- **Run Stats > Analysis**: Pro 전용
  - 미구독은 **블러 미리보기 + 잠금 오버레이**
  - 오버레이에서 `UNLOCK PRO` CTA
  - 스크롤은 허용, 분석 컨텐츠는 블러 처리

### Share
- **Pro 템플릿 배지/잠금 오버레이** + 블러 프리뷰
- **Pro 템플릿 선택 시 CTA 전환**: `SHARE TO STORY` → `UNLOCK PRO`
- **잠금 템플릿에서 다운로드/배경 사진 선택 비활성화**

### Paywall
- **StoreKit 상품 연동**: Monthly/Annual/Lifetime 실상품 기반
- **Intro Offer CTA**: 실제 무료 체험 기간 노출
- **구매 실패 알림** 및 **구독 복원 버튼**

## 타임라인/히트맵 과금 구조 (확장형 레이어 시스템)
- **레이어 단위로 무료/유료 잠금**: UI는 동일, 권한만 제어
- 레이어 예시:
  - Map: `routeBase(무료)`, `statusSegments(무료)`, `speedHeatmap(Pro)`, `topSpeedPin(Pro)`
  - Charts: `speed(Pro)`, `gForce(Pro)`, `flow(Pro)`, `edge(Pro)`, `scoreEvents(Pro)`
- 확장성: 신규 유료 지표는 **레이어 등록만 추가**하면 UI 자동 노출
- UX: 잠금 레이어는 블러 프리뷰 + 탭 시 구독 CTA

## 광고 정책
- 트래킹/런 디테일/공유 화면엔 광고 배치하지 않음
- 히스토리/프로필 하단 1개 네이티브 배너 정도로 최소화
- 구독 시 완전 광고 제거

## 가격/상품 구성 제안
### 한국 (시즌 중심)
- 월간 7,900~9,900원 유지
- 영구 49,000원~60,000원
- 연간 24,900원

### 가격 신호 체크
- “너무 싸보이는 가격”은 가치 신호가 약해질 수 있음

## 결정 질문 (후속)
- Pro 핵심 1순위는 분석인가, 커뮤니티인가, 공유인가?
- 리조트 확장(콘텐츠 팩)을 구독에 포함할지, 별도 IAP로 분리할지?

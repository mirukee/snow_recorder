# 코드 리뷰 요약 (서비스 런칭 전)

작성일: 2026-02-06

아래 내용은 랭킹/파이어스토어 관련 코드의 **서비스 안정성**과 **비용 리스크** 관점에서 정리한 핵심 이슈입니다.

## 요약
- **해결됨**: 파이어스토어 보안 규칙 과도 권한
- **해결됨**: 시즌/주차 하드코딩, 리더보드 배치 고정 비용(큐 기반 배치 처리)
- **남은 이슈**: 리더보드 응답 레이스, 로그아웃 후 뱃지 업로드 가능

## 상세 이슈 목록

### 1) [해결됨] 리더보드 배치 고정 비용
- 위치: `/Users/gimdoyun/Documents/snow_recorder/functions/index.js`
- 변경: `rankings/{uid}` 변경 시 **큐에 적재** → 스케줄러가 **주기적 배치(현재 10분 간격)**로 처리.
- 효과: 고정 비용 제거, **활성 유저/변경량에 비례한 비용 구조**로 개선.

### 2) [해결됨] 과도한 Firestore 권한
- 위치: `/Users/gimdoyun/Documents/snow_recorder/firestore.rules`
- 변경: `rankings/{uid}` 본인 문서만 쓰기/삭제 허용, 그 외 모든 경로 기본 차단.
- 남은 과제: 필드 수준 검증 규칙 강화 (필드/범위 제한).

### 3) [해결됨] 시즌 범위 하드코딩
- 위치: `/Users/gimdoyun/Documents/snow_recorder/snow_recorder/Services/RankingService.swift`
- 변경: **6/1 시작 ~ 다음 해 5/31 종료** 기준으로 계산.
- 추가: 시즌 ID를 반구 포함 (`NH_25_26`, `SH_2026`)으로 생성.

### 4) [해결됨] 서버 시즌 ID 하드코딩
- 위치: `/Users/gimdoyun/Documents/snow_recorder/functions/index.js`
- 변경: 시즌 ID 고정값 제거, **클라이언트 업로드된 시즌 ID** 기준으로 보드 갱신.

### 5) [해결됨] 주차 계산 불일치 가능
- 위치: `/Users/gimdoyun/Documents/snow_recorder/snow_recorder/Services/RankingService.swift`
- 변경: 주차 ID에 **반구 prefix 포함** (`NH_YYYY-Www`, `SH_YYYY-Www`)으로 충돌 방지.
- 참고: 현재 KST 캘린더 사용 유지(추후 ISO 일치 필요 시 개선 가능).

### 6) [P2] 리더보드 응답 레이스 (미해결)
- 위치: `/Users/gimdoyun/Documents/snow_recorder/snow_recorder/Services/RankingService.swift:206`
- 내용: 비동기 응답 시 요청 당시 `boardId` 유효성 확인 없음.
- 영향: 필터 연타 시 이전 응답이 최신 UI를 덮어쓸 수 있음.
- 제안: 요청 토큰/boardId 검증 후 반영.

### 7) [P2] 로그아웃 후 뱃지 업로드 가능 (미해결)
- 위치: `/Users/gimdoyun/Documents/snow_recorder/snow_recorder/Managers/AuthenticationManager.swift:229`
- 내용: 지연 업로드가 캡처된 `user`로 실행.
- 영향: 로그아웃/탈퇴 직후에도 이전 UID로 쓰기 발생 가능.
- 제안: 실행 시점의 `currentUser` 재확인 또는 workItem 강제 취소.

## 권장 우선순위
1. 리더보드 응답 레이스 해결
2. 로그아웃 후 뱃지 업로드 방지
3. Firestore 필드 수준 검증 규칙 추가

## 추가 변경 (UX)
- 랭킹 페이지에 **리더보드 갱신 방식 안내(HELP)** 추가.

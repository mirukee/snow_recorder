# 기압계(Barometer) 기반 로직 전환: 효용성 분석 및 도입 계획

## 1) 개요
- 목표: **런 분리, 리프트/활강 구분, 수직낙차, 경사 기반 분석**의 핵심 신호를 GPS 고도 대신 **iPhone 기압계(Barometer)** 중심으로 전환
- 범위: `LocationManager`의 상태 판정 및 `RunSession` 메트릭 산출 로직
- 전제: **기압계를 메인으로 즉시 적용**, 기존 GPS/슬로프 로직은 **폴백/호환성 유지** 목적의 백업 신호로 보존
  - 구형 기기(현재는 실사용 빈도 낮음), 센서 오류 상황, **추후 Android(Kotlin) 확장**을 고려해 GPS 로직을 삭제하지 않음

---

## 2) 현행 로직 요약 및 문제점
- 현재는 **GPS 속도 + GPS 고도 변화** 기반으로 상태 전환 및 낙차 계산
- 현장 이슈
  - 리프트 탑승 중 `speed=0` 빈번 → `ON_LIFT → RESTING` 오판 발생
  - 리프트 초반 저속 구간에서 `isClimbing` 조건 미충족 → 리프트 시작 누락
  - 슬로프 상공 통과 시 `RESTING` 전환, 슬로프 인식 오탐지 등
- 결론: **GPS 고도·속도 신호의 노이즈/불연속성**이 상태 전환과 낙차 계산 품질을 저하시킴

### 현행 고도 판단 로직 (GPS 고도 기반)
- 고도 변화 계산: `altitudeChange = prev.altitude - current.altitude` (양수 = 하강)
- 하강 판단 `isDescending`
  - 최근 샘플(>=3) 기준 **누적 하강 1.5m 이상** 또는 **현재 프레임 하강 0.5m 이상**
- 상승 판단 `isClimbing`
  - 최근 10샘플 기준 **누적 상승 5m 이상**
- 강한 하강 판단 `isStrongDescent`
  - 최근 10샘플 기준 **누적 하강 5m 이상**
- OnLift 하차 판정
  - `speed < 1.5 km/h` + **상승/하강 없음** 상태가 60초 지속 시 `RESTING` 전환

---

## 3) 기압계 도입 효용성 분석

### A. 기대 효용
1. **상승/하강 판정 안정화**
   - 기압계는 단기 고도 변화(상승/하강)에 민감 → 리프트 상승을 더 안정적으로 감지
2. **수직낙차 정확도 개선**
   - 런 구간의 **상대 고도 변화**를 고해상도로 누적 가능
3. **경사 기반 분석 정밀화**
   - 수직 속도(Barometer) + 수평 속도(GPS)로 **경사각/경사율** 산출 가능
4. **속도 0 이슈 보완**
   - GPS 속도가 0으로 떨어져도, 상승/하강 신호가 유지되면 상태 전환의 안전장치 역할

### B. 기대 결과 (정량 목표)
- 리프트 오탐지(RESTING 전환) 빈도 **50% 이상 감소**
- 런 분리 누락(초반 구간) **현저 감소**
- 런별 수직낙차 변동성(표준편차) **감소**

---

## 4) 리스크 및 제약

1. **기압 드리프트(기상 변화)**
   - 장시간 세션에서 압력 변화가 고도 오프셋을 유발할 수 있음
2. **절대 고도 부정확**
   - 바리오 값은 상대 고도 중심 → **기준점 보정** 필요
3. **기기/센서 가용성**
   - 일부 구형 기기 미지원 가능 → **GPS 폴백** 필요
4. **환경 영향**
   - 체온, 바람, 기기 위치(포켓/가방) 등이 압력 변화에 영향 가능

---

## 5) 핵심 설계 방향

### A. 센서 융합 전략
- **Barometer = 수직 방향의 1차 신호 (즉시 메인 적용)**
- **GPS = 수평 속도/위치, 절대 고도 보정용**
- 상태 전환 로직은 바리오 기반 상승/하강을 우선 적용하고, GPS는 보조/폴백으로 사용
  - 센서 미지원/오류 시 **GPS 기반 로직으로 자동 전환** 가능하게 유지
  - Android 확장 시 Kotlin으로 **GPS 로직을 이식 가능한 백업 경로**로 남김

### B. 기준점 보정 방식
- 세션 시작 시점에 `baselineAltitude` 설정
  - **현재 구현:** 초기 N샘플(기본 5개) **중앙값**으로 베이스라인 설정 (노이즈 완화)
  - (선택) 향후 **슬로프 Top/Bottom 고도 → GPS 고도** 우선 보정 가능
- 런 종료 시점에 drift 확인 후, 일정 범위를 벗어나면 **부분 보정** 수행
  - **현재 구현:** 시작/종료 GPS 거리 ≤ 100m **그리고** GPS 고도 차 ≤ 5m일 때만 drift 보정 적용
  - **추가 보정:** `RESTING` 구간에서만 GPS-바리오 편차를 **저속 비율로 서서히 보정**

### C. 필터링/스무딩
- 샘플 윈도우: 5~10초 이동 평균
- 급격한 압력 점프는 **outlier 제거**
- **업데이트 주기 고정 불가:** `CMAltimeter` 콜백 주기는 OS/기기 상태에 의해 결정됨
- 따라서 **샘플 개수 기준 스무딩/베이스라인** 방식 유지
- **GPS 사용 시 항상 스무딩 적용** (이동 평균 + 아웃라이어 제거)

### D. 슬로프 좌표 의존 최소화
- **상태 판정(런/리프트/정지)은 물리 신호(수직속도·수평속도·지속시간)만 사용**
- 슬로프 좌표 사용 범위는 **UI/기록 태깅**으로 축소
  - 현재 슬로프명 표시
  - 기록 저장 시 슬로프명/난이도/메타데이터 부여
- 좌표 의존을 더 줄이기 위한 보호장치
  - **세션 시작/종료 버튼을 게이트로 사용** (사용자가 시작을 눌러야 상태 로직이 동작)
  - **리조트 “대략 영역”만 선택적으로 유지** (슬로프 폴리곤 없이 큰 경계 폴리곤/원형 영역)
    - 목적: 리조트 외부 이동의 **비의도 트래킹 차단**
    - 상태 로직 자체에는 관여하지 않고, 세션 활성 조건에만 사용

---

## 6) 알고리즘 초안 (기압계 중심)

### A. 파생 변수
- `baroAltitude`: 상대 고도 (m)
- `verticalSpeed`: ΔbaroAltitude / Δt (m/s)
- `verticalGain`: 누적 상승량
- `verticalDrop`: 누적 하강량

### B. 상태 전환 기준 (초안)
- **Riding 진입**
  - `sessionActive == true`
  - (선택) `isInsideResortRegion == true` 인 경우에만 허용
  - `speed > 5 km/h`
  - `verticalSpeed < -0.3 m/s` **또는** `recentDrop >= 1.5m`

- **OnLift 진입**
  - `verticalSpeed > +0.2 m/s` **지속 10~15초**
  - 또는 `recentGain >= 5m / 15초`

- **Resting 전환**
  - `speed < 1.5 km/h` + `abs(verticalSpeed) < 0.05 m/s` **60초 이상**
  - (선택) 리조트 영역 밖 감지 시 세션 자동 종료 후보

### C. 수직낙차 계산
- 런 구간에서 `verticalDrop`만 누적
- 런 종료 시 drift 보정

### D. 경사 기반 분석
- `slopeAngle = atan(|verticalSpeed| / horizontalSpeed)`
- 일정 속도 이하(예: 3 km/h)는 분석 제외

### E. 세션 시작/종료 게이트
- 상태 로직은 `sessionActive == true`일 때만 동작
- **시작:** 사용자가 명시적으로 “세션 시작” 버튼을 눌렀을 때 활성화
- **종료:** 사용자가 “세션 종료” 버튼을 누르거나,
  - `speed < 1.0 km/h` + `abs(verticalSpeed) < 0.05 m/s` 상태가 10분 이상 지속 시 자동 종료(선택)
  - (선택) 리조트 대략 영역 이탈 시 자동 종료 후보

---

## 7) 데이터 모델 및 저장 전략

### A. `RunSession` 추가 필드 (권장, Optional 기본)
- `baroAvailable: Bool`
- `baroVerticalDrop: Double?`
- `baroGain: Double?`
- `baroSampleCount: Int?`
- `baroBaselineAltitude: Double?`
- `baroDriftCorrection: Double?`

### B. 마이그레이션 주의사항
- **필수 속성 추가 금지** (SwiftData 마이그레이션 실패 이슈 예방)
- 기본값 또는 Optional로 설계

---

## 8) 도입 계획 (단계별)

### Phase 0: 사전 검증 (1주)
- Barometer 샘플링 안정성 확인
- 세션 길이별 drift 범위 측정

### Phase 1: **즉시 메인 적용** (1주)
- Barometer 기반 상태 전환/낙차/경사 계산을 **기본 경로로 전환**
- GPS 로직은 **삭제하지 않고** 폴백/보정 경로로 유지
- 센서 오류/미지원 기기에서 자동 전환 동작 확인

### Phase 2: 로그 기반 보정 (2주)
- Barometer vs GPS 낙차/상승량 비교 로그 확보
- 임계치(상승/하강 m/s) 및 스무딩 윈도우 튜닝

### Phase 3: 안정화 및 튜닝
- 리조트별 threshold 미세 조정
- 실제 필드 테스트 기반 파라미터 고정

---

## 8-1) 단계별 실행 체크리스트 (즉시 실행용)
> 목표: **Phase 0 → Phase 1 → Phase 2 → Phase 3** 순서로 안전하게 진행

### Step 1. 준비/세팅 (Phase 0)
- [x] **Feature Flag 추가**: `barometerEnabled` (로컬 토글)
- [x] **기기 지원 체크 추가**: `CMAltimeter.isRelativeAltitudeAvailable()`
- [x] **데이터 모델 필드 추가 (Optional 기본)**  
  - `baroAvailable`, `baroVerticalDrop`, `baroGain`, `baroSampleCount`, `baroBaselineAltitude`, `baroDriftCorrection`
- [x] **기본 로깅 설계**  
  - 기록: `timestamp`, `baroAltitude`, `verticalSpeed`, `speed`, `state`, `recentGain/Drop`
- [x] **기존 GPS 로직 유지** (폴백 경로로 남김)

### Step 2. 바리오 파이프라인 구현 (Phase 1-1)
- [x] **바리오 샘플링 시작/중지** 구현  
  - 세션 시작 시 `startRelativeAltitudeUpdates`  
  - 세션 종료/백그라운드 전환 시 `stopRelativeAltitudeUpdates`
- [x] **스무딩/필터 추가**  
  - 5~10초 이동 평균  
  - 급격한 점프(outlier) 제거
- [x] **파생 변수 계산**  
  - `verticalSpeed`, `verticalGain`, `verticalDrop`

### Step 3. 상태 전환 연결 (Phase 1-2)
- [x] **상태 판정 기준 교체**  
  - `Riding/OnLift/Resting` 전환을 바리오 기준으로 우선 적용
- [x] **폴백 조건 추가**  
  - 바리오 미지원/오류/샘플 없음 → GPS 고도 로직 사용
- [x] **슬로프 좌표 의존 최소화**  
  - 상태 전환은 물리 신호만 사용, 좌표는 태깅 전용

### Step 4. 낙차/경사 계산 전환 (Phase 1-3)
- [x] **수직낙차**: 런 구간에서 `verticalDrop` 누적
- [x] **경사 계산**: `atan(|verticalSpeed| / horizontalSpeed)`  
  - 저속 구간(예: < 3km/h) 제외
- [x] **드리프트 보정**: 세션 종료 시 drift 범위 확인 후 보정 적용

### Step 5. 로그 기반 튜닝 (Phase 2)
- [ ] **GPS vs Barometer 비교 로그 수집**  
  - 런별 낙차/상승량 편차 기록
- [ ] **임계치 튜닝**  
  - `verticalSpeed` / `recentGain/Drop` 기준 조정
- [ ] **스무딩 윈도우 재조정**  
  - 노이즈 vs 반응성 균형 탐색

### Step 6. 안정화/현장 고정 (Phase 3)
- [ ] **리조트별 파라미터 고정**
- [ ] **리프트 오탐/런 누락 지표 확인**
- [ ] **Feature Flag 기본값 전환**  
  - 성공 기준 충족 시 Barometer 기본 ON

---

## 9) 검증 플랜

- **정확도 테스트**
  - 동일 코스에서 GPS vs Barometer 낙차 편차 비교
- **상태 전환 안정성**
  - 리프트 구간 RESTING 전환 빈도 측정
- **Slope 인식 일관성**
  - OnLift 상태에서 슬로프 오탐지 감소 여부 확인
  - **OnLift → Riding 오탐 방지**: 직진성/방향 분산 필터 적용 여부 확인

### 로그 기반 검증 (필드 테스트 없이)
> 목적: 실사용 전이라도 **상태 전환 안정성/신호 품질**을 정량 점검

**A. 상태 전환 지표**
- **Riding ↔ OnLift 전환 빈도** (시간 대비 전환 횟수)
- **Resting 과다 전환** (짧은 시간 내 Resting 다발 여부)
- **Riding 구간 평균 지속시간/분산** (너무 짧으면 분리 과민 가능성)

**B. 신호 품질 지표**
- **바리오 outlier 제거 횟수/비율**
- **바리오 샘플 누락 구간 길이**
- **바리오 드리프트 보정 누적량** (세션당 보정량 분포)

**C. GPS vs Baro 비교 지표**
- **바리오 누적 낙차 vs GPS 누적 낙차 편차** (상대 비교)
- **경사각(바리오 기반) 평균/분산** (비정상 급증 여부)

**D. 세션/런 구조 지표**
- **런 개수/총 라이딩 시간 대비 런 수 비율**
- **최단 런 길이/최단 런 지속시간** (노이즈 런 필터 동작 확인)

**E. 기준점/드리프트 관련**
- **베이스라인 설정 지연(초기 N샘플 시간)**
- **RESTING 구간 보정 발생 횟수/보정량**

> 로그는 `timestamp, baroAltitude, verticalSpeed, speed, state` 기준으로 추출 가능  
> **세션 종료 시 BarometerLogs JSON 파일로 자동 저장**

---

## 10) 롤백 및 안전장치
- Feature Flag로 Barometer 로직 on/off
- 비지원 기기 또는 센서 오류 시 GPS 로직 자동 폴백

---

## 11) 결론
- Barometer는 **수직 방향 신호의 품질을 근본적으로 개선**할 수 있는 유효한 대안
- 단, **드리프트 보정과 센서 융합 설계**가 핵심
- Shadow Mode → Hybrid → Full 적용의 단계적 도입이 가장 안전한 경로

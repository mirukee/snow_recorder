# 슬로프 인식 알고리즘 및 특이사항 기록

이 문서는 Snow Record 앱의 슬로프 인식 엔진 로직과 특정 슬로프(ZEUS II)의 좌표 분석 결과를 기록합니다.

## 1. 슬로프 인식 알고리즘 (Slope Recognition Logic)

### A. 기본 원리
GPS 좌표가 슬로프의 **다각형(Polygon)** 내부에 포함되는지를 `Ray Casting` 알고리즘으로 1차 판별합니다. 그러나 슬로프가 겹치거나 인접한 경우(교차로, 합류 지점 등) 단순 포함 여부만으로는 정확한 판별이 어렵습니다. 이를 보완하기 위해 **Dwell Time(체류 시간)**과 **Start/Finish(시작/종료) 게이트** 로직을 사용합니다.

### B. 중복 인식 해결 (Dwell Time Logic)
- **개념:** 사용자가 런(Run) 중에 실제로 가장 오래 머물러 있었던 슬로프를 '주행한 슬로프'로 판단합니다.
- **로직:**
    1. `RIDING` 상태에서 매초 GPS 좌표를 수집할 때마다, 해당 좌표가 포함된 모든 슬로프의 '방문 횟수(Counter)'를 증가시킵니다.
    2. 런이 종료(`RESTING` 전환)되면, 방문 횟수가 가장 높은 슬로프를 1순위 후보로 선정합니다.
    3. **노이즈 필터링:** 최대 방문 횟수의 10% 미만인 슬로프(잠깐 스쳐 지나간 경우)는 후보에서 제외합니다.
    4. **우선순위:** 방문 횟수가 비슷할 경우, `면적이 더 작은 슬로프`(더 구체적인 경로)를 우선합니다.

### C. 시작점/도착점 자동 산출 (Start/Finish Point Derivation)
- **목적:** 슬로프의 시작(Top)과 끝(Bottom)을 통과했는지를 확인하여 '완주 여부'를 판단하기 위함.
- **알고리즘 (Altitude-based Logic):**
    1.  **데이터 전처리:** 슬로프 경계 폴리곤의 모든 좌표에 대해 **해발고도(Elevation)** 데이터를 조회합니다.
    2.  **Top Point (시작점):** 경계 좌표 중 **해발고도가 가장 높은 지점**을 시작점으로 정의합니다.
    3.  **Bottom Point (종료점):** 경계 좌표 중 **해발고도가 가장 낮은 지점**을 종료점으로 정의합니다.
    4.  **장점:** 물리적인 중력 방향과 100% 일치하므로 별도의 수동 보정 없이도 정확한 주행 방향(Top -> Bottom)을 판별할 수 있습니다. S자형이나 복잡한 형태의 슬로프에서도 오동작하지 않습니다.

---

## 2. 케이스 스터디: 제우스 2 (ZEUS II) 개선 결과

### A. 기존 문제 상황 (장축 로직)
- **이슈:** 중간에 크게 굽이치는 'S자' 구간으로 인해 기하학적 장축의 끝점이 실제 출발점과 약 192m 오차 발생.
- **결과:** 실제 출발점이 아닌 슬로프 중간 지점이 Start Point로 잡히는 문제.

### B. 고도 기반 로직 적용 결과 (2026-01-23 완료)
- **Start Point:** Index 0 (해발 1337m) - 물리적 최상단
- **Finish Point:** Index 47 부근 (해발 1036m) - 물리적 최하단
- **결과:** Open-Elevation API 데이터를 기반으로 정확한 Start/Finish Point가 설정됨.

---

## 3. 진행률(Progress) 및 고도차(Vertical Drop) 계산

사용자의 현재 위치를 $P_{current}$, 시작점을 $P_{top}$, 종료점을 $P_{bottom}$이라 할 때:

### A. 고도차 (Vertical Drop)
- `Vertical Drop` = $Alt_{top} - Alt_{bottom}$
- 슬로프의 공식적인 제원과 일치하는 수직 낙하 높이입니다.

### B. 진행률 (Progress)
- **계산식:** $Progress(\%) = \frac{Alt_{top} - Alt_{current}}{Alt_{top} - Alt_{bottom}} \times 100$
- **특징:** 수평 거리가 아닌 **고도 변화**를 기준으로 진행률을 표시하여, 활강 스포츠의 특성을 더 잘 반영합니다.

---

## 4. 필드테스트 분석 결과 (2026-01-23)

> 실제 현장 테스트에서 발견된 이슈와 개선 방안을 기록합니다.

---

### Session 1: 밸리 → 제우스 리프트 → 헤라 리프트 → HERA II

#### 테스트 경로
1. 밸리 스키하우스 출발
2. 제우스 리프트 탑승 → 밸리허브 하차
3. 도보 이동 → 헤라 리프트 탑승 → 마운틴탑 도착
4. HERA II 슬로프 라이딩

#### 🐛 Issue #1: 리프트 상공 슬로프 오탐지
| 항목 | 내용 |
|------|------|
| **현상** | 제우스 리프트로 ZEUS III 상공 통과 시, 실제 라이딩하지 않았음에도 ZEUS III가 기록됨 |
| **원인** | `LocationManager.swift` Line 414-426에서 슬로프 인식이 **상태(ON_LIFT/RIDING)와 무관하게** 실행됨. `currentSlope` 업데이트가 ON_LIFT에서도 발생하고, 리프트 하차 직후 RIDING 판정 순간에 폴리곤 내부로 감지 |
| **영향 코드** | `if shouldCheckSlope(at: newLocation) { ... }` |
| **해결 방안** | 슬로프 인식을 RIDING 상태에서만 수행하도록 조건 추가 |

```diff
- if shouldCheckSlope(at: newLocation) {
+ if currentState == .riding, shouldCheckSlope(at: newLocation) {
```

#### 🐛 Issue #2: 리프트 탑승 초기 속도 0 표시
| 항목 | 내용 |
|------|------|
| **현상** | 리프트 탑승 후 **15초 이상** 속도가 0으로 표시됨 |
| **추정 원인** | GPS 정확도 변경 시 위치 업데이트 지연, 또는 `CLLocation.speed`가 정지→이동 시 초기화되는 iOS 동작 |
| **해결 방안** | 추가 분석 필요 (세션 로그 확인) |

---

### Session 2: 헤라 리프트 탑승 중 상태 전환 오류

#### 테스트 경로
- 헤라 리프트 탑승 중

#### GPX 파일
- `testdata/SR_S2.gpx` - Snow Record 앱 기록
- `testdata/Slopes_S2.gpx` - Slopes 앱 기록 (고도/속도 정보 포함)

#### 🐛 Issue #3: 리프트 탑승 중 불규칙한 RESTING 전환
| 항목 | 내용 |
|------|------|
| **현상** | 리프트(ON_LIFT) 상태에서 슬로프 상공 통과 시 갑자기 RESTING으로 전환됨 |
| **원인** | `LocationManager.swift` Line 257-261의 ON_LIFT → RESTING 조건 문제 |
| **조건** | `currentSpeedKmH < pauseSpeedThreshold && !isNearLift` |

**근본 원인 분석:**
1. **속도 0 문제**: Slopes 앱 GPX에서 리프트 탑승 중 `speed=0.000000`이 빈번하게 발생 (약 5초마다)
2. **isNearLift 판정**: 리프트 라인 좌표가 불완전하거나, 슬로프 영역 통과 시 리프트 라인 버퍼에서 이탈
3. **결과**: 속도 0 + 리프트 라인 이탈 → RESTING 전환

#### 🐛 Issue #4: 슬로프 이탈 시 RESTING 전환 (추가 보고)
| 항목 | 내용 |
|------|------|
| **현상** | 리프트 탑승 중 슬로프 영역 밖으로 나가면 다시 RESTING으로 전환 |
| **원인** | Session 2 Issue #3과 동일한 로직 문제 |

#### 상세 분석 (Slopes GPX 기반)

Slopes_S2.gpx에서 속도가 0이 되는 지점들:
```
14:42:04 - speed=0.000000 (alt: 1003m)
14:43:20 - speed=0.000000 (alt: 1004m)
14:43:25 - speed=0.000000 (alt: 1012m, 갑자기 고도 상승)
14:44:08 - speed=0.000000 (alt: 1047m)
14:45:15 - speed=0.000000 (alt: 1089m)
... (이후 계속)
```
→ 리프트 상승 중에도 iOS가 GPS 속도를 0으로 보고하는 경우가 많음

#### 해결 방안 (제안)
```swift
case .onLift:
    // ON_LIFT → RESTING: 더 엄격한 조건 필요
    // 방안 1: 상승이 멈춰야 함 (!isClimbing)
    // 방안 2: 일정 시간 이상 정지 유지 (현재 debounce 5초, 더 늘릴 필요)
    // 방안 3: 고도 변화가 없어야 함 (플랫한 구간)
    if currentSpeedKmH < pauseSpeedThreshold 
       && !isNearLift 
       && !isClimbing  // 추가 조건
       && altitudeChangeRate < 0.5 {  // 추가 조건
        if canChangeState() {
            return .resting
        }
    }
```

---

### Session 3: 헤라 리프트 - 초기 RESTING 후 정상 ON_LIFT 인식

#### 테스트 경로
- 헤라 리프트 탑승 (전체 구간)

#### GPX 파일
- `testdata/SR_S3.gpx` - Snow Record 앱 기록

#### 관찰된 동작
| 구간 | 예상 시간 | 동작 | 상태 |
|------|-----------|------|------|
| 리프트 0~30% | 06:09:13 ~ 06:12:39 | 속도 0으로 인식 | ❌ RESTING 유지 |
| 리프트 30~100% | 06:12:44 ~ 06:25:31 | 정상 속도 감지 | ✅ ON_LIFT 인식 |
| 슬로프 상공 통과 | 중반 | RESTING 전환 없음 | ✅ ON_LIFT 유지 |

#### 분석

**Session 2와의 차이점:**
- Session 2: 슬로프 상공에서 RESTING 전환됨
- Session 3: 슬로프 상공에서도 ON_LIFT 유지됨

**추정 원인:**
1. `isClimbing` 조건이 Session 3에서는 **지속적으로 true**였을 가능성
2. Session 2에서는 속도 0이 빈번하고 + `canChangeState()` debounce 통과
3. Session 3에서는 속도가 어느 정도 유지되어 debounce 리셋

**GPX 패턴 분석:**
```
06:09:13~06:12:39 (약 3분 30초): 37.1833xx → 37.1837xx
   → 이동 거리 매우 짧음, 속도 감지 안됨 (RESTING 유지)

06:12:44 이후: 빠르게 북쪽으로 이동 시작
   → isClimbing 조건 충족, ON_LIFT 진입
   → 이후 속도가 유지되어 RESTING 전환 안됨
```

#### 🐛 Issue #5: 리프트 초기 구간 RESTING 유지
| 항목 | 내용 |
|------|------|
| **현상** | 리프트 탑승 후 약 30% 구간(3분 30초)까지 RESTING으로 유지됨 |
| **원인** | `isClimbing` 조건이 10초간 8m 이상 상승 필요 → 리프트 가속 전까지 충족 안됨 |
| **영향** | 리프트 초반 구간이 기록에서 누락됨 |

#### 해결 방안 (제안)
```swift
// isClimbing 조건 완화
// 현재: 10초간 8m 이상 상승 (0.8m/s)
// 제안: 15초간 5m 이상 상승 (0.33m/s) - 리프트 저속 구간 대응
let isClimbing: Bool
if let first = altitudeHistory.first, let last = altitudeHistory.last, altitudeHistory.count >= 15 {
    isClimbing = (last - first) > 5.0
} else {
    isClimbing = false
}
```

---

### Session 4: 헤라 리프트 → HERA II → HERA I → ZEUS III (정상 동작)

#### 테스트 경로
```
1. 헤라 리프트 탑승
2. HERA II 슬로프 라이딩
3. 헤라 리프트 다시 탑승
4. HERA I 슬로프 라이딩
5. ZEUS III 슬로프 라이딩
6. 밸리 스키하우스 도착
```

#### GPX 파일
- `testdata/SR_S4.gpx` - Snow Record 앱 기록 (3:30~4:00 PM)
- `testdata/Slopes_S4.gpx` - Slopes 앱 기록

#### 앱 인식 결과
| 항목 | 결과 | 비고 |
|------|------|------|
| 슬로프 인식 | ✅ HERA I, HERA II, ZEUS III 모두 정상 인식 | |
| 런 분리 | ✅ 정상 | 3개 런 각각 분리됨 |
| Max Speed | 44.4 km/h | |
| Distance | 5056m | (합계) |
| Vertical Drop | 853m | (합계) |

> � **참고**: GPX 파일 메타데이터에는 "ZEUS III"만 표시되지만, 이는 내보내기 시 마지막 슬로프 이름이 사용된 것. 실제 앱에서는 모든 슬로프가 정상 인식됨.

#### Slopes GPX 비교
- 리프트 구간에서 속도 0이 여전히 빈번 (`speed="0.000000"`)
- 고도: 999m → 1342m 상승 (리프트 구간 약 343m 상승)

#### 🔍 관찰: 세션 간 일관성 비교
| 세션 | 리프트 상공 오탐지 | RESTING 전환 | 슬로프 인식 | 비고 |
|------|-------------------|--------------|-------------|------|
| S1 | ❌ ZEUS III 오탐지 | - | - | Issue #1 |
| S2 | - | ❌ 불규칙 전환 | - | Issue #3 |
| S3 | ✅ 정상 | ❌ 초기 30% RESTING | ✅ 정상 | Issue #5 |
| S4 | ✅ 정상 | ✅ 정상 | ✅ 정상 | **정상 동작** |

**분석 결론:**
- Session 4는 모든 기능이 **정상 동작**
- 동일한 리프트/슬로프에서도 세션마다 다른 결과 → **타이밍/GPS 상태에 따른 레이스 컨디션** 존재 가능성


---

## 5. 필드테스트 결과 및 최종 해결 (2026-01-23)

총 4개 세션 데이터(S1~S4) 분석을 통해 발견된 5가지 핵심 이슈를 모두 해결했습니다.

### 📊 해결된 이슈 목록 (LocationManager.swift 적용 완료)

| ID | 문제 현상 | 원인 | **최종 해결책 (적용됨)** |
|:---:|---|---|---|
| **#1** | **리프트 상공 오탐지**<br>(S1: ZEUS III) | 리프트 이동 중에도 슬로프 영역 체크가 동작하여, 슬로프 상공 통과 시 라이딩으로 인식 | **인식 차단**: `currentState == .riding`일 때만 슬로프 인식(`findSlope`)을 수행하도록 변경 |
| **#3**<br>**#4** | **리프트 중단 RESTING**<br>(S2: HERA) | 리프트 좌표 데이터 부재로 `isNearLift`가 `false`가 되어, 속도 0 또는 영역 이탈 시 즉시 휴식 처리 | **조건 강화**: `!isNearLift` 조건 제거, 대신 **`!isClimbing` (상승 중이 아님)** 조건을 추가하여 물리적 상승 시 상태 유지 |
| **#5** | **리프트 초기 인식 지연**<br>(S3: HERA) | 리프트 초반 저속 구간에서 상승 감지 기준(8m) 미달로 3분간 `RESTING` 유지 | **임계값 완화**: 상승 감지 기준을 `10초간 8m` → **`5m`**로 완화하여 초기 감지력 향상 |
| **New**| **리프트 탈출 오인식**<br>(사용자 피드백) | 리프트의 일시적 하강(꿀렁임) 시 `RIDING`으로 잘못 전환될 우려 | **강력한 하강 조건**: `ON_LIFT` → `RIDING` 전환 시 **`10초간 5m 이상 하강`** 조건을 필수 적용 (초보자 인식 가능 + 오작동 방지) |

### 🛠️ 최종 로직 요약

#### A. 리프트 탑승 감지 (`isClimbing`)
> "10초 동안 5m 이상 수직 상승하면 리프트다."
- 기존 8m에서 5m로 완화하여 저속 리프트/초기 구간 감지력 향상

#### B. 리프트 상태 유지 (`ON_LIFT`)
> "상승 중(`isClimbing`)이라면 절대 휴식(`RESTING`)으로 떨어지지 않는다."
- 좌표 데이터가 없어도 고도 변화만으로 리프트 상태를 견고하게 유지

#### C. 리프트 탈출 감지 (`isStrongDescent`)
> "리프트에서 내려서 10초 동안 5m 이상 확실하게 내려가야 라이딩(`RIDING`)이다."
- 단순 하강(1.5m)이 아닌 강력한 하강(5m)을 요구하여, 리프트 탑승 중 슬로프 상공을 지나갈 때의 오인식 원천 차단

---
    LiftLine(name: "ZEUS EXPRESS", koreanName: "제우스 익스프레스", path: []),           // ❌ 빈 배열
    LiftLine(name: "VICTORIA EXPRESS", koreanName: "빅토리아 익스프레스", path: []),     // ❌ 빈 배열
    LiftLine(name: "APOLLO EXPRESS", koreanName: "아폴로 익스프레스", path: []),         // ❌ 빈 배열
    LiftLine(name: "HERA EXPRESS", koreanName: "헤라 익스프레스", path: [])              // ❌ 빈 배열
]
```

### isNear() 함수 동작

```swift
func isNear(_ coordinate: CLLocationCoordinate2D) -> Bool {
    guard !path.isEmpty else { return false }  // 빈 배열 → 항상 false!
    // ...
}
```

**결과:** `isNearLift`는 현재 **항상 `false`**를 반환!

### 영향 받는 로직

| 위치 | 조건문 | 현재 동작 |
|------|--------|-----------|
| Line 218 (RESTING → ON_LIFT) | `isNearLift && altitudeChange < -1.0` | 좌측 조건 무조건 false, **isClimbing만으로 판정** |
| Line 258 (ON_LIFT → RESTING) | `currentSpeedKmH < 3 && !isNearLift` | `!isNearLift`가 항상 true, **속도만으로 판정** |

### 문제 시나리오

```
1. 리프트 탑승 시작
   → isClimbing=true로 ON_LIFT 진입 ✅

2. 리프트 탑승 중 속도 0 발생 (iOS GPS 특성)
   → currentSpeedKmH < 3 ✅
   → !isNearLift = true ✅ (좌표가 없으므로)
   → canChangeState() ✅ (5초 debounce 통과)
   → RESTING 전환! ❌

3. 다시 속도 감지되면 isClimbing으로 ON_LIFT 진입
   → 반복...
```

### 해결 방안

**Option 1: 리프트 좌표 데이터 입력 (정공법)**
- GPX 데이터를 기반으로 리프트 경로 좌표 추출
- 가장 정확하지만 수작업 필요

**Option 2: isNearLift 조건 제거 (임시)**
```swift
// ON_LIFT → RESTING 조건 변경
if currentSpeedKmH < pauseSpeedThreshold && !isClimbing {  // isNearLift 제거
    if canChangeState() {
        return .resting
    }
}
```

**Option 3: debounce 시간 증가 (보완)**
- 현재 5초 → 15~20초로 증가
- 리프트 정차 시간(철탑 통과 등)을 버틸 수 있도록

---

## 6. 개선 방안 Pool (미적용)

> 필드테스트 완료 후 종합적으로 검토하여 적용 예정

### A. ON_LIFT 상태 슬로프 인식 차단 (우선순위: 높음)
- **적용 위치:** `LocationManager.swift` Line 414
- **효과:** 리프트 탑승 중 모든 슬로프 인식/Dwell Time 카운트 차단

### B. 고도 기반 리프트 필터링 (중간)
- 리프트는 슬로프보다 높은 고도에서 이동
- 슬로프의 `topAltitude`보다 높으면 인식 제외
```swift
if newLocation.altitude < slope.topAltitude + 20 { // 20m 여유
    // 슬로프 인식 허용
}
```

### C. 최소 런 시간/Dwell Time 임계값 상향 (낮음)
- 현재: 10% 미만 필터링
- 제안: 20% 미만 또는 최소 5회 이상 방문

### D. 속도 기반 Dwell Time 필터링 (낮음)
- 15 km/h 미만 속도로 슬로프 통과 시 카운트 제외

### E. ON_LIFT → RESTING 조건 강화 (높음, 신규)
- `!isNearLift` 조건 제거 또는 `!isClimbing` 조건 추가
- debounce 시간 5초 → 15초 이상 증가

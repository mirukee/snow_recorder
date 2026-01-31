# 로컬라이제이션 키맵 v1 (KO/EN)

## 기준
- 1차 지원: 한국어/영어
- 라벨(짧은 스탯/태그)은 영어 유지
- 문장형/설명/에러/가이드/CTA는 로컬라이즈
- 각 키는 Localizable.strings에서 **한국어 원문 주석** 유지
- **현재 앱에 이미 영어로 표시되는 문자열은 목록에서 제외**

---

## 로컬라이즈 대상 (한국어가 원문인 문자열)
> 아래 키는 한국어/영어 모두 제공. 한국어 원문은 주석으로 남김.

| Key | 한국어 (원문) | English | 위치 |
|---|---|---|---|
| login.guest_mode | 게스트 모드(기록만 하기) | Guest Mode (Record only) | `snow_recorder/Views/LoginView.swift` |
| history.delete | 삭제하기 | Delete | `snow_recorder/HistoryView.swift` |
| dashboard.wait_first_run | 첫 런을 기다리는 중... | Waiting for your first run... | `snow_recorder/DashboardView.swift` |
| ranking.tech_guide_title | 테크니컬 스코어 가이드 | Technical Score Guide | `snow_recorder/RankingView.swift` |
| ranking.tech_guide_body | [EDGE SCORE]\n"얼마나 날카롭게 베고 나갔는가?"\n당신의 턴이 설면을 얼마나 견고하게 파고들었는지 분석한 '카빙(Carving) 완성도' 지표입니다.\n- 분석 기준: 턴의 깊이, 엣징 각도(G-Force), 슬립 최소화\n\n[FLOW SCORE]\n"얼마나 물 흐르듯 내려왔는가?"\n주행의 리듬과 속도 유지를 분석한 '주행 안정성(Smoothness)' 지표입니다.\n- 분석 기준: 속도 유지력, 턴 연결의 부드러움, 급제동 여부 | [EDGE SCORE]\n"How sharply did you carve?"\nA carving-completion metric that analyzes how firmly your turns cut into the snow.\n- Criteria: turn depth, edge angle (G-Force), minimal slip\n\n[FLOW SCORE]\n"How smoothly did you flow down?"\nA stability metric that analyzes rhythm and speed maintenance.\n- Criteria: speed retention, smooth turn linking, hard braking | `snow_recorder/RankingView.swift` |
| ranking.tech_guide_ok | 확인 | OK | `snow_recorder/RankingView.swift` |
| ranking.sync_pending | SYNC PENDING | SYNC PENDING | `snow_recorder/RankingView.swift` |
| ranking.guest_title | 랭킹 잠김 | RANKING LOCKED | `snow_recorder/RankingView.swift` |
| ranking.guest_body | 로그인 후 리더보드에 참여할 수 있어요. | Sign in to participate in the leaderboard. | `snow_recorder/RankingView.swift` |
| ranking.sync_help_title | SYNC HELP | SYNC HELP | `snow_recorder/RankingView.swift` |
| ranking.sync_help_body | 리더보드 수치는 서버 집계 및 동기화 타이밍에 따라 지연될 수 있습니다.\n세션 삭제/편집 후에는 로컬 수치가 먼저 반영되고, 서버 반영은 지연될 수 있어요.\nSYNC PENDING은 아직 서버에 반영되지 않은 변경이 있다는 뜻입니다. | Leaderboard values may be delayed depending on server aggregation and sync timing.\nAfter deleting/editing sessions, local values update first and server values may lag.\nSYNC PENDING means changes haven't been synced to the server yet. | `snow_recorder/RankingView.swift` |
| ranking.sync_help_ok | 확인 | OK | `snow_recorder/RankingView.swift` |
| settings.legal | 법적 문서 | LEGAL | `snow_recorder/ProfileView.swift` |
| settings.title | 설정 | Settings | `snow_recorder/ProfileView.swift` |
| settings.done | 완료 | Done | `snow_recorder/ProfileView.swift` |
| settings.section_privacy_competition | 프라이버시 & 랭킹 | PRIVACY & COMPETITION | `snow_recorder/ProfileView.swift` |
| settings.ranking_participate_title | 랭킹 참여 | Participate in Ranking | `snow_recorder/ProfileView.swift` |
| settings.ranking_participate_desc | 주행 기록을 리더보드에 자동 업로드합니다. | Upload your runs to the leaderboard automatically. | `snow_recorder/ProfileView.swift` |
| settings.section_backup | 백업 (iCloud) | BACKUP (ICLOUD) | `snow_recorder/ProfileView.swift` |
| settings.backup_last_label | 마지막 백업 | LAST BACKUP | `snow_recorder/ProfileView.swift` |
| settings.backup_now | 지금 백업 | BACKUP NOW | `snow_recorder/ProfileView.swift` |
| settings.restore_overwrite | 복원 (덮어쓰기) | RESTORE (OVERWRITE) | `snow_recorder/ProfileView.swift` |
| settings.section_language | 언어 | LANGUAGE | `snow_recorder/ProfileView.swift` |
| settings.language_label | 언어 | Language | `snow_recorder/ProfileView.swift` |
| settings.language_system | 시스템 | System | `snow_recorder/ProfileView.swift` |
| settings.language_ko | 한국어 | Korean | `snow_recorder/ProfileView.swift` |
| settings.language_en | 영어 | English | `snow_recorder/ProfileView.swift` |
| settings.section_app_info | 앱 정보 | APP INFO | `snow_recorder/ProfileView.swift` |
| settings.app_version | 버전 | Version | `snow_recorder/ProfileView.swift` |
| settings.section_debug | 디버그 | DEBUG | `snow_recorder/ProfileView.swift` |
| settings.debug_force_nonpro_title | 비구독 강제 | Force Non-Pro | `snow_recorder/ProfileView.swift` |
| settings.debug_force_nonpro_desc | 구독 여부와 상관없이 비구독 상태로 강제 전환 | Force non-subscription status regardless of subscription. | `snow_recorder/ProfileView.swift` |
| settings.backup_sessions_format | SESSIONS %d | SESSIONS %d | `snow_recorder/ProfileView.swift` |
| settings.backup_none | 없음 | NONE | `snow_recorder/ProfileView.swift` |
| profile.restore_title | 기존 기록을 모두 덮어쓸까요? | Overwrite all existing records? | `snow_recorder/ProfileView.swift` |
| profile.restore_message | 현재 기기 기록이 전부 삭제되고 iCloud 백업으로 복원됩니다. | All records on this device will be deleted and restored from your iCloud backup. | `snow_recorder/ProfileView.swift` |
| profile.restore_cancel | 취소 | Cancel | `snow_recorder/ProfileView.swift` |
| profile.restore_confirm | 덮어쓰기 | Overwrite | `snow_recorder/ProfileView.swift` |
| profile.backup_load_fail | 백업 정보를 불러오지 못했습니다. | Failed to load backup information. | `snow_recorder/ProfileView.swift` |
| profile.backup_fail | 백업에 실패했습니다. | Backup failed. | `snow_recorder/ProfileView.swift` |
| profile.restore_fail | 복원에 실패했습니다. | Restore failed. | `snow_recorder/ProfileView.swift` |
| profile.mvp_later | MVP 이후 업데이트 예정 | Planned after MVP. | `snow_recorder/ProfileView.swift` |
| run_detail.edge_desc | "얼마나 날카롭게 베고 나갔는가?" ... | "How sharply did you carve?" ... | `snow_recorder/RunDetailView.swift` |
| run_detail.flow_desc | "얼마나 물 흐르듯 내려왔는가?" ... | "How smoothly did you flow down?" ... | `snow_recorder/RunDetailView.swift` |
| paywall.headline_go_pro | PRO 시작: | GO PRO: | `snow_recorder/PaywallView.swift` |
| paywall.headline_unlock_potential | 잠재력 해제 | UNLOCK POTENTIAL | `snow_recorder/PaywallView.swift` |
| paywall.subtitle | 고급 텔레메트리, 무제한 동기화,\n프로급 분석 도구. | Advanced telemetry, unlimited sync,\nand pro-grade analysis tools. | `snow_recorder/PaywallView.swift` |
| paywall.purchase_fail_title | 결제 실패 | Purchase Failed | `snow_recorder/PaywallView.swift` |
| profile.nickname_cooldown_title | 닉네임 변경 제한 | Nickname cooldown | `snow_recorder/Views/EditProfileView.swift` |
| profile.nickname_cooldown_ok | 확인 | OK | `snow_recorder/Views/EditProfileView.swift` |
| profile.nickname_cooldown_remaining_format | 다음 변경까지 %d일 남았어요. | You can change again in %d days. | `snow_recorder/Views/EditProfileView.swift` |
| profile.nickname_cooldown_alert_remaining_format | %d일 후에 다시 변경할 수 있어요. | You can change your nickname again in %d days. | `snow_recorder/Views/EditProfileView.swift` |
| profile.nickname_cooldown_alert_fallback | 닉네임은 한 달에 한 번만 변경할 수 있어요. | You can change your nickname once per month. | `snow_recorder/Views/EditProfileView.swift` |
| profile.featured_badges_empty | 획득한 뱃지가 없어요. | No badges earned yet. | `snow_recorder/Views/EditProfileView.swift` |
| profile.featured_badges_limit_title | 선택 제한 | Selection limit | `snow_recorder/Views/EditProfileView.swift` |
| profile.featured_badges_limit_ok | 확인 | OK | `snow_recorder/Views/EditProfileView.swift` |
| profile.featured_badges_limit_message | 최대 3개까지 선택할 수 있어요. | You can select up to 3 badges. | `snow_recorder/Views/EditProfileView.swift` |
| profile.featured_badges_cooldown_title | 뱃지 변경 제한 | Badge cooldown | `snow_recorder/Views/EditProfileView.swift` |
| profile.featured_badges_cooldown_remaining_format | 다음 변경까지 %d일 남았어요. | Next change in %d days. | `snow_recorder/Views/EditProfileView.swift` |
| profile.featured_badges_cooldown_alert_remaining_format | %d일 후에 다시 변경할 수 있어요. | You can change featured badges again in %d days. | `snow_recorder/Views/EditProfileView.swift` |
| profile.featured_badges_cooldown_fallback | 뱃지는 하루에 한 번만 변경할 수 있어요. | Featured badges can be changed once per day. | `snow_recorder/Views/EditProfileView.swift` |
| paywall.alert_ok | 확인 | OK | `snow_recorder/PaywallView.swift` |
| paywall.purchase_fail_default | 예기치 못한 오류가 발생했습니다. | An unexpected error occurred. | `snow_recorder/PaywallView.swift` |
| paywall.restore | 복원 | RESTORE | `snow_recorder/PaywallView.swift` |
| paywall.feature_ai_analysis | AI 퍼포먼스\n분석 | AI PERFORMANCE\nANALYSIS | `snow_recorder/PaywallView.swift` |
| paywall.feature_3d_replay | 3D 맵\n리플레이 | 3D MAP\nREPLAY | `snow_recorder/PaywallView.swift` |
| paywall.feature_flex_cards | 프리미엄\n플렉스 카드 | PREMIUM\nFLEX CARDS | `snow_recorder/PaywallView.swift` |
| paywall.feature_sync | 무제한\n데이터 동기화 | UNLIMITED\nDATA SYNC | `snow_recorder/PaywallView.swift` |
| paywall.footer_social_proof | 10,000+ Pro 라이더 • 언제든 해지 가능 | Join 10,000+ Pro Riders • Cancel anytime | `snow_recorder/PaywallView.swift` |
| paywall.terms | 이용약관 | Terms of Service | `snow_recorder/PaywallView.swift` |
| paywall.privacy | 개인정보 처리방침 | Privacy Policy | `snow_recorder/PaywallView.swift` |
| paywall.cta_forever | 평생 이용권 잠금 해제 | UNLOCK FOREVER | `snow_recorder/PaywallView.swift` |
| paywall.cta_trial_format | %@ 무료 체험 시작 | START %@ FREE TRIAL | `snow_recorder/PaywallView.swift` |
| paywall.cta_start_pro | PRO 시작 | START PRO | `snow_recorder/PaywallView.swift` |
| paywall.trial_day_format | %d일 | %d-DAY | `snow_recorder/PaywallView.swift` |
| paywall.trial_week_format | %d주 | %d-WEEK | `snow_recorder/PaywallView.swift` |
| paywall.trial_month_format | %d개월 | %d-MONTH | `snow_recorder/PaywallView.swift` |
| paywall.trial_year_format | %d년 | %d-YEAR | `snow_recorder/PaywallView.swift` |
| paywall.billing_monthly | 월간 결제 | Billed monthly | `snow_recorder/PaywallView.swift` |
| paywall.billing_lifetime | 1회 결제 | One-time payment | `snow_recorder/PaywallView.swift` |
| paywall.billing_yearly_format | 연간 결제 %@ | Billed yearly %@ | `snow_recorder/PaywallView.swift` |

---

## 배지 설명(이름 제외)
> 배지 타이틀은 영어 고정, 설명만 로컬라이즈.

| Key | 한국어 (원문) | English | 위치 |
|---|---|---|---|
| badge.desc.first_steps | 첫 번째 런을 완료하세요. | Complete your first run. | `snow_recorder/Services/GamificationService.swift` |
| badge.desc.marathoner | 총 100km를 주행하세요. | Ski a total of 100km. | `snow_recorder/Services/GamificationService.swift` |
| badge.desc.speed_demon | 최고 속도 80km/h에 도달하세요. | Reach a speed of 80km/h. | `snow_recorder/Services/GamificationService.swift` |
| badge.desc.century_club | 100런을 완주하세요. | Complete 100 runs. | `snow_recorder/Services/GamificationService.swift` |
| badge.desc.everest | 총 하강고도 8,848m를 달성하세요. | Ski 8,848m vertical drop. | `snow_recorder/Services/GamificationService.swift` |
| badge.desc.high_flyer | 총 하강고도 20,000m를 달성하세요. | Ski 20,000m vertical drop. | `snow_recorder/Services/GamificationService.swift` |
| badge.desc.early_bird | 오전 9시 이전에 출발하세요. | Start skiing before 9 AM. | `snow_recorder/Services/GamificationService.swift` |
| badge.desc.night_owl | 오후 7시 이후에 주행하세요. | Ski after 7 PM. | `snow_recorder/Services/GamificationService.swift` |
| badge.desc.safe_rider | 크래시 없이 10회 기록하세요. | Record 10 sessions without crashing. | `snow_recorder/Services/GamificationService.swift` |

---

## 권한 요청 메시지 (InfoPlist.strings)
> `InfoPlist.strings`로 분리하여 KO/EN에서 직접 수정.

| Key | 한국어 (원문) | English | 위치 |
|---|---|---|---|
| NSLocationWhenInUseUsageDescription | 스키/보드 활강 기록을 위해 위치 권한이 필요합니다. | We need location access to record your ski/snowboard runs. | `ko.lproj/InfoPlist.strings` / `en.lproj/InfoPlist.strings` |
| NSLocationAlwaysAndWhenInUseUsageDescription | 앱이 백그라운드 상태일 때도 활강 경로를 정확히 기록하기 위해 위치 권한이 필요합니다. | We need location access in the background to accurately record your run path. | `ko.lproj/InfoPlist.strings` / `en.lproj/InfoPlist.strings` |
| NSMotionUsageDescription | 활강 분석 및 주행 점수 계산을 위해 모션 데이터가 필요합니다. | We need motion data for run analysis and scoring. | `ko.lproj/InfoPlist.strings` / `en.lproj/InfoPlist.strings` |
| NSPhotoLibraryAddUsageDescription | 공유 이미지를 사진 앨범에 저장하기 위해 권한이 필요합니다. | We need photo access to save share images to your library. | `ko.lproj/InfoPlist.strings` / `en.lproj/InfoPlist.strings` |

---

## 영어 고정 라벨(로컬라이즈 제외)
> 스탯/짧은 태그/브랜드 라벨로 영어 고정 유지.

- 브랜드/로고: `SNOW RECORD`, `SNOW RECORD™`
- 스탯 라벨: `MAX SPEED`, `AVG SPEED`, `DISTANCE`, `RUNS`, `VERT DROP`, `EDGE`, `FLOW`, `EDGE SCORE`, `FLOW SCORE`, `PTS`, `KM/H`, `KM`, `M`
- 상태/탭 라벨: `RIDING`, `LIFT`, `REST`, `PAUSE`, `UNKNOWN`
- 섹션 태그: `RUN STATS`, `LEADERBOARD`, `PERSONAL STATS`, `MY BADGES`, `EARNED BADGES`, `BADGE COLLECTION`

import Foundation
import CoreLocation

private func localizedLabel(key: String, fallback: String) -> String {
    let preferred = UserDefaults.standard.string(forKey: "preferred_language") ?? "system"
    let locale: Locale
    switch preferred {
    case "ko":
        locale = Locale(identifier: "ko")
    case "en":
        locale = Locale(identifier: "en")
    default:
        locale = Locale.autoupdatingCurrent
    }
    let value = String(localized: .init(key), locale: locale)
    return value.isEmpty ? fallback : value
}

private func preferredName(ko: String, en: String) -> String {
    let preferred = UserDefaults.standard.string(forKey: "preferred_language") ?? "system"
    switch preferred {
    case "ko":
        return ko
    case "en":
        return en
    default:
        return Locale.autoupdatingCurrent.languageCode == "en" ? en : ko
    }
}

/// 슬로프 난이도
enum SlopeDifficulty: String, Codable {
    case beginner = "초급"
    case intermediate = "중급"
    case advancedIntermediate = "중상급"
    case advanced = "상급"
    case expert = "최상급"

    var displayLabel: String {
        switch self {
        case .beginner:
            return localizedLabel(key: "slope.difficulty.beginner", fallback: "초급")
        case .intermediate:
            return localizedLabel(key: "slope.difficulty.intermediate", fallback: "중급")
        case .advancedIntermediate:
            return localizedLabel(key: "slope.difficulty.advanced_intermediate", fallback: "중상급")
        case .advanced:
            return localizedLabel(key: "slope.difficulty.advanced", fallback: "상급")
        case .expert:
            return localizedLabel(key: "slope.difficulty.expert", fallback: "최상급")
        }
    }
    
    /// 색상 표시용 (UI에서 사용)
    var colorHex: String {
        switch self {
        case .beginner: return "#00FF00"            // 초록
        case .intermediate: return "#0000FF"        // 파랑
        case .advancedIntermediate: return "#FF8C00" // 주황
        case .advanced: return "#FF0000"            // 빨강
        case .expert: return "#000000"              // 검정
        }
    }
    /// 우선순위 (높을수록 먼저 체크)
    var priority: Int {
        switch self {
        case .expert: return 5
        case .advanced: return 4
        case .advancedIntermediate: return 3
        case .intermediate: return 2
        case .beginner: return 1
        }
    }
}

/// 슬로프 운영 상태
enum SlopeStatus: String, Codable {
    case operating = "운영중"
    case closed = "미운영"
    case seasonal = "시즌운영"  // 특정 시즌만 운영

    var displayLabel: String {
        switch self {
        case .operating:
            return localizedLabel(key: "slope.status.operating", fallback: "운영중")
        case .closed:
            return localizedLabel(key: "slope.status.closed", fallback: "미운영")
        case .seasonal:
            return localizedLabel(key: "slope.status.seasonal", fallback: "시즌운영")
        }
    }
}

/// 슬로프 정보 모델 (폴리곤 기반)
struct Slope: Identifiable {
    let id = UUID()
    let name: String                            // 슬로프 이름 (예: ZEUS I)
    let koreanName: String                      // 한글 이름 (예: 제우스 1)
    let difficulty: SlopeDifficulty             // 난이도
    let length: Double                          // 길이 (m)
    let avgGradient: Double                     // 평균 경사도 (°)
    let maxGradient: Double                     // 최대 경사도 (°)
    let status: SlopeStatus                     // 운영 상태
    var boundary: [CLLocationCoordinate2D]      // 슬로프 경계 폴리곤
    var topPoint: CLLocationCoordinate2D?       // 정상 지점 (자동 산출)
    var bottomPoint: CLLocationCoordinate2D?    // 하단 지점 (자동 산출)
    var topAltitude: Double?                    // 정상 해발고도 (m)
    var bottomAltitude: Double?                 // 하단 해발고도 (m)

    var displayName: String {
        preferredName(ko: koreanName, en: name)
    }
    
    /// 주어진 좌표가 슬로프 폴리곤 내부에 있는지 확인 (Ray Casting 알고리즘)
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard boundary.count >= 3 else { return false }
        
        var isInside = false
        let n = boundary.count
        var j = n - 1
        
        for i in 0..<n {
            let xi = boundary[i].latitude
            let yi = boundary[i].longitude
            let xj = boundary[j].latitude
            let yj = boundary[j].longitude
            
            if ((yi > coordinate.longitude) != (yj > coordinate.longitude)) &&
               (coordinate.latitude < (xj - xi) * (coordinate.longitude - yi) / (yj - yi) + xi) {
                isInside = !isInside
            }
            j = i
        }
        return isInside
    }
    /// 폴리곤 면적 계산 (Shoelace Formula) - 대략적인 크기 비교용
    var polygonArea: Double {
        guard boundary.count >= 3 else { return Double.greatestFiniteMagnitude }
        
        var area: Double = 0
        let n = boundary.count
        var j = n - 1
        
        for i in 0..<n {
            let p1 = boundary[i]
            let p2 = boundary[j]
            area += (p2.longitude + p1.longitude) * (p2.latitude - p1.latitude)
            j = i
        }
        return abs(area / 2.0)
    }
}

/// 리프트 정보
struct LiftLine: Identifiable {
    let id = UUID()
    let name: String                            // 리프트 이름
    let koreanName: String                      // 한글 이름
    var path: [CLLocationCoordinate2D]          // 리프트 경로 좌표들 (TODO: 좌표 입력 필요)
    let bufferRadius: CLLocationDistance = 30.0 // 리프트 라인으로 인식할 반경 (m)

    var displayName: String {
        preferredName(ko: koreanName, en: name)
    }
    
    /// 주어진 좌표가 리프트 라인 근처인지 확인
    func isNear(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard !path.isEmpty else { return false }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        for point in path {
            let pathLocation = CLLocation(latitude: point.latitude, longitude: point.longitude)
            if location.distance(from: pathLocation) <= bufferRadius {
                return true
            }
        }
        return false
    }
}

/// 하이원 리조트 슬로프 데이터베이스
/// 공식 데이터 기반 - 좌표는 추후 입력 필요
class SlopeDatabase {
    static let shared = SlopeDatabase()
    
    // MARK: - 슬로프 데이터 (하이원 리조트 공식 정보 기반)
    // TODO: 각 슬로프의 boundary, topPoint, bottomPoint 좌표 입력 필요
    
    let slopes: [Slope] = [
        Slope(
            name: "ZEUS I",
            koreanName: "제우스 1",
            difficulty: .beginner,
            length: 2328,
            avgGradient: 9.48,
            maxGradient: 13.6,
            status: .operating,
            boundary: [
                CLLocationCoordinate2D(latitude: 37.178744880000494, longitude: 128.82922190134218),
                CLLocationCoordinate2D(latitude: 37.17851548680713, longitude: 128.82889428053375),
                CLLocationCoordinate2D(latitude: 37.17825840687628, longitude: 128.8282489716022),
                CLLocationCoordinate2D(latitude: 37.17806856306069, longitude: 128.827544090473),
                CLLocationCoordinate2D(latitude: 37.177914314609, longitude: 128.82627828281522),
                CLLocationCoordinate2D(latitude: 37.17801714694511, longitude: 128.82521103321903),
                CLLocationCoordinate2D(latitude: 37.178104161359684, longitude: 128.82446644070762),
                CLLocationCoordinate2D(latitude: 37.178278184793726, longitude: 128.8240742885307),
                CLLocationCoordinate2D(latitude: 37.17872906182582, longitude: 128.82389062232033),
                CLLocationCoordinate2D(latitude: 37.17901315530945, longitude: 128.8238062346253),
                CLLocationCoordinate2D(latitude: 37.17925441205976, longitude: 128.82334955107746),
                CLLocationCoordinate2D(latitude: 37.17933746748416, longitude: 128.82336940688236),
                CLLocationCoordinate2D(latitude: 37.17919904172642, longitude: 128.8227389850291),
                CLLocationCoordinate2D(latitude: 37.17877189778871, longitude: 128.82316092091588),
                CLLocationCoordinate2D(latitude: 37.17825773984572, longitude: 128.8234438661558),
                CLLocationCoordinate2D(latitude: 37.1779099431141, longitude: 128.823830898172),
                CLLocationCoordinate2D(latitude: 37.177660771858925, longitude: 128.8242577980099),
                CLLocationCoordinate2D(latitude: 37.1774986123465, longitude: 128.82492793147554),
                CLLocationCoordinate2D(latitude: 37.177443242410774, longitude: 128.82556331476496),
                CLLocationCoordinate2D(latitude: 37.17747883845696, longitude: 128.82627315984286),
                CLLocationCoordinate2D(latitude: 37.1775539864899, longitude: 128.8270177533393),
                CLLocationCoordinate2D(latitude: 37.17752234559245, longitude: 128.82773752632215),
                CLLocationCoordinate2D(latitude: 37.177838753974356, longitude: 128.8283679481754),
                CLLocationCoordinate2D(latitude: 37.17806371239193, longitude: 128.82905490118907),
                CLLocationCoordinate2D(latitude: 37.17834452288491, longitude: 128.82938252199511),
                CLLocationCoordinate2D(latitude: 37.178605557054894, longitude: 128.8294520173173),
                CLLocationCoordinate2D(latitude: 37.17875980409519, longitude: 128.82924353134825),
            ],
            topPoint: CLLocationCoordinate2D(latitude: 37.178744880000494, longitude: 128.82922190134218),
            bottomPoint: CLLocationCoordinate2D(latitude: 37.17933746748416, longitude: 128.82336940688236),
            topAltitude: 1389.0,
            bottomAltitude: 1229.0
        ),
        Slope(
            name: "ZEUS II",
            koreanName: "제우스 2",
            difficulty: .beginner,
            length: 2198,
            avgGradient: 7.49,
            maxGradient: 13.5,
            status: .operating,
            boundary: [
                CLLocationCoordinate2D(latitude: 37.181471757439496, longitude: 128.81785474414573),
                CLLocationCoordinate2D(latitude: 37.18112989732103, longitude: 128.81811555779626),
                CLLocationCoordinate2D(latitude: 37.18056683022375, longitude: 128.81819127788856),
                CLLocationCoordinate2D(latitude: 37.18032551446852, longitude: 128.81883069199625),
                CLLocationCoordinate2D(latitude: 37.18029870155961, longitude: 128.8196972663788),
                CLLocationCoordinate2D(latitude: 37.18019144982712, longitude: 128.82070686760085),
                CLLocationCoordinate2D(latitude: 37.180312108015244, longitude: 128.8218090156031),
                CLLocationCoordinate2D(latitude: 37.180332217694655, longitude: 128.82222126943617),
                CLLocationCoordinate2D(latitude: 37.17968200201949, longitude: 128.82240636299434),
                CLLocationCoordinate2D(latitude: 37.179467496651895, longitude: 128.82272607004717),
                CLLocationCoordinate2D(latitude: 37.17924665569785, longitude: 128.82272163926302),
                CLLocationCoordinate2D(latitude: 37.17937210335512, longitude: 128.82333456792657),
                CLLocationCoordinate2D(latitude: 37.179322820372136, longitude: 128.82354824947828),
                CLLocationCoordinate2D(latitude: 37.179090557532064, longitude: 128.8239158217403),
                CLLocationCoordinate2D(latitude: 37.17888647684468, longitude: 128.82455451080045),
                CLLocationCoordinate2D(latitude: 37.178838769591096, longitude: 128.8247840396824),
                CLLocationCoordinate2D(latitude: 37.17888647684468, longitude: 128.82496699748555),
                CLLocationCoordinate2D(latitude: 37.17901634643704, longitude: 128.8251333227625),
                CLLocationCoordinate2D(latitude: 37.179284036116286, longitude: 128.82512666975026),
                CLLocationCoordinate2D(latitude: 37.17961735677716, longitude: 128.82503046302054),
                CLLocationCoordinate2D(latitude: 37.18023754232699, longitude: 128.82447826310403),
                CLLocationCoordinate2D(latitude: 37.18032235363049, longitude: 128.82442503901478),
                CLLocationCoordinate2D(latitude: 37.1800202129274, longitude: 128.82485748473312),
                CLLocationCoordinate2D(latitude: 37.179927450188856, longitude: 128.82515687023078),
                CLLocationCoordinate2D(latitude: 37.18008647195718, longitude: 128.82543297018822),
                CLLocationCoordinate2D(latitude: 37.18027464728374, longitude: 128.8254263171777),
                CLLocationCoordinate2D(latitude: 37.18055558422394, longitude: 128.8253165424954),
                CLLocationCoordinate2D(latitude: 37.18088422617038, longitude: 128.8250038492837),
                CLLocationCoordinate2D(latitude: 37.181242020146755, longitude: 128.82460799512654),
                CLLocationCoordinate2D(latitude: 37.18137422301804, longitude: 128.82456823307945),
                CLLocationCoordinate2D(latitude: 37.18173996557995, longitude: 128.82484433303853),
                CLLocationCoordinate2D(latitude: 37.182224270762646, longitude: 128.82501275301973),
                CLLocationCoordinate2D(latitude: 37.18285164057977, longitude: 128.8249653604023),
                CLLocationCoordinate2D(latitude: 37.1834499612077, longitude: 128.82491432089762),
                CLLocationCoordinate2D(latitude: 37.18393449737765, longitude: 128.8248930825796),
                CLLocationCoordinate2D(latitude: 37.18443405875131, longitude: 128.82508265304944),
                CLLocationCoordinate2D(latitude: 37.18479130119498, longitude: 128.82530503379223),
                CLLocationCoordinate2D(latitude: 37.18545059949777, longitude: 128.82561490621623),
                CLLocationCoordinate2D(latitude: 37.185941437766004, longitude: 128.82587374281758),
                CLLocationCoordinate2D(latitude: 37.18630157887503, longitude: 128.8260742487622),
                CLLocationCoordinate2D(latitude: 37.18675755968887, longitude: 128.82609612227623),
                CLLocationCoordinate2D(latitude: 37.187065417789924, longitude: 128.82613257813665),
                CLLocationCoordinate2D(latitude: 37.18747492570394, longitude: 128.8262820467553),
                CLLocationCoordinate2D(latitude: 37.187811823757045, longitude: 128.82645703488248),
                CLLocationCoordinate2D(latitude: 37.188238753202484, longitude: 128.8267123119419),
                CLLocationCoordinate2D(latitude: 37.18848852006654, longitude: 128.82692375592757),
                CLLocationCoordinate2D(latitude: 37.18931042200228, longitude: 128.8280611770807),
                CLLocationCoordinate2D(latitude: 37.18948467834376, longitude: 128.82698572417303),
                CLLocationCoordinate2D(latitude: 37.18881961234132, longitude: 128.8265081565441),
                CLLocationCoordinate2D(latitude: 37.188293941564666, longitude: 128.82608162298885),
                CLLocationCoordinate2D(latitude: 37.18771796108382, longitude: 128.8256610570408),
                CLLocationCoordinate2D(latitude: 37.187194679163994, longitude: 128.82538225323663),
                CLLocationCoordinate2D(latitude: 37.18614057531943, longitude: 128.82522631223077),
                CLLocationCoordinate2D(latitude: 37.18550434109186, longitude: 128.82499948879757),
                CLLocationCoordinate2D(latitude: 37.184853445906825, longitude: 128.82456921397812),
                CLLocationCoordinate2D(latitude: 37.18436402709716, longitude: 128.8242384298029),
                CLLocationCoordinate2D(latitude: 37.183938606632566, longitude: 128.82419117492213),
                CLLocationCoordinate2D(latitude: 37.18355028750824, longitude: 128.82418745979163),
                CLLocationCoordinate2D(latitude: 37.182834969682744, longitude: 128.82448044005935),
                CLLocationCoordinate2D(latitude: 37.18208199623152, longitude: 128.8243859302953),
                CLLocationCoordinate2D(latitude: 37.18169100854726, longitude: 128.82393653666702),
                CLLocationCoordinate2D(latitude: 37.181438759456825, longitude: 128.82381367397363),
                CLLocationCoordinate2D(latitude: 37.18102838227122, longitude: 128.82393653666702),
                CLLocationCoordinate2D(latitude: 37.18044876527888, longitude: 128.8247490876525),
                CLLocationCoordinate2D(latitude: 37.18070854758457, longitude: 128.82398828405024),
                CLLocationCoordinate2D(latitude: 37.180520299626295, longitude: 128.82381344098815),
                CLLocationCoordinate2D(latitude: 37.17993296298057, longitude: 128.82415840162685),
                CLLocationCoordinate2D(latitude: 37.17945998518336, longitude: 128.82445759504554),
                CLLocationCoordinate2D(latitude: 37.17980431398722, longitude: 128.82369298745942),
                CLLocationCoordinate2D(latitude: 37.17986107133166, longitude: 128.82309934802828),
                CLLocationCoordinate2D(latitude: 37.18003512692219, longitude: 128.82277640817858),
                CLLocationCoordinate2D(latitude: 37.180553507500534, longitude: 128.82255319975042),
                CLLocationCoordinate2D(latitude: 37.18075963293634, longitude: 128.822443740968),
                CLLocationCoordinate2D(latitude: 37.180718011382865, longitude: 128.82137518912123),
                CLLocationCoordinate2D(latitude: 37.18059059125952, longitude: 128.82097936646),
                CLLocationCoordinate2D(latitude: 37.180625631822764, longitude: 128.8204316127468),
                CLLocationCoordinate2D(latitude: 37.180714825908524, longitude: 128.81968794712276),
                CLLocationCoordinate2D(latitude: 37.18080401988982, longitude: 128.81889630307086),
                CLLocationCoordinate2D(latitude: 37.18109071579707, longitude: 128.81859244181953),
                CLLocationCoordinate2D(latitude: 37.18150790161454, longitude: 128.81829713681464),
                CLLocationCoordinate2D(latitude: 37.181469675991565, longitude: 128.8178653309689),
            ],
            topPoint: CLLocationCoordinate2D(latitude: 37.181471757439496, longitude: 128.81785474414573),
            bottomPoint: CLLocationCoordinate2D(latitude: 37.18771796108382, longitude: 128.8256610570408),
            topAltitude: 1337.0,
            bottomAltitude: 1036.0
        ),
        Slope(
            name: "ZEUS III",
            koreanName: "제우스 3",
            difficulty: .beginner,
            length: 1835,
            avgGradient: 8.73,
            maxGradient: 13.8,
            status: .operating,
            boundary: [
                CLLocationCoordinate2D(latitude: 37.191400106953566, longitude: 128.8282164252758),
                CLLocationCoordinate2D(latitude: 37.19043035956672, longitude: 128.8294623866882),
                CLLocationCoordinate2D(latitude: 37.19195913214142, longitude: 128.8306653839137),
                CLLocationCoordinate2D(latitude: 37.194708563131016, longitude: 128.8318970239298),
                CLLocationCoordinate2D(latitude: 37.19665934651711, longitude: 128.8324269133339),
                CLLocationCoordinate2D(latitude: 37.19825643910153, longitude: 128.83301409055127),
                CLLocationCoordinate2D(latitude: 37.20030979547393, longitude: 128.83413115982069),
                CLLocationCoordinate2D(latitude: 37.201165343615216, longitude: 128.83511933611135),
                CLLocationCoordinate2D(latitude: 37.202066510504096, longitude: 128.83569219193424),
                CLLocationCoordinate2D(latitude: 37.202285962272924, longitude: 128.83613579598455),
                CLLocationCoordinate2D(latitude: 37.20224766472283, longitude: 128.83738592632756),
                CLLocationCoordinate2D(latitude: 37.20369019237734, longitude: 128.83894057560144),
                CLLocationCoordinate2D(latitude: 37.20422634607047, longitude: 128.8379949641872),
                CLLocationCoordinate2D(latitude: 37.20293701766056, longitude: 128.83684099771745),
                CLLocationCoordinate2D(latitude: 37.20282212594135, longitude: 128.83541456694076),
                CLLocationCoordinate2D(latitude: 37.20049872253763, longitude: 128.83352334411228),
                CLLocationCoordinate2D(latitude: 37.19854547643274, longitude: 128.83232129570388),
                CLLocationCoordinate2D(latitude: 37.19691260011945, longitude: 128.83178925983452),
                CLLocationCoordinate2D(latitude: 37.19544440893489, longitude: 128.83113214003822),
                CLLocationCoordinate2D(latitude: 37.194103859822775, longitude: 128.8307474849642),
                CLLocationCoordinate2D(latitude: 37.19318461361637, longitude: 128.8303788567859),
                CLLocationCoordinate2D(latitude: 37.19137162301659, longitude: 128.8282311969653),
                CLLocationCoordinate2D(latitude: 37.19253347411508, longitude: 128.82824722427614),
            ],
            topPoint: CLLocationCoordinate2D(latitude: 37.19253347411508, longitude: 128.82824722427614),
            bottomPoint: CLLocationCoordinate2D(latitude: 37.20369019237734, longitude: 128.83894057560144),
            topAltitude: 1061.0,
            bottomAltitude: 743.0
        ),
        Slope(
            name: "ZEUS III-1",
            koreanName: "제우스 3-1",
            difficulty: .beginner,
            length: 1023,
            avgGradient: 6.8,
            maxGradient: 10.8,
            status: .operating,
            boundary: [],
            topPoint: nil,
            bottomPoint: nil,
            topAltitude: nil,
            bottomAltitude: nil
        ),
        Slope(
            name: "ATHENA I",
            koreanName: "아테나 1",
            difficulty: .beginner,
            length: 0,
            avgGradient: 0,
            maxGradient: 0,
            status: .closed,
            boundary: [],
            topPoint: nil,
            bottomPoint: nil,
            topAltitude: nil,
            bottomAltitude: nil
        ),
        Slope(
            name: "ATHENA II",
            koreanName: "아테나 2",
            difficulty: .intermediate,
            length: 2100,
            avgGradient: 12.0,
            maxGradient: 18.0,
            status: .operating,
            boundary: [
                CLLocationCoordinate2D(latitude: 37.19520800932537, longitude: 128.82009401885097),
                CLLocationCoordinate2D(latitude: 37.19502220037265, longitude: 128.82089746287767),
                CLLocationCoordinate2D(latitude: 37.196374466196986, longitude: 128.8213769375394),
                CLLocationCoordinate2D(latitude: 37.197840253702, longitude: 128.8220507938185),
                CLLocationCoordinate2D(latitude: 37.19951245620091, longitude: 128.8227764845567),
                CLLocationCoordinate2D(latitude: 37.20044144113649, longitude: 128.8240205269194),
                CLLocationCoordinate2D(latitude: 37.20076142368602, longitude: 128.8240982766078),
                CLLocationCoordinate2D(latitude: 37.201133012883744, longitude: 128.82351513174893),
                CLLocationCoordinate2D(latitude: 37.20153556578323, longitude: 128.82337258522927),
                CLLocationCoordinate2D(latitude: 37.20204133433231, longitude: 128.82412419415664),
                CLLocationCoordinate2D(latitude: 37.202526456082396, longitude: 128.82517385490024),
                CLLocationCoordinate2D(latitude: 37.20370312225728, longitude: 128.8259005376404),
                CLLocationCoordinate2D(latitude: 37.204177911846884, longitude: 128.8261208368084),
                CLLocationCoordinate2D(latitude: 37.204487555621895, longitude: 128.82552473317588),
                CLLocationCoordinate2D(latitude: 37.205437121944755, longitude: 128.82501934096535),
                CLLocationCoordinate2D(latitude: 37.20658277845203, longitude: 128.82491567076818),
                CLLocationCoordinate2D(latitude: 37.20689241236093, longitude: 128.82498046464121),
                CLLocationCoordinate2D(latitude: 37.206913054576034, longitude: 128.82409926796782),
                CLLocationCoordinate2D(latitude: 37.20551969236425, longitude: 128.82434548468632),
                CLLocationCoordinate2D(latitude: 37.204239840703394, longitude: 128.82495454709237),
                CLLocationCoordinate2D(latitude: 37.20386826680081, longitude: 128.82531739278159),
                CLLocationCoordinate2D(latitude: 37.201896830218914, longitude: 128.82271267908385),
                CLLocationCoordinate2D(latitude: 37.20123623317535, longitude: 128.82238870539743),
                CLLocationCoordinate2D(latitude: 37.200616917676584, longitude: 128.82321806697308),
                CLLocationCoordinate2D(latitude: 37.19988405443921, longitude: 128.82212952990534),
                CLLocationCoordinate2D(latitude: 37.19886216670827, longitude: 128.8218962699387),
                CLLocationCoordinate2D(latitude: 37.19792284000199, longitude: 128.82119649610905),
                CLLocationCoordinate2D(latitude: 37.19522045491938, longitude: 128.82010484699634),
            ],
            topPoint: CLLocationCoordinate2D(latitude: 37.19520800932537, longitude: 128.82009401885097),
            bottomPoint: CLLocationCoordinate2D(latitude: 37.206913054576034, longitude: 128.82409926796782),
            topAltitude: 1257.0,
            bottomAltitude: 960.0
        ),
        Slope(
            name: "ATHENA III",
            koreanName: "아테나 3",
            difficulty: .beginner,
            length: 1676,
            avgGradient: 9.3,
            maxGradient: 19.3,
            status: .operating,
            boundary: [
                CLLocationCoordinate2D(latitude: 37.205798431568454, longitude: 128.82681777245784),
                CLLocationCoordinate2D(latitude: 37.20614366528517, longitude: 128.82728892077137),
                CLLocationCoordinate2D(latitude: 37.20559579365133, longitude: 128.8278542987477),
                CLLocationCoordinate2D(latitude: 37.20517550586713, longitude: 128.82938081928467),
                CLLocationCoordinate2D(latitude: 37.204957855915566, longitude: 128.83025715515055),
                CLLocationCoordinate2D(latitude: 37.204155856244114, longitude: 128.83060447107033),
                CLLocationCoordinate2D(latitude: 37.2040958141301, longitude: 128.831094465315),
                CLLocationCoordinate2D(latitude: 37.204125835192826, longitude: 128.83147138396583),
                CLLocationCoordinate2D(latitude: 37.205529308796415, longitude: 128.83432446369738),
                CLLocationCoordinate2D(latitude: 37.20612971638606, longitude: 128.8354363737189),
                CLLocationCoordinate2D(latitude: 37.20620476610267, longitude: 128.83603002107543),
                CLLocationCoordinate2D(latitude: 37.20607718001625, longitude: 128.83652943828804),
                CLLocationCoordinate2D(latitude: 37.20534918469194, longitude: 128.83733039041994),
                CLLocationCoordinate2D(latitude: 37.204943905901104, longitude: 128.8371984688926),
                CLLocationCoordinate2D(latitude: 37.20414835231624, longitude: 128.83643520862535),
                CLLocationCoordinate2D(latitude: 37.20292498435677, longitude: 128.83601117314453),
                CLLocationCoordinate2D(latitude: 37.20287244665229, longitude: 128.83556829372998),
                CLLocationCoordinate2D(latitude: 37.20371304553166, longitude: 128.83568136932382),
                CLLocationCoordinate2D(latitude: 37.204523614155846, longitude: 128.83636924586193),
                CLLocationCoordinate2D(latitude: 37.20502024695931, longitude: 128.8368914108152),
                CLLocationCoordinate2D(latitude: 37.2052904327884, longitude: 128.8369102567463),
                CLLocationCoordinate2D(latitude: 37.20589084227845, longitude: 128.83618468834362),
                CLLocationCoordinate2D(latitude: 37.20586832700863, longitude: 128.83569469409645),
                CLLocationCoordinate2D(latitude: 37.20520787611012, longitude: 128.83442259364858),
                CLLocationCoordinate2D(latitude: 37.20429974668684, longitude: 128.83261338412353),
                CLLocationCoordinate2D(latitude: 37.20373685278511, longitude: 128.8313224366966),
                CLLocationCoordinate2D(latitude: 37.20385693753745, longitude: 128.83013514294595),
                CLLocationCoordinate2D(latitude: 37.20419467487797, longitude: 128.82988072285445),
                CLLocationCoordinate2D(latitude: 37.20462997855486, longitude: 128.82983360802433),
                CLLocationCoordinate2D(latitude: 37.20485441588049, longitude: 128.82917400048007),
                CLLocationCoordinate2D(latitude: 37.20543231343942, longitude: 128.82710094789786),
                CLLocationCoordinate2D(latitude: 37.205800064127374, longitude: 128.82678999001064),
            ],
            topPoint: CLLocationCoordinate2D(latitude: 37.205798431568454, longitude: 128.82681777245784),
            bottomPoint: CLLocationCoordinate2D(latitude: 37.20371304553166, longitude: 128.83568136932382),
            topAltitude: 981.0,
            bottomAltitude: 782.0
        ),
        Slope(
            name: "ATHENA III-1",
            koreanName: "아테나 3-1",
            difficulty: .beginner,
            length: 800,
            avgGradient: 7.0,
            maxGradient: 10.0,
            status: .operating,
            boundary: [],
            topPoint: nil,
            bottomPoint: nil,
            topAltitude: nil,
            bottomAltitude: nil
        ),
        Slope(
            name: "HERA I",
            koreanName: "헤라 1",
            difficulty: .intermediate,
            length: 1508,
            avgGradient: 14.86,
            maxGradient: 21.8,
            status: .operating,
            boundary: [
                CLLocationCoordinate2D(latitude: 37.18243393589621, longitude: 128.81797945392674),
                CLLocationCoordinate2D(latitude: 37.182215526791126, longitude: 128.81775369439202),
                CLLocationCoordinate2D(latitude: 37.18176585899893, longitude: 128.81804395664983),
                CLLocationCoordinate2D(latitude: 37.18123910189422, longitude: 128.81888249206162),
                CLLocationCoordinate2D(latitude: 37.18116201518076, longitude: 128.81976940451483),
                CLLocationCoordinate2D(latitude: 37.18152175250482, longitude: 128.8202854263073),
                CLLocationCoordinate2D(latitude: 37.181733739768504, longitude: 128.82148678953985),
                CLLocationCoordinate2D(latitude: 37.18224131611157, longitude: 128.82217212615416),
                CLLocationCoordinate2D(latitude: 37.182588200747134, longitude: 128.82266395942509),
                CLLocationCoordinate2D(latitude: 37.182723099896705, longitude: 128.82322835825892),
                CLLocationCoordinate2D(latitude: 37.18284515130148, longitude: 128.82441359580963),
                CLLocationCoordinate2D(latitude: 37.183580443295824, longitude: 128.82411468677196),
                CLLocationCoordinate2D(latitude: 37.183246410655855, longitude: 128.82351803657667),
                CLLocationCoordinate2D(latitude: 37.18311793617043, longitude: 128.82234086186367),
                CLLocationCoordinate2D(latitude: 37.182430593960774, longitude: 128.8214700750924),
                CLLocationCoordinate2D(latitude: 37.18213248183211, longitude: 128.82108049986476),
                CLLocationCoordinate2D(latitude: 37.182077749188124, longitude: 128.8202061670844),
                CLLocationCoordinate2D(latitude: 37.18168964384927, longitude: 128.81951294609593),
                CLLocationCoordinate2D(latitude: 37.18199316229719, longitude: 128.8186635942518),
                CLLocationCoordinate2D(latitude: 37.18246087768492, longitude: 128.81800784875617),
            ],
            topPoint: CLLocationCoordinate2D(latitude: 37.18243393589621, longitude: 128.81797945392674),
            bottomPoint: CLLocationCoordinate2D(latitude: 37.183580443295824, longitude: 128.82411468677196),
            topAltitude: 1337.0,
            bottomAltitude: 1136.0
        ),
        Slope(
            name: "HERA II",
            koreanName: "헤라 2",
            difficulty: .advancedIntermediate,
            length: 1301,
            avgGradient: 17.40,
            maxGradient: 24.2,
            status: .operating,
            boundary: [
                CLLocationCoordinate2D(latitude: 37.18352944379001, longitude: 128.8172288396492),
                CLLocationCoordinate2D(latitude: 37.18308280765861, longitude: 128.8177682882228),
                CLLocationCoordinate2D(latitude: 37.183631202309954, longitude: 128.8185427971436),
                CLLocationCoordinate2D(latitude: 37.18356754152049, longitude: 128.81916872200924),
                CLLocationCoordinate2D(latitude: 37.18344021977994, longitude: 128.8196747889212),
                CLLocationCoordinate2D(latitude: 37.18361528711742, longitude: 128.82005433910467),
                CLLocationCoordinate2D(latitude: 37.18383809950596, longitude: 128.8204205717389),
                CLLocationCoordinate2D(latitude: 37.18400786043553, longitude: 128.82071342160106),
                CLLocationCoordinate2D(latitude: 37.184198841529536, longitude: 128.82113958321213),
                CLLocationCoordinate2D(latitude: 37.184167011381064, longitude: 128.82158572114713),
                CLLocationCoordinate2D(latitude: 37.184373907108665, longitude: 128.82215837581055),
                CLLocationCoordinate2D(latitude: 37.184814223917726, longitude: 128.82275100513385),
                CLLocationCoordinate2D(latitude: 37.185201486499864, longitude: 128.8232570720457),
                CLLocationCoordinate2D(latitude: 37.18554630767508, longitude: 128.82353674060272),
                CLLocationCoordinate2D(latitude: 37.18588051746568, longitude: 128.8241360303665),
                CLLocationCoordinate2D(latitude: 37.186320823822314, longitude: 128.82485517275938),
                CLLocationCoordinate2D(latitude: 37.186352653063736, longitude: 128.8250682535633),
                CLLocationCoordinate2D(latitude: 37.18701045437784, longitude: 128.8249417368349),
                CLLocationCoordinate2D(latitude: 37.18660728651014, longitude: 128.82434910584584),
                CLLocationCoordinate2D(latitude: 37.18630490919661, longitude: 128.8237564748568),
                CLLocationCoordinate2D(latitude: 37.18504764317501, longitude: 128.82208512229244),
                CLLocationCoordinate2D(latitude: 37.184696139514514, longitude: 128.82159903203177),
                CLLocationCoordinate2D(latitude: 37.184547599682986, longitude: 128.82041377005368),
                CLLocationCoordinate2D(latitude: 37.18437253450645, longitude: 128.82000758476823),
                CLLocationCoordinate2D(latitude: 37.18410197843545, longitude: 128.81969462233627),
                CLLocationCoordinate2D(latitude: 37.18419746892414, longitude: 128.81876905258957),
                CLLocationCoordinate2D(latitude: 37.18416563913145, longitude: 128.81826964332276),
                CLLocationCoordinate2D(latitude: 37.18353433839499, longitude: 128.8172508507226),
            ],
            topPoint: CLLocationCoordinate2D(latitude: 37.18308280765861, longitude: 128.8177682882228),
            bottomPoint: CLLocationCoordinate2D(latitude: 37.186352653063736, longitude: 128.8250682535633),
            topAltitude: 1337.0,
            bottomAltitude: 1056.0
        ),
        Slope(
            name: "HERA III",
            koreanName: "헤라 3",
            difficulty: .advanced,
            length: 1278,
            avgGradient: 19.75,
            maxGradient: 25.8,
            status: .operating,
            boundary: [
                CLLocationCoordinate2D(latitude: 37.18400932452556, longitude: 128.81663824401113),
                CLLocationCoordinate2D(latitude: 37.1837236017806, longitude: 128.81723874533083),
                CLLocationCoordinate2D(latitude: 37.18452760953757, longitude: 128.8179059690184),
                CLLocationCoordinate2D(latitude: 37.184873130902204, longitude: 128.81872331803692),
                CLLocationCoordinate2D(latitude: 37.185079114814314, longitude: 128.81956568590732),
                CLLocationCoordinate2D(latitude: 37.185404699920156, longitude: 128.82043307670284),
                CLLocationCoordinate2D(latitude: 37.18559739248428, longitude: 128.82105025861335),
                CLLocationCoordinate2D(latitude: 37.18600270972327, longitude: 128.82174250318945),
                CLLocationCoordinate2D(latitude: 37.18657414261028, longitude: 128.82236801409857),
                CLLocationCoordinate2D(latitude: 37.18671367649404, longitude: 128.8227016259424),
                CLLocationCoordinate2D(latitude: 37.18676018773104, longitude: 128.82346893318396),
                CLLocationCoordinate2D(latitude: 37.18679341002576, longitude: 128.82415283746457),
                CLLocationCoordinate2D(latitude: 37.18670703387592, longitude: 128.82441137314612),
                CLLocationCoordinate2D(latitude: 37.18707912300434, longitude: 128.82492013120935),
                CLLocationCoordinate2D(latitude: 37.18718543384742, longitude: 128.8237941912355),
                CLLocationCoordinate2D(latitude: 37.18721201153437, longitude: 128.82299352281),
                CLLocationCoordinate2D(latitude: 37.18711898958824, longitude: 128.8223680006019),
                CLLocationCoordinate2D(latitude: 37.186793411872785, longitude: 128.8218175410592),
                CLLocationCoordinate2D(latitude: 37.18628178691277, longitude: 128.82122538003495),
                CLLocationCoordinate2D(latitude: 37.18581638303483, longitude: 128.82020006566705),
                CLLocationCoordinate2D(latitude: 37.185610401906814, longitude: 128.81930765398306),
                CLLocationCoordinate2D(latitude: 37.18526488391515, longitude: 128.8185320064461),
                CLLocationCoordinate2D(latitude: 37.18523830605406, longitude: 128.8176229159908),
                CLLocationCoordinate2D(latitude: 37.18402233550694, longitude: 128.8166387610525),
            ],
            topPoint: CLLocationCoordinate2D(latitude: 37.1837236017806, longitude: 128.81723874533083),
            bottomPoint: CLLocationCoordinate2D(latitude: 37.18721201153437, longitude: 128.82299352281),
            topAltitude: 1320.0,
            bottomAltitude: 1109.0
        ),
        Slope(
            name: "VICTORIA I",
            koreanName: "빅토리아 1",
            difficulty: .advanced,
            length: 1439,
            avgGradient: 15.58,
            maxGradient: 27.7,
            status: .operating,
            boundary: [
                CLLocationCoordinate2D(latitude: 37.17964194502517, longitude: 128.8310998353042),
                CLLocationCoordinate2D(latitude: 37.17992021960406, longitude: 128.8310998353042),
                CLLocationCoordinate2D(latitude: 37.18043502487312, longitude: 128.83130939434892),
                CLLocationCoordinate2D(latitude: 37.18099156716349, longitude: 128.83157134315252),
                CLLocationCoordinate2D(latitude: 37.18177071948068, longitude: 128.83200792449196),
                CLLocationCoordinate2D(latitude: 37.182535950539915, longitude: 128.83230479980227),
                CLLocationCoordinate2D(latitude: 37.183203782221085, longitude: 128.8323222630567),
                CLLocationCoordinate2D(latitude: 37.184177692837224, longitude: 128.83260167511258),
                CLLocationCoordinate2D(latitude: 37.1852339488413, longitude: 128.8329940725734),
                CLLocationCoordinate2D(latitude: 37.185964269030165, longitude: 128.8333637106482),
                CLLocationCoordinate2D(latitude: 37.18674169889029, longitude: 128.8323435095607),
                CLLocationCoordinate2D(latitude: 37.18760157411171, longitude: 128.83147116370503),
                CLLocationCoordinate2D(latitude: 37.18790095125878, longitude: 128.83127483544422),
                CLLocationCoordinate2D(latitude: 37.18814890771978, longitude: 128.8309566723717),
                CLLocationCoordinate2D(latitude: 37.18838033301536, longitude: 128.83066617565294),
                CLLocationCoordinate2D(latitude: 37.18879910079622, longitude: 128.8299814333884),
                CLLocationCoordinate2D(latitude: 37.18912419523443, longitude: 128.8295456883112),
                CLLocationCoordinate2D(latitude: 37.18973093760498, longitude: 128.82904091925525),
                CLLocationCoordinate2D(latitude: 37.1901093635191, longitude: 128.82881779922855),
                CLLocationCoordinate2D(latitude: 37.18959906146202, longitude: 128.82842913853938),
                CLLocationCoordinate2D(latitude: 37.188922475889115, longitude: 128.82904811667493),
                CLLocationCoordinate2D(latitude: 37.188320424307705, longitude: 128.82966709481025),
                CLLocationCoordinate2D(latitude: 37.18809107006206, longitude: 128.83007015034042),
                CLLocationCoordinate2D(latitude: 37.18762662558083, longitude: 128.8306243516937),
                CLLocationCoordinate2D(latitude: 37.18717364611294, longitude: 128.8310705917453),
                CLLocationCoordinate2D(latitude: 37.18676604512572, longitude: 128.83150143111544),
                CLLocationCoordinate2D(latitude: 37.186480006244366, longitude: 128.83186047375938),
                CLLocationCoordinate2D(latitude: 37.1862511743585, longitude: 128.8321028275439),
                CLLocationCoordinate2D(latitude: 37.18585786793598, longitude: 128.83233620526283),
                CLLocationCoordinate2D(latitude: 37.185328688789596, longitude: 128.83243494198928),
                CLLocationCoordinate2D(latitude: 37.18475655730191, longitude: 128.83221058222017),
                CLLocationCoordinate2D(latitude: 37.18419161443623, longitude: 128.83204901303145),
                CLLocationCoordinate2D(latitude: 37.18344877018659, longitude: 128.83184931935773),
                CLLocationCoordinate2D(latitude: 37.18313411353675, longitude: 128.83162491770406),
                CLLocationCoordinate2D(latitude: 37.18212577316916, longitude: 128.83153515704305),
                CLLocationCoordinate2D(latitude: 37.1814544006248, longitude: 128.8313376761601),
                CLLocationCoordinate2D(latitude: 37.18095379666694, longitude: 128.83095170531766),
                CLLocationCoordinate2D(latitude: 37.18023048090029, longitude: 128.83073500591604),
                CLLocationCoordinate2D(latitude: 37.179686959070494, longitude: 128.83043879573444),
                CLLocationCoordinate2D(latitude: 37.17964201089474, longitude: 128.83109644171213),
            ],
            topPoint: CLLocationCoordinate2D(latitude: 37.17964194502517, longitude: 128.8310998353042),
            bottomPoint: CLLocationCoordinate2D(latitude: 37.18959906146202, longitude: 128.82842913853938),
            topAltitude: 1347.0,
            bottomAltitude: 991.0
        ),
        Slope(
            name: "VICTORIA II",
            koreanName: "빅토리아 2",
            difficulty: .advanced,
            length: 1382,
            avgGradient: 18.72,
            maxGradient: 25.8,
            status: .operating,
            boundary: [
                CLLocationCoordinate2D(latitude: 37.183107799491836, longitude: 128.83178060327867),
                CLLocationCoordinate2D(latitude: 37.18345091220981, longitude: 128.83112410330665),
                CLLocationCoordinate2D(latitude: 37.18437239961162, longitude: 128.82996293675058),
                CLLocationCoordinate2D(latitude: 37.18499166472361, longitude: 128.8292276567813),
                CLLocationCoordinate2D(latitude: 37.18550213620057, longitude: 128.82854489681102),
                CLLocationCoordinate2D(latitude: 37.18624246992266, longitude: 128.82798342694906),
                CLLocationCoordinate2D(latitude: 37.186881162630925, longitude: 128.82783822595962),
                CLLocationCoordinate2D(latitude: 37.187446014273974, longitude: 128.82788549395792),
                CLLocationCoordinate2D(latitude: 37.18814893486291, longitude: 128.82786448595908),
                CLLocationCoordinate2D(latitude: 37.18870487286729, longitude: 128.8278699669832),
                CLLocationCoordinate2D(latitude: 37.189212392187216, longitude: 128.8280687327407),
                CLLocationCoordinate2D(latitude: 37.188465322563346, longitude: 128.82706980739744),
                CLLocationCoordinate2D(latitude: 37.18771824554875, longitude: 128.82727366971233),
                CLLocationCoordinate2D(latitude: 37.18688995587155, longitude: 128.82726857315487),
                CLLocationCoordinate2D(latitude: 37.186228129114056, longitude: 128.827426566342),
                CLLocationCoordinate2D(latitude: 37.18552569371148, longitude: 128.82778842195057),
                CLLocationCoordinate2D(latitude: 37.18490443064535, longitude: 128.8282930152809),
                CLLocationCoordinate2D(latitude: 37.1841857412886, longitude: 128.82936838899286),
                CLLocationCoordinate2D(latitude: 37.18348766049208, longitude: 128.8301077881676),
                CLLocationCoordinate2D(latitude: 37.183256214561624, longitude: 128.83055118870362),
                CLLocationCoordinate2D(latitude: 37.18266338490889, longitude: 128.8312137412271),
                CLLocationCoordinate2D(latitude: 37.18217272462414, longitude: 128.83151672699506),
                CLLocationCoordinate2D(latitude: 37.18310663830857, longitude: 128.8317919411199),
            ],
            topPoint: CLLocationCoordinate2D(latitude: 37.183107799491836, longitude: 128.83178060327867),
            bottomPoint: CLLocationCoordinate2D(latitude: 37.18771824554875, longitude: 128.82727366971233),
            topAltitude: 1297.0,
            bottomAltitude: 1036.0
        ),
        Slope(
            name: "VICTORIA III",
            koreanName: "빅토리아 3",
            difficulty: .expert,
            length: 1311,
            avgGradient: 17.01,
            maxGradient: 35.4,
            status: .closed,
            boundary: [],
            topPoint: nil,
            bottomPoint: nil,
            topAltitude: nil,
            bottomAltitude: nil
        ),
        Slope(
            name: "APOLLO I",
            koreanName: "아폴로 1",
            difficulty: .advanced,
            length: 1506,
            avgGradient: 11.35,
            maxGradient: 25.4,
            status: .operating,
            boundary: [
                CLLocationCoordinate2D(latitude: 37.185318975467666, longitude: 128.81762977579837),
                CLLocationCoordinate2D(latitude: 37.18532600135799, longitude: 128.81853812335908),
                CLLocationCoordinate2D(latitude: 37.1863236710997, longitude: 128.81855576117437),
                CLLocationCoordinate2D(latitude: 37.18705435043691, longitude: 128.81882032842435),
                CLLocationCoordinate2D(latitude: 37.18781254243274, longitude: 128.81878432169123),
                CLLocationCoordinate2D(latitude: 37.18859941206672, longitude: 128.81925172383296),
                CLLocationCoordinate2D(latitude: 37.18925981418106, longitude: 128.82007188230818),
                CLLocationCoordinate2D(latitude: 37.189751598156704, longitude: 128.82117424338765),
                CLLocationCoordinate2D(latitude: 37.190433066440505, longitude: 128.8225411741804),
                CLLocationCoordinate2D(latitude: 37.19057357460112, longitude: 128.82359944318023),
                CLLocationCoordinate2D(latitude: 37.19030731057131, longitude: 128.82715346547303),
                CLLocationCoordinate2D(latitude: 37.19084124107711, longitude: 128.82720637892345),
                CLLocationCoordinate2D(latitude: 37.19093959628438, longitude: 128.8252485812706),
                CLLocationCoordinate2D(latitude: 37.19112225561612, longitude: 128.82348479960405),
                CLLocationCoordinate2D(latitude: 37.19109415234631, longitude: 128.82284983733558),
                CLLocationCoordinate2D(latitude: 37.19074990926319, longitude: 128.82202967886047),
                CLLocationCoordinate2D(latitude: 37.189667992213785, longitude: 128.81956920343288),
                CLLocationCoordinate2D(latitude: 37.18887545432881, longitude: 128.81881247635891),
                CLLocationCoordinate2D(latitude: 37.188798173135055, longitude: 128.81815987714282),
                CLLocationCoordinate2D(latitude: 37.18534174058529, longitude: 128.81762201896458),
                CLLocationCoordinate2D(latitude: 37.185313460320344, longitude: 128.8176229569338),
            ],
            topPoint: CLLocationCoordinate2D(latitude: 37.185318975467666, longitude: 128.81762977579837),
            bottomPoint: CLLocationCoordinate2D(latitude: 37.19084124107711, longitude: 128.82720637892345),
            topAltitude: 1320.0,
            bottomAltitude: 991.0
        ),
        Slope(
            name: "APOLLO II",
            koreanName: "아폴로 2",
            difficulty: .advanced,
            length: 863,
            avgGradient: 20.32,
            maxGradient: 24.2,
            status: .operating,
            boundary: [
                CLLocationCoordinate2D(latitude: 37.193366544629484, longitude: 128.81955682248986),
                CLLocationCoordinate2D(latitude: 37.192524443176055, longitude: 128.82024826799386),
                CLLocationCoordinate2D(latitude: 37.19204777781391, longitude: 128.82085328280812),
                CLLocationCoordinate2D(latitude: 37.190861397624246, longitude: 128.82206996095397),
                CLLocationCoordinate2D(latitude: 37.190834918640846, longitude: 128.82217633343265),
                CLLocationCoordinate2D(latitude: 37.19112092281296, longitude: 128.8227879967626),
                CLLocationCoordinate2D(latitude: 37.191300998958724, longitude: 128.82228935817812),
                CLLocationCoordinate2D(latitude: 37.19186241006737, longitude: 128.8216710463343),
                CLLocationCoordinate2D(latitude: 37.192413224457624, longitude: 128.82114581369245),
                CLLocationCoordinate2D(latitude: 37.19283692506188, longitude: 128.82073360534298),
                CLLocationCoordinate2D(latitude: 37.19330299302274, longitude: 128.8202748578455),
                CLLocationCoordinate2D(latitude: 37.19361546879436, longitude: 128.8201152934991),
                CLLocationCoordinate2D(latitude: 37.19337184372759, longitude: 128.81953687275058),
            ],
            topPoint: CLLocationCoordinate2D(latitude: 37.193366544629484, longitude: 128.81955682248986),
            bottomPoint: CLLocationCoordinate2D(latitude: 37.191300998958724, longitude: 128.82228935817812),
            topAltitude: 1251.0,
            bottomAltitude: 1126.0
        ),
        Slope(
            name: "APOLLO III",
            koreanName: "아폴로 3",
            difficulty: .advanced,
            length: 754,
            avgGradient: 15.85,
            maxGradient: 26.3,
            status: .operating,
            boundary: [
                CLLocationCoordinate2D(latitude: 37.19440356695854, longitude: 128.82050013262756),
                CLLocationCoordinate2D(latitude: 37.19437421620373, longitude: 128.82121862061717),
                CLLocationCoordinate2D(latitude: 37.194300839267015, longitude: 128.82166076707296),
                CLLocationCoordinate2D(latitude: 37.19360375481031, longitude: 128.82246215752104),
                CLLocationCoordinate2D(latitude: 37.192891988251404, longitude: 128.82336487320003),
                CLLocationCoordinate2D(latitude: 37.19248106843138, longitude: 128.82389913614992),
                CLLocationCoordinate2D(latitude: 37.19154181470421, longitude: 128.8249031770572),
                CLLocationCoordinate2D(latitude: 37.190984127275854, longitude: 128.8256216650468),
                CLLocationCoordinate2D(latitude: 37.190932761121545, longitude: 128.82674545395247),
                CLLocationCoordinate2D(latitude: 37.191233619529214, longitude: 128.826165136731),
                CLLocationCoordinate2D(latitude: 37.19206280844921, longitude: 128.8250966161326),
                CLLocationCoordinate2D(latitude: 37.19315614983053, longitude: 128.82395440445714),
                CLLocationCoordinate2D(latitude: 37.19329556806315, longitude: 128.82358594907856),
                CLLocationCoordinate2D(latitude: 37.193765185479265, longitude: 128.8230609001643),
                CLLocationCoordinate2D(latitude: 37.19441824234299, longitude: 128.82242531463555),
                CLLocationCoordinate2D(latitude: 37.19479980104218, longitude: 128.82190026571897),
                CLLocationCoordinate2D(latitude: 37.19489519041581, longitude: 128.82117256634552),
                CLLocationCoordinate2D(latitude: 37.19478512574345, longitude: 128.82066594020114),
                CLLocationCoordinate2D(latitude: 37.19442558002834, longitude: 128.8205185580493),
            ],
            topPoint: CLLocationCoordinate2D(latitude: 37.19440356695854, longitude: 128.82050013262756),
            bottomPoint: CLLocationCoordinate2D(latitude: 37.191233619529214, longitude: 128.826165136731),
            topAltitude: 1257.0,
            bottomAltitude: 1033.0
        ),
        Slope(
            name: "APOLLO IV",
            koreanName: "아폴로 4",
            difficulty: .advanced,
            length: 1569,
            avgGradient: 15.45,
            maxGradient: 24.2,
            status: .operating,
            boundary: [
                CLLocationCoordinate2D(latitude: 37.19363567916977, longitude: 128.8232870762393),
                CLLocationCoordinate2D(latitude: 37.19328082738585, longitude: 128.8236745889322),
                CLLocationCoordinate2D(latitude: 37.19329236730729, longitude: 128.8239643180484),
                CLLocationCoordinate2D(latitude: 37.19320004788537, longitude: 128.8243409659002),
                CLLocationCoordinate2D(latitude: 37.19320004788537, longitude: 128.82479728925847),
                CLLocationCoordinate2D(latitude: 37.19315698033964, longitude: 128.82512168892896),
                CLLocationCoordinate2D(latitude: 37.19354460470021, longitude: 128.82545381167893),
                CLLocationCoordinate2D(latitude: 37.19391069254692, longitude: 128.82580524389147),
                CLLocationCoordinate2D(latitude: 37.19439069392992, longitude: 128.82614543363502),
                CLLocationCoordinate2D(latitude: 37.1952028437028, longitude: 128.82684057427394),
                CLLocationCoordinate2D(latitude: 37.196229316902944, longitude: 128.82734659057857),
                CLLocationCoordinate2D(latitude: 37.19668976680626, longitude: 128.82723820757178),
                CLLocationCoordinate2D(latitude: 37.19703510239077, longitude: 128.82715046894577),
                CLLocationCoordinate2D(latitude: 37.197776000483145, longitude: 128.82733909543856),
                CLLocationCoordinate2D(latitude: 37.19827338233485, longitude: 128.82650653606646),
                CLLocationCoordinate2D(latitude: 37.197402961944604, longitude: 128.826649632209),
                CLLocationCoordinate2D(latitude: 37.19628901644734, longitude: 128.8265000316968),
                CLLocationCoordinate2D(latitude: 37.19530741158471, longitude: 128.82579605197304),
                CLLocationCoordinate2D(latitude: 37.193639355458174, longitude: 128.82417481043268),
                CLLocationCoordinate2D(latitude: 37.193634649976374, longitude: 128.82329632759337),
            ],
            topPoint: CLLocationCoordinate2D(latitude: 37.19363567916977, longitude: 128.8232870762393),
            bottomPoint: CLLocationCoordinate2D(latitude: 37.197776000483145, longitude: 128.82733909543856),
            topAltitude: 1116.0,
            bottomAltitude: 1006.0
        ),
        Slope(
            name: "APOLLO V",
            koreanName: "아폴로 5",
            difficulty: .expert,
            length: 1239,
            avgGradient: 22.13,
            maxGradient: 33.0,
            status: .closed,
            boundary: [],
            topPoint: nil,
            bottomPoint: nil,
            topAltitude: nil,
            bottomAltitude: nil
        ),
        Slope(
            name: "APOLLO VI",
            koreanName: "아폴로 6",
            difficulty: .advanced,
            length: 1543,
            avgGradient: 18.03,
            maxGradient: 24.3,
            status: .operating,
            boundary: [
                CLLocationCoordinate2D(latitude: 37.19793104253665, longitude: 128.8219800207852),
                CLLocationCoordinate2D(latitude: 37.199341073646096, longitude: 128.82266626005816),
                CLLocationCoordinate2D(latitude: 37.199207525572504, longitude: 128.82316534316783),
                CLLocationCoordinate2D(latitude: 37.199446669629225, longitude: 128.82377749979344),
                CLLocationCoordinate2D(latitude: 37.19978519733573, longitude: 128.8243857581797),
                CLLocationCoordinate2D(latitude: 37.19978519733573, longitude: 128.8251070892369),
                CLLocationCoordinate2D(latitude: 37.19948378702985, longitude: 128.82585194174516),
                CLLocationCoordinate2D(latitude: 37.198629698056365, longitude: 128.82725951207522),
                CLLocationCoordinate2D(latitude: 37.19854894961142, longitude: 128.82873727026566),
                CLLocationCoordinate2D(latitude: 37.19852099680243, longitude: 128.83035928726554),
                CLLocationCoordinate2D(latitude: 37.19837502458036, longitude: 128.83205507038514),
                CLLocationCoordinate2D(latitude: 37.19775580171067, longitude: 128.83154750631843),
                CLLocationCoordinate2D(latitude: 37.19803872007135, longitude: 128.83043297997824),
                CLLocationCoordinate2D(latitude: 37.198038720815376, longitude: 128.82763237798594),
                CLLocationCoordinate2D(latitude: 37.19782734494048, longitude: 128.82740784084666),
                CLLocationCoordinate2D(latitude: 37.1983834243223, longitude: 128.8263667997623),
                CLLocationCoordinate2D(latitude: 37.19907282916884, longitude: 128.8257095150745),
                CLLocationCoordinate2D(latitude: 37.19934273510242, longitude: 128.82491750734522),
                CLLocationCoordinate2D(latitude: 37.19906307351454, longitude: 128.82395403402825),
                CLLocationCoordinate2D(latitude: 37.198672836779934, longitude: 128.8232273439295),
                CLLocationCoordinate2D(latitude: 37.197924895668734, longitude: 128.8219862596548),
            ],
            topPoint: CLLocationCoordinate2D(latitude: 37.19793104253665, longitude: 128.8219800207852),
            bottomPoint: CLLocationCoordinate2D(latitude: 37.19837502458036, longitude: 128.83205507038514),
            topAltitude: 1165.0,
            bottomAltitude: 865.0
        ),

    ]
    
    // MARK: - 리프트 데이터
    // TODO: 리프트 경로 좌표 입력 필요 (구글 어스나 현장 데이터로 보강해야 함)
    // 현재는 이름만 있고 경로가 비어있어 isNearLiftLine()이 항상 false를 반환함.
    
    let liftLines: [LiftLine] = [
        LiftLine(name: "MOUNTAIN TOP EXPRESS", koreanName: "마운틴탑 익스프레스", path: []), // 곤돌라
        LiftLine(name: "ZEUS EXPRESS", koreanName: "제우스 익스프레스", path: []), // 밸리 허브 -> 제우스 2 상단
        LiftLine(name: "VICTORIA EXPRESS", koreanName: "빅토리아 익스프레스", path: []),
        LiftLine(name: "APOLLO EXPRESS", koreanName: "아폴로 익스프레스", path: []),
        LiftLine(name: "HERA EXPRESS", koreanName: "헤라 익스프레스", path: []), // 밸리 허브 -> 마운틴 탑
        LiftLine(name: "VALLEY GONDOLA", koreanName: "밸리 곤돌라", path: []) // 스키하우스 -> 밸리 허브 -> 마운틴 탑
    ]
    
    // MARK: - 운영 중인 슬로프만 필터링
    
    var operatingSlopes: [Slope] {
        slopes.filter { $0.status == .operating }
    }
    
    // MARK: - 위치 판정 함수
    
    /// 현재 위치가 어떤 슬로프 내부에 있는지 확인 (운영 중인 슬로프만, 난이도 높은 순 우선)
    func findSlope(at location: CLLocation) -> Slope? {
        let coordinate = location.coordinate
        // 난이도가 높은(범위가 좁은) 슬로프부터 체크하여 겹침 문제 해결
        return operatingSlopes
            .sorted { $0.difficulty.priority > $1.difficulty.priority }
            .first { $0.contains(coordinate) }
    }
    
    /// 현재 위치가 슬로프 내부인지 확인
    func isInsideAnySlope(_ location: CLLocation) -> Bool {
        return findSlope(at: location) != nil
    }
    
    /// 현재 위치가 리프트 라인 근처인지 확인
    func isNearLiftLine(_ location: CLLocation) -> Bool {
        let coordinate = location.coordinate
        return liftLines.contains { $0.isNear(coordinate) }
    }
    
    /// 난이도별 슬로프 필터링
    func slopes(by difficulty: SlopeDifficulty) -> [Slope] {
        operatingSlopes.filter { $0.difficulty == difficulty }
    }
    
    /// 슬로프 이름으로 검색
    func findSlope(byName name: String) -> Slope? {
        slopes.first { $0.name == name || $0.koreanName == name }
    }
}

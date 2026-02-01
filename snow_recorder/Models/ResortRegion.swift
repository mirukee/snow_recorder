import CoreLocation

/// 리조트별 대략 좌표/반경 정보 (대시보드용)
struct ResortRegion: Identifiable {
    let id = UUID()
    let key: String
    let displayName: String
    let center: CLLocationCoordinate2D
    let radiusMeters: CLLocationDistance
    
    func contains(_ location: CLLocation) -> Bool {
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return centerLocation.distance(from: location) <= radiusMeters
    }
    
    static func match(for location: CLLocation) -> ResortRegion? {
        var best: (region: ResortRegion, distance: CLLocationDistance)?
        for region in domesticResorts {
            let centerLocation = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
            let distance = centerLocation.distance(from: location)
            guard distance <= region.radiusMeters else { continue }
            if best == nil || distance < (best?.distance ?? .greatestFiniteMagnitude) {
                best = (region, distance)
            }
        }
        return best?.region
    }
    
    // 대략 중심 좌표 기준, 반경 6km 내로 판정
    static let domesticResorts: [ResortRegion] = [
        .init(
            key: "high1",
            displayName: "하이원 리조트",
            center: CLLocationCoordinate2D(latitude: 37.19391, longitude: 128.82935),
            radiusMeters: 6000
        ),
        .init(
            key: "yongpyong",
            displayName: "용평 리조트",
            center: CLLocationCoordinate2D(latitude: 37.643, longitude: 128.682),
            radiusMeters: 6000
        ),
        .init(
            key: "phoenix",
            displayName: "휘닉스 파크",
            center: CLLocationCoordinate2D(latitude: 37.58238, longitude: 128.32682),
            radiusMeters: 6000
        ),
        .init(
            key: "alpensia",
            displayName: "알펜시아 리조트",
            center: CLLocationCoordinate2D(latitude: 37.65727, longitude: 128.67277),
            radiusMeters: 6000
        ),
        .init(
            key: "vivaldi",
            displayName: "비발디 파크",
            center: CLLocationCoordinate2D(latitude: 37.64617, longitude: 127.68124),
            radiusMeters: 6000
        ),
        .init(
            key: "wellihilli",
            displayName: "웰리힐리 파크",
            center: CLLocationCoordinate2D(latitude: 37.490556, longitude: 128.250556),
            radiusMeters: 6000
        ),
        .init(
            key: "gangchon",
            displayName: "엘리시안 강촌",
            center: CLLocationCoordinate2D(latitude: 37.82046, longitude: 127.58253),
            radiusMeters: 6000
        ),
        .init(
            key: "oakvalley",
            displayName: "오크밸리",
            center: CLLocationCoordinate2D(latitude: 37.40664, longitude: 127.81308),
            radiusMeters: 6000
        ),
        .init(
            key: "edenvalley",
            displayName: "에덴밸리",
            center: CLLocationCoordinate2D(latitude: 35.42746, longitude: 128.9932),
            radiusMeters: 6000
        ),
        .init(
            key: "o2",
            displayName: "오투 리조트",
            center: CLLocationCoordinate2D(latitude: 37.17, longitude: 128.937),
            radiusMeters: 6000
        ),
        .init(
            key: "muju",
            displayName: "무주 덕유산 리조트",
            center: CLLocationCoordinate2D(latitude: 35.89083, longitude: 127.73694),
            radiusMeters: 6000
        ),
        .init(
            key: "konjiam",
            displayName: "곤지암 리조트",
            center: CLLocationCoordinate2D(latitude: 37.33, longitude: 127.288),
            radiusMeters: 6000
        ),
        .init(
            key: "jisan",
            displayName: "지산 포레스트 리조트",
            center: CLLocationCoordinate2D(latitude: 37.21569, longitude: 127.34364),
            radiusMeters: 6000
        )
    ]
}

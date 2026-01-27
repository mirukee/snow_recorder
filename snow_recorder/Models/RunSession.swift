import Foundation
import SwiftData
import CoreLocation

/// 스키/보드 주행 기록을 저장하는 데이터 모델
@Model
final class RunSession {
    var id: UUID = UUID()
    var startTime: Date = Date()
    var endTime: Date = Date()
    var duration: TimeInterval = 0
    var distance: Double = 0.0        // 활강 거리 (m) - RIDING 상태에서만 측정됨
    var maxSpeed: Double = 0.0        // 최고 속도 (km/h)
    var avgSpeed: Double = 0.0        // 평균 속도 (km/h) - RIDING 상태에서만 측정됨
    var verticalDrop: Double = 0.0    // 총 하강 고도 (m)
    var runCount: Int = 0           // 런 횟수
    var slopeName: String?      // 주행한 슬로프 이름 (대표 슬로프)
    var riddenSlopes: [String: Int] = [:] // 세션 동안 탄 슬로프 목록 (이름: 횟수)
    var locationName: String = "HIGH1 RESORT"    // 스키장 이름 (예: HIGH1 RESORT)
    var countryCode: String = "UNKNOWN"     // 국가 코드 (예: KR, JP)
    var routeCoordinates: [[Double]] = [] // GPS 경로 좌표 [[lat, lon], ...] - 지도 폴리라인용
    var routeSpeeds: [Double] = []   // GPS 경로별 속도 (km/h) - 히트맵용
    var runStartIndices: [Int] = [0] // 각 런의 시작 인덱스 (리프트 점선 연결용)
    var timelineEvents: [TimelineEvent] = [] // 타임라인 이벤트 목록
    
    // MARK: - 기압계 메트릭 (Optional)
    var baroAvailable: Bool?
    var baroVerticalDrop: Double?
    var baroGain: Double?
    var baroSampleCount: Int?
    var baroBaselineAltitude: Double?
    var baroDriftCorrection: Double?
    
    // MARK: - Riding Metrics
    var edgeScore: Int = 0          // 엣지 점수 (0-1000) (세션 최고점)
    var flowScore: Int = 0          // 플로우 점수 (0-1000) (세션 최고점)
    var maxGForce: Double = 0.0       // 최대 G-Force (세션 최고점)
    
    // 런별 상세 기록 (Run Metrics)
    var runMetrics: [RunMetric] = []
    
    // MARK: - 분석 리포트 데이터
    var analysisSamples: [AnalysisSample] = []
    var analysisEvents: [AnalysisEvent] = []
    var analysisSegments: [AnalysisSegment] = []
    var flowBreakdown: FlowScoreBreakdown = RunSession.FlowScoreBreakdown.empty
    var edgeBreakdown: EdgeScoreBreakdown = RunSession.EdgeScoreBreakdown.empty
    
    struct RunMetric: Codable, Identifiable {
        var id: UUID = UUID()
        var runNumber: Int
        var slopeName: String
        var startTime: Date
        var endTime: Date
        var duration: TimeInterval
        var distance: Double = 0.0
        var verticalDrop: Double = 0.0
        var maxSpeed: Double
        var avgSpeed: Double
        var edgeScore: Int
        var flowScore: Int
        var maxGForce: Double
        
        enum CodingKeys: String, CodingKey {
            case id
            case runNumber
            case slopeName
            case startTime
            case endTime
            case duration
            case distance
            case verticalDrop
            case maxSpeed
            case avgSpeed
            case edgeScore
            case flowScore
            case maxGForce
        }
        
        init(
            id: UUID = UUID(),
            runNumber: Int,
            slopeName: String,
            startTime: Date,
            endTime: Date,
            duration: TimeInterval,
            distance: Double = 0.0,
            verticalDrop: Double = 0.0,
            maxSpeed: Double,
            avgSpeed: Double,
            edgeScore: Int,
            flowScore: Int,
            maxGForce: Double
        ) {
            self.id = id
            self.runNumber = runNumber
            self.slopeName = slopeName
            self.startTime = startTime
            self.endTime = endTime
            self.duration = duration
            self.distance = distance
            self.verticalDrop = verticalDrop
            self.maxSpeed = maxSpeed
            self.avgSpeed = avgSpeed
            self.edgeScore = edgeScore
            self.flowScore = flowScore
            self.maxGForce = maxGForce
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            runNumber = try container.decode(Int.self, forKey: .runNumber)
            slopeName = try container.decode(String.self, forKey: .slopeName)
            startTime = try container.decode(Date.self, forKey: .startTime)
            endTime = try container.decode(Date.self, forKey: .endTime)
            duration = try container.decode(TimeInterval.self, forKey: .duration)
            distance = try container.decodeIfPresent(Double.self, forKey: .distance) ?? 0.0
            verticalDrop = try container.decodeIfPresent(Double.self, forKey: .verticalDrop) ?? 0.0
            maxSpeed = try container.decode(Double.self, forKey: .maxSpeed)
            avgSpeed = try container.decode(Double.self, forKey: .avgSpeed)
            edgeScore = try container.decode(Int.self, forKey: .edgeScore)
            flowScore = try container.decode(Int.self, forKey: .flowScore)
            maxGForce = try container.decode(Double.self, forKey: .maxGForce)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(runNumber, forKey: .runNumber)
            try container.encode(slopeName, forKey: .slopeName)
            try container.encode(startTime, forKey: .startTime)
            try container.encode(endTime, forKey: .endTime)
            try container.encode(duration, forKey: .duration)
            try container.encode(distance, forKey: .distance)
            try container.encode(verticalDrop, forKey: .verticalDrop)
            try container.encode(maxSpeed, forKey: .maxSpeed)
            try container.encode(avgSpeed, forKey: .avgSpeed)
            try container.encode(edgeScore, forKey: .edgeScore)
            try container.encode(flowScore, forKey: .flowScore)
            try container.encode(maxGForce, forKey: .maxGForce)
        }
    }
    
    // 타임라인 이벤트 구조체 (Nested Struct)
    struct TimelineEvent: Codable, Identifiable {
        var id: UUID = UUID()
        var type: EventType
        var startTime: Date
        var endTime: Date?
        var detail: String // 예: "제우스 3", "리프트", "휴식" 등
        
        enum EventType: String, Codable {
            case riding
            case lift
            case rest
            case pause
            case unknown
        }
        
        var duration: TimeInterval {
            guard let end = endTime else { return 0 }
            return end.timeIntervalSince(startTime)
        }
    }
    
    // MARK: - 분석 샘플 (1초 단위)
    struct AnalysisSample: Codable, Identifiable {
        var id: UUID = UUID()
        var t: Double                 // 세션 시작 기준 초
        var speedAvg: Double          // km/h
        var speedMax: Double          // km/h
        var speedStdDev: Double       // km/h
        var gAvg: Double              // G
        var gMax: Double              // G
        var jerkPeak: Double          // G/s
    }
    
    // MARK: - 이벤트 로그
    struct AnalysisEvent: Codable, Identifiable {
        enum EventType: String, Codable {
            case hardBrake
            case chatter
            case quietPhase
        }
        
        var id: UUID = UUID()
        var t: Double                 // 세션 시작 기준 초
        var type: EventType
        var value: Double?            // 타입별 추가 값 (예: 브레이크 지속 시간)
        var speed: Double?            // km/h
    }
    
    // MARK: - 이벤트 구간 (10Hz)
    struct AnalysisSegment: Codable, Identifiable {
        var id: UUID = UUID()
        var type: AnalysisEvent.EventType
        var tStart: Double            // 세션 시작 기준 초
        var interval: Double          // 샘플 간격(초)
        var gSamples: [Double]        // G
        var jerkSamples: [Double]     // G/s
        var speedSamples: [Double]    // km/h
    }
    
    // MARK: - 점수 구성요소 (Flow)
    struct FlowScoreBreakdown: Codable {
        var avgStability: Double?
        var baseScore: Double?
        var activeTime: Double?
        var movingTime: Double?
        var totalStopDuration: Double?
        var stopPenalty: Double?
        var hardBrakeCount: Int?
        var brakePenalty: Double?
        var chatterEventCount: Int?
        var chatterPenalty: Double?
        var quietEventCount: Int?
        var quietBonus: Double?
        var finalScore: Int?
        var locationSampleCount: Int?
        var locationSampleSkippedAccuracyCount: Int?
        var locationSampleUsedCount: Int?
        var stabilitySampleCount: Int?
        
        static let empty = FlowScoreBreakdown(
            avgStability: 0.0,
            baseScore: 0.0,
            activeTime: 0.0,
            movingTime: 0.0,
            totalStopDuration: 0.0,
            stopPenalty: 0.0,
            hardBrakeCount: 0,
            brakePenalty: 0.0,
            chatterEventCount: 0,
            chatterPenalty: 0.0,
            quietEventCount: 0,
            quietBonus: 0.0,
            finalScore: 0,
            locationSampleCount: 0,
            locationSampleSkippedAccuracyCount: 0,
            locationSampleUsedCount: 0,
            stabilitySampleCount: 0
        )
    }
    
    // MARK: - 점수 구성요소 (Edge)
    struct EdgeScoreBreakdown: Codable {
        var edgeRawScore: Double?
        var normalized: Double?
        var rawScore: Double?
        var finalScore: Int?
        var maxGForce: Double?
        var tieredTimeTotal: Double?
        var tier2PlusTime: Double?
        var tier2Ratio: Double?
        var proCapApplied: Bool?
        var tier2CapApplied: Bool?
        
        static let empty = EdgeScoreBreakdown(
            edgeRawScore: 0.0,
            normalized: 0.0,
            rawScore: 0.0,
            finalScore: 0,
            maxGForce: 0.0,
            tieredTimeTotal: 0.0,
            tier2PlusTime: 0.0,
            tier2Ratio: 0.0,
            proCapApplied: false,
            tier2CapApplied: false
        )
    }
    
    init(
        startTime: Date,
        endTime: Date,
        duration: TimeInterval,
        distance: Double,
        maxSpeed: Double,
        avgSpeed: Double = 0.0,
        verticalDrop: Double = 0.0,
        runCount: Int = 0,
        slopeName: String? = nil,
        riddenSlopes: [String: Int] = [:],
        locationName: String = "HIGH1 RESORT",
        countryCode: String = "UNKNOWN",
        routeCoordinates: [[Double]] = [],
        routeSpeeds: [Double] = [],
        runStartIndices: [Int] = [0],
        timelineEvents: [TimelineEvent] = [],
        edgeScore: Int = 0,
        flowScore: Int = 0,
        maxGForce: Double = 0.0,
        baroAvailable: Bool? = nil,
        baroVerticalDrop: Double? = nil,
        baroGain: Double? = nil,
        baroSampleCount: Int? = nil,
        baroBaselineAltitude: Double? = nil,
        baroDriftCorrection: Double? = nil,
        analysisSamples: [AnalysisSample] = [],
        analysisEvents: [AnalysisEvent] = [],
        analysisSegments: [AnalysisSegment] = [],
        flowBreakdown: FlowScoreBreakdown = .empty,
        edgeBreakdown: EdgeScoreBreakdown = .empty
    ) {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.distance = distance
        self.maxSpeed = maxSpeed
        self.avgSpeed = avgSpeed
        self.verticalDrop = verticalDrop
        self.runCount = runCount
        self.slopeName = slopeName
        self.riddenSlopes = riddenSlopes
        self.locationName = locationName
        self.countryCode = countryCode
        self.routeCoordinates = routeCoordinates
        self.routeSpeeds = routeSpeeds
        self.runStartIndices = runStartIndices
        self.timelineEvents = timelineEvents
        self.edgeScore = edgeScore
        self.flowScore = flowScore
        self.maxGForce = maxGForce
        self.baroAvailable = baroAvailable
        self.baroVerticalDrop = baroVerticalDrop
        self.baroGain = baroGain
        self.baroSampleCount = baroSampleCount
        self.baroBaselineAltitude = baroBaselineAltitude
        self.baroDriftCorrection = baroDriftCorrection
        self.analysisSamples = analysisSamples
        self.analysisEvents = analysisEvents
        self.analysisSegments = analysisSegments
        self.flowBreakdown = flowBreakdown
        self.edgeBreakdown = edgeBreakdown
    }
    
    // MARK: - Helper Properties
    var coordinates: [CLLocationCoordinate2D] {
        routeCoordinates.compactMap { coord in
            guard coord.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: coord[0], longitude: coord[1])
        }
    }
}


// MARK: - Test Data Generation
extension RunSession {
    static func createMockSession(context: ModelContext) {
        let calendar = Calendar.current
        let now = Date()
        // Start time calculation (approx 1h duration total)
        let startTime = now.addingTimeInterval(-3600)
        
        var currentCoordinates: [[Double]] = []
        var currentSpeeds: [Double] = []
        var runStartIndices: [Int] = []
        var timelineEvents: [RunSession.TimelineEvent] = []
        
        var currentTime = startTime
        
        // --- Helper for interpolation ---
        func addSegment(from start: (lat: Double, lon: Double), to end: (lat: Double, lon: Double), duration: TimeInterval, type: RunSession.TimelineEvent.EventType, name: String) {
            let eventStart = currentTime
            let steps = Int(duration) // 1 point per second approx
            
            // Record Run Start Index if riding
            if type == .riding {
                runStartIndices.append(currentCoordinates.count)
            }
            
            for i in 0...steps {
                let ratio = Double(i) / Double(steps)
                let lat = start.lat + (end.lat - start.lat) * ratio
                let lon = start.lon + (end.lon - start.lon) * ratio
                let coord = [lat + Double.random(in: -0.00005...0.00005), lon + Double.random(in: -0.00005...0.00005)]
                
                currentCoordinates.append(coord)
                
                // Speed Logic
                var speed: Double = 0.0
                switch type {
                case .riding:
                    // Curve speed: Fast in middle
                    speed = 20.0 + 40.0 * sin(ratio * .pi) + Double.random(in: -5...5)
                case .lift:
                    speed = 15.0 // Constant
                case .rest:
                    speed = 0.0
                case .unknown, .pause:
                    speed = 2.0 // Walking
                }
                currentSpeeds.append(max(0, speed))
            }
            
            currentTime = currentTime.addingTimeInterval(duration)
            
            // Add Event
            timelineEvents.append(RunSession.TimelineEvent(
                type: type,
                startTime: eventStart,
                endTime: currentTime,
                detail: name
            ))
        }
        
        // Coordinates (Approximate High1)
        let valleyHub = (lat: 37.2000, lon: 128.8280)
        let heraStation = (lat: 37.2010, lon: 128.8290)
        let heraTop = (lat: 37.2080, lon: 128.8350)
        let victoriaStation = (lat: 37.2005, lon: 128.8285)
        let victoriaTop = (lat: 37.2150, lon: 128.8400)
        
        // 1. Valley Hub Start > Walk to Hera Lift (5 min)
        addSegment(from: valleyHub, to: heraStation, duration: 300, type: .unknown, name: "이동")
        
        // 2. Hera Lift (10 min)
        addSegment(from: heraStation, to: heraTop, duration: 600, type: .lift, name: "헤라 리프트")
        
        // 3. Hera 3 Run (5 min)
        addSegment(from: heraTop, to: valleyHub, duration: 300, type: .riding, name: "헤라 3")
        
        // 4. Rest at Valley Hub (10 min) - No movement (repeat same coord)
        // Since we process segments by distance in real app, we might check if duplicate coords are issue.
        // LocationManager filters by distance 5m. Mock data doesn't filter, so we add duplicates.
        // But for map visual, duplicates stack.
        // Let's create a *timeline event* but NOT add many points, maybe just one or two to simulate drift.
        let restStart = currentTime
        currentTime = currentTime.addingTimeInterval(600) // +10 mins
        timelineEvents.append(RunSession.TimelineEvent(type: .rest, startTime: restStart, endTime: currentTime, detail: "휴식"))
        // Add minimal drift points for heatmap continuity? No, rest is gap.
        
        // 5. Walk to Victoria Lift (2 min)
        addSegment(from: valleyHub, to: victoriaStation, duration: 120, type: .unknown, name: "이동")
        
        // 6. Victoria Lift (15 min)
        addSegment(from: victoriaStation, to: victoriaTop, duration: 900, type: .lift, name: "빅토리아 리프트")
        
        // 7. Victoria 1 Run (Top -> Valley Hub) (7 min)
        addSegment(from: victoriaTop, to: valleyHub, duration: 420, type: .riding, name: "빅토리아 1")
        
        
        // Create Session
        let session = RunSession(
            startTime: startTime,
            endTime: currentTime,
            duration: currentTime.timeIntervalSince(startTime),
            distance: 4500, // Approx
            maxSpeed: currentSpeeds.max() ?? 0,
            avgSpeed: currentSpeeds.reduce(0, +) / Double(max(1, currentSpeeds.count)),
            verticalDrop: 600,
            runCount: 2,
            slopeName: "헤라 3",
            riddenSlopes: ["헤라 3": 1, "빅토리아 1": 1],
            locationName: "HIGH1 RESORT",
            countryCode: "KR",
            routeCoordinates: currentCoordinates,
            routeSpeeds: currentSpeeds,
            runStartIndices: runStartIndices,
            timelineEvents: timelineEvents
        )
        
        context.insert(session)
        print("✅ Mock Session Created: Customized High1 Scenario")
    }
}

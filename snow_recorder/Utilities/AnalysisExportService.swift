import Foundation

/// 분석 리포트 내보내기용 페이로드
struct AnalysisExportPayload: Codable {
    struct Meta: Codable {
        var schemaVersion: Int
        var appVersion: String
        var exportTime: Date
    }
    
    struct SessionSummary: Codable {
        var id: String
        var startTime: Date
        var endTime: Date
        var duration: TimeInterval
        var distance: Double
        var maxSpeed: Double
        var avgSpeed: Double
        var verticalDrop: Double
        var runCount: Int
        var slopeName: String?
        var locationName: String
    }
    
    struct Diagnostics: Codable {
        var routeSpeedCount: Int
        var runStartIndices: [Int]
        var runEndIndices: [Int]
        var runMetricsCount: Int
    }
    
    struct ScoreSummary: Codable {
        var edgeScore: Int
        var flowScore: Int
        var maxGForce: Double
    }
    
    var meta: Meta
    var session: SessionSummary
    var scores: ScoreSummary
    var flowBreakdown: RunSession.FlowScoreBreakdown
    var edgeBreakdown: RunSession.EdgeScoreBreakdown
    var samples: [RunSession.AnalysisSample]
    var events: [RunSession.AnalysisEvent]
    var segments: [RunSession.AnalysisSegment]
    var runMetrics: [RunSession.RunMetric]
    var diagnostics: Diagnostics
}

enum AnalysisExportError: Error {
    case noData
}

/// 분석 데이터 내보내기 서비스
enum AnalysisExportService {
    static func hasAnalysisData(session: RunSession) -> Bool {
        return session.duration > 0
            || !session.runMetrics.isEmpty
            || !session.analysisSamples.isEmpty
            || !session.analysisEvents.isEmpty
            || !session.analysisSegments.isEmpty
    }
    
    static func export(session: RunSession) throws -> URL {
        guard hasAnalysisData(session: session) else {
            throw AnalysisExportError.noData
        }
        
        let payload = AnalysisExportPayload(
            meta: .init(
                schemaVersion: 3,
                appVersion: appVersion(),
                exportTime: Date()
            ),
            session: .init(
                id: session.id.uuidString,
                startTime: session.startTime,
                endTime: session.endTime,
                duration: session.duration,
                distance: session.distance,
                maxSpeed: session.maxSpeed,
                avgSpeed: session.avgSpeed,
                verticalDrop: session.verticalDrop,
                runCount: session.runCount,
                slopeName: session.slopeName,
                locationName: session.locationName
            ),
            scores: .init(
                edgeScore: session.edgeScore,
                flowScore: session.flowScore,
                maxGForce: session.maxGForce
            ),
            flowBreakdown: session.flowBreakdown ?? .empty,
            edgeBreakdown: session.edgeBreakdown ?? .empty,
            samples: session.analysisSamples,
            events: session.analysisEvents,
            segments: session.analysisSegments,
            runMetrics: session.runMetrics,
            diagnostics: .init(
                routeSpeedCount: session.routeSpeeds.count,
                runStartIndices: session.runStartIndices,
                runEndIndices: session.runStartIndices.indices.map { index in
                    if index < session.runStartIndices.count - 1 {
                        return session.runStartIndices[index + 1]
                    }
                    return session.routeSpeeds.count
                },
                runMetricsCount: session.runMetrics.count
            )
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(payload)
        let fileURL = makeExportURL(startTime: session.startTime)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
    
    private static func appVersion() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let version, let build {
            return "\(version) (\(build))"
        }
        return version ?? "unknown"
    }
    
    private static func makeExportURL(startTime: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timeString = formatter.string(from: startTime)
        let fileName = "SnowRecord_Analysis_\(timeString).json"
        return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }
}

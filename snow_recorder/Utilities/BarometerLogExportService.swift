import Foundation

/// 바리오 로그 내보내기 페이로드
struct BarometerLogPayload: Codable {
    struct Meta: Codable {
        var schemaVersion: Int
        var appVersion: String
        var exportTime: Date
    }
    
    struct Summary: Codable {
        var startTime: Date
        var endTime: Date
        var baroAvailable: Bool
        var baroSampleCount: Int
        var baroGainTotal: Double
        var baroDropTotal: Double
        var baroDriftCorrection: Double
        var baroDriftOffset: Double
        var baroOutlierCount: Int
        var gpsAltitudeOutlierCount: Int
        var driftUpdateCount: Int
        var baselineSampleWindow: Int
        var baselineDelay: TimeInterval?
    }
    
    struct Entry: Codable {
        var timestamp: Date
        var baroAltitude: Double?
        var verticalSpeed: Double?
        var speed: Double?
        var state: String?
        var recentGain: Double?
        var recentDrop: Double?
        var note: String?
    }
    
    var meta: Meta
    var summary: Summary
    var logs: [Entry]
}

enum BarometerLogExportError: Error {
    case noData
}

/// 바리오 로그 내보내기 서비스
enum BarometerLogExportService {
    static func export(summary: BarometerLogPayload.Summary, logs: [BarometerLogPayload.Entry]) throws -> URL {
        guard !logs.isEmpty else {
            throw BarometerLogExportError.noData
        }
        
        let payload = BarometerLogPayload(
            meta: .init(
                schemaVersion: 1,
                appVersion: appVersion(),
                exportTime: Date()
            ),
            summary: summary,
            logs: logs
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(payload)
        let fileURL = makeExportURL(startTime: summary.startTime)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
    
    static func existingURL(startTime: Date) -> URL {
        makeExportURL(startTime: startTime)
    }
    
    private static func makeExportURL(startTime: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timeString = formatter.string(from: startTime)
        let fileName = "SnowRecord_Barometer_\(timeString).json"
        
        let baseDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let targetDir = (baseDir ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("BarometerLogs", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: targetDir.path) {
            try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        }
        
        return targetDir.appendingPathComponent(fileName)
    }
    
    private static func appVersion() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let version, let build {
            return "\(version) (\(build))"
        }
        return version ?? "unknown"
    }
}

import Foundation
import CloudKit
import SwiftData
import UIKit

final class CloudBackupService {
    static let shared = CloudBackupService()
    
    private let recordType = "RunSessionBackup"
    private let payloadVersion = 1
    private let database = CKContainer.default().privateCloudDatabase
    private let userDefaults = UserDefaults.standard
    private let lastBackupKey = "icloud_last_backup_at"
    private let maxRoutePoints = 2000
    
    struct BackupMetadata {
        let createdAt: Date
        let sessionCount: Int
    }
    
    enum BackupError: Error {
        case noBackup
        case invalidPayload
        case assetMissing
        case assetReadFailed
        case tempFileWriteFailed
    }
    
    func lastBackupDate() -> Date? {
        return userDefaults.object(forKey: lastBackupKey) as? Date
    }
    
    func backup(sessions: [RunSession]) async throws -> BackupMetadata {
        let payload = makePayload(from: sessions)
        let fileURL = try writePayloadToTempFile(payload)
        
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        let record = CKRecord(recordType: recordType)
        record["version"] = payloadVersion as CKRecordValue
        record["createdAt"] = payload.createdAt as CKRecordValue
        record["deviceName"] = payload.deviceName as CKRecordValue
        record["appVersion"] = payload.appVersion as CKRecordValue
        record["sessionCount"] = payload.sessions.count as CKRecordValue
        record["payload"] = CKAsset(fileURL: fileURL)
        
        _ = try await database.save(record)
        userDefaults.set(payload.createdAt, forKey: lastBackupKey)
        return BackupMetadata(createdAt: payload.createdAt, sessionCount: payload.sessions.count)
    }
    
    func fetchLatestMetadata() async throws -> BackupMetadata? {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        
        let result = try await database.records(matching: query, resultsLimit: 1)
        guard let match = result.matchResults.first else {
            return nil
        }
        let record = try match.1.get()
        guard let createdAt = record["createdAt"] as? Date else {
            return nil
        }
        let sessionCount = record["sessionCount"] as? Int ?? 0
        return BackupMetadata(createdAt: createdAt, sessionCount: sessionCount)
    }
    
    @MainActor
    func restoreLatestBackup(context: ModelContext) async throws -> BackupMetadata {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        
        let result = try await database.records(matching: query, resultsLimit: 1)
        guard let match = result.matchResults.first else {
            throw BackupError.noBackup
        }
        let record = try match.1.get()
        guard let asset = record["payload"] as? CKAsset else {
            throw BackupError.assetMissing
        }
        guard let fileURL = asset.fileURL else {
            throw BackupError.assetReadFailed
        }
        let data = try Data(contentsOf: fileURL)
        let payload = try decodePayload(data)
        
        let existing = try context.fetch(FetchDescriptor<RunSession>())
        for session in existing {
            context.delete(session)
        }
        
        for sessionPayload in payload.sessions {
            let session = makeSession(from: sessionPayload)
            context.insert(session)
        }
        
        try context.save()
        userDefaults.set(payload.createdAt, forKey: lastBackupKey)
        return BackupMetadata(createdAt: payload.createdAt, sessionCount: payload.sessions.count)
    }
    
    private func makePayload(from sessions: [RunSession]) -> BackupPayload {
        let sorted = sessions.sorted { $0.startTime < $1.startTime }
        let deviceName = UIDevice.current.name
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let sessionPayloads = sorted.map { makeSessionPayload(from: $0) }
        
        return BackupPayload(
            version: payloadVersion,
            createdAt: Date(),
            deviceName: deviceName,
            appVersion: appVersion,
            sessions: sessionPayloads
        )
    }
    
    private func makeSessionPayload(from session: RunSession) -> RunSessionPayload {
        let indices = downsampleIndices(count: session.routeCoordinates.count, maxPoints: maxRoutePoints)
        
        return RunSessionPayload(
            id: session.id,
            startTime: session.startTime,
            endTime: session.endTime,
            duration: session.duration,
            distance: session.distance,
            maxSpeed: session.maxSpeed,
            avgSpeed: session.avgSpeed,
            verticalDrop: session.verticalDrop,
            runCount: session.runCount,
            userID: session.userID,
            slopeName: session.slopeName,
            riddenSlopes: session.riddenSlopes,
            locationName: session.locationName,
            countryCode: session.countryCode,
            routeCoordinates: sampleArray(session.routeCoordinates, indices: indices),
            routeSpeeds: sampleArray(session.routeSpeeds, indices: indices),
            routeTimestamps: sampleArray(session.routeTimestamps, indices: indices),
            routeAltitudes: sampleArray(session.routeAltitudes, indices: indices),
            routeDistances: sampleArray(session.routeDistances, indices: indices),
            routeStates: sampleArray(session.routeStates, indices: indices),
            runStartIndices: session.runStartIndices,
            timelineEvents: session.timelineEvents,
            edgeScore: session.edgeScore,
            flowScore: session.flowScore,
            maxGForce: session.maxGForce,
            baroAvailable: session.baroAvailable,
            baroVerticalDrop: session.baroVerticalDrop,
            baroGain: session.baroGain,
            baroSampleCount: session.baroSampleCount,
            baroBaselineAltitude: session.baroBaselineAltitude,
            baroDriftCorrection: session.baroDriftCorrection,
            runMetrics: session.runMetrics,
            analysisSamples: session.analysisSamples,
            analysisEvents: session.analysisEvents,
            analysisSegments: session.analysisSegments,
            gForceSamples: session.gForceSamples,
            flowBreakdown: session.flowBreakdown,
            edgeBreakdown: session.edgeBreakdown
        )
    }
    
    private func makeSession(from payload: RunSessionPayload) -> RunSession {
        let session = RunSession(
            startTime: payload.startTime,
            endTime: payload.endTime,
            duration: payload.duration,
            distance: payload.distance,
            maxSpeed: payload.maxSpeed,
            avgSpeed: payload.avgSpeed,
            verticalDrop: payload.verticalDrop,
            runCount: payload.runCount,
            userID: payload.userID,
            slopeName: payload.slopeName,
            riddenSlopes: payload.riddenSlopes,
            locationName: payload.locationName,
            countryCode: payload.countryCode,
            routeCoordinates: payload.routeCoordinates,
            routeSpeeds: payload.routeSpeeds,
            routeTimestamps: payload.routeTimestamps,
            routeAltitudes: payload.routeAltitudes,
            routeDistances: payload.routeDistances,
            routeStates: payload.routeStates,
            runStartIndices: payload.runStartIndices,
            timelineEvents: payload.timelineEvents,
            edgeScore: payload.edgeScore,
            flowScore: payload.flowScore,
            maxGForce: payload.maxGForce,
            baroAvailable: payload.baroAvailable,
            baroVerticalDrop: payload.baroVerticalDrop,
            baroGain: payload.baroGain,
            baroSampleCount: payload.baroSampleCount,
            baroBaselineAltitude: payload.baroBaselineAltitude,
            baroDriftCorrection: payload.baroDriftCorrection,
            analysisSamples: payload.analysisSamples,
            analysisEvents: payload.analysisEvents,
            analysisSegments: payload.analysisSegments,
            gForceSamples: payload.gForceSamples,
            flowBreakdown: payload.flowBreakdown ?? .empty,
            edgeBreakdown: payload.edgeBreakdown ?? .empty
        )
        session.id = payload.id
        session.runMetrics = payload.runMetrics
        return session
    }
    
    private func writePayloadToTempFile(_ payload: BackupPayload) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("snow_record_backup_\(UUID().uuidString)")
            .appendingPathExtension("json")
        
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw BackupError.tempFileWriteFailed
        }
        
        return fileURL
    }
    
    private func decodePayload(_ data: Data) throws -> BackupPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupPayload.self, from: data)
    }
    
    private func downsampleIndices(count: Int, maxPoints: Int) -> [Int] {
        guard count > maxPoints, maxPoints > 1 else {
            return Array(0..<count)
        }
        let stride = Double(count - 1) / Double(maxPoints - 1)
        return (0..<maxPoints).map { index in
            Int(round(Double(index) * stride))
        }
    }
    
    private func sampleArray<T>(_ array: [T], indices: [Int]) -> [T] {
        guard !array.isEmpty else { return [] }
        return indices.compactMap { index in
            guard index >= 0, index < array.count else { return nil }
            return array[index]
        }
    }
}

private struct BackupPayload: Codable {
    let version: Int
    let createdAt: Date
    let deviceName: String
    let appVersion: String
    let sessions: [RunSessionPayload]
}

private struct RunSessionPayload: Codable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval
    let distance: Double
    let maxSpeed: Double
    let avgSpeed: Double
    let verticalDrop: Double
    let runCount: Int
    let userID: String?
    let slopeName: String?
    let riddenSlopes: [String: Int]
    let locationName: String
    let countryCode: String
    let routeCoordinates: [[Double]]
    let routeSpeeds: [Double]
    let routeTimestamps: [TimeInterval]
    let routeAltitudes: [Double]
    let routeDistances: [Double]
    let routeStates: [RunSession.TimelineEvent.EventType]
    let runStartIndices: [Int]
    let timelineEvents: [RunSession.TimelineEvent]
    let edgeScore: Int
    let flowScore: Int
    let maxGForce: Double
    let baroAvailable: Bool?
    let baroVerticalDrop: Double?
    let baroGain: Double?
    let baroSampleCount: Int?
    let baroBaselineAltitude: Double?
    let baroDriftCorrection: Double?
    let runMetrics: [RunSession.RunMetric]
    let analysisSamples: [RunSession.AnalysisSample]
    let analysisEvents: [RunSession.AnalysisEvent]
    let analysisSegments: [RunSession.AnalysisSegment]
    let gForceSamples: [RunSession.GForceSample]?
    let flowBreakdown: RunSession.FlowScoreBreakdown?
    let edgeBreakdown: RunSession.EdgeScoreBreakdown?
}

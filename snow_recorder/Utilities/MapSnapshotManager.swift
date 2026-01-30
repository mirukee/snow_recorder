import Foundation
import MapKit
import UIKit

/// Manages generating and caching map snapshots for RunSessions
class MapSnapshotManager {
    static let shared = MapSnapshotManager()
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    private init() {
        // Create a specific subdirectory for map snapshots
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("MapSnapshots_v2")
        
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    /// Returns the file URL for a given session ID
    func snapshotURL(for sessionID: UUID) -> URL {
        return cacheDirectory.appendingPathComponent("\(sessionID.uuidString).png")
    }
    
    /// Checks if a snapshot exists for the given session ID
    func snapshotExists(for sessionID: UUID) -> Bool {
        return fileManager.fileExists(atPath: snapshotURL(for: sessionID).path)
    }
    
    /// Loads a snapshot from disk if available
    func loadSnapshot(for sessionID: UUID) -> UIImage? {
        let url = snapshotURL(for: sessionID)
        if let data = try? Data(contentsOf: url) {
            return UIImage(data: data)
        }
        return nil
    }
    
    /// Generates a map snapshot for the session
    /// - Parameters:
    ///   - coordinates: The route coordinates
    ///   - routeStates: The states for each coordinate (optional)
    ///   - size: Target size for the image
    ///   - sessionID: The UUID of the session (for saving)
    ///   - completion: Completion handler with the generated image
    func generateSnapshot(coordinates: [CLLocationCoordinate2D], routeStates: [RunSession.TimelineEvent.EventType]? = nil, size: CGSize, sessionID: UUID, completion: @escaping (UIImage?) -> Void) {
        // 1. Check if already exists (although usually caller checks)
        if let existing = loadSnapshot(for: sessionID) {
            completion(existing)
            return
        }
        
        guard !coordinates.isEmpty else {
            completion(nil)
            return
        }
        
        // 2. Setup Options
        let options = MKMapSnapshotter.Options()
        options.region = calculateRegion(from: coordinates)
        options.size = size
        options.scale = UIScreen.main.scale
        options.mapType = .standard
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark) // Dark mode map
        
        // 3. Create Snapshotter
        let snapshotter = MKMapSnapshotter(options: options)
        
        snapshotter.start { [weak self] snapshot, error in
            guard let self = self, let snapshot = snapshot, error == nil else {
                print("❌ Snapshot generation failed: \(error?.localizedDescription ?? "Unknown error")")
                completion(nil)
                return
            }
            
            // 4. Draw Polyline on the Snapshot
            let image = self.drawOverlay(on: snapshot, coordinates: coordinates, routeStates: routeStates)
            
            // 5. Save to Disk
            self.saveSnapshot(image, for: sessionID)
            
            completion(image)
        }
    }
    
    private func saveSnapshot(_ image: UIImage, for sessionID: UUID) {
        guard let data = image.pngData() else { return }
        let url = snapshotURL(for: sessionID)
        try? data.write(to: url)
    }
    
    // MARK: - Helper: Draw Polyline
    private func drawOverlay(on snapshot: MKMapSnapshotter.Snapshot, coordinates: [CLLocationCoordinate2D], routeStates: [RunSession.TimelineEvent.EventType]?) -> UIImage {
        let image = snapshot.image
        
        UIGraphicsBeginImageContextWithOptions(image.size, true, image.scale)
        image.draw(at: .zero)
        
        guard let context = UIGraphicsGetCurrentContext() else { return image }
        
        let neonColor = UIColor(red: 107/255, green: 249/255, blue: 6/255, alpha: 1.0)
        
        if let states = routeStates, states.count == coordinates.count {
            // --- State-based Drawing ---
            let points = coordinates.map { snapshot.point(for: $0) }
            
            // 1. Draw Dotted Lines (Lifts/Rest) - Bottom Layer
            context.setLineWidth(2.0)
            context.setStrokeColor(neonColor.withAlphaComponent(0.5).cgColor)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setLineDash(phase: 0, lengths: [4, 4])
            
            context.beginPath()
            var i = 0
            while i < points.count - 1 {
                if states[i] != .riding {
                    context.move(to: points[i])
                    while i < points.count - 1 && states[i+1] != .riding {
                        i += 1
                        context.addLine(to: points[i])
                    }
                    // Transition
                    if i < points.count - 1 {
                        context.addLine(to: points[i+1])
                        i += 1 // Fix: Advance index to prevent infinite loop
                    }
                } else {
                    i += 1
                }
            }
            context.strokePath()
            
            // 2. Draw Solid Lines (Riding) - Top Layer
            context.setLineWidth(3.0)
            context.setStrokeColor(neonColor.cgColor)
            context.setLineDash(phase: 0, lengths: []) // Reset dash
            
            context.beginPath()
            i = 0
            while i < points.count - 1 {
                if states[i] == .riding {
                    context.move(to: points[i])
                    while i < points.count - 1 && states[i+1] == .riding {
                        i += 1
                        context.addLine(to: points[i])
                    }
                    // Transition
                    if i < points.count - 1 {
                        context.addLine(to: points[i+1])
                        i += 1 // Fix: Advance index to prevent infinite loop
                    }
                } else {
                    i += 1
                }
            }
            context.strokePath()
            
        } else {
            // --- Fallback: Simple Solid Line ---
            context.setLineWidth(3.0)
            context.setStrokeColor(neonColor.cgColor)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            
            if !coordinates.isEmpty {
                let points = coordinates.map { snapshot.point(for: $0) }
                context.move(to: points[0])
                for point in points.dropFirst() {
                    context.addLine(to: point)
                }
                context.strokePath()
            }
        }
        
        let compositeImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return compositeImage ?? image
    }
    
    // MARK: - Helper: Region Calculation (Copied/Adapted logic)
    private func calculateRegion(from coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !coordinates.isEmpty else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 37, longitude: 127), span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        }
        
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude
        
        for coord in coordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }
        
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: (maxLat - minLat) * 1.5, longitudeDelta: (maxLon - minLon) * 1.5)
        
        return MKCoordinateRegion(center: center, span: span)
    }
}

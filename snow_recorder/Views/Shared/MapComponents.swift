import SwiftUI
import MapKit

/// Calculates the map region strictly bounding the coordinates with some padding
func calculateMapRegion(from coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
    guard !coordinates.isEmpty else {
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.198, longitude: 128.825), // High1 Resort default
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
    }
    
    let lats = coordinates.map { $0.latitude }
    let lons = coordinates.map { $0.longitude }
    let center = CLLocationCoordinate2D(
        latitude: (lats.min()! + lats.max()!) / 2,
        longitude: (lons.min()! + lons.max()!) / 2
    )
    let span = MKCoordinateSpan(
        latitudeDelta: max((lats.max()! - lats.min()!) * 1.5, 0.005),
        longitudeDelta: max((lons.max()! - lons.min()!) * 1.5, 0.005)
    )
    return MKCoordinateRegion(center: center, span: span)
}

// MARK: - Map Route Overlay (Simple)
struct MapRouteOverlay: View {
    let coordinates: [CLLocationCoordinate2D]
    let color: Color
    
    var body: some View {
        GeometryReader { geometry in
            if coordinates.count >= 2 {
                Path { path in
                    let points = coordinates.map { coord -> CGPoint in
                        projectToView(coord, in: geometry.size)
                    }
                    path.move(to: points[0])
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .shadow(color: color.opacity(0.8), radius: 5)
            }
        }
    }
    
    private func projectToView(_ coord: CLLocationCoordinate2D, in size: CGSize) -> CGPoint {
        guard coordinates.count >= 2 else { return .zero }
        let lats = coordinates.map { $0.latitude }
        let lons = coordinates.map { $0.longitude }
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        
        // Avoid division by zero
        let latRange = max(maxLat - minLat, 0.001)
        let lonRange = max(maxLon - minLon, 0.001)
        let padding: CGFloat = 0.15
        
        let normalizedX = CGFloat((coord.longitude - minLon) / lonRange) * (1 - 2 * padding) + padding
        let normalizedY = 1 - (CGFloat((coord.latitude - minLat) / latRange) * (1 - 2 * padding) + padding)
        
        return CGPoint(x: normalizedX * size.width, y: normalizedY * size.height)
    }
}

// MARK: - Gradient Route Overlay (Advanced)
struct GradientRouteOverlay: View {
    let coordinates: [CLLocationCoordinate2D]
    let speeds: [Double]
    let maxSpeed: Double
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard coordinates.count >= 2 else { return }
                let points = projectCoordinates(coordinates, to: size)
                
                for i in 0..<(points.count - 1) {
                    let startPoint = points[i]
                    let endPoint = points[i+1]
                    
                    let speed = getSpeed(at: i, totalPoints: points.count)
                    let color = speedToColor(speed)
                    
                    var path = Path()
                    path.move(to: startPoint)
                    path.addLine(to: endPoint)
                    
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .drawingGroup() // Performance optimization
    }
    
    private func getSpeed(at index: Int, totalPoints: Int) -> Double {
        if speeds.isEmpty { return 0 }
        let ratio = Double(index) / Double(totalPoints - 1)
        let speedIndex = Int(ratio * Double(speeds.count - 1))
        return speeds[min(speedIndex, speeds.count - 1)]
    }
    
    private func speedToColor(_ speed: Double) -> Color {
        let ratio = maxSpeed > 0 ? speed / maxSpeed : 0
        let hue = 0.33 - (0.33 * min(max(ratio, 0), 1))
        return Color(hue: hue, saturation: 1.0, brightness: 1.0)
    }
    
    private func projectCoordinates(_ coords: [CLLocationCoordinate2D], to size: CGSize) -> [CGPoint] {
        guard !coords.isEmpty else { return [] }
        let lats = coords.map { $0.latitude }
        let lons = coords.map { $0.longitude }
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        
        let latRange = max(maxLat - minLat, 0.001)
        let lonRange = max(maxLon - minLon, 0.001)
        let padding: CGFloat = 0.1
        let availableWidth = size.width * (1 - 2 * padding)
        let availableHeight = size.height * (1 - 2 * padding)
        
        return coords.map { coord in
            let normalizedX = CGFloat((coord.longitude - minLon) / lonRange)
            let normalizedY = CGFloat((coord.latitude - minLat) / latRange)
            let x = padding * size.width + normalizedX * availableWidth
            let y = size.height - (padding * size.height + normalizedY * availableHeight)
            return CGPoint(x: x, y: y)
        }
    }
}

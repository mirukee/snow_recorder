import Foundation

// 1. Mock CoreLocation structure for standalone script execution
struct CLLocationCoordinate2D {
    var latitude: Double
    var longitude: Double
}

// 2. The exact logic from SlopeDatabase.swift
func contains(_ coordinate: CLLocationCoordinate2D, boundary: [CLLocationCoordinate2D]) -> Bool {
    guard boundary.count >= 3 else { return false }
    
    var isInside = false
    let n = boundary.count
    var j = n - 1
    
    for i in 0..<n {
        let xi = boundary[i].latitude
        let yi = boundary[i].longitude
        let xj = boundary[j].latitude
        let yj = boundary[j].longitude
        
        // The Ray Casting Algorithm
        if ((yi > coordinate.longitude) != (yj > coordinate.longitude)) &&
           (coordinate.latitude < (xj - xi) * (coordinate.longitude - yi) / (yj - yi) + xi) {
            isInside = !isInside
        }
        j = i
    }
    return isInside
}

// 3. Test Data (APOLLO VI Polygon)
let apollo6_boundary = [
    CLLocationCoordinate2D(latitude: 37.185625, longitude: 128.817298),
    CLLocationCoordinate2D(latitude: 37.185625, longitude: 128.823481),
    CLLocationCoordinate2D(latitude: 37.183367, longitude: 128.823481),
    CLLocationCoordinate2D(latitude: 37.183367, longitude: 128.817298)
]

// 4. Test Points
let testPoints: [(name: String, point: CLLocationCoordinate2D, expected: Bool)] = [
    // Inside Points
    ("Center Point", CLLocationCoordinate2D(latitude: 37.1845, longitude: 128.8200), true),
    ("Edge Near", CLLocationCoordinate2D(latitude: 37.185620, longitude: 128.8200), true),
    
    // Outside Points
    ("Far North", CLLocationCoordinate2D(latitude: 37.1900, longitude: 128.8200), false),
    ("Far East", CLLocationCoordinate2D(latitude: 37.1845, longitude: 128.8300), false),
    ("Just Outside", CLLocationCoordinate2D(latitude: 37.185630, longitude: 128.8200), false)
]

// 5. Run Verification
print("Running Swift Porting Verification...")
print("--------------------------------------------------")
var allPassed = true

for test in testPoints {
    let result = contains(test.point, boundary: apollo6_boundary)
    let status = (result == test.expected) ? "✅ PASS" : "❌ FAIL"
    if result != test.expected { allPassed = false }
    
    print("Test: \(test.name)")
    print("   Point: (\(test.point.latitude), \(test.point.longitude))")
    print("   Expected: \(test.expected), Got: \(result) -> \(status)")
    print("--------------------------------------------------")
}

if allPassed {
    print("Result: INTEGRITY CONFIRMED. Swift logic matches expected behavior.")
} else {
    print("Result: VERIFICATION FAILED.")
}

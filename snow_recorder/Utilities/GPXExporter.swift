import Foundation

/// GPX 파일 생성을 담당하는 유틸리티
/// GPX 1.1 표준 형식을 준수하여 트랙 데이터를 XML로 변환합니다.
struct GPXExporter {
    
    /// RunSession 데이터를 GPX XML 문자열로 변환
    /// - Parameter session: GPX로 변환할 RunSession
    /// - Returns: GPX 형식의 XML 문자열
    static func generateGPX(from session: RunSession) -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Snow Record App"
             xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:snowrecord="https://snowrecord.app/gpx/1/0"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
          <metadata>
            <name>\(escapeXML(session.locationName)) - \(session.slopeName ?? "Session")</name>
            <desc>Snow Record 앱에서 기록된 스키/스노보드 세션</desc>
            <time>\(dateFormatter.string(from: session.startTime))</time>
          </metadata>
          <trk>
            <name>\(escapeXML(session.slopeName ?? "Ski Run"))</name>
            <desc>Max Speed: \(String(format: "%.1f", session.maxSpeed)) km/h, Distance: \(String(format: "%.0f", session.distance))m, Vertical Drop: \(String(format: "%.0f", session.verticalDrop))m</desc>
            <trkseg>
        
        """
        
        // 각 좌표를 트랙포인트로 변환
        // routeCoordinates는 [[lat, lon], ...] 형식
        let sortedEvents = session.timelineEvents.sorted { $0.startTime < $1.startTime }
        var eventIndex = 0
        var currentEvent: RunSession.TimelineEvent?
        
        func statusForTime(_ time: Date) -> String? {
            guard !sortedEvents.isEmpty else { return nil }
            
            while eventIndex < sortedEvents.count {
                let candidate = sortedEvents[eventIndex]
                let candidateEnd = candidate.endTime ?? session.endTime
                
                if time < candidate.startTime {
                    return nil
                }
                
                if time <= candidateEnd {
                    currentEvent = candidate
                    return candidate.type.rawValue
                }
                
                eventIndex += 1
            }
            
            return currentEvent?.type.rawValue
        }
        
        for (index, coord) in session.routeCoordinates.enumerated() {
            guard coord.count >= 2 else { continue }
            let lat = coord[0]
            let lon = coord[1]
            
            // 고도 정보가 있으면 포함 (coord[2]가 있을 경우)
            let elevation = coord.count >= 3 ? coord[2] : nil
            
            // 시간 계산: 타임스탬프가 있으면 사용, 없으면 균등 보간
            let pointTime: Date
            if session.routeTimestamps.count == session.routeCoordinates.count {
                pointTime = Date(timeIntervalSince1970: session.routeTimestamps[index])
            } else {
                let progress = session.routeCoordinates.count > 1
                    ? Double(index) / Double(session.routeCoordinates.count - 1)
                    : 0.0
                pointTime = session.startTime.addingTimeInterval(session.duration * progress)
            }
            
            let speedValue: Double? = index < session.routeSpeeds.count ? session.routeSpeeds[index] : nil
            let statusValue: String? = statusForTime(pointTime)
            var extensions = ""
            
            if speedValue != nil || statusValue != nil {
                extensions += "        <extensions>\n"
                if let speed = speedValue {
                    extensions += "          <snowrecord:speed>\(String(format: "%.1f", speed))</snowrecord:speed>\n"
                }
                if let status = statusValue {
                    extensions += "          <snowrecord:status>\(status)</snowrecord:status>\n"
                }
                extensions += "        </extensions>\n"
            }
            
            if let ele = elevation {
                var trackPoint = """
                      <trkpt lat="\(lat)" lon="\(lon)">
                        <ele>\(String(format: "%.1f", ele))</ele>
                        <time>\(dateFormatter.string(from: pointTime))</time>
                """
                trackPoint += extensions
                trackPoint += """
                      </trkpt>
                
                """
                gpx += trackPoint
            } else {
                var trackPoint = """
                      <trkpt lat="\(lat)" lon="\(lon)">
                        <time>\(dateFormatter.string(from: pointTime))</time>
                """
                trackPoint += extensions
                trackPoint += """
                      </trkpt>
                
                """
                gpx += trackPoint
            }
        }
        
        gpx += """
            </trkseg>
          </trk>
        </gpx>
        """
        
        return gpx
    }
    
    /// GPX 데이터를 임시 파일로 저장하고 URL 반환
    /// - Parameter session: 저장할 RunSession
    /// - Returns: 생성된 GPX 파일의 URL (실패 시 nil)
    static func saveToFile(session: RunSession) -> URL? {
        let gpxContent = generateGPX(from: session)
        
        // 파일명 생성 (날짜_슬로프명.gpx)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = dateFormatter.string(from: session.startTime)
        let slopeName = session.slopeName?.replacingOccurrences(of: " ", with: "_") ?? "session"
        let fileName = "SnowRecord_\(dateString)_\(slopeName).gpx"
        
        // 임시 디렉토리에 저장
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try gpxContent.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("GPX 파일 저장 실패: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// XML 특수문자 이스케이프 처리
    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

#!/usr/bin/env python3
"""
슬로프 인식 검증 스크립트
Swift의 Ray Caasting 로직을 Python으로 포팅하여, 
SlopeDatabase.swift에 정의된 폴리곤이 실제 GPX 경로를 올바르게 감지하는지 검증합니다.
"""

import xml.etree.ElementTree as ET
import sys
from collections import defaultdict

# =============================================================================
# 1. SlopeDatabase.swift에서 정의된 폴리곤 좌표 (직접 포팅)
# =============================================================================

SLOPE_DEFINITIONS = {
    "APOLLO VI": [
        (37.185625, 128.817298),
        (37.185625, 128.823481),
        (37.183367, 128.823481),
        (37.183367, 128.817298),
    ],
    "HERA II": [
        (37.190233, 128.817327),
        (37.190233, 128.828115),
        (37.183076, 128.828115),
        (37.183076, 128.817327),
    ],
    "ZEUS III": [
        (37.197708, 128.827842),
        (37.197708, 128.832255),
        (37.190316, 128.832255),
        (37.190316, 128.827842),
    ],
    "ATHENA II": [
        (37.199586, 128.820060),
        (37.199586, 128.832025),
        (37.183794, 128.832025),
        (37.183794, 128.820060),
    ],
}

# =============================================================================
# 2. 로직 구현 (Swift 포팅)
# =============================================================================

def contains_coordinate(polygon: list, lat: float, lon: float) -> bool:
    """Ray Casting 알고리즘 (Swift의 contains 메서드와 동일)"""
    if len(polygon) < 3:
        return False
    
    is_inside = False
    n = len(polygon)
    j = n - 1
    
    for i in range(n):
        xi = polygon[i][0] # Latitude
        yi = polygon[i][1] # Longitude
        xj = polygon[j][0]
        yj = polygon[j][1]
        
        # 주의: Swift 코드에서는 (yi > coordinate.longitude) != (yj > coordinate.longitude)
        # 여기서 yi는 Longitude여야 하는데, Swift 코드의 변수명이 좀 헷갈리게 되어 있음.
        # Swift: let xi = boundary[i].latitude, let yi = boundary[i].longitude
        # Swift Logic:
        # if ((yi > coordinate.longitude) != (yj > coordinate.longitude)) &&
        #    (coordinate.latitude < (xj - xi) * (coordinate.longitude - yi) / (yj - yi) + xi)
        
        # Python으로 정확히 옮김:
        xi = polygon[i][0] # Lat
        yi = polygon[i][1] # Lon
        xj = polygon[j][0] # Lat
        yj = polygon[j][1] # Lon
        
        if ((yi > lon) != (yj > lon)) and \
           (lat < (xj - xi) * (lon - yi) / (yj - yi) + xi):
            is_inside = not is_inside
            
        j = i
        
    return is_inside

def find_slope(lat: float, lon: float) -> str:
    """주어진 좌표가 포함된 슬로프 이름 반환 (첫 번째 매칭)"""
    # 우선순위: 상세한 구역부터 체크 (겹칠 경우 대비)
    # 여기서는 단순 순회
    for name, polygon in SLOPE_DEFINITIONS.items():
        if contains_coordinate(polygon, lat, lon):
            return name
    return None

# =============================================================================
# 3. GPX 파싱 및 검증
# =============================================================================

def parse_gpx_points(file_path: str):
    tree = ET.parse(file_path)
    root = tree.getroot()
    ns = {'gpx': 'http://www.topografix.com/GPX/1/1', 'gte': 'http://www.gpstrackeditor.com/xmlschemas/General/1'}
    
    points = []
    for trkpt in root.findall('.//gpx:trkpt', ns):
        lat = float(trkpt.get('lat'))
        lon = float(trkpt.get('lon'))
        ele_elem = trkpt.find('gpx:ele', ns)
        ele = float(ele_elem.text) if ele_elem is not None else 0
        
        # 속도 (m/s)
        speed = 0.0
        extensions = trkpt.find('gpx:extensions', ns)
        if extensions is not None:
            gps = extensions.find('gte:gps', ns)
            if gps is not None:
                speed = float(gps.get('speed', 0))
                
        points.append({'lat': lat, 'lon': lon, 'ele': ele, 'speed_kmh': speed * 3.6})
    return points

def identify_runs(points):
    """간단한 런 식별 (속도 > 10km/h)"""
    runs = []
    current_run = []
    in_run = False
    
    for p in points:
        if p['speed_kmh'] > 10:
            if not in_run:
                in_run = True
                current_run = [p]
            else:
                current_run.append(p)
        else:
            if in_run and len(current_run) > 20: 
                runs.append(current_run)
            in_run = False
            current_run = []
    return runs

def main():
    if len(sys.argv) > 1:
        file_path = sys.argv[1]
    else:
        file_path = '/Users/gimdoyun/Documents/snow_recorder/2026년 1월 22일 - High 1.gpx'
        
    print(f"🔍 GPX 파일 분석 중: {file_path}")
    points = parse_gpx_points(file_path)
    runs = identify_runs(points)
    
    print(f"   총 {len(runs)}개의 런 감지됨")
    print("\n[검증 결과]")
    print(f"{'Run Index':<10} | {'Points':<8} | {'Identified Slopes'}")
    print("-" * 60)
    
    slope_counts = defaultdict(int)
    
    for i, run in enumerate(runs, 1):
        detected_slopes = set()
        slope_votes = defaultdict(int)
        
        for p in run:
            slope = find_slope(p['lat'], p['lon'])
            if slope:
                detected_slopes.add(slope)
                slope_votes[slope] += 1
        
        # 가장 많이 감지된 슬로프 선정
        if slope_votes:
            primary_slope = max(slope_votes, key=slope_votes.get)
            percentage = (slope_votes[primary_slope] / len(run)) * 100
            result_str = f"{primary_slope} ({percentage:.1f}%)"
            slope_counts[primary_slope] += 1
        else:
            result_str = "Unknown"
            
        print(f"Run {i:<6} | {len(run):<8} | {result_str}")
        
    print("\n📊 종합 요약")
    for slope, count in sorted(slope_counts.items()):
        print(f"   - {slope}: {count}회 주행")

if __name__ == '__main__':
    main()

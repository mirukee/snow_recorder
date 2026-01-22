#!/usr/bin/env python3
"""
GPX에서 슬로프별 경계 좌표 추출
사용자 피드백 기반:
- HERA II: 주로 탐
- APOLLO VI: 탐 (기존 VICTORIA로 잘못 감지)
- ATHENA II: 연결 슬로프
- ZEUS III: 연결 슬로프
"""

import xml.etree.ElementTree as ET
from collections import defaultdict
import json

def parse_gpx(file_path: str):
    """GPX 파일 파싱"""
    tree = ET.parse(file_path)
    root = tree.getroot()
    ns = {'gpx': 'http://www.topografix.com/GPX/1/1', 'gte': 'http://www.gpstrackeditor.com/xmlschemas/General/1'}
    
    points = []
    for trkpt in root.findall('.//gpx:trkpt', ns):
        lat = float(trkpt.get('lat'))
        lon = float(trkpt.get('lon'))
        ele_elem = trkpt.find('gpx:ele', ns)
        ele = float(ele_elem.text) if ele_elem is not None else 0
        time_elem = trkpt.find('gpx:time', ns)
        time = time_elem.text if time_elem is not None else ''
        
        speed = 0.0
        extensions = trkpt.find('gpx:extensions', ns)
        if extensions is not None:
            gps = extensions.find('gte:gps', ns)
            if gps is not None:
                speed = float(gps.get('speed', 0))
        
        points.append({'lat': lat, 'lon': lon, 'ele': ele, 'time': time, 'speed': speed})
    
    return points

def identify_runs(points):
    """런 구간 식별 (하강 + 고속)"""
    runs = []
    current_run = []
    in_run = False
    
    for i, p in enumerate(points):
        speed_kmh = p['speed'] * 3.6
        
        # 런 시작 조건: 속도 > 10km/h
        if speed_kmh > 10:
            if not in_run:
                in_run = True
                current_run = [p]
            else:
                current_run.append(p)
        else:
            # 런 종료
            if in_run and len(current_run) > 20:  # 최소 20포인트
                runs.append(current_run)
            in_run = False
            current_run = []
    
    return runs

def classify_runs_by_elevation(runs):
    """
    고도와 좌표 패턴으로 슬로프 분류
    사용자 피드백 기반:
    - 헤라2: 정상(~1340m)에서 시작, 경도 128.822~128.826
    - 아폴로6: 정상(~1340m)에서 시작, 경도 < 128.822 (서쪽)
    - 아테나2: 중간 고도(~1100m)에서 시작
    - 제우스3: 하단(~1000m 이하)
    """
    classified = {
        'HERA_II': [],
        'APOLLO_VI': [],
        'ATHENA_II': [],
        'ZEUS_III': []
    }
    
    for run in runs:
        start_ele = run[0]['ele']
        end_ele = run[-1]['ele']
        mid_point = run[len(run)//2]
        avg_lon = sum(p['lon'] for p in run) / len(run)
        
        vertical = start_ele - end_ele
        
        # 분류 로직
        if start_ele > 1300:
            # 정상에서 시작하는 런
            if avg_lon < 128.822:
                # 서쪽 = 아폴로6 (기존에 빅토리아로 잘못 감지)
                classified['APOLLO_VI'].append(run)
            else:
                # 동쪽 = 헤라2
                classified['HERA_II'].append(run)
        elif start_ele > 1000 and end_ele < 1000:
            # 중간에서 하단까지 = 아테나2
            classified['ATHENA_II'].append(run)
        elif end_ele < 900:
            # 하단 연결 = 제우스3
            classified['ZEUS_III'].append(run)
        else:
            # 기타는 아테나로
            classified['ATHENA_II'].append(run)
    
    return classified

def extract_boundary(runs_for_slope):
    """슬로프의 모든 런에서 경계 좌표 추출"""
    if not runs_for_slope:
        return [], None, None
    
    all_points = []
    for run in runs_for_slope:
        all_points.extend(run)
    
    if not all_points:
        return [], None, None
    
    # 위도/경도 범위
    lats = [p['lat'] for p in all_points]
    lons = [p['lon'] for p in all_points]
    eles = [p['ele'] for p in all_points]
    
    min_lat, max_lat = min(lats), max(lats)
    min_lon, max_lon = min(lons), max(lons)
    min_ele, max_ele = min(eles), max(eles)
    
    # 경계 폴리곤 (사각형 근사)
    boundary = [
        {'lat': max_lat, 'lon': min_lon},  # 상단 좌측
        {'lat': max_lat, 'lon': max_lon},  # 상단 우측
        {'lat': min_lat, 'lon': max_lon},  # 하단 우측
        {'lat': min_lat, 'lon': min_lon},  # 하단 좌측
    ]
    
    # 정상/하단 포인트 (가장 높은/낮은 고도)
    top_point = max(all_points, key=lambda p: p['ele'])
    bottom_point = min(all_points, key=lambda p: p['ele'])
    
    return boundary, top_point, bottom_point

def main():
    file_path = '/Users/gimdoyun/Documents/snow_recorder/2026년 1월 22일 - High 1.gpx'
    
    print("🔍 GPX 파싱 중...")
    points = parse_gpx(file_path)
    print(f"   총 포인트: {len(points)}")
    
    print("\n🏔️ 런 구간 식별 중...")
    runs = identify_runs(points)
    print(f"   감지된 런: {len(runs)}개")
    
    print("\n📊 슬로프 분류 중...")
    classified = classify_runs_by_elevation(runs)
    
    # Swift 코드 생성
    print("\n" + "="*60)
    print("📝 SlopeDatabase.swift 업데이트용 좌표")
    print("="*60)
    
    for slope_name, slope_runs in classified.items():
        if not slope_runs:
            continue
            
        boundary, top, bottom = extract_boundary(slope_runs)
        
        print(f"\n// {slope_name}: {len(slope_runs)}런 감지")
        print(f"// 고도 범위: {bottom['ele']:.0f}m ~ {top['ele']:.0f}m")
        print(f"boundary: [")
        for b in boundary:
            print(f"    CLLocationCoordinate2D(latitude: {b['lat']:.6f}, longitude: {b['lon']:.6f}),")
        print("],")
        print(f"topPoint: CLLocationCoordinate2D(latitude: {top['lat']:.6f}, longitude: {top['lon']:.6f}),")
        print(f"bottomPoint: CLLocationCoordinate2D(latitude: {bottom['lat']:.6f}, longitude: {bottom['lon']:.6f})")

if __name__ == '__main__':
    main()

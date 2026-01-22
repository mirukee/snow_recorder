#!/usr/bin/env python3
"""
하이원 GPX 분석 스크립트
GPX 파일을 파싱하여 런/리프트 구간을 분리하고 슬로프를 추정합니다.
"""

import xml.etree.ElementTree as ET
from dataclasses import dataclass
from typing import List, Tuple
from datetime import datetime
import math

@dataclass
class TrackPoint:
    lat: float
    lon: float
    ele: float  # 고도 (m)
    time: str
    speed: float  # m/s

@dataclass
class Segment:
    """런 또는 리프트 구간"""
    segment_type: str  # 'run' or 'lift' or 'rest'
    points: List[TrackPoint]
    start_time: str
    end_time: str
    start_ele: float
    end_ele: float
    vertical_change: float  # 고도 변화 (음수 = 하강)
    distance: float  # 총 이동 거리 (m)
    max_speed: float  # km/h
    avg_speed: float  # km/h
    estimated_slope: str  # 추정 슬로프

# 하이원 리조트 대략적인 슬로프 구역 정의
# GPX 좌표 범위: lat 37.183~37.199, lon 128.817~128.832
# 기준점: 37.208°N, 128.826°E (정상 부근)

# 슬로프 구역 정의 (대략적인 경도 기준)
SLOPE_ZONES = {
    # 경도(lon) 범위로 대략 구분 (서쪽 -> 동쪽)
    # 위도(lat) 범위도 고려
    
    # 서쪽 구역 (빅토리아/헤라)
    'VICTORIA': {'lon_range': (128.817, 128.822), 'lat_range': (37.183, 37.200), 'ele_top': 1340, 'difficulty': 'advanced'},
    'HERA': {'lon_range': (128.822, 128.826), 'lat_range': (37.183, 37.200), 'ele_top': 1340, 'difficulty': 'intermediate'},
    
    # 중앙 구역 (제우스/아테나)
    'ZEUS': {'lon_range': (128.826, 128.830), 'lat_range': (37.190, 37.210), 'ele_top': 1340, 'difficulty': 'beginner'},
    'ATHENA': {'lon_range': (128.826, 128.832), 'lat_range': (37.183, 37.200), 'ele_top': 1200, 'difficulty': 'intermediate'},
    
    # 동쪽 구역 (아폴로)
    'APOLLO': {'lon_range': (128.830, 128.835), 'lat_range': (37.183, 37.200), 'ele_top': 1340, 'difficulty': 'advanced'},
}

def parse_gpx(file_path: str) -> List[TrackPoint]:
    """GPX 파일을 파싱하여 트랙포인트 리스트 반환"""
    tree = ET.parse(file_path)
    root = tree.getroot()
    
    # GPX 네임스페이스 처리
    ns = {'gpx': 'http://www.topografix.com/GPX/1/1', 'gte': 'http://www.gpstrackeditor.com/xmlschemas/General/1'}
    
    points = []
    for trkpt in root.findall('.//gpx:trkpt', ns):
        lat = float(trkpt.get('lat'))
        lon = float(trkpt.get('lon'))
        
        ele_elem = trkpt.find('gpx:ele', ns)
        ele = float(ele_elem.text) if ele_elem is not None else 0
        
        time_elem = trkpt.find('gpx:time', ns)
        time = time_elem.text if time_elem is not None else ''
        
        # 속도 추출
        speed = 0.0
        extensions = trkpt.find('gpx:extensions', ns)
        if extensions is not None:
            gps = extensions.find('gte:gps', ns)
            if gps is not None:
                speed = float(gps.get('speed', 0))
        
        points.append(TrackPoint(lat=lat, lon=lon, ele=ele, time=time, speed=speed))
    
    return points

def calculate_distance(p1: TrackPoint, p2: TrackPoint) -> float:
    """두 점 사이의 거리 계산 (미터)"""
    R = 6371000  # 지구 반경 (m)
    lat1, lat2 = math.radians(p1.lat), math.radians(p2.lat)
    dlat = math.radians(p2.lat - p1.lat)
    dlon = math.radians(p2.lon - p1.lon)
    
    a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c

def estimate_slope_zone(lat: float, lon: float, ele: float) -> str:
    """좌표를 기반으로 슬로프 구역 추정"""
    for zone_name, zone in SLOPE_ZONES.items():
        if (zone['lon_range'][0] <= lon <= zone['lon_range'][1] and
            zone['lat_range'][0] <= lat <= zone['lat_range'][1]):
            return zone_name
    return 'UNKNOWN'

def segment_runs(points: List[TrackPoint]) -> List[Segment]:
    """트랙포인트를 런/리프트/휴식 구간으로 분리"""
    segments = []
    current_points = []
    current_type = None
    
    SPEED_THRESHOLD_RUN = 5.0  # km/h - 이 이상이면 런
    SPEED_THRESHOLD_LIFT = 2.0  # km/h - 이 이하면 휴식, 사이면 리프트
    MIN_SEGMENT_POINTS = 10  # 최소 포인트 수
    
    for i, point in enumerate(points):
        speed_kmh = point.speed * 3.6
        
        # 상태 결정
        if speed_kmh > SPEED_THRESHOLD_RUN:
            # 고도 변화 방향 체크 (이전 5포인트 평균)
            if i > 5:
                recent_ele_change = point.ele - points[i-5].ele
                if recent_ele_change < -3:  # 하강 중
                    new_type = 'run'
                elif recent_ele_change > 3:  # 상승 중 (빠른 속도)
                    new_type = 'lift'  # 곤돌라?
                else:
                    new_type = 'run'
            else:
                new_type = 'run'
        elif speed_kmh > SPEED_THRESHOLD_LIFT:
            # 저속 이동 - 리프트 또는 천천히 이동
            if i > 5:
                recent_ele_change = point.ele - points[i-5].ele
                if recent_ele_change > 2:  # 상승 중
                    new_type = 'lift'
                else:
                    new_type = 'rest'
            else:
                new_type = 'lift'
        else:
            new_type = 'rest'
        
        # 상태 변경 감지
        if current_type is None:
            current_type = new_type
        
        if new_type != current_type and len(current_points) >= MIN_SEGMENT_POINTS:
            # 새 세그먼트 시작
            seg = create_segment(current_points, current_type)
            if seg:
                segments.append(seg)
            current_points = [point]
            current_type = new_type
        else:
            current_points.append(point)
    
    # 마지막 세그먼트
    if len(current_points) >= MIN_SEGMENT_POINTS:
        seg = create_segment(current_points, current_type)
        if seg:
            segments.append(seg)
    
    return segments

def create_segment(points: List[TrackPoint], seg_type: str) -> Segment:
    """세그먼트 생성"""
    if not points:
        return None
    
    # 총 거리 계산
    total_distance = 0
    for i in range(1, len(points)):
        total_distance += calculate_distance(points[i-1], points[i])
    
    # 속도 계산
    speeds_kmh = [p.speed * 3.6 for p in points if p.speed > 0]
    max_speed = max(speeds_kmh) if speeds_kmh else 0
    avg_speed = sum(speeds_kmh) / len(speeds_kmh) if speeds_kmh else 0
    
    # 슬로프 추정 (런 구간만)
    estimated_slope = 'N/A'
    if seg_type == 'run':
        # 중간 지점 기준으로 슬로프 추정
        mid_point = points[len(points) // 2]
        estimated_slope = estimate_slope_zone(mid_point.lat, mid_point.lon, mid_point.ele)
    
    return Segment(
        segment_type=seg_type,
        points=points,
        start_time=points[0].time,
        end_time=points[-1].time,
        start_ele=points[0].ele,
        end_ele=points[-1].ele,
        vertical_change=points[-1].ele - points[0].ele,
        distance=total_distance,
        max_speed=max_speed,
        avg_speed=avg_speed,
        estimated_slope=estimated_slope
    )

def analyze_gpx(file_path: str):
    """GPX 파일 분석 및 결과 출력"""
    print(f"\n{'='*60}")
    print(f"🎿 하이원 GPX 분석 결과")
    print(f"{'='*60}\n")
    
    # 파싱
    points = parse_gpx(file_path)
    print(f"📍 총 트랙포인트: {len(points)}개")
    
    # 기본 통계
    if points:
        min_lat = min(p.lat for p in points)
        max_lat = max(p.lat for p in points)
        min_lon = min(p.lon for p in points)
        max_lon = max(p.lon for p in points)
        min_ele = min(p.ele for p in points)
        max_ele = max(p.ele for p in points)
        
        print(f"📊 좌표 범위:")
        print(f"   위도: {min_lat:.4f} ~ {max_lat:.4f}")
        print(f"   경도: {min_lon:.4f} ~ {max_lon:.4f}")
        print(f"   고도: {min_ele:.0f}m ~ {max_ele:.0f}m (차이: {max_ele-min_ele:.0f}m)")
        print(f"   시간: {points[0].time} ~ {points[-1].time}")
    
    # 세그먼트 분리
    segments = segment_runs(points)
    
    # 런만 필터링
    runs = [s for s in segments if s.segment_type == 'run']
    lifts = [s for s in segments if s.segment_type == 'lift']
    
    print(f"\n{'='*60}")
    print(f"🏔️ 감지된 런: {len(runs)}개")
    print(f"🚡 감지된 리프트: {len(lifts)}개")
    print(f"{'='*60}\n")
    
    # 각 런 상세 정보
    for i, run in enumerate(runs, 1):
        print(f"[Run {i}] {run.estimated_slope}")
        print(f"   ⏰ 시간: {run.start_time[11:19]} → {run.end_time[11:19]}")
        print(f"   📍 고도: {run.start_ele:.0f}m → {run.end_ele:.0f}m (↓{abs(run.vertical_change):.0f}m)")
        print(f"   📏 거리: {run.distance:.0f}m")
        print(f"   🏃 속도: 최고 {run.max_speed:.1f}km/h, 평균 {run.avg_speed:.1f}km/h")
        print()
    
    # 슬로프별 통계
    print(f"\n{'='*60}")
    print(f"📊 슬로프별 런 수")
    print(f"{'='*60}")
    
    slope_counts = {}
    for run in runs:
        slope = run.estimated_slope
        if slope not in slope_counts:
            slope_counts[slope] = []
        slope_counts[slope].append(run)
    
    for slope, slope_runs in sorted(slope_counts.items()):
        total_vertical = sum(abs(r.vertical_change) for r in slope_runs)
        total_distance = sum(r.distance for r in slope_runs)
        max_speed = max(r.max_speed for r in slope_runs)
        print(f"   {slope}: {len(slope_runs)}런, 총 {total_vertical:.0f}m 하강, 거리 {total_distance:.0f}m, 최고속도 {max_speed:.1f}km/h")
    
    return runs, lifts

if __name__ == '__main__':
    import sys
    if len(sys.argv) > 1:
        file_path = sys.argv[1]
    else:
        file_path = '/Users/gimdoyun/Documents/snow_recorder/2026년 1월 22일 - High 1.gpx'
    
    analyze_gpx(file_path)

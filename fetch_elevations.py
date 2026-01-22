#!/usr/bin/env python3
"""
슬로프 고도 조회 스크립트
Open-Elevation API를 사용하여 각 슬로프의 시작점/종료점 고도를 조회합니다.
"""

import requests
import json
import time

# SlopeDatabase.swift에서 추출한 슬로프 시작점/종료점 좌표
SLOPE_POINTS = {
    "ZEUS I": {
        "top": (37.177443, 128.825563),
        "bottom": (37.179337, 128.823369),
    },
    "ZEUS II": {
        "top": (37.178838769591096, 128.8247840396824),
        "bottom": (37.18948467834376, 128.82698572417303),
    },
    "ZEUS III": {
        "top": (37.19043035956672, 128.8294623866882),
        "bottom": (37.20422634607047, 128.8379949641872),
    },
    "ATHENA II": {
        "top": (37.19502220037265, 128.82089746287767),
        "bottom": (37.206913054576034, 128.82409926796782),
    },
    "ATHENA III": {
        "top": (37.20287244665229, 128.83556829372998),
        "bottom": (37.20620476610267, 128.83603002107543),
    },
    "HERA I": {
        "top": (37.181162, 128.819769),
        "bottom": (37.183580, 128.824114),
    },
    "HERA II": {
        "top": (37.18308280765861, 128.8177682882228),
        "bottom": (37.18701045437784, 128.8249417368349),
    },
    "HERA III": {
        "top": (37.183723, 128.817238),
        "bottom": (37.187212, 128.822993),
    },
    "VICTORIA I": {
        "top": (37.179641, 128.831099),
        "bottom": (37.190109, 128.828817),
    },
    "VICTORIA II": {
        "top": (37.182172, 128.831516),
        "bottom": (37.189212, 128.828068),
    },
    "APOLLO I": {
        "top": (37.185313460320344, 128.8176229569338),
        "bottom": (37.19112225561612, 128.82348479960405),
    },
    "APOLLO II": {
        "top": (37.190834918640846, 128.82217633343265),
        "bottom": (37.19361546879436, 128.8201152934991),
    },
    "APOLLO III": {
        "top": (37.190932761121545, 128.82674545395247),
        "bottom": (37.19489519041581, 128.82117256634552),
    },
    "APOLLO IV": {
        "top": (37.19315698033964, 128.82512168892896),
        "bottom": (37.19827338233485, 128.82650653606646),
    },
    "APOLLO VI": {
        "top": (37.19793104253665, 128.8219800207852),
        "bottom": (37.19837502458036, 128.83205507038514),
    },
}


def fetch_elevation_batch(locations: list) -> list:
    """Open-Elevation API로 고도 조회 (배치)"""
    url = "https://api.open-elevation.com/api/v1/lookup"
    
    payload = {
        "locations": [
            {"latitude": lat, "longitude": lon}
            for lat, lon in locations
        ]
    }
    
    try:
        response = requests.post(url, json=payload, timeout=30)
        response.raise_for_status()
        data = response.json()
        return [r["elevation"] for r in data["results"]]
    except Exception as e:
        print(f"   ⚠️ API 오류: {e}")
        return [None] * len(locations)


def main():
    print("=" * 70)
    print("🏔️  하이원 리조트 슬로프 고도 조회")
    print("=" * 70)
    print("   API: Open-Elevation (무료)")
    print()
    
    # 모든 좌표 수집
    all_locations = []
    location_map = []  # (슬로프명, point_type) 매핑
    
    for slope_name, points in SLOPE_POINTS.items():
        if points.get("top"):
            all_locations.append(points["top"])
            location_map.append((slope_name, "top"))
        if points.get("bottom"):
            all_locations.append(points["bottom"])
            location_map.append((slope_name, "bottom"))
    
    print(f"📍 총 {len(all_locations)}개 지점 조회 중...")
    print()
    
    # API 호출 (배치)
    elevations = fetch_elevation_batch(all_locations)
    
    # 결과 매핑
    results = {}
    for i, (slope_name, point_type) in enumerate(location_map):
        if slope_name not in results:
            results[slope_name] = {}
        results[slope_name][point_type] = elevations[i]
    
    # 출력
    print("=" * 70)
    print(f"{'슬로프':<15} | {'시작점 고도':>12} | {'종료점 고도':>12} | {'고도차':>10}")
    print("-" * 70)
    
    for slope_name in SLOPE_POINTS.keys():
        if slope_name not in results:
            continue
            
        top_elev = results[slope_name].get("top")
        bottom_elev = results[slope_name].get("bottom")
        
        if top_elev is not None and bottom_elev is not None:
            vertical_drop = top_elev - bottom_elev
            status = "✅" if vertical_drop > 0 else "⚠️ 역전!"
            print(f"{slope_name:<15} | {top_elev:>10.1f}m | {bottom_elev:>10.1f}m | {vertical_drop:>8.1f}m {status}")
        else:
            print(f"{slope_name:<15} | {'N/A':>12} | {'N/A':>12} | {'N/A':>10}")
    
    print("=" * 70)
    
    # Swift 코드 생성
    print("\n📝 SlopeDatabase.swift에 추가할 고도 데이터:")
    print("-" * 70)
    
    for slope_name in SLOPE_POINTS.keys():
        if slope_name not in results:
            continue
        top_elev = results[slope_name].get("top")
        bottom_elev = results[slope_name].get("bottom")
        
        if top_elev is not None and bottom_elev is not None:
            print(f'// {slope_name}')
            print(f'topAltitude: {top_elev:.1f},')
            print(f'bottomAltitude: {bottom_elev:.1f},')
            print()


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
SlopeDatabase.swift 파일을 파싱하여 모든 슬로프의 좌표를 추출하고,
고도 정보를 조회하여 Start/Finish Point와 Altitude를 업데이트한
새로운 Swift 코드를 생성하는 스크립트입니다.
"""

import re
import requests
import json
import time

SWIFT_FILE_PATH = "snow_recorder/Models/SlopeDatabase.swift"
OUTPUT_FILE_PATH = "snow_recorder/Models/SlopeDatabase_Updated.swift"

def fetch_elevations_batch(locations):
    """Open-Elevation API: 50개씩 배치 처리"""
    url = "https://api.open-elevation.com/api/v1/lookup"
    results = []
    
    # 50개 단위로 청크 분할
    chunk_size = 50
    for i in range(0, len(locations), chunk_size):
        chunk = locations[i:i + chunk_size]
        payload = {
            "locations": [
                {"latitude": lat, "longitude": lon}
                for lat, lon in chunk
            ]
        }
        try:
            print(f"   📡 고도 조회 중... ({i+1}~{min(i+chunk_size, len(locations))}/{len(locations)})")
            response = requests.post(url, json=payload, timeout=30)
            response.raise_for_status()
            data = response.json()
            results.extend([r["elevation"] for r in data["results"]])
            time.sleep(0.5) # API 부하 방지
        except Exception as e:
            print(f"   ⚠️ API 오류: {e}")
            results.extend([None] * len(chunk))
            
    return results

def parse_slopes(content):
    # Regex 대신, 'Slope(' 문자를 기준으로 split하여 처리
    # 이렇게 하면 괄호 중첩 문제를 피할 수 있음.
    raw_blocks = content.split("Slope(")
    slopes = []
    
    # 첫 번째 조각은 import 문 등이므로 제외
    for block in raw_blocks[1:]:
        # block은 "name: ..., ... )" 형태일 것임.
        # 편의상 block 전체에서 검색
        slope_block = block
        
        # 이름 추출
        name_match = re.search(r'name:\s*"([^"]+)"', slope_block)
        name = name_match.group(1) if name_match else "Unknown"
        
        # Boundary 추출
        # boundary: [...] 패턴을 찾음.
        # 대괄호 안의 내용이 상당히 길 수 있으므로 DOTALL 필수
        # 닫는 대괄호 ']' 뒤에 콤마가 오거나, 다른 필드가 옴.
        # 가장 마지막 ']'를 찾기보다, 'boundary:' 시작 후 '[' ... ']' 쌍을 찾는게 정확하지만,
        # 여기서는 단순하게 "boundary: [" 뒤의 내용을 잡고,
        # 다음 필드 키워드(Start with topPoint? or just look for ']') 전까지?
        # 아니면 단순하게 `boundary:\s*\[(.*?)\]` 쓰되, 
        # CLLocationCoordinate2D(...) 가 많으므로 `]`가 나올때까지... 
        # 하지만 `bounds` 배열 끝의 `]`를 정확히 찾아야 함.
        # 배열 요소 사이에는 `),` 가 있고, 배열 끝에는 `]`가 있음.
        
        # 팁: `boundary`는 `CLLocationCoordinate2D` 리스트임.
        # 따라서 `boundary: [` 부터 `CLLocationCoordinate2D` 들이 나오고, 마지막에 `]` 가 나옴.
        # `]` 뒤에는 보통 `topPoint:` 또는 `)` 가 나옴.
        
        boundary_coords = []
        
        # boundary 블록 전체를 안전하게 잡기 위해:
        # 1. 'boundary:' 위치 찾기
        b_start = slope_block.find("boundary:")
        if b_start != -1:
            # '[' 찾기
            sq_open = slope_block.find("[", b_start)
            if sq_open != -1:
                # 닫는 ']' 찾기. 중첩 대괄호는 없다고 가정하되,
                # boundary 배열이 끝나는 지점을 찾아야 함.
                # 배열 내부는 `CLLocationCoordinate2D(...)` 들뿐임. `[`나 `]`가 더 없음.
                sq_close = slope_block.find("]", sq_open)
                if sq_close != -1:
                    boundary_text = slope_block[sq_open:sq_close]
                    
                    # 좌표 추출
                    coord_pattern = re.compile(r'latitude:\s*([\d\.]+),\s*longitude:\s*([\d\.]+)')
                    for cm in coord_pattern.finditer(boundary_text):
                        lat = float(cm.group(1))
                        lon = float(cm.group(2))
                        boundary_coords.append((lat, lon))
        
        # 기타 필드 보존을 위해 원본 블록 저장 (필요시)
        # 여기서는 새로 생성할 것이므로 파싱만 함
        
        # 기존 필드값 파싱 (Optional하게 처리)
        korean_name_m = re.search(r'koreanName:\s*"([^"]+)"', slope_block)
        korean_name = korean_name_m.group(1) if korean_name_m else ""
        
        difficulty_m = re.search(r'difficulty:\s*(\.[a-zA-Z]+)', slope_block)
        difficulty = difficulty_m.group(1) if difficulty_m else ".beginner"
        
        length_m = re.search(r'length:\s*([\d\.]+)', slope_block)
        length = length_m.group(1) if length_m else "0"
        
        avg_grad_m = re.search(r'avgGradient:\s*([\d\.]+)', slope_block)
        avg_grad = avg_grad_m.group(1) if avg_grad_m else "0"
        
        max_grad_m = re.search(r'maxGradient:\s*([\d\.]+)', slope_block)
        max_grad = max_grad_m.group(1) if max_grad_m else "0"
        
        status_m = re.search(r'status:\s*(\.[a-zA-Z]+)', slope_block)
        status = status_m.group(1) if status_m else ".closed"
        
        slopes.append({
            "name": name,
            "koreanName": korean_name,
            "difficulty": difficulty,
            "length": length,
            "avgGradient": avg_grad,
            "maxGradient": max_grad,
            "status": status,
            "boundary": boundary_coords
        })
        
    return slopes

def generate_slope_code(slope_data):
    """Slope 구조체 Swift 코드로 변환"""
    
    boundary_str = ""
    if not slope_data["boundary"]:
        boundary_str = "            boundary: [],"
    else:
        boundary_str = "            boundary: [\n"
        for lat, lon in slope_data["boundary"]:
            boundary_str += f"                CLLocationCoordinate2D(latitude: {lat}, longitude: {lon}),\n"
        boundary_str += "            ],"

    # Top/Bottom Point & Altitude
    top_p = slope_data.get("topPoint")
    bottom_p = slope_data.get("bottomPoint")
    
    top_str = "nil"
    top_alt_str = "nil"
    if top_p:
        top_str = f"CLLocationCoordinate2D(latitude: {top_p['lat']}, longitude: {top_p['lon']})"
        top_alt_str = f"{top_p['alt']:.1f}"

    bottom_str = "nil"
    bottom_alt_str = "nil"
    if bottom_p:
        bottom_str = f"CLLocationCoordinate2D(latitude: {bottom_p['lat']}, longitude: {bottom_p['lon']})"
        bottom_alt_str = f"{bottom_p['alt']:.1f}"

    code = f"""        Slope(
            name: "{slope_data['name']}",
            koreanName: "{slope_data['koreanName']}",
            difficulty: {slope_data['difficulty']},
            length: {slope_data['length']},
            avgGradient: {slope_data['avgGradient']},
            maxGradient: {slope_data['maxGradient']},
            status: {slope_data['status']},
{boundary_str}
            topPoint: {top_str},
            bottomPoint: {bottom_str},
            topAltitude: {top_alt_str},
            bottomAltitude: {bottom_alt_str}
        ),"""
    return code

def main():
    print("📂 SlopeDatabase.swift 읽는 중...")
    with open(SWIFT_FILE_PATH, "r") as f:
        content = f.read()
        
    slopes = parse_slopes(content)
    print(f"🧩 {len(slopes)}개의 슬로프 파싱 완료.")
    
    updated_slopes_code = []
    
    for slope in slopes:
        print(f"\n🏔️  [{slope['name']}] 처리 중...")
        
        if not slope["boundary"]:
            print("   ⚠️ Boundary 데이터 없음. 건너뜀.")
            updated_slopes_code.append(generate_slope_code(slope))
            continue
            
        # 고도 조회
        elevations = fetch_elevations_batch(slope["boundary"])
        
        if None in elevations:
             print("   ⚠️ 고도 데이터 조회 실패. 기존 데이터 유지 시도.")
             # 실패 시 로직 생략
             updated_slopes_code.append(generate_slope_code(slope))
             continue
             
        # 데이터 결합 및 정렬
        points = []
        for i, ((lat, lon), alt) in enumerate(zip(slope["boundary"], elevations)):
            points.append({"lat": lat, "lon": lon, "alt": alt})
            
        # 고도순 정렬 (내림차순)
        sorted_points = sorted(points, key=lambda x: x["alt"], reverse=True)
        
        slope["topPoint"] = sorted_points[0]
        slope["bottomPoint"] = sorted_points[-1]
        
        print(f"   ✅ Top: {slope['topPoint']['alt']}m, Bottom: {slope['bottomPoint']['alt']}m")
        
        updated_slopes_code.append(generate_slope_code(slope))

    # 최종 파일 생성
    print("\n💾 새로운 Swift 코드 생성 중...")
    
    # slopes 배열 부분만 교체하는 건 복잡하므로,
    # 템플릿 형태로 전체 파일을 다시 쓰는 방식보다는
    # "slopes: [ ... ]" 내부를 교체하는 방식을 권장하지만,
    # 여기서는 전체 파일을 읽어서 Regex로 slopes 배열 부분을 찾아서 교체하겠습니다.
    
    # 배열 시작 찾기
    start_marker = "let slopes: [Slope] = ["
    end_marker = "    ]" # 배열 끝 (들여쓰기 주의) -> 정확히 매칭하기 어려울 수 있음.
    
    # 하지만 Python 스크립트에서 직접 작성하기보다, 
    # 생성된 슬로프 코드 블록들을 별도 파일로 저장하면 
    # Agent가 'replace_file_content'로 안전하게 교체하는 것이 낫습니다.
    
    with open("new_slopes_array.swift", "w") as f:
        f.write("\n".join(updated_slopes_code))
        
    print("✨ new_slopes_array.swift 생성 완료!")

if __name__ == "__main__":
    main()

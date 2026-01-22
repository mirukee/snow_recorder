import urllib.request
import json
import ssl

# High1 Resort Bounding Box (Approximate)
# Min Lat, Min Lon, Max Lat, Max Lon
BBOX = "37.17,128.81,37.21,128.85"

# Overpass Query
# Search for ways with piste:type = downhill within the bbox
# Increased timeout to 180 seconds
query = f"""
[out:json][timeout:180];
(
  way["piste:type"="downhill"]({BBOX});
  relation["piste:type"="downhill"]({BBOX});
);
out body;
>;
out skel qt;
"""

url = "https://overpass-api.de/api/interpreter"
data = query.encode('utf-8')

print(f"Querying OpenStreetMap for slopes in High1 Resort ({BBOX})...")

try:
    # Relax SSL verification just in case environment has issues
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    
    req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/x-www-form-urlencoded'})
    with urllib.request.urlopen(req, context=ctx) as response:
        result = json.loads(response.read().decode('utf-8'))
        
    elements = result.get('elements', [])
    nodes = {n['id']: (n['lat'], n['lon']) for n in elements if n['type'] == 'node'}
    ways = [w for w in elements if w['type'] == 'way']
    
    print(f"Found {len(ways)} slopes (ways).")
    print("-" * 40)
    
    found_names = []
    
    for way in ways:
        tags = way.get('tags', {})
        name = tags.get('name', 'Unknown')
        name_en = tags.get('name:en', '')
        piste_difficulty = tags.get('piste:difficulty', 'Unknown')
        
        # Get coordinates for the way
        coords = []
        for node_id in way.get('nodes', []):
            if node_id in nodes:
                coords.append(nodes[node_id])
                
        print(f"Slope: {name} ({name_en})")
        print(f"Difficulty: {piste_difficulty}")
        print(f"Points: {len(coords)}")
        
        if name != 'Unknown' or name_en != '':
             found_names.append(name if name != 'Unknown' else name_en)
        
        print("-" * 20)

    print("\n[Summary] Detected Named Slopes:")
    for n in sorted(list(set(found_names))):
        print(f"- {n}")

except Exception as e:
    print(f"Error fetching data: {e}")

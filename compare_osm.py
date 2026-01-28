import requests
import json

overpass_url = "http://overpass-api.de/api/interpreter"
overpass_query = """
[out:json];
way["name:en"="Zeus3"](37.17, 128.80, 37.21, 128.85);
out body;
>;
out skel qt;
"""

response = requests.get(overpass_url, params={'data': overpass_query})
data = response.json()

nodes = {node['id']: (node['lat'], node['lon']) for node in data['elements'] if node['type'] == 'node'}
ways = [way for way in data['elements'] if way['type'] == 'way']

if not ways:
    print("No way found")
else:
    way = ways[0]
    coords = [nodes[node_id] for node_id in way['nodes']]
    print(f"OSM Zeus3 Start: {coords[0]}")
    print(f"OSM Zeus3 End: {coords[-1]}")
    print(f"Total Points: {len(coords)}")

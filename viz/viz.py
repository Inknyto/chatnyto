# ~/Documents/git/chatnyto/viz/viz.py 29 Jul 2026 at 08:50:37 PM

import graphviz
import os

output_dir = './output'
os.makedirs(output_dir, exist_ok=True)

# ============================================================
# Diagram 1: System Overview
# ============================================================
d1 = graphviz.Digraph('SystemOverview', format='png')
d1.attr(rankdir='TB', bgcolor='#1a1a2e', fontcolor='white', fontsize='20', label='ChatNyto — System Overview')
d1.attr('node', shape='box', style='rounded,filled', fontcolor='white', fontsize='11')
d1.attr('edge', color='#8899aa', fontcolor='#aabbcc', fontsize='10')

# App platforms
with d1.subgraph(name='cluster_app') as c:
    c.attr(label='ChatNyto App (Flutter)', style='rounded,filled', color='#16213e', bgcolor='#0f3460')
    c.node('android', 'Android\n(foreground service)', fillcolor='#e94560')
    c.node('ios', 'iOS', fillcolor='#e94560')
    c.node('desktop', 'Linux / macOS / Windows', fillcolor='#e94560')
    c.node('crypto', 'X25519/Ed25519\nAES-256-GCM', fillcolor='#533483')
    c.node('storage', 'Encrypted Local Storage\n(SQLite + files)', fillcolor='#533483')

# Brokers
with d1.subgraph(name='cluster_brokers') as c:
    c.attr(label='MQTT Brokers (Zero-Trust)', style='rounded,filled', color='#16213e', bgcolor='#0f3460')
    c.node('esp32', 'Heltec V3 ESP32\nLoRa Bridge (SX1262)\nRetained messages', fillcolor='#16c79a')
    c.node('local', 'Local Mosquitto\nWiFi / LAN', fillcolor='#16c79a')
    c.node('cloud', 'Cloud Broker\nwss://domain/mqtt\nCloudflare Tunnel', fillcolor='#16c79a')

# Deployment
with d1.subgraph(name='cluster_deploy') as c:
    c.attr(label='Server Deployment (Optional)', style='rounded,filled', color='#16213e', bgcolor='#0f3460')
    c.node('mosquitto', 'Mosquitto 2.0\nWebSocket 9001', fillcolor='#f9a826')
    c.node('coturn', 'Coturn TURN\n(optional)', fillcolor='#f9a826')
    c.node('profile', 'nginx profile\n/.well-known/chatnyto.json', fillcolor='#f9a826')
    c.node('cf', 'cloudflared', fillcolor='#f9a826')

# Connections
d1.edge('android', 'esp32', label='MQTT over LoRa\n868MHz / 915MHz')
d1.edge('android', 'local', label='MQTT 1883 / WS')
d1.edge('android', 'cloud', label='WSS 443')
d1.edge('ios', 'cloud', style='dashed')
d1.edge('desktop', 'local', style='dashed')
d1.edge('cloud', 'mosquitto', style='dashed', color='#f9a826')
d1.edge('mosquitto', 'cf', style='dashed', color='#f9a826')
d1.edge('profile', 'cf', style='dashed', color='#f9a826')
d1.edge('coturn', 'android', label='UDP TURN\nfor calls', style='dashed', color='#ff6b6b')

d1.render(f'{output_dir}/1_system_overview', cleanup=True)
print("Diagram 1 done")

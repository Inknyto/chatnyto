#!/usr/bin/env bash
# Flashes the ChatNyto MQTT broker onto a Heltec WiFi LoRa 32 V3 and opens
# the serial monitor.
#
# Usage: ./flash_heltec_v3.sh [port]   (default port: /dev/ttyUSB0)
#
# After flashing, the OLED shows the broker SSID, IP address and MQTT port.
# For configuration without the IDF monitor, connect a terminal to the
# console REPL instead:
#     screen /dev/ttyUSB0 115200
# and type `help` (commands: info, wifi <ssid> [password], wifi-clear, reboot).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/esp-idf-mqtt-broker"
IDF_DIR="${IDF_PATH:-$HOME/esp/esp-idf}"
PORT="${1:-/dev/ttyUSB0}"

# shellcheck disable=SC1091
source "$IDF_DIR/export.sh"

cd "$PROJECT_DIR"
idf.py -p "$PORT" flash monitor

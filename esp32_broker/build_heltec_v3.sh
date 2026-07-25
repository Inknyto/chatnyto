#!/usr/bin/env bash
# Builds the ChatNyto MQTT broker for the Heltec WiFi LoRa 32 V3 (ESP32-S3).
#
# - Installs ESP-IDF v5.2 under ~/esp/esp-idf if not present
# - Fetches the mongoose (MQTT) and ssd1306 (OLED) components
# - Builds with the Heltec V3 defaults (AP mode, OLED, serial console)
#
# Usage: ./build_heltec_v3.sh [menuconfig]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/esp-idf-mqtt-broker"
IDF_DIR="${IDF_PATH:-$HOME/esp/esp-idf}"
IDF_VERSION="v5.2.3"

# --- ESP-IDF -----------------------------------------------------------------
if [ ! -f "$IDF_DIR/export.sh" ]; then
    echo ">> Installing ESP-IDF $IDF_VERSION into $IDF_DIR"
    mkdir -p "$(dirname "$IDF_DIR")"
    git clone -b "$IDF_VERSION" --recursive --depth 1 \
        https://github.com/espressif/esp-idf.git "$IDF_DIR"
    "$IDF_DIR/install.sh" esp32s3
fi
# shellcheck disable=SC1091
source "$IDF_DIR/export.sh"

cd "$PROJECT_DIR"

# --- Components --------------------------------------------------------------
mkdir -p components

if [ ! -d components/mongoose ]; then
    echo ">> Fetching mongoose"
    git clone -b 7.9 --depth 1 https://github.com/cesanta/mongoose.git \
        components/mongoose
    echo 'idf_component_register(SRCS "mongoose.c" PRIV_REQUIRES esp_timer INCLUDE_DIRS ".")' \
        > components/mongoose/CMakeLists.txt
fi

if [ ! -d components/ssd1306 ]; then
    echo ">> Fetching ssd1306 OLED driver"
    git clone --depth 1 https://github.com/nopnop2002/esp-idf-ssd1306.git \
        /tmp/esp-idf-ssd1306.$$
    cp -r /tmp/esp-idf-ssd1306.$$/components/ssd1306 components/ssd1306
    rm -rf /tmp/esp-idf-ssd1306.$$
fi

if [ ! -d components/ra01s ]; then
    echo ">> Fetching SX1262 LoRa driver"
    git clone --depth 1 https://github.com/nopnop2002/esp-idf-sx126x.git \
        /tmp/esp-idf-sx126x.$$
    cp -r /tmp/esp-idf-sx126x.$$/components/ra01s components/ra01s
    rm -rf /tmp/esp-idf-sx126x.$$
fi

# --- Build -------------------------------------------------------------------
export SDKCONFIG_DEFAULTS="sdkconfig.defaults;sdkconfig.defaults.heltec_v3"
idf.py set-target esp32s3

if [ "${1:-}" = "menuconfig" ]; then
    idf.py menuconfig
fi

idf.py build
echo ">> Build done. Flash with: ./flash_heltec_v3.sh [/dev/ttyUSB0]"

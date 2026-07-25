# ChatNyto broker on the Heltec WiFi LoRa 32 V3

MQTT broker (mongoose) for ESP32, extended for the Heltec V3:

- **OLED status** — the on-board SSD1306 shows the broker SSID, IP address
  and MQTT port once the network is up.
- **Serial console** — a REPL on `/dev/ttyUSB0` for configuring the broker
  without reflashing:

  ```sh
  screen /dev/ttyUSB0 115200
  chatnyto> help
  chatnyto> info                    # IP, SSID, MQTT port
  chatnyto> wifi MySSID MyPassword  # stored in NVS, overrides menuconfig
  chatnyto> reboot
  ```

- **LoRa bridge** — every MQTT message is relayed over the SX1262 radio
  (and vice versa), so two brokers keep exchanging chats without any
  WiFi/internet path between them. Frequency and TX power are set in
  menuconfig (`LoRa Bridge Configuration`); defaults are EU868 at the
  maximum 22 dBm. Pick the maximum band/power your region authorizes.

## Build & flash

```sh
./build_heltec_v3.sh              # installs ESP-IDF if needed, builds
./build_heltec_v3.sh menuconfig   # same, but opens menuconfig first
./flash_heltec_v3.sh              # flash + monitor on /dev/ttyUSB0
./flash_heltec_v3.sh /dev/ttyACM0 # custom port
```

The build script fetches the third-party components on first run:
`mongoose` (MQTT), `ssd1306` (OLED), `ra01s` (SX1262).

`build.sh` is the older generic-ESP32 build script kept for reference.

## Defaults

The broker starts as an access point `chatnyto` / `chatnyto123`
(sdkconfig.defaults.heltec_v3) with the broker reachable on
`mqtt://192.168.4.1:1883`. Use the console `wifi` command or menuconfig to
join an existing network instead (ST mode).

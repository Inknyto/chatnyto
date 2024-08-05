#!/usr/bin/bash
git clone https://github.com/nopnop2002/esp-idf-mqtt-broker &&
cd esp-idf-mqtt-broker &&
mkdir components &&
cd components/ &&
git clone -b 7.9 https://github.com/cesanta/mongoose.git &&
cd mongoose/ &&
echo "idf_component_register(SRCS \"mongoose.c\" PRIV_REQUIRES esp_timer INCLUDE_DIRS \".\")" > CMakeLists.txt &&
cd ../.. &&
idf.py set-target esp32 &&
idf.py menuconfig &&
idf.py flash monitor

#!/usr/bin/bash
git clone https://github.com/eclipse/mosquitto.git 
cd mosquitto
mkdir build
cd build
cmake -DWITH_STATIC_LIBRARIES=ON ../
make


#!/usr/bin/bash
#
# This file is for building mosquitto statically
# skip this if you have installed mosquitto 
# using termux, or your prefered package manager
#
git clone https://github.com/eclipse/mosquitto.git 
cd mosquitto
mkdir build
cd build
cmake -DWITH_STATIC_LIBRARIES=ON ../
make


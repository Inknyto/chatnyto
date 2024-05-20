#!/usr/bin/bash
sudo apt install mosquitto node-mqtt -y &&
npm i pm2 -g &&
pm2 start mosquitto


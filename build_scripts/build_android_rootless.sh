#!/data/data/com.termux/files/usr/bin/bash
pkg update && pkg upgrade -y &&
pkg i nodejs mosquitto mqtt -y &&
npm i pm2 -g && 
pm2 start 'mosquitto'




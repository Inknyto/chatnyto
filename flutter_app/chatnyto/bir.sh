#!/usr/bin/bash
flutter build apk && 
adb install -r build/app/outputs/flutter-apk/app-release.apk && 
adb shell monkey -p com.example.chatnyto -v 1 && 
adb shell input keyevent 26 && 
adb shell input keyevent 82 && 
scrcpy


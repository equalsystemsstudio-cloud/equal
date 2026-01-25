# APK Installation Guide

## Problem Solved: Reduced APK Size from 500MB+

The original universal APK was over 500MB, which is too large for most devices to install. We've created **split APKs** that are much smaller and more manageable.

## Available APK Files (Much Smaller!)

In the `build/app/outputs/flutter-apk/` folder, you'll find these optimized APKs:

### Debug APKs (Ready to Install)
- **app-arm64-v8a-debug.apk** - 199MB (for most modern phones)
- **app-armeabi-v7a-debug.apk** - 154MB (for older phones)
- **app-x86_64-debug.apk** - 194MB (for emulators/tablets)
- **app-x86-debug.apk** - 195MB (for older emulators)

### Release APKs (Smaller, but need proper keystore)
- **app-arm64-v8a-release.apk** - 132MB
- **app-armeabi-v7a-release.apk** - 104MB
- **app-x86_64-release.apk** - 141MB

## Which APK Should You Install?

### For Most Android Phones (Recommended)
Use: **app-arm64-v8a-debug.apk** (199MB)
- Works on most phones from 2017 onwards
- Samsung Galaxy S8+, Google Pixel 2+, OnePlus 5+, etc.

### For Older Android Phones
Use: **app-armeabi-v7a-debug.apk** (154MB)
- Works on older phones and budget devices
- Samsung Galaxy S7 and older, older budget phones

### For Emulators
Use: **app-x86_64-debug.apk** (194MB)
- For Android Studio emulator
- For BlueStacks, NoxPlayer, etc.

## Installation Steps

1. **Copy the appropriate APK** to your phone
2. **Enable "Install from Unknown Sources"** in your phone settings
3. **Tap the APK file** to install
4. **Allow installation** when prompted

## Why This Works Better

- **Original APK**: 500MB+ (too large to install)
- **Split APKs**: 104-199MB (much more reasonable)
- **Faster installation** and **less storage usage**
- **Better performance** as only necessary architecture is included

## For Production Release

To create proper release APKs:
1. Generate a proper keystore file
2. Update `android/key.properties` with real keystore info
3. Run: `flutter build apk --release --split-per-abi`

The release APKs will be even smaller (104-132MB) and optimized for production use.
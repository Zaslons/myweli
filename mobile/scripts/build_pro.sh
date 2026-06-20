#!/bin/bash
# Build script for Myweli Pro (Provider App)

echo "Building Myweli Pro for iOS..."
flutter build ios --flavor pro --release

echo "Building Myweli Pro for Android..."
flutter build apk --flavor pro --release

echo "Build complete!"

#!/bin/bash
# Build script for Myweli (Consumer App)

echo "Building Myweli (Consumer) for iOS..."
flutter build ios --flavor consumer --release

echo "Building Myweli (Consumer) for Android..."
flutter build apk --flavor consumer --release

echo "Build complete!"

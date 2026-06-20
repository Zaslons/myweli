#!/bin/bash
# Run Myweli Pro app using --target (workaround until Xcode schemes are configured)

echo "Running Myweli Pro..."
flutter run --target lib/main_pro.dart -d "$1"

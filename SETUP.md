# Myweli Setup Instructions

## Flutter Installation

Flutter is not currently installed on your system. Follow these steps to set it up:

### 1. Install Flutter

#### Option A: Using Homebrew (Recommended for macOS)
```bash
brew install --cask flutter
```

#### Option B: Manual Installation
1. Download Flutter SDK from: https://docs.flutter.dev/get-started/install/macos
2. Extract the zip file to a location like `~/development/flutter`
3. Add Flutter to your PATH by editing `~/.zshrc`:
   ```bash
   export PATH="$PATH:$HOME/development/flutter/bin"
   ```
4. Reload your shell:
   ```bash
   source ~/.zshrc
   ```

### 2. Verify Installation
```bash
flutter doctor
```

This will check your Flutter installation and show what else needs to be configured (Xcode, Android Studio, etc.).

### 3. Install Dependencies
Once Flutter is installed, navigate to the mobile directory and install dependencies:
```bash
cd mobile
flutter pub get
```

### 4. Run the App

#### For iOS Simulator:
```bash
flutter run -d ios
```

#### For Android Emulator:
```bash
flutter run -d android
```

#### For a Connected Device:
```bash
flutter devices  # List available devices
flutter run -d <device-id>
```

## Quick Start (After Flutter Installation)

```bash
# Navigate to project
cd "/Users/sadreddinedaher/beauty app/mobile"

# Install dependencies
flutter pub get

# Check available devices
flutter devices

# Run the app
flutter run
```

## Troubleshooting

### If you see "command not found: flutter"
- Make sure Flutter is installed and added to your PATH
- Restart your terminal or run `source ~/.zshrc`

### If you see "No devices found"
- For iOS: Open Xcode and install iOS Simulator
- For Android: Open Android Studio and create an Android Virtual Device (AVD)

### If dependencies fail to install
- Make sure you have internet connection
- Try running `flutter pub cache repair`
- Check your `pubspec.yaml` for any syntax errors

## Development Notes

- The app currently uses **mock data** - all services are simulated
- OTP code for testing: **123456** (always accepted in mock mode)
- All screens are functional with sample data
- Backend integration can be added later by replacing mock services




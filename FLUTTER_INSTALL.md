# Flutter Manual Installation Guide for macOS

## Official Flutter Installation Page
Visit: **https://docs.flutter.dev/get-started/install/macos**

## Step-by-Step Installation

### 1. Download Flutter SDK

**For Apple Silicon (M1/M2/M3 Macs - ARM64):**
- Direct download link: https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_stable.tar.xz
- Or visit: https://docs.flutter.dev/get-started/install/macos and click "Download Flutter SDK"

**For Intel Macs (x64):**
- Direct download link: https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_stable.tar.xz

### 2. Extract Flutter SDK

After downloading, extract the archive:

```bash
cd ~
mkdir -p development
cd development
# If you downloaded the .tar.xz file:
tar xf ~/Downloads/flutter_macos_arm64_stable.tar.xz
# Or if you downloaded a .zip file:
unzip ~/Downloads/flutter_macos_arm64_stable.zip
```

This will create a `flutter` directory in `~/development/`

### 3. Add Flutter to PATH

Edit your `~/.zshrc` file (since you're using zsh):

```bash
nano ~/.zshrc
```

Add this line at the end:
```bash
export PATH="$PATH:$HOME/development/flutter/bin"
```

Save and exit (Ctrl+X, then Y, then Enter)

### 4. Reload Your Shell

```bash
source ~/.zshrc
```

### 5. Verify Installation

```bash
flutter --version
```

You should see the Flutter version number.

### 6. Run Flutter Doctor

```bash
flutter doctor
```

This will check your setup and tell you what else needs to be installed (Xcode, Android Studio, etc.)

### 7. Accept Android Licenses (if using Android)

```bash
flutter doctor --android-licenses
```

## After Installation - Run Myweli App

Once Flutter is installed:

```bash
cd "/Users/sadreddinedaher/beauty app/mobile"
flutter pub get
flutter run
```

## Alternative: Using Git (Recommended)

If you prefer using Git:

```bash
cd ~/development
git clone https://github.com/flutter/flutter.git -b stable
```

Then add to PATH as shown in step 3 above.

## Troubleshooting

- **"command not found: flutter"**: Make sure you added Flutter to PATH and reloaded your shell
- **Permission denied**: Make sure you extracted Flutter to a directory you own (like ~/development)
- **Xcode issues**: Install Xcode from App Store and run `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`

## Official Documentation

For the most up-to-date instructions, always refer to:
**https://docs.flutter.dev/get-started/install/macos**




# iOS Flavors Setup Guide

To use Flutter flavors (`--flavor consumer` or `--flavor pro`) on iOS, you need to configure Xcode schemes. Currently, the project uses a workaround with `--target` to run different entry points.

## Quick Workaround (Current)

To run the Pro app:
```bash
flutter run --target lib/main_pro.dart -d <device-id>
```

Or use the script:
```bash
./scripts/run_pro.sh <device-id>
```

To run the Consumer app (default):
```bash
flutter run -d <device-id>
```

## Proper Flavor Setup (Recommended)

To set up proper iOS flavors with different bundle IDs and app names:

### 1. Open Xcode
```bash
cd ios
open Runner.xcworkspace
```

### 2. Create Build Configurations

1. Select the **Runner** project in the navigator
2. Select the **Runner** target
3. Go to **Info** tab
4. Under **Configurations**, duplicate the existing configurations:
   - Duplicate **Debug** → Name it **Debug-consumer**
   - Duplicate **Debug** → Name it **Debug-pro**
   - Duplicate **Release** → Name it **Release-consumer**
   - Duplicate **Release** → Name it **Release-pro**

### 3. Configure Build Settings

For each configuration, set:

**Debug-consumer & Release-consumer:**
- `PRODUCT_BUNDLE_IDENTIFIER`: `com.example.myweli`
- `INFOPLIST_FILE`: `Runner/Info-consumer.plist`
- `PRODUCT_NAME`: `Myweli`

**Debug-pro & Release-pro:**
- `PRODUCT_BUNDLE_IDENTIFIER`: `com.example.myweli.pro`
- `INFOPLIST_FILE`: `Runner/Info-pro.plist`
- `PRODUCT_NAME`: `Myweli Pro`

### 4. Create Schemes

1. Go to **Product** → **Scheme** → **Manage Schemes...**
2. Click **+** to create a new scheme
3. Name it **consumer** and set the target to **Runner**
4. Click **+** again and create **pro** scheme
5. For each scheme:
   - Edit the scheme (click the scheme name → Edit Scheme)
   - Set **Run** → **Build Configuration**:
     - **consumer**: Debug-consumer
     - **pro**: Debug-pro
   - Set **Archive** → **Build Configuration**:
     - **consumer**: Release-consumer
     - **pro**: Release-pro

### 5. Configure Flutter Build Configurations

The xcconfig files are already created in `ios/Flutter/Config/`. Make sure they reference the correct configurations.

### 6. Update Podfile (if needed)

The Podfile should reference the build configurations. Update it if necessary:

```ruby
project 'Runner', {
  'Debug-consumer' => :debug,
  'Release-consumer' => :release,
  'Debug-pro' => :debug,
  'Release-pro' => :release,
}
```

Then run:
```bash
cd ios
pod install
```

### 7. Test

After setup, you should be able to run:
```bash
flutter run --flavor consumer -d <device-id>
flutter run --flavor pro -d <device-id>
```

## Alternative: Use Different Entry Points

Until Xcode schemes are configured, you can use:
- Consumer: `flutter run -d <device-id>` (uses `lib/main.dart`)
- Pro: `flutter run --target lib/main_pro.dart -d <device-id>`

Note: This approach uses the same bundle ID for both apps, so they cannot be installed simultaneously.

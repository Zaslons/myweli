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

## The local environment (backend + database)

**This is where almost all development happens**, and it is the cheapest of the
four environments by a wide margin — every bug caught here never occupies
staging, a deploy, or your attention. The other three are staging, Vercel
previews and production; see
[docs/design/infra-staging.md](docs/design/infra-staging.md) §2.2.

You need this only when working on the backend, or on an app/web slice that
talks to it. Pure UI work on mocks needs nothing but Flutter.

**Prerequisite:** Docker Desktop.

### 1. Start the database

```bash
docker compose up -d
```

Postgres 16 on `localhost:5432`, pinned to the same major as CI and Cloud SQL.
Data survives `docker compose down`; `docker compose down -v` drops it for a
clean slate.

### 2. Run the API

Once, if you have never run the backend on this machine:

```bash
dart pub global activate dart_frog_cli
```

Then:

```bash
cd backend && cp .env.example .env && dart pub global run dart_frog_cli:dart_frog dev
```

The long invocation is deliberate: `dart pub global activate` installs the
`dart_frog` binary into `~/.pub-cache/bin`, which is **not on `PATH` by
default**, so the short `dart_frog dev` fails with *command not found* even
though the CLI is installed. Add `export PATH="$PATH:$HOME/.pub-cache/bin"` to
your `~/.zshrc` if you prefer the short form.

Then edit `.env` — the one line that matters locally is:

```
DATABASE_URL=postgres://postgres:postgres@localhost:5432/myweli
```

Leave `ENV=dev`. That is what keeps the guards off (so nothing has to be
configured to boot) and what lets the demo salons seed and OTP responses return
`devCode` inline, so you can sign in without an SMS channel. `ENV=staging` and
`ENV=prod` both turn the guards on and every "must be set" check becomes real —
see [docs/BACKEND.md](docs/BACKEND.md) §3.2.1.

The API comes up on `http://localhost:8080`. Check it with:

```bash
curl -s localhost:8080/health
```

First boot runs every migration and, because `ENV=dev`, seeds the demo salons —
so `curl -s "localhost:8080/providers?pageSize=3"` should come back with four
providers. A `StdinException: Error setting terminal echo mode` in the log is
harmless: `dart_frog dev` wants a TTY for its interactive helpers and the server
serves regardless. In a non-interactive shell, run the generated entrypoint
directly instead:

```bash
dart pub global run dart_frog_cli:dart_frog build && dart build/bin/server.dart
```

### 3. Point a client at it

```bash
# the consumer app
cd mobile && flutter run --flavor consumer \
  --dart-define=USE_API_BACKEND=true \
  --dart-define=API_BASE_URL=http://localhost:8080
```

On an **Android emulator** use `http://10.0.2.2:8080` — the emulator's alias for
your host. `localhost` there is the emulator itself.

```bash
# the web app
cd web && cp .env.example .env.local && npm install && npm run dev
```

## Development Notes

- The app runs on **mock data by default** — `USE_API_BACKEND` is off unless you
  pass it, so every screen works with no server at all.
- **Release builds refuse to run on mocks.** A release build without
  `USE_API_BACKEND=true` and a real `API_BASE_URL` shows a blocking
  `BUILD MISCONFIGURED` screen instead of starting, because it would otherwise
  look completely healthy while testing nothing. `ALLOW_MOCK_RELEASE=true` is
  the deliberate opt-out for a demo build.
- OTP code in mock mode: **123456**. Against a local backend the real code comes
  back inline in the response as `devCode` (dev and staging only, never prod).
- The backend is **live in production** at `api.myweli.com` — it is no longer
  something to add later. Architecture and rules:
  [docs/BACKEND.md](docs/BACKEND.md).




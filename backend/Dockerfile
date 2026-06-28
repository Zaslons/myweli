# Myweli API (dart_frog) — multi-stage build to a minimal runtime image.
# Host-agnostic: runs on Fly.io / Cloud Run / Render / any Docker host.
#
#   docker build -t myweli-api backend/
#   docker run -p 8080:8080 -e ENV=prod -e JWT_SECRET=… -e DATABASE_URL=… myweli-api
#
# All config comes from env (never baked into the image) — see backend/.env.example
# and docs/DEPLOYMENT.md. Migrations run automatically on boot when DATABASE_URL
# is set. The server reads PORT (default 8080) and binds 0.0.0.0.
#
# Pin `dart:3.10` (or a digest) for fully reproducible prod builds; `stable`
# tracks CI.
FROM dart:stable AS build

WORKDIR /app

# Resolve dependencies first for better layer caching.
COPY pubspec.* ./
RUN dart pub get

# Generate the dart_frog server, then compile a self-contained executable.
COPY . .
RUN dart pub global activate dart_frog_cli \
 && dart pub global run dart_frog_cli:dart_frog build
RUN cd build \
 && dart pub get \
 && dart compile exe bin/server.dart -o bin/server

# Minimal runtime: the Dart runtime + the compiled server only.
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/build/bin/server /app/bin/server

EXPOSE 8080
ENTRYPOINT ["/app/bin/server"]

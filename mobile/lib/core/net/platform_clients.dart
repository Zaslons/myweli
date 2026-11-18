// What the transport needs from the platform, chosen at compile time so the
// admin console — a web build — never compiles cronet_http or jni
// (docs/design/android-http3-transport.md §4.1).
export 'platform_clients_stub.dart'
    if (dart.library.io) 'platform_clients_io.dart'
    if (dart.library.js_interop) 'platform_clients_web.dart';

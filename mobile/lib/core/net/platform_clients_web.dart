import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

import 'net_settings.dart';

/// The admin console, a web build: never Android.
bool get runsOnAndroid => false;

/// The browser's client — what `http.Client()` gives on the web.
http.Client buildPlatformClient() => BrowserClient();

/// Never called: [runsOnAndroid] is false.
http.Client buildCronetClient(CronetSettings settings) =>
    throw UnsupportedError('Cronet is Android only.');

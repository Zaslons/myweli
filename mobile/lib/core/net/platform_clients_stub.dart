import 'package:http/http.dart' as http;

import 'net_settings.dart';

// A platform with neither dart:io nor a browser. None that this app builds for.

bool get runsOnAndroid => false;

http.Client buildPlatformClient() =>
    throw UnsupportedError('No HTTP client on this platform.');

http.Client buildCronetClient(CronetSettings settings) =>
    throw UnsupportedError('Cronet is Android only.');

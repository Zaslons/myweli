import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dart_source.dart';

/// The guards of docs/design/android-http3-transport.md §7.
///
/// ## Why
///
/// On Android, `dart:io`'s TLS over TCP cannot reach our Cloudflare hosts on
/// Orange CI fibre, and the app says « Pas de connexion ». The fix only holds
/// if EVERY call goes through the app's transport (`lib/core/net/`): one
/// service built with its own `http.Client()`, one `NetworkImage`, and that
/// screen is broken again on that network while every test stays green. And
/// moving off `dart:io` moves certificate checks to Android's store, so the
/// trust list for our domains (§5.2) is part of the fix, not an extra.
///
/// ## What it cannot see
///
/// That Play Services builds an engine on a given phone, that HTTP/3 is
/// negotiated, and that Android applies the trust list to Cronet: the device
/// reads of §7, red first for the trust list. Nor a client built inside a
/// package from a URL we pass it — the `runWithClient` backstop is for those.
void main() {
  final root = Directory.current.path.endsWith('mobile') ? '' : 'mobile/';
  final lib = '${root}lib';
  final androidSrc = '${root}android/app/src';

  String code(String path) => stripDartComments(File(path).readAsStringSync());

  Iterable<File> dartFiles() => Directory(lib)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  String rel(File f) => f.path.substring(lib.length + 1);

  group('no HTTP outside the transport', () {
    // Each of these reaches the network without `lib/core/net/`.
    final banned = <String, RegExp>{
      'http.Client()': RegExp(r'\bhttp\.Client\(\s*\)'),
      'Client()': RegExp(r'(?<![\w.])Client\(\s*\)'),
      'IOClient(': RegExp(r'\bIOClient\('),
      'BrowserClient(': RegExp(r'\bBrowserClient\('),
      'HttpClient(': RegExp(r'(?<![\w.])HttpClient\('),
      'CronetClient': RegExp(r'\bCronetClient\b'),
      'NetworkImage(': RegExp(r'(?<![\w.])NetworkImage\('),
      'Image.network(': RegExp(r'\bImage\.network\('),
    };
    // Admin console only — a web build no Android flavour includes (§4.4) —
    // and held to its own path by admin_remote_images_guard_test.dart.
    const allowed = {
      'Image.network(': {'screens/admin/widgets/admin_remote_image.dart'},
    };

    for (final entry in banned.entries) {
      test('no ${entry.key} under lib/ outside core/net/', () {
        final offenders = [
          for (final f in dartFiles())
            if (!rel(f).startsWith('core/net/') &&
                !(allowed[entry.key]?.contains(rel(f)) ?? false) &&
                entry.value.hasMatch(code(f.path)))
              rel(f),
        ];
        expect(
          offenders,
          isEmpty,
          reason:
              '${entry.key} goes around the app transport; on Android that '
              'call fails on Orange fibre. Pass AppHttpTransport.client.',
        );
      });
    }

    test('cronet_http is imported by the io platform file alone', () {
      final importers = [
        for (final f in dartFiles())
          if (code(f.path).contains('package:cronet_http/')) rel(f),
      ];
      expect(importers, ['core/net/platform_clients_io.dart']);
    });

    test('the platform files are chosen at compile time, so the web console '
        'never compiles cronet_http', () {
      final s = code('$lib/core/net/platform_clients.dart');
      expect(s, contains("if (dart.library.io) 'platform_clients_io.dart'"));
      expect(
        s,
        contains("if (dart.library.js_interop) 'platform_clients_web.dart'"),
      );
    });
  });

  group('the shared client is handed over explicitly (§4.1)', () {
    test('every Api*Service in dependency injection gets it', () {
      final s = code('$lib/core/di/dependency_injection.dart');
      final all = RegExp(r'\bApi\w+Service\(').allMatches(s).length;
      final shared = RegExp(
        r'\bApi\w+Service\(\s*client: AppHttpTransport\.client\b',
      ).allMatches(s).length;
      expect(all, greaterThanOrEqualTo(20));
      expect(shared, all);
    });

    test('the admin service, the version gate in both entries, and the '
        'image cache get it', () {
      expect(
        code('$lib/services/admin/admin_service.dart'),
        matches(
          RegExp(r'adminService = AdminService\(\s*client: AppHttpTransport'),
        ),
      );
      for (final entry in ['main.dart', 'main_pro.dart']) {
        expect(
          code('$lib/$entry'),
          contains('ClientVersionGate(client: AppHttpTransport.client)'),
          reason: entry,
        );
      }
      expect(
        code('$lib/core/utils/timeout_cache_manager.dart'),
        contains('client: AppHttpTransport.client'),
      );
    });

    test('the map tiles get it, with flutter_map\'s retries kept', () {
      expect(
        code('$lib/widgets/common/carto_basemap_layer.dart'),
        contains('httpClient: RetryClient(AppHttpTransport.client)'),
      );
    });

    test('both entries install the runWithClient backstop — the Android Pro '
        'entry runs runProApp', () {
      for (final entry in ['main.dart', 'main_pro.dart']) {
        final s = code('$lib/$entry');
        expect(s, contains('http.runWithClient('), reason: entry);
        expect(s, contains('() => AppHttpTransport.client)'), reason: entry);
      }
      expect(code('$lib/main_pro_android.dart'), contains('runProApp('));
    });

    test('error reporting tags every event with the transport (§4.7)', () {
      expect(
        code('$lib/core/observability/error_reporting.dart'),
        contains('AppHttpTransport.instance.whenSettled(reportNetTransport)'),
      );
    });
  });

  test('the Cronet engine: HTTP/3 with the hints, no cache, no storage, the '
      'system DNS, never closed (§4.1)', () {
    final s = code('$lib/core/net/platform_clients_io.dart');
    expect(s, contains('enableQuic: true'));
    expect(s, contains('(host, 443, 443)'));
    expect(s, contains('cacheMode: CacheMode.disabled'));
    expect(s, contains('useBuiltInDnsResolver: false'));
    expect(s, contains('closeEngine: false'));
    expect(s, isNot(contains('storagePath')));
  });

  group('the trust list for our domains (§5.2)', () {
    // SHA-256 of each bundled root, DER. Each file is the copy in macOS's
    // system root store, and equals the copy in Mozilla's CCADB report
    // (read 2026-11-18). A root added, removed or swapped turns this red.
    const anchors = {
      'gts_root_r1':
          'D947432ABDE7B7FA90FC2E6B59101B1280E0E1C7E4E40FA3C6887FFF57A7F4CF',
      'gts_root_r3':
          '34D8A73EE208D9BCDB0D956520934B4E40E69482596E8B6F73C8426B010A6F48',
      'gts_root_r4':
          '349DFA4058C5E263123B398AE795573C4E1313C83FE68F93556CD5E8031B3C7D',
      'isrg_root_x1':
          '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6',
      'isrg_root_x2':
          '69729B8E15A86EFC177A57AFB7171DFC64ADD28C2FCA8CF1507E34453CCB1470',
      'ssl_com_tls_ecc_root_ca_2022':
          'C32FFD9F46F936D16C3673990959434B9AD60AAFBB9E7CF33654F144CC1BA143',
      'ssl_com_tls_rsa_root_ca_2022':
          '8FAF7D2E2CB4709BB8E0B33666BF75A5DD45B5DE480F8EA8D4BFE6BEBC17F2ED',
      'ssl_com_root_ca_ecc':
          '3417BB06CC6007DA1B961C920B8AB4CE3FAD820E4AA30B9ACBC4A74EBDCEBC65',
      'ssl_com_root_ca_rsa':
          '85666A562EE0BE5CE925C1D8890A6F76A87EC16D4D7D5F29EA7419CF20123B69',
      'certum_trusted_network_ca':
          '5C58468D55F58E497E743982D2B50010B6D165374ACF83A7D4A32DB768C4408E',
      'usertrust_ecc_ca':
          '4FF460D54B9C86DABFBCFC5712E0400D2BED3FBC4D4FBDAA86E06ADCD2A9AD7A',
      'usertrust_rsa_ca':
          'E793C9B02FD8AA13E21C31228ACCB08119643B749C898964B1746D46C3D4CBD2',
      'sectigo_public_server_auth_root_e46':
          'C90F26F0FB1B4018B22227519B5CA2B53E2CA5B3BE5CF18EFE1BEF47380C5383',
      'sectigo_public_server_auth_root_r46':
          '7BB647A62AEEAC88BF257AA522D01FFEA395E0AB45C73F93F65654EC38F25A06',
    };

    // The roots the compromised eMudhra certificates chain to, from the
    // disclosure's roots.json (read 2026-11-18), and emSign's other root.
    // Never an anchor, whatever the reason.
    const forbidden = {
      'AAA Certificate Services':
          'D7A7A0FB5D7E2731D771E9484EBCDEF71D5F0C3E0A2948782BC83EE0EA699EF4',
      'emSign ECC Root CA - G3':
          '86A1ECBA089C4A8D3BBE2734C612BA341D813E043CF9E8A862CD5C57A36BBE6B',
      'emSign Root TLS CA - G3':
          '7DD78D5F4F13459A83DFF9ABBBA62EDBAF6F2D102BF257FD712F4D9F2746ED8D',
      'emSign Root CS CA - G3':
          'F2EDAAFF3D9B701FB4D14C9F285F8C0BAD90FC3BCC1FA07D47F4718EDABA34A5',
      'emSign Root CA - G1':
          '40F6AF0346A99AA1CD1D555A4E9CCE62C7F9634603EE406615833DC8C8D00367',
    };

    final mainXml = File(
      '$androidSrc/main/res/xml/network_security_config.xml',
    ).readAsStringSync();
    final debugXml = File(
      '$androidSrc/debug/res/xml/network_security_config.xml',
    ).readAsStringSync();

    String withoutComments(String xml) =>
        xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

    /// The `<domain-config>` holding myweli.com, normalised.
    String myweliBlock(String xml) {
      final blocks = RegExp(
        r'<domain-config>.*?</domain-config>',
        dotAll: true,
      ).allMatches(withoutComments(xml)).map((m) => m.group(0)!).toList();
      final ours = blocks.where((b) => b.contains('myweli.com')).toList();
      expect(ours, hasLength(1));
      return ours.single.replaceAll(RegExp(r'\s+'), ' ');
    }

    List<int> der(File pem) {
      final body = pem
          .readAsLinesSync()
          .where((l) => !l.startsWith('-----'))
          .join();
      return base64.decode(body);
    }

    test('one domain, myweli.com with its subdomains', () {
      final block = myweliBlock(mainXml);
      final domains = RegExp(
        r'<domain\b[^>]*>([^<]*)</domain>',
      ).allMatches(block).map((m) => m.group(0)).toList();
      expect(domains, ['<domain includeSubdomains="true">myweli.com</domain>']);
    });

    test('the anchors are exactly the bundled list, and nothing from the '
        'system or the user', () {
      final block = myweliBlock(mainXml);
      final srcs = RegExp(
        r'<certificates src="([^"]+)"',
      ).allMatches(block).map((m) => m.group(1)).toSet();
      expect(srcs, {for (final name in anchors.keys) '@raw/$name'});
      expect(block, isNot(contains('overridePins')));
      expect(block, isNot(contains('<pin-set')));
    });

    test('each bundled file is the root it claims to be', () {
      final files = Directory(
        '$androidSrc/main/res/raw',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.pem'));
      final found = {
        for (final f in files)
          f.uri.pathSegments.last.replaceAll('.pem', ''): sha256
              .convert(der(f))
              .toString()
              .toUpperCase(),
      };
      expect(found, anchors);
    });

    test('AAA Certificate Services and every emSign root stay out', () {
      expect(
        anchors.values.toSet().intersection(forbidden.values.toSet()),
        isEmpty,
      );
      for (final f in Directory(
        '$androidSrc/main/res/raw',
      ).listSync().whereType<File>()) {
        final text = latin1.decode(der(f));
        for (final name in ['AAA Certificate Services', 'emSign']) {
          expect(text, isNot(contains(name)), reason: f.path);
        }
      }
    });

    test('the debug build trusts our domains exactly as release does, and '
        'only it allows plain HTTP — to the Mac\'s backend alone', () {
      expect(myweliBlock(debugXml), myweliBlock(mainXml));
      expect(
        withoutComments(mainXml),
        isNot(contains('cleartextTrafficPermitted')),
      );
      final cleartext = RegExp(
        r'<domain-config cleartextTrafficPermitted="true">(.*?)</domain-config>',
        dotAll: true,
      ).allMatches(withoutComments(debugXml)).toList();
      expect(cleartext, hasLength(1));
      final hosts = RegExp(
        r'<domain includeSubdomains="false">([^<]+)</domain>',
      ).allMatches(cleartext.single.group(1)!).map((m) => m.group(1)).toSet();
      expect(hosts, {'10.0.2.2', 'localhost', '127.0.0.1'});
      expect(withoutComments(debugXml), isNot(contains('base-config')));
    });

    test('the manifest applies it', () {
      expect(
        File('$androidSrc/main/AndroidManifest.xml').readAsStringSync(),
        contains(
          'android:networkSecurityConfig="@xml/network_security_config"',
        ),
      );
    });
  });
}

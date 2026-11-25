import 'dart:io';

import 'package:myweli_backend/src/demo/demo_reset_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:test/test.dart';

/// Two guards around the demo salon's reset (B16.2,
/// docs/design/demo-reset-restore.md §5.1, §6, §8.4).
void main() {
  // ---------------------------------------------------------------------------
  // The key guard. The reset MERGES the snapshot into the salon's document,
  // so a key the snapshot lacks is never removed. Every key a salon owner's
  // writers can set is in a new salon's document — so in any snapshot —
  // except those listed in `kDemoRestoredByOwnWriter`, which the reset puts
  // back through their own writer instead.
  //
  // Read from the writers an owner (and so a store reviewer on the demo
  // account) can reach, 2026-11-25:
  //   · the profile PATCH (`ProviderCatalogService.updateProfile`: its
  //     `editable` list, the logo, and the market keys an `areaId` derives,
  //     `localities_repository.dart` `marketChangesForArea`);
  //   · the deposit policy (`updateDepositPolicy`);
  //   · the gallery (`updateGallery`), the before/after pairs
  //     (`updateBeforeAfters`), the artists (`addArtist`, `updateArtist`,
  //     `deleteArtist`);
  //   · the services (`addService`, `updateService`, `deleteService`) and the
  //     hours (`replaceAvailability`).
  //
  // What this guard CANNOT see: a key a writer starts writing without being
  // added here. Whoever adds one to a writer above adds it to this list.
  // ---------------------------------------------------------------------------
  const ownerWritableKeys = {
    // profile PATCH, `editable`
    'name', 'description', 'address', 'city', 'commune', 'phoneNumber',
    'whatsapp', 'latitude', 'longitude', 'category',
    // profile PATCH, the logo and the area's market keys
    'logoUrl', 'areaId', 'citySlug', 'countryCode', 'timezone', 'currency',
    // deposit policy
    'depositRequired', 'depositPercentage', 'depositMobileMoneyOperator',
    'depositMobileMoneyNumber', 'cancellationWindowHours',
    // gallery, before/after, artists, services, hours
    'imageUrls', 'beforeAfters', 'artists', 'services', 'availability',
  };

  test('[keys] every key an owner can set is in a new salon\'s document, or '
      'restored by its own writer', () {
    final fresh = draftSalonDocument(
      id: 'p',
      slug: 's',
      name: 'n',
      category: 'salon',
      phoneNumber: '+2250700000000',
    ).keys.toSet();
    final unreached = {
      for (final k in ownerWritableKeys)
        if (!fresh.contains(k) && !kDemoRestoredByOwnWriter.contains(k)) k,
    };
    expect(
      unreached,
      isEmpty,
      reason:
          '[keys] a snapshot may lack these, and the reset\'s merge would '
          'never remove a reviewer\'s value',
    );
  });

  test('[keys] the two sets never overlap', () {
    expect(
      kDemoNeverRestored.intersection(kDemoRestoredByOwnWriter),
      isEmpty,
      reason: '[keys] a key both never restored and restored',
    );
  });

  // ---------------------------------------------------------------------------
  // The caller guard (§6). `replaceServices` wipes a salon's catalogue and has
  // no route; its owner check is the reset's (`_demoOwned`). A second caller
  // is a decision, so it turns this red rather than slipping in.
  //
  // It looks for `.replaceServices(` — a call through a receiver — across
  // everything the server is built from and every operator script, comments
  // stripped (two guards in this repo matched text that existed only in a
  // comment). It cannot see a call written without a receiver inside a
  // repository class itself, or one built by reflection.
  // ---------------------------------------------------------------------------
  test('[callers] only the demo reset calls replaceServices', () {
    String stripComments(String source) => source
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');
    final files = [
      for (final dir in const ['lib', 'routes', 'tool'])
        ...Directory(dir)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')),
      File('main.dart'),
    ];
    final callers = {
      for (final f in files)
        if (f.existsSync() &&
            stripComments(f.readAsStringSync()).contains('.replaceServices('))
          f.path,
    };
    expect(callers, {
      'lib/src/demo/demo_reset_service.dart',
    }, reason: '[callers] the files that call replaceServices');
  });
}

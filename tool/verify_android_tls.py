#!/usr/bin/env python3
"""Refuse an Android APK or AAB whose Flutter engine trusts the eMudhra CAs.

    python3 -I tool/verify_android_tls.py <app.apk | app.aab>
    python3 -I tool/verify_android_tls.py --self-test
    python3 -I tool/verify_android_tls.py --write-fixture {fixed,vulnerable} PATH

Advisory GHSA-frr6-h895-5pxp (2026-10-23): eight eMudhra intermediate CAs have
derivable private keys. On Android, `dart:io` verifies TLS with the BoringSSL
compiled into `libflutter.so`, not with Android's own verifier, so every API
call the app makes (tokens, sign-in codes, KYC uploads) trusts a forged
certificate until the app is rebuilt with Flutter >= 3.47.8 (Dart >= 3.13.7).

This reads the shipped bytes rather than the configuration that should have
produced them (docs/design/android-tls-artifact-gate.md). Every
`libflutter.so` in the archive must carry:

  * the Dart VM version string `X.Y.Z (stable) (...) on "android_<arch>"`
    with X.Y.Z >= MIN_DART, and
  * all eight SPKI hashes of BoringSSL's `kBlockList`, i.e. the fix itself.

Measured 2026-11-11 on the engines Gradle resolves: Flutter 3.44.9's
libflutter.so reads 3.12.2 with 0/8 hashes, 3.47.9's reads 3.13.7 with 8/8.

Fails closed: anything it cannot read is a refusal (exit 1).

If a future SDK legitimately restructures or drops the static blocklist, the
hash rule will refuse a good engine. Re-read the advisory, then change the
rule. Do not lower it to make a build pass.

`--write-fixture` writes a small synthetic AAB. It is test support for
mobile/test/infra/release_build_test.dart, whose stub `flutter` needs an AAB
this script will judge.
"""

import os
import re
import sys
import tempfile
import zipfile

# The first Dart release with the blocklist (Flutter 3.47.8 bundles it).
# Guarded: backend/test/infra/android_tls_gate_test.dart refuses a lower value.
MIN_DART = (3, 13, 7)

# BoringSSL `crypto/x509/x509_vfy.cc`, `kBlockList`, at c7eb007fd106 (the roll
# in Dart 3.13.7, commit ecb2c83516). SHA-256 of each blocked certificate's
# SubjectPublicKeyInfo. Public data, copied verbatim.
BLOCKLIST = (
    'e0254c7fcdc265e2f0f8a428dabb75ab4ae039b4872d62f5ee57f0877d5a8a41',
    '43bffa19d6ef651451f6841e019931e96f6f2eaeff28ab4b6f1ce4576de2717b',
    'ebed6475c2c2d80fcb199f3fe8dd6e6b3ce60b77eb15d4e42c3dec0c6f5b5105',
    '5c0660a2b164910d8ff589c18e14552e9e0ec237dcefe2cb736d41a4811f81a0',
    '63ecefee431d49523bc1136c4e72d0206a477086caf606cd5cf025686c109cf8',
    '49dd353dc2b919a3770645117d0e60c16115e7d1bc259eefe734b00ea434fe5f',
    'ec4ffa1ad0ac88081314b7aaffef6a91f97cd57291bb5ba686c5415f5eb4f6b6',
    '92c063d67e8f14db71d288e11266ffdaf69cbf115f7bab14f3bc2f68d25e0e30',
)

# `lib/<abi>/libflutter.so` in an APK, `base/lib/<abi>/libflutter.so` in an AAB.
_LIBRARY = re.compile(r'^(?:base/)?lib/([^/]+)/libflutter\.so$')

# Dart's VM version string, as `Dart::VersionString()` embeds it.
_VERSION = re.compile(
    rb'(\d+)\.(\d+)\.(\d+)(-[0-9A-Za-z.]+)? \((stable|beta|dev|main)\) '
    rb'\([^)\n]{1,80}\) on "android_[a-z0-9_]+"'
)


class Refused(Exception):
    """The archive must not ship."""


def _fmt(version):
    return '.'.join(str(p) for p in version)


def check_library(name, data):
    """Return a one-line verdict for one libflutter.so, or raise Refused."""
    found = {}
    for m in _VERSION.finditer(data):
        version = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
        found[(version, m.group(4), m.group(5))] = m.group(0).decode('ascii')
    if not found:
        raise Refused(f'{name}: no Dart VM version string found')
    if len(found) > 1:
        raise Refused(
            f'{name}: {len(found)} different Dart versions: '
            + '; '.join(sorted(found.values()))
        )
    (version, suffix, channel), text = next(iter(found.items()))
    if channel != b'stable' or suffix:
        raise Refused(f'{name}: not a stable Dart release ({text})')
    if version < MIN_DART:
        raise Refused(
            f'{name}: Dart {_fmt(version)} < {_fmt(MIN_DART)}: this engine '
            'trusts the compromised eMudhra CAs (GHSA-frr6-h895-5pxp). '
            'Build with Flutter >= 3.47.8.'
        )
    missing = [h for h in BLOCKLIST if bytes.fromhex(h) not in data]
    if missing:
        raise Refused(
            f'{name}: Dart {_fmt(version)} but {len(BLOCKLIST) - len(missing)}'
            f'/{len(BLOCKLIST)} blocklist hashes present (missing '
            + ', '.join(h[:12] for h in missing)
            + '). If a newer SDK restructured BoringSSL\'s blocklist, re-read '
            'the advisory before changing this rule.'
        )
    return f'{name}: Dart {_fmt(version)} (stable), blocklist 8/8'


def verify(path):
    """Return the verdict lines for an APK or AAB, or raise Refused."""
    if not os.path.isfile(path):
        raise Refused(f'{path}: no such file')
    try:
        archive = zipfile.ZipFile(path)
    except (zipfile.BadZipFile, OSError) as e:
        raise Refused(f'{path}: not a readable APK/AAB ({e})')
    with archive:
        names = [n for n in archive.namelist() if _LIBRARY.match(n)]
        if not names:
            raise Refused(
                f'{path}: no lib/<abi>/libflutter.so: not a Flutter Android '
                'build, or not the archive that was built'
            )
        lines = []
        for name in sorted(names):
            try:
                data = archive.read(name)
            except Exception as e:  # a truncated or corrupt member
                raise Refused(f'{name}: unreadable ({e})')
            lines.append(check_library(name, data))
        return lines


# --- fixtures and self-test --------------------------------------------------

_ABIS = {'arm64-v8a': 'arm64', 'armeabi-v7a': 'arm', 'x86_64': 'x64'}


def _library(arch, version='3.13.7 (stable)', hashes=BLOCKLIST):
    body = (
        b'\x7fELF padding '
        + f'{version} (Thu Oct 22 14:28:57 2026 -0700) on "android_{arch}"'
        .encode('ascii')
        + b' padding '
    )
    return body + b''.join(bytes.fromhex(h) for h in hashes) + b' end'


def _write_zip(path, members):
    with zipfile.ZipFile(path, 'w') as z:
        for name, data in members.items():
            z.writestr(name, data)


def write_fixture(kind, path):
    """A synthetic AAB, three ABIs, from a fixed or a vulnerable engine."""
    if kind == 'fixed':
        lib = {abi: _library(arch) for abi, arch in _ABIS.items()}
    elif kind == 'vulnerable':
        lib = {abi: _library(arch, '3.12.2 (stable)', ()) for abi, arch in
               _ABIS.items()}
    else:
        raise SystemExit(f'unknown fixture {kind!r}')
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    members = {'base/manifest/AndroidManifest.xml': b'<manifest/>'}
    members.update({f'base/lib/{abi}/libflutter.so': data
                    for abi, data in lib.items()})
    _write_zip(path, members)


def self_test():
    """Every verdict this script can give, on archives built here."""
    ok = _library('arm64')
    cases = [
        # (label, members or raw bytes, should pass)
        ('APK, fixed engine', {'lib/arm64-v8a/libflutter.so': ok}, True),
        ('AAB, three ABIs, fixed', 'fixture:fixed', True),
        ('a later patch, 3.13.10 (numbers, not strings)',
         {'lib/arm64-v8a/libflutter.so': _library('arm64', '3.13.10 (stable)')},
         True),
        ('a later minor, 3.14.1',
         {'lib/arm64-v8a/libflutter.so': _library('arm64', '3.14.1 (stable)')},
         True),
        ('AAB, three ABIs, vulnerable (3.12.2, 0/8)', 'fixture:vulnerable',
         False),
        ('3.13.6, the release before the fix',
         {'lib/arm64-v8a/libflutter.so': _library('arm64', '3.13.6 (stable)')},
         False),
        ('3.13.7 with one hash missing',
         {'lib/arm64-v8a/libflutter.so': _library('arm64',
                                                  hashes=BLOCKLIST[1:])},
         False),
        ('no version string',
         {'lib/arm64-v8a/libflutter.so': b'\x7fELF'
          + b''.join(bytes.fromhex(h) for h in BLOCKLIST)},
         False),
        ('two different versions in one library',
         {'lib/arm64-v8a/libflutter.so': ok + _library('arm64',
                                                       '3.12.2 (stable)')},
         False),
        ('a beta engine',
         {'lib/arm64-v8a/libflutter.so':
          _library('arm64', '3.14.0-315.3.beta (beta)')},
         False),
        ('one ABI fixed, one vulnerable',
         {'lib/arm64-v8a/libflutter.so': ok,
          'lib/armeabi-v7a/libflutter.so': _library('arm', '3.12.2 (stable)',
                                                    ())},
         False),
        ('no libflutter.so at all', {'classes.dex': b'dex'}, False),
        ('not a zip', b'this is not an archive', False),
        ('no such file', None, False),
    ]
    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        for i, (label, content, should_pass) in enumerate(cases):
            path = os.path.join(tmp, f'case{i}.zip')
            if isinstance(content, str):
                write_fixture(content.split(':', 1)[1], path)
            elif isinstance(content, dict):
                _write_zip(path, content)
            elif isinstance(content, bytes):
                with open(path, 'wb') as f:
                    f.write(content)
            try:
                verify(path)
                passed, why = True, ''
            except Refused as e:
                passed, why = False, str(e)
            good = passed == should_pass
            failures += not good
            mark = 'ok ' if good else 'FAIL'
            verdict = 'accepted' if passed else 'refused'
            print(f'  {mark} {verdict:8} {label}'
                  + (f'  [{why.split(": ", 1)[-1][:70]}]' if why else ''))
    total = len(cases)
    if failures:
        print(f'self-test: {failures} of {total} verdicts WRONG', file=sys.stderr)
        return 1
    print(f'self-test: {total} of {total} verdicts as expected')
    return 0


def main(argv):
    if argv == ['--self-test']:
        return self_test()
    if len(argv) == 3 and argv[0] == '--write-fixture':
        write_fixture(argv[1], argv[2])
        return 0
    if len(argv) != 1 or argv[0].startswith('-'):
        print(__doc__.strip().split('\n\n')[0], file=sys.stderr)
        return 2
    try:
        for line in verify(argv[0]):
            print(f'  ok {line}')
    except Refused as e:
        print(f'::error:: REFUSED {e}', file=sys.stderr)
        return 1
    print(f'Android TLS gate: {argv[0]} carries the eMudhra blocklist.')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

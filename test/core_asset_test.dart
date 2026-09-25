import 'package:flutter_test/flutter_test.dart';
import 'package:nukefy_vpn/core/services/vpn_platform.dart';

/// Asset names copied from a real SagerNet/sing-box release. The important
/// part is that the installers live in the same release as the CLI archives.
const _releaseAssets = <String>[
  'SFA-1.14.2-arm64-v8a.apk',
  'SFA-1.14.2-armeabi-v7a.apk',
  'SFA-1.14.2-legacy-android-5-arm64-v8a.apk',
  'SFA-1.14.2-legacy-android-5-armeabi-v7a.apk',
  'SFA-1.14.2-legacy-android-5-universal.apk',
  'SFA-1.14.2-universal.apk',
  'SFA-1.14.2-x86.apk',
  'SFA-1.14.2-x86_64.apk',
  'SFW-1.14.2-arm64.exe',
  'SFW-1.14.2-x64.exe',
  'SFW-1.14.2-x86.exe',
  'sing-box-1.14.2-android-386.tar.gz',
  'sing-box-1.14.2-android-amd64.tar.gz',
  'sing-box-1.14.2-android-arm.tar.gz',
  'sing-box-1.14.2-android-arm64.tar.gz',
  'sing-box-1.14.2-linux-amd64-glibc.tar.gz',
  'sing-box-1.14.2-linux-amd64-musl.tar.gz',
  'sing-box-1.14.2-linux-amd64.tar.gz',
  'sing-box-1.14.2-windows-386-legacy-windows-7.zip',
  'sing-box-1.14.2-windows-386.zip',
  'sing-box-1.14.2-windows-amd64-legacy-windows-7.zip',
  'sing-box-1.14.2-windows-amd64.zip',
  'sing-box-1.14.2-windows-arm64.zip',
  'sing-box_1.14.2_linux_amd64.deb',
  'sing-box_1.14.2_linux_armv7.apk',
  'sing-box_1.14.2_linux_x86_64.rpm',
];

const _keys = ['android-arm64', 'android-arm', 'windows-amd64', 'linux-amd64'];

void main() {
  test('android arm64 takes the CLI tar.gz, never the SFA apk', () {
    expect(
      VpnPlatform.matchCoreAssetName(_releaseAssets, 'android-arm64'),
      'sing-box-1.14.2-android-arm64.tar.gz',
    );
  });

  test('32-bit android arm takes android-arm, not android-arm64', () {
    expect(
      VpnPlatform.matchCoreAssetName(_releaseAssets, 'android-arm'),
      'sing-box-1.14.2-android-arm.tar.gz',
    );
  });

  test('windows takes the official amd64 zip', () {
    expect(
      VpnPlatform.matchCoreAssetName(_releaseAssets, 'windows-amd64'),
      'sing-box-1.14.2-windows-amd64.zip',
    );
  });

  test('the legacy windows 7 build is skipped', () {
    expect(
      VpnPlatform.matchCoreAssetName(
        const ['sing-box-1.14.2-windows-amd64-legacy-windows-7.zip'],
        'windows-amd64',
      ),
      isNull,
    );
  });

  test('installers and packages never match', () {
    final installers = _releaseAssets
        .where((name) => !name.startsWith('sing-box-'))
        .toList();
    expect(installers, isNotEmpty);
    for (final name in installers) {
      for (final key in _keys) {
        expect(
          VpnPlatform.matchCoreAssetName([name], key),
          isNull,
          reason: '$name / $key',
        );
      }
    }
    for (final name in const [
      'sing-box_1.14.2_linux_amd64.deb',
      'sing-box_1.14.2_linux_x86_64.rpm',
      'sing-box_1.14.2_linux_armv7.apk',
    ]) {
      for (final key in _keys) {
        expect(
          VpnPlatform.matchCoreAssetName([name], key),
          isNull,
          reason: '$name / $key',
        );
      }
    }
  });

  test('an unknown platform key matches nothing', () {
    expect(VpnPlatform.matchCoreAssetName(_releaseAssets, 'macos-arm64'), isNull);
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nukefy_vpn/core/models/app_settings.dart';
import 'package:nukefy_vpn/core/services/game_blocklist_service.dart';
import 'package:nukefy_vpn/core/services/zapret_probe.dart';
import 'package:nukefy_vpn/core/services/zapret_service.dart';

void main() {
  test('game mode migrates legacy settings, targets survive save/load', () {
    final settings = AppSettings.fromJson({'zapretGameFilter': true});
    expect(settings.zapretGameMode, 'all');
    settings.zapretGameMode = 'udp';
    settings.zapretGameUdp = '1024-1934,1936-65535';
    settings.zapretCheckTargets = ['youtube', 'game:EpicGames_Fortnite'];
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.zapretGameMode, 'udp');
    expect(restored.zapretGameUdp, settings.zapretGameUdp);
    expect(restored.zapretCheckTargets, settings.zapretCheckTargets);
  });

  test('game filenames cannot escape the catalog directory', () {
    for (final valid in ['Steam', 'EpicGames_Fortnite', 'game-2']) {
      expect(GameBlocklistService.validId(valid), isTrue);
    }
    for (final invalid in ['../bin/winws', '..', r'C:\Windows', '/tmp/a', 'a/b', 'a%2fb', 'game.txt', 'a\u0000']) {
      expect(GameBlocklistService.validId(invalid), isFalse, reason: invalid);
    }
  });

  test('domain lists reject addresses, executable names and winws switches', () {
    for (final valid in ['api.steampowered.com', 'discord.media', 'xn--e1afmkfd.xn--p1ai']) {
      expect(GameBlocklistService.validDomain(valid), isTrue);
    }
    for (final invalid in ['winws.exe', 'evil.bat', '--hostlist=/tmp/a', '127.0.0.1', '10.0.0.0/8', 'https://example.com', '*.example.com', 'x.local', 'a;calc.com', '-x.com', 'a..com', '${'a' * 64}.com']) {
      expect(GameBlocklistService.validDomain(invalid), isFalse, reason: invalid);
    }
  });

  test('port grammar rejects out-of-range values and command injection', () {
    for (final valid in ['1', '65535', '1024-1934,1936-65535']) {
      expect(ZapretService.validPorts(valid), isTrue);
    }
    for (final invalid in ['', '0', '65536', '2000-1000', '80,', '80;whoami', '080', '80 --new']) {
      expect(ZapretService.validPorts(invalid), isFalse, reason: invalid);
    }
  });

  test('IPSet validation handles both address families and CIDR bounds', () {
    expect(ZapretService.validIpOrCidr('8.8.8.0/24'), isTrue);
    expect(ZapretService.validIpOrCidr('2001:4860::/32'), isTrue);
    for (final invalid in ['8.8.8.8/33', '2001:4860::/129', '999.0.0.1', '--new', 'example.com']) {
      expect(ZapretService.validIpOrCidr(invalid), isFalse);
    }
  });

  test('game probes cannot connect to loopback, LAN, link-local or mapped addresses', () {
    for (final ip in ['127.0.0.1', '10.2.3.4', '172.16.1.2', '192.168.1.1', '169.254.169.254', '100.64.0.1', '::1', '::ffff:127.0.0.1', 'fd00::1', 'fe80::1']) {
      expect(ZapretProbe.publicAddress(InternetAddress(ip)), isFalse, reason: ip);
    }
    expect(ZapretProbe.publicAddress(InternetAddress('1.1.1.1')), isTrue);
    expect(ZapretProbe.publicAddress(InternetAddress('2606:4700:4700::1111')), isTrue);
  });

  test('game hostlists injected per profile even when upstream includes user lists', () {
    final args = ['--filter-tcp=443', '--hostlist=C:/lists/list-general.txt', '--hostlist=C:/lists/list-general-user.txt', '--new', '--filter-udp=443', '--hostlist=C:/lists/list-general.txt', '--new', '--hostlist-domains=discord.media'];
    final result = ZapretService.withHostlists(args, userList: 'C:/lists/list-general-user.txt', gameLists: ['C:/user games/Steam.txt']);
    expect(result.where((a) => a == '--hostlist=C:/user games/Steam.txt'), hasLength(2));
    expect(result.where((a) => a == '--hostlist=C:/lists/list-general-user.txt'), hasLength(2));
    expect(result.last, '--hostlist-domains=discord.media');
    expect(result.where((a) => a == '--new'), hasLength(2));
  });
}

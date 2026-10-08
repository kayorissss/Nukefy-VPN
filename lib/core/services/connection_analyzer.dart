import 'dart:async';
import 'dart:io';

import 'connectivity_probe.dart';

/// Severity of one analyzer line.
enum CheckLevel { ok, warn, error, info }

/// One line of the connection report. Every check carries actionable copy so
/// the user is never left with "не удалось проверить TLS-сертификат" and no
/// idea what to do next.
class AnalyzerCheck {
  AnalyzerCheck({
    required this.id,
    required this.level,
    required this.title,
    required this.detail,
    this.hint,
    this.fixId,
    this.fixLabel,
    this.fixHint,
  });

  final String id;
  final CheckLevel level;
  final String title;
  final String detail;
  final String? hint;

  /// Id of a safe, reversible remedy the UI can offer as a button right on
  /// this row (see DiagnosticsScreen). Null when the finding is informational
  /// or can only be fixed by the user in Windows itself.
  final String? fixId;

  /// Button caption for [fixId].
  final String? fixLabel;

  /// Second line under the button: what the fix will do, exactly.
  final String? fixHint;

  String asText() {
    final mark = switch (level) {
      CheckLevel.ok => '[ OK ]',
      CheckLevel.warn => '[WARN]',
      CheckLevel.error => '[FAIL]',
      CheckLevel.info => '[INFO]',
    };
    final buffer = StringBuffer('$mark $title — $detail');
    if (hint != null) buffer.write('\n       → $hint');
    return buffer.toString();
  }
}

/// Local health checks that explain why a "connected" VPN can still leave the
/// user without internet. Everything here runs on the user's machine, nothing
/// is uploaded anywhere.
class ConnectionAnalyzer {
  ConnectionAnalyzer._();

  static Future<AnalyzerCheck> checkClock() async {
    final local = DateTime.now().toUtc();
    DateTime? remote;
    String? error;
    for (final url in ['https://cloudflare.com/cdn-cgi/trace', 'https://ya.ru/', 'https://www.google.com/generate_204']) {
      final result = await _head(url);
      if (result != null) {
        remote = result;
        break;
      }
      error ??= 'нет ответа';
    }
    if (remote == null) {
      return AnalyzerCheck(
        id: 'clock',
        level: CheckLevel.warn,
        title: 'Часы и время',
        detail: 'Не удалось сверить время с сервером ($error)',
        hint: 'Проверьте интернет. Если он есть, разрешите синхронизацию времени: Параметры → Время и язык.',
      );
    }
    final skew = remote.difference(local).inSeconds.abs();
    if (skew > 300) {
      return AnalyzerCheck(
        id: 'clock',
        fixId: 'clock-open',
        fixLabel: 'Открыть настройки времени',
        fixHint: 'Открывает «Дата и время» Windows — время надо синхронизировать вручную.',
        level: CheckLevel.error,
        title: 'Часы и время',
        detail: 'Время сбито на ${_human(skew)}',
        hint: 'Из-за сбитого времени любой HTTPS падает с ошибкой сертификата. Включите «Установить время автоматически» и синхронизируйте часы.',
      );
    }
    if (skew > 60) {
      return AnalyzerCheck(
        id: 'clock',
        level: CheckLevel.warn,
        title: 'Часы и время',
        detail: 'Небольшое расхождение: ${_human(skew)}',
        hint: 'Часы стоит синхронизировать, иначе часть сайтов будет ругаться на сертификат.',
      );
    }
    return AnalyzerCheck(
      id: 'clock',
      level: CheckLevel.ok,
      title: 'Часы и время',
      detail: 'Точное время (расхождение $skew с)',
    );
  }

  static Future<AnalyzerCheck> checkSystemProxy() async {
    if (!Platform.isWindows) {
      return AnalyzerCheck(id: 'proxy', level: CheckLevel.info, title: 'Системный прокси', detail: 'Проверяется только на Windows');
    }
    final enabled = await _regValue(r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings', 'ProxyEnable');
    final server = await _regValue(r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings', 'ProxyServer');
    if (enabled == '0x1' || enabled == '1') {
      return AnalyzerCheck(
        id: 'proxy',
        fixId: 'proxy-off',
        fixLabel: 'Отключить системный прокси',
        fixHint: 'Снимает прокси в настройках Windows и сбрасывает winhttp. Обратимо.',
        level: CheckLevel.warn,
        title: 'Системный прокси',
        detail: 'Включён${server == null ? '' : ' ($server)'}',
        hint: 'Посторонний HTTPS-прокси перехватывает трафик и ломает сертификаты. Отключите прокси в Параметрах Windows → Сеть → Прокси.',
      );
    }
    return AnalyzerCheck(
      id: 'proxy',
      level: CheckLevel.ok,
      title: 'Системный прокси',
      detail: server == null ? 'Выключен' : 'Выключен (записан $server)',
    );
  }

  /// Antivirus/DPI software that injects its own root certificate re-signs
  /// every HTTPS connection. That is exactly what produces "не удалось
  /// проверить TLS-сертификат" while the connection itself works.
  static Future<AnalyzerCheck> checkCertificateInspectors() async {
    if (!Platform.isWindows) {
      return AnalyzerCheck(id: 'mitm', level: CheckLevel.info, title: 'Проверка сертификатов', detail: 'Проверяется только на Windows');
    }
    const vendors = [
      'kaspersky', 'eset', 'avast', 'avg', 'bitdefender', 'dr.web', 'drweb',
      'adguard', '360', 'yandex', 'comodo', 'fortinet', 'panda', 'mcafee',
      'sophos', 'trend micro', 'fiddler', 'mitmproxy', 'charles',
    ];
    final output = await _powershell(
      r"Get-ChildItem Cert:\LocalMachine\Root | ForEach-Object { $_.Subject }",
    );
    if (output == null) {
      return AnalyzerCheck(id: 'mitm', level: CheckLevel.warn, title: 'Проверка сертификатов', detail: 'Не удалось прочитать хранилище сертификатов');
    }
    final hits = <String>{};
    for (final line in output.split('\n')) {
      final lower = line.toLowerCase();
      for (final vendor in vendors) {
        if (lower.contains(vendor)) hits.add(vendor.toUpperCase());
      }
    }
    if (hits.isNotEmpty) {
      return AnalyzerCheck(
        id: 'mitm',
        level: CheckLevel.warn,
        title: 'Проверка сертификатов',
        detail: 'В системе есть перехватывающие корневые сертификаты: ${hits.join(', ')}',
        hint: 'Антивирус или прокси подменяет сертификаты. Добавьте nukefy_vpn.exe и sing-box.exe в исключения HTTPS-проверки, либо отключите «сканирование HTTPS» в антивирусе.',
      );
    }
    return AnalyzerCheck(id: 'mitm', level: CheckLevel.ok, title: 'Проверка сертификатов', detail: 'Посторонних перехватывающих сертификатов не найдено');
  }

  /// Other VPN clients (Cloudflare WARP, WireGuard, OpenVPN, TAP adapters)
  /// fight with sing-box for the TUN device and the routing table.
  static Future<AnalyzerCheck> checkVpnConflicts() async {
    if (!Platform.isWindows) {
      return AnalyzerCheck(id: 'vpn', level: CheckLevel.info, title: 'Конфликты VPN', detail: 'Проверяется только на Windows');
    }
    final services = await _powershell(
      r"Get-Service | Where-Object { $_.Status -eq 'Running' -and ($_.Name -like '*WARP*' -or $_.Name -like '*WireGuard*' -or $_.Name -like '*OpenVPN*' -or $_.Name -like '*Tap*' -or $_.Name -like '*Nord*' -or $_.Name -like '*Proton*') } | ForEach-Object { $_.Name }",
    );
    final adapters = await _powershell(
      r"Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and ($_.InterfaceDescription -like '*TAP*' -or $_.InterfaceDescription -like '*WireGuard*' -or $_.InterfaceDescription -like '*Wintun*' -or $_.InterfaceDescription -like '*OpenVPN*' -or $_.InterfaceDescription -like '*TUN*') } | ForEach-Object { $_.Name + ' (' + $_.InterfaceDescription + ')' }",
    );
    final running = (services ?? '').split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final up = (adapters ?? '').split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty && !e.toLowerCase().contains('sing-box')).toList();
    if (running.isNotEmpty || up.isNotEmpty) {
      final parts = <String>[
        if (running.isNotEmpty) 'службы: ${running.take(3).join(', ')}',
        if (up.isNotEmpty) 'адаптеры: ${up.take(3).join(', ')}',
      ];
      return AnalyzerCheck(
        id: 'vpn',
        level: CheckLevel.warn,
        title: 'Конфликты VPN',
        detail: 'Работает ещё один VPN — ${parts.join('; ')}',
        hint: 'Два TUN-драйвера делят один маршрут: интернет будет «мигать» или не работать совсем. Отключите второй VPN (WARP можно выключить в Настройки → Инструменты сети).',
      );
    }
    return AnalyzerCheck(id: 'vpn', level: CheckLevel.ok, title: 'Конфликты VPN', detail: 'Посторонних VPN-служб и адаптеров не найдено');
  }

  static Future<AnalyzerCheck> checkZapretStack() async {
    if (!Platform.isWindows) {
      return AnalyzerCheck(id: 'zapret', level: CheckLevel.info, title: 'Zapret (winws)', detail: 'Проверяется только на Windows');
    }
    final running = await _powershell(
      r"Get-Process -Name winws -ErrorAction SilentlyContinue | ForEach-Object { $_.Id }",
    );
    final service = await _powershell(
      r"Get-Service -Name zapret -ErrorAction SilentlyContinue | ForEach-Object { $_.Status }",
    );
    final winws = (running ?? '').trim();
    final serviceState = (service ?? '').trim();
    if (winws.isNotEmpty) {
      return AnalyzerCheck(
        id: 'zapret',
        fixId: 'zapret-stop',
        fixLabel: 'Остановить наш Zapret',
        fixHint: 'Останавливает только нашу службу nukefy-zapret. Чужие winws не трогает.',
        level: CheckLevel.warn,
        title: 'Zapret (winws)',
        detail: 'winws работает${serviceState.isEmpty ? '' : ' (служба: $serviceState)'}',
        hint: 'WinDivert перехватывает трафик на уровне драйвера и мешает sing-box. Для VPN остановите zapret на его странице.',
      );
    }
    return AnalyzerCheck(id: 'zapret', level: CheckLevel.ok, title: 'Zapret (winws)', detail: serviceState.isEmpty ? 'Не запущен, служба не установлена' : 'Не запущен (служба: $serviceState)');
  }

  static Future<AnalyzerCheck> checkDns() async {
    const hosts = ['www.youtube.com', 'discord.com', 'api.github.com', 'core.telegram.org'];
    final failed = <String>[];
    for (final host in hosts) {
      try {
        final result = await InternetAddress.lookup(host).timeout(const Duration(seconds: 4));
        if (result.isEmpty) failed.add(host);
      } catch (_) {
        failed.add(host);
      }
    }
    if (failed.length == hosts.length) {
      return AnalyzerCheck(
        id: 'dns',
        fixId: 'dns-apply',
        fixLabel: 'Поставить DNS 1.1.1.1',
        fixHint: 'Прописывает Cloudflare DNS на активный адаптер через netsh. Возврат — «DNS как было» в настройках.',
        level: CheckLevel.error,
        title: 'DNS',
        detail: 'Ни один домен не резолвится (${hosts.length} проверено)',
        hint: 'Провайдер режет DNS. Включите VPN (в режиме TUN домены резолвит туннель) или поставьте DNS из настроек приложения.',
      );
    }
    if (failed.isNotEmpty) {
      return AnalyzerCheck(
        id: 'dns',
        level: CheckLevel.warn,
        title: 'DNS',
        detail: 'Не резолвятся: ${failed.join(', ')}',
        hint: 'Обычно это блокировка на уровне DNS. Эти сайты поедут через VPN, если туннель поднят — проверьте их ниже.',
      );
    }
    return AnalyzerCheck(id: 'dns', level: CheckLevel.ok, title: 'DNS', detail: 'Все ${hosts.length} проверенных домена резолвятся');
  }

  /// Direct (no VPN) public IP plus a reachability verdict for the internet
  /// as a whole.
  static Future<(AnalyzerCheck, String?)> checkDirectInternet() async {
    final ip = await ConnectivityProbe.text('https://cloudflare.com/cdn-cgi/trace');
    final direct = ip.body?.split('\n').firstWhere((line) => line.startsWith('ip='), orElse: () => '').replaceFirst('ip=', '');
    if (ip.body == null) {
      return (
        AnalyzerCheck(
          id: 'direct',
          level: CheckLevel.error,
          title: 'Интернет без VPN',
          detail: 'Прямое подключение тоже не работает (${ip.error ?? 'нет ответа'})',
          hint: 'Сначала почините обычный интернет: без него не скачается ни подписка, ни ядро. Проверьте кабель/Wi-Fi и системный прокси.',
        ),
        null,
      );
    }
    return (
      AnalyzerCheck(
        id: 'direct',
        level: CheckLevel.ok,
        title: 'Интернет без VPN',
        detail: direct == null || direct.isEmpty ? 'Соединение есть' : 'Соединение есть, ваш IP $direct',
      ),
      (direct == null || direct.isEmpty) ? null : direct,
    );
  }

  /// Verifies that traffic really leaves through the tunnel: fetches the exit
  /// IP through the local inbound and compares it with the direct one.
  static Future<AnalyzerCheck> checkTunnelExit({required int httpProxyPort, String? directIp}) async {
    final probe = await ConnectivityProbe.text('https://cloudflare.com/cdn-cgi/trace', httpProxyPort: httpProxyPort);
    if (probe.body == null) {
      return AnalyzerCheck(
        id: 'tunnel',
        level: CheckLevel.error,
        title: 'Трафик через VPN',
        detail: 'Через туннель ничего не проходит (${probe.error ?? 'нет ответа'})',
        hint: 'Сервер принял подключение, но данные не идут. Смените сервер или транспорт, включите/выключите TUN и повторите проверку.',
      );
    }
    final exit = probe.body!.split('\n').firstWhere((line) => line.startsWith('ip='), orElse: () => '').replaceFirst('ip=', '');
    if (directIp != null && exit.isNotEmpty && exit == directIp) {
      return AnalyzerCheck(
        id: 'tunnel',
        level: CheckLevel.error,
        title: 'Трафик через VPN',
        detail: 'IP не изменился ($exit) — трафик идёт мимо туннеля',
        hint: 'Приложение подключено, но система не направляет трафик в туннель: включите режим TUN в настройках VPN (нужны права администратора) или проверьте порты локального прокси.',
      );
    }
    return AnalyzerCheck(
      id: 'tunnel',
      level: CheckLevel.ok,
      title: 'Трафик через VPN',
      detail: exit.isEmpty ? 'Туннель пропускает данные' : 'Выход через $exit${directIp == null ? '' : ' (напрямую был $directIp)'}',
    );
  }

  /// The list people actually care about: do YouTube, Discord and Telegram
  /// load through the current path?
  static Future<(List<AnalyzerCheck>, Map<String, bool>)> checkTargets({int? httpProxyPort}) async {
    final checks = <AnalyzerCheck>[];
    final results = <String, bool>{};
    for (final target in ConnectivityProbe.defaultTargets) {
      final probe = await ConnectivityProbe.http(target.url, httpProxyPort: httpProxyPort);
      results[target.id] = probe.ok;
      checks.add(
        AnalyzerCheck(
          id: 'target-${target.id}',
          level: probe.ok ? CheckLevel.ok : CheckLevel.error,
          title: target.label,
          detail: probe.ok ? 'Открывается (${probe.ms} мс)' : 'Не открывается (${probe.error ?? 'HTTP ${probe.status}'})',
          hint: probe.ok ? null : 'Если в режиме TUN тоже не открывается — сервер не обходит блокировку. Возьмите другой сервер: вкладка «Сервера» → Проверить серверы.',
        ),
      );
    }
    return (checks, results);
  }

  /// Human-readable, copyable dump of every line, as the user demanded for
  /// every error in the app.
  static String report(List<AnalyzerCheck> checks) {
    final buffer = StringBuffer()
      ..writeln('Nukefy Client — отчёт о соединении')
      ..writeln('Время: ${DateTime.now()}')
      ..writeln('Машина: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
      ..writeln('');
    for (final check in checks) {
      buffer.writeln(check.asText());
    }
    return buffer.toString();
  }

  static String _human(int seconds) {
    if (seconds < 90) return '$seconds с';
    if (seconds < 5400) return '${seconds ~/ 60} мин';
    return '${seconds ~/ 3600} ч';
  }

  static Future<DateTime?> _head(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final request = await client.headUrl(Uri.parse(url)).timeout(const Duration(seconds: 8));
      final response = await request.close().timeout(const Duration(seconds: 8));
      await response.drain<void>().timeout(const Duration(seconds: 5));
      final raw = response.headers.value(HttpHeaders.dateHeader);
      if (raw == null) return null;
      return HttpDate.parse(raw).toUtc();
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<String?> _regValue(String key, String name) async {
    try {
      final result = await Process.run('reg', ['query', key, '/v', name]).timeout(const Duration(seconds: 6));
      if (result.exitCode != 0) return null;
      final line = '${result.stdout}'.split('\n').firstWhere((l) => l.contains(name), orElse: () => '');
      final parts = line.split(RegExp(r'\s{2,}')).where((e) => e.trim().isNotEmpty).toList();
      return parts.isEmpty ? null : parts.last.trim();
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _powershell(String script) async {
    try {
      final result = await Process.run('powershell.exe', ['-NoProfile', '-Command', script]).timeout(const Duration(seconds: 12));
      if (result.exitCode != 0) return null;
      return '${result.stdout}'.replaceAll('\r', '');
    } catch (_) {
      return null;
    }
  }
}

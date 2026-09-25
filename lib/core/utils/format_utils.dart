class FormatUtils {
  static String bytes(int value) {
    if (value < 0) value = 0;
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = value.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    if (unit == 0) return '${size.toStringAsFixed(0)} ${units[unit]}';
    return '${size.toStringAsFixed(size >= 100 ? 0 : 1)} ${units[unit]}';
  }

  static String speed(int bytesPerSecond) {
    return '${bytes(bytesPerSecond)}/s';
  }

  static String duration(Duration value) {
    final total = value.inSeconds < 0 ? 0 : value.inSeconds;
    final h = (total ~/ 3600).toString().padLeft(2, '0');
    final m = ((total % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  static String eta(Duration value) {
    if (value.inSeconds < 0) return '—';
    if (value.inHours >= 1) {
      return '${value.inHours}ч ${value.inMinutes.remainder(60)}м';
    }
    if (value.inMinutes >= 1) {
      return '${value.inMinutes}м ${value.inSeconds.remainder(60)}с';
    }
    return '${value.inSeconds}с';
  }

  static String timeAgo(DateTime time, {required bool ru}) {
    final diff = DateTime.now().difference(time);
    if (diff.isNegative || diff.inSeconds < 45) {
      return ru ? 'только что' : 'just now';
    }
    if (diff.inMinutes < 60) {
      final n = diff.inMinutes;
      return ru ? '$n мин назад' : '${n}m ago';
    }
    if (diff.inHours < 24) {
      final n = diff.inHours;
      return ru ? '$n ч назад' : '${n}h ago';
    }
    if (diff.inDays == 1) return ru ? 'вчера' : 'yesterday';
    if (diff.inDays < 14) {
      return ru ? '${diff.inDays} дн назад' : '${diff.inDays}d ago';
    }
    final d = time.toLocal();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  static String clock(DateTime time) {
    final d = time.toLocal();
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    final ss = d.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  static String protocolLabel(String protocol) {
    switch (protocol) {
      case 'vless':
        return 'VLESS';
      case 'vmess':
        return 'VMess';
      case 'trojan':
        return 'Trojan';
      case 'shadowsocks':
        return 'SS';
      case 'hysteria2':
        return 'Hysteria2';
      case 'tuic':
        return 'TUIC';
      case 'wireguard':
        return 'WireGuard';
      case 'amneziawg':
        return 'AmneziaWG';
      default:
        return protocol;
    }
  }
}

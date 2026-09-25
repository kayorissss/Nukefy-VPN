class VersionUtils {
  static int compare(String a, String b) {
    final pa = _parse(a);
    final pb = _parse(b);
    final len = pa.numbers.length > pb.numbers.length
        ? pa.numbers.length
        : pb.numbers.length;
    for (var i = 0; i < len; i++) {
      final av = i < pa.numbers.length ? pa.numbers[i] : 0;
      final bv = i < pb.numbers.length ? pb.numbers[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    if (pa.pre == null && pb.pre != null) return 1;
    if (pa.pre != null && pb.pre == null) return -1;
    if (pa.pre != null && pb.pre != null) return pa.pre!.compareTo(pb.pre!);
    return 0;
  }

  static bool isNewer(String remote, String local) => compare(remote, local) > 0;

  static _Parsed _parse(String raw) {
    var value = raw.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    final plus = value.indexOf('+');
    if (plus >= 0) value = value.substring(0, plus);
    String? pre;
    final dash = value.indexOf('-');
    if (dash >= 0) {
      pre = value.substring(dash + 1);
      value = value.substring(0, dash);
    }
    final numbers = value
        .split('.')
        .map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    if (numbers.isEmpty) numbers.add(0);
    return _Parsed(numbers, pre);
  }
}

class _Parsed {
  _Parsed(this.numbers, this.pre);
  final List<int> numbers;
  final String? pre;
}

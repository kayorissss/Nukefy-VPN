/// Mirror catalog for the whitelist-bypass subscription (zieng2/wl).
///
/// The subscription lives on several hosts because mobile operators block
/// individual mirrors during communication restrictions. The app keeps the
/// ordered list here so a refresh can silently fall back to another mirror
/// instead of forcing the user to delete and re-add the subscription.
class WhitelistMirror {
  const WhitelistMirror({
    required this.id,
    required this.label,
    required this.url,
    this.experimental = false,
  });

  final String id;
  final String label;
  final String url;

  /// Experimental mirrors survive communication restrictions but are not
  /// guaranteed to be up to date.
  final bool experimental;
}

class WhitelistCatalog {
  WhitelistCatalog._();

  static const String repo = 'zieng2/wl';

  /// Order matters: stable hosts first, restriction-proof mirrors after.
  static const List<WhitelistMirror> mirrors = [
    WhitelistMirror(
      id: 'github',
      label: 'GitHub',
      url: 'https://raw.githubusercontent.com/zieng2/wl/main/vless_universal.txt',
    ),
    WhitelistMirror(
      id: 'codeberg',
      label: 'Codeberg',
      url: 'https://codeberg.org/zieng2/wl/raw/branch/main/vless_universal.txt',
    ),
    WhitelistMirror(
      id: 'gitlab',
      label: 'GitLab',
      url: 'https://gitlab.com/zieng2/wl/raw/main/vless_universal.txt',
    ),
    WhitelistMirror(
      id: 'mos',
      label: 'Mos.Hub',
      url: 'https://hub.mos.ru/zieng2/wl/raw/main/list_universal.txt',
      experimental: true,
    ),
    WhitelistMirror(
      id: 'gitverse',
      label: 'GitVerse',
      url: 'https://gitverse.ru/api/repos/zieng2/wl/raw/branch/master/list_universal.txt',
      experimental: true,
    ),
  ];

  static const String defaultName = 'zieng2 · обход белых списков';

  /// Extracts `owner/repo` from any of the supported mirror URL shapes.
  static String? repoOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 2) return null;
    final host = uri.host.toLowerCase();
    if (host == 'raw.githubusercontent.com' || host == 'github.com') {
      return '${segments[0]}/${segments[1]}';
    }
    if (host == 'codeberg.org') {
      return '${segments[0]}/${segments[1]}';
    }
    if (host == 'gitlab.com') {
      return '${segments[0]}/${segments[1]}';
    }
    if (host == 'hub.mos.ru') {
      return '${segments[0]}/${segments[1]}';
    }
    if (host == 'gitverse.ru') {
      // /api/repos/<owner>/<repo>/raw/branch/<branch>/<file>
      final index = segments.indexOf('repos');
      if (index >= 0 && segments.length > index + 2) {
        return '${segments[index + 1]}/${segments[index + 2]}';
      }
    }
    return null;
  }

  static bool isWhitelistUrl(String url) => repoOf(url) == repo;

  /// Every mirror of the same repository except [url], stable first.
  static List<String> fallbacksFor(String url) {
    if (!isWhitelistUrl(url)) return const [];
    final normalized = url.trim();
    return [
      for (final mirror in mirrors)
        if (mirror.url != normalized) mirror.url,
    ];
  }
}

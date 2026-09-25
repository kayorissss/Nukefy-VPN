class AppConstants {
  static const String appName = 'Nukefy VPN';
  static const String version = '1.0.1';
  static const int buildNumber = 2;
  static const String packageName = 'com.nukefy.vpn';

  static const String author = '@kayorisan';
  static const String authorUrl = 'https://t.me/kayorisan';
  static const String githubRepo = 'kayorissss/Nukefy-VPN';
  static const String githubUrl = 'https://github.com/kayorissss/Nukefy-VPN';
  static const String releasesApi =
      'https://api.github.com/repos/kayorissss/Nukefy-VPN/releases/latest';
  static const String releasesPage =
      'https://github.com/kayorissss/Nukefy-VPN/releases';

  static const String singboxRepo = 'SagerNet/sing-box';
  static const String singboxReleasesApi =
      'https://api.github.com/repos/SagerNet/sing-box/releases/latest';

  /// Only official CLI archives are unpackable. The same release also ships
  /// GUI apps (SFA-*.apk, SFW-*.exe) and Linux packages — none of them are
  /// archives with a sing-box binary inside, so they must never be picked.
  static const List<String> coreBlockedSuffixes = [
    '.apk',
    '.exe',
    '.deb',
    '.rpm',
    '.msi',
    '.dmg',
    '.pkg',
    '.zst',
  ];

  /// Port used by the "jammers" probe: plain TCP connect, no payload.
  static const int jammerProbePort = 443;

  /// Sites that stay reachable behind Russian whitelists.
  static const List<String> jammerTargetsRu = [
    'yandex.ru',
    'vk.com',
    'www.gosuslugi.ru',
    'mail.ru',
  ];

  /// Sites that a whitelist-based jammer blocks first.
  static const List<String> jammerTargetsOther = [
    'google.com',
    'www.gstatic.com',
    'update.miui.com',
    'cloudflare.com',
    'github.com',
  ];

  /// Hardcoded MTProto proxy. Opens Telegram, which offers to enable it.
  static const String telegramProxyUrl =
      'https://t.me/proxy?server=data.npven.me&port=443&secret=ee27aae470e38f627657de7562ac358e657777772e6f7a6f6e2e7275';

  static const int defaultSocksPort = 10808;
  static const int defaultHttpPort = 10809;
  static const int clashApiPort = 19090;
  static const int defaultMtu = 9000;
  static const String tunInterface = 'nkfy';
  static const String tunAddress = '172.19.0.1/30';

  static const String ruleSetGeositeRu =
      'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ru.srs';
  static const String ruleSetGeoipRu =
      'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-ru.srs';
  static const String ruleSetAds =
      'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs';
  static const String ruleSetPrivate =
      'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-private.srs';

  static const String speedTestUrl =
      'https://speed.cloudflare.com/__down?bytes=8000000';
  static const String speedTestUploadUrl = 'https://speed.cloudflare.com/__up';

  static const String defaultProxyDns = 'https://1.1.1.1/dns-query';
  static const String defaultDirectDns = '77.88.8.8';
  static const String userAgent = 'NukefyVPN/1.0.1';

  static const List<String> shareSchemes = [
    'vless',
    'vmess',
    'trojan',
    'ss',
    'shadowsocks',
    'hysteria',
    'hysteria2',
    'hy2',
    'tuic',
    'wg',
    'wireguard',
    'awg',
    'amneziawg',
  ];

  /// Domains commonly unreachable on restrictive networks. Used by the
  /// "only blocked sites" routing mode so it works without a remote list.
  static const List<String> blockedDomainSuffixes = [
    'youtube.com',
    'youtu.be',
    'ytimg.com',
    'googlevideo.com',
    'youtubei.googleapis.com',
    'instagram.com',
    'cdninstagram.com',
    'facebook.com',
    'fbcdn.net',
    'fb.com',
    'twitter.com',
    'x.com',
    't.co',
    'twimg.com',
    'discord.com',
    'discord.gg',
    'discordapp.com',
    'discordapp.net',
    'tiktok.com',
    'tiktokv.com',
    'musical.ly',
    'reddit.com',
    'redd.it',
    'medium.com',
    'openai.com',
    'chatgpt.com',
    'oaistatic.com',
    'claude.ai',
    'anthropic.com',
    'linkedin.com',
    'twitch.tv',
    'ttvnw.net',
    'spotify.com',
    'scdn.co',
    'netflix.com',
    'nflxvideo.net',
    'patreon.com',
    'notion.so',
    'notion.site',
    'quora.com',
    'proton.me',
    'protonmail.com',
    'signal.org',
    'wikipedia.org',
    'wikimedia.org',
    'vimeo.com',
    'soundcloud.com',
    'pinterest.com',
    'tumblr.com',
    'archive.org',
    'bbc.com',
    'bbc.co.uk',
    'theguardian.com',
    'nytimes.com',
    'dw.com',
    'rferl.org',
    'meduza.io',
  ];
}

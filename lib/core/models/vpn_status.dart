enum VpnStatus { disconnected, connecting, connected, error }

enum RoutingMode { global, blockedOnly, bypassRu, custom }

enum ThemePreference { dark, light, system }

enum LanguagePreference { ru, en, system }

enum PerAppMode { off, include, exclude }

enum UpdateInterval {
  manual(0),
  min30(30),
  hour1(60),
  hour6(360),
  hour12(720);

  const UpdateInterval(this.minutes);
  final int minutes;

  static UpdateInterval fromMinutes(int minutes) {
    return UpdateInterval.values.firstWhere(
      (v) => v.minutes == minutes,
      orElse: () => UpdateInterval.manual,
    );
  }
}

enum CoreMode { missing, proxy, tun }

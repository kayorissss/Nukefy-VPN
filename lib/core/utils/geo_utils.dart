class GeoUtils {
  static String flagEmoji(String? code) {
    if (code == null || code.length != 2) return '🌐';
    final upper = code.toUpperCase();
    final a = upper.codeUnitAt(0);
    final b = upper.codeUnitAt(1);
    if (a < 65 || a > 90 || b < 65 || b > 90) return '🌐';
    return String.fromCharCodes([
      0x1F1E6 + (a - 65),
      0x1F1E6 + (b - 65),
    ]);
  }

  static String countryName(String? code, {required bool ru}) {
    if (code == null) return ru ? 'Неизвестно' : 'Unknown';
    final names = ru ? _namesRu : _namesEn;
    return names[code.toUpperCase()] ?? code.toUpperCase();
  }

  static ({String? code, List<String> tags}) detect(String name) {
    final tags = <String>[];
    final lower = name.toLowerCase();
    if (RegExp(r'антиглуш|antiblock|anti[-_ ]?block|whitelist|бел(ый|ых) спис')
        .hasMatch(lower)) {
      tags.add('antiblock');
    }
    if (RegExp(r'\bbridge\b|мост|ru[-_ ]?bridge|relay').hasMatch(lower)) {
      tags.add('bridge');
    }
    if (tags.contains('antiblock') && !tags.contains('bridge')) {
      // Bridges are the practical antiblock path; keep the explicit tag only.
    }

    final emoji = _flagFromEmoji(name);
    if (emoji != null) return (code: emoji, tags: tags);

    final token = _flagFromToken(name);
    if (token != null) return (code: token, tags: tags);

    final named = _flagFromName(lower);
    if (named != null) return (code: named, tags: tags);

    return (code: null, tags: tags);
  }

  static String? _flagFromEmoji(String name) {
    final runes = name.runes.toList();
    for (var i = 0; i < runes.length - 1; i++) {
      final a = runes[i];
      final b = runes[i + 1];
      if (a >= 0x1F1E6 && a <= 0x1F1FF && b >= 0x1F1E6 && b <= 0x1F1FF) {
        final code = String.fromCharCodes([
          65 + (a - 0x1F1E6),
          65 + (b - 0x1F1E6),
        ]);
        if (_namesEn.containsKey(code)) return code;
      }
    }
    return null;
  }

  static String? _flagFromToken(String name) {
    final upper = name.toUpperCase();
    final matches = RegExp(r'(^|[^A-Z])([A-Z]{2})(?=$|[^A-Z])').allMatches(upper);
    for (final match in matches) {
      final code = match.group(2)!;
      if (code == 'SS' ||
          code == 'IP' ||
          code == 'OK' ||
          code == 'TV' ||
          code == 'PC' ||
          code == 'QR' ||
          code == 'VM' ||
          code == 'WG' ||
          code == 'HY') {
        continue;
      }
      final normalized = code == 'UK' ? 'GB' : code;
      if (_namesEn.containsKey(normalized)) return normalized;
    }
    return null;
  }

  static String? _flagFromName(String lower) {
    for (final entry in _aliases.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return null;
  }

  static const Map<String, String> _namesEn = {
    'NL': 'Netherlands',
    'DE': 'Germany',
    'FI': 'Finland',
    'SE': 'Sweden',
    'US': 'United States',
    'GB': 'United Kingdom',
    'FR': 'France',
    'PL': 'Poland',
    'CZ': 'Czechia',
    'AT': 'Austria',
    'CH': 'Switzerland',
    'ES': 'Spain',
    'IT': 'Italy',
    'JP': 'Japan',
    'SG': 'Singapore',
    'HK': 'Hong Kong',
    'KR': 'South Korea',
    'AU': 'Australia',
    'CA': 'Canada',
    'TR': 'Turkey',
    'RU': 'Russia',
    'KZ': 'Kazakhstan',
    'GE': 'Georgia',
    'AM': 'Armenia',
    'EE': 'Estonia',
    'LV': 'Latvia',
    'LT': 'Lithuania',
    'UA': 'Ukraine',
    'RO': 'Romania',
    'BG': 'Bulgaria',
    'GR': 'Greece',
    'PT': 'Portugal',
    'IE': 'Ireland',
    'BE': 'Belgium',
    'LU': 'Luxembourg',
    'NO': 'Norway',
    'DK': 'Denmark',
    'IS': 'Iceland',
    'AE': 'UAE',
    'IL': 'Israel',
    'IN': 'India',
    'BR': 'Brazil',
    'AR': 'Argentina',
    'CL': 'Chile',
    'ZA': 'South Africa',
    'EG': 'Egypt',
    'TH': 'Thailand',
    'ID': 'Indonesia',
    'PH': 'Philippines',
    'VN': 'Vietnam',
    'TW': 'Taiwan',
    'MY': 'Malaysia',
    'MD': 'Moldova',
    'RS': 'Serbia',
    'HU': 'Hungary',
    'SK': 'Slovakia',
    'HR': 'Croatia',
    'SI': 'Slovenia',
    'MX': 'Mexico',
    'NZ': 'New Zealand',
    'CN': 'China',
  };

  static const Map<String, String> _namesRu = {
    'NL': 'Нидерланды',
    'DE': 'Германия',
    'FI': 'Финляндия',
    'SE': 'Швеция',
    'US': 'США',
    'GB': 'Великобритания',
    'FR': 'Франция',
    'PL': 'Польша',
    'CZ': 'Чехия',
    'AT': 'Австрия',
    'CH': 'Швейцария',
    'ES': 'Испания',
    'IT': 'Италия',
    'JP': 'Япония',
    'SG': 'Сингапур',
    'HK': 'Гонконг',
    'KR': 'Корея',
    'AU': 'Австралия',
    'CA': 'Канада',
    'TR': 'Турция',
    'RU': 'Россия',
    'KZ': 'Казахстан',
    'GE': 'Грузия',
    'AM': 'Армения',
    'EE': 'Эстония',
    'LV': 'Латвия',
    'LT': 'Литва',
    'UA': 'Украина',
    'RO': 'Румыния',
    'BG': 'Болгария',
    'GR': 'Греция',
    'PT': 'Португалия',
    'IE': 'Ирландия',
    'BE': 'Бельгия',
    'LU': 'Люксембург',
    'NO': 'Норвегия',
    'DK': 'Дания',
    'IS': 'Исландия',
    'AE': 'ОАЭ',
    'IL': 'Израиль',
    'IN': 'Индия',
    'BR': 'Бразилия',
    'AR': 'Аргентина',
    'CL': 'Чили',
    'ZA': 'ЮАР',
    'EG': 'Египет',
    'TH': 'Таиланд',
    'ID': 'Индонезия',
    'PH': 'Филиппины',
    'VN': 'Вьетнам',
    'TW': 'Тайвань',
    'MY': 'Малайзия',
    'MD': 'Молдова',
    'RS': 'Сербия',
    'HU': 'Венгрия',
    'SK': 'Словакия',
    'HR': 'Хорватия',
    'SI': 'Словения',
    'MX': 'Мексика',
    'NZ': 'Новая Зеландия',
    'CN': 'Китай',
  };

  static const Map<String, String> _aliases = {
    'amsterdam': 'NL',
    'rotterdam': 'NL',
    'нидерланд': 'NL',
    'голлан': 'NL',
    'frankfurt': 'DE',
    'berlin': 'DE',
    'munich': 'DE',
    'герман': 'DE',
    'helsinki': 'FI',
    'хельсинк': 'FI',
    'финлянд': 'FI',
    'stockholm': 'SE',
    'швеци': 'SE',
    'london': 'GB',
    'лондон': 'GB',
    'paris': 'FR',
    'париж': 'FR',
    'франц': 'FR',
    'warsaw': 'PL',
    'варшав': 'PL',
    'польш': 'PL',
    'prague': 'CZ',
    'праг': 'CZ',
    'vienna': 'AT',
    'вена': 'AT',
    'zurich': 'CH',
    'цюрих': 'CH',
    'madrid': 'ES',
    'испан': 'ES',
    'milan': 'IT',
    'rome': 'IT',
    'итали': 'IT',
    'new york': 'US',
    'newyork': 'US',
    'los angeles': 'US',
    'seattle': 'US',
    'chicago': 'US',
    'dallas': 'US',
    'miami': 'US',
    'ashburn': 'US',
    'сша': 'US',
    'америк': 'US',
    'tokyo': 'JP',
    'osaka': 'JP',
    'япони': 'JP',
    'singapore': 'SG',
    'сингапур': 'SG',
    'hong kong': 'HK',
    'hongkong': 'HK',
    'гонконг': 'HK',
    'seoul': 'KR',
    'sydney': 'AU',
    'toronto': 'CA',
    'montreal': 'CA',
    'istanbul': 'TR',
    'стамбул': 'TR',
    'moscow': 'RU',
    'москв': 'RU',
    'petersburg': 'RU',
    'петербург': 'RU',
    'росси': 'RU',
    'almaty': 'KZ',
    'astana': 'KZ',
    'tbilisi': 'GE',
    'тбилиси': 'GE',
    'yerevan': 'AM',
    'ереван': 'AM',
    'tallinn': 'EE',
    'таллин': 'EE',
    'riga': 'LV',
    'рига': 'LV',
    'vilnius': 'LT',
    'kyiv': 'UA',
    'kiev': 'UA',
    'киев': 'UA',
    'київ': 'UA',
    'bucharest': 'RO',
    'sofia': 'BG',
    'athens': 'GR',
    'lisbon': 'PT',
    'dublin': 'IE',
    'brussels': 'BE',
    'oslo': 'NO',
    'copenhagen': 'DK',
    'dubai': 'AE',
    'tel aviv': 'IL',
    'mumbai': 'IN',
    'bangkok': 'TH',
    'jakarta': 'ID',
    'taipei': 'TW',
    'казах': 'KZ',
    'украин': 'UA',
    'эстон': 'EE',
    'латви': 'LV',
    'литв': 'LT',
    'армен': 'AM',
    'грузи': 'GE',
  };
}

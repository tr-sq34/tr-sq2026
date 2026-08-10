/// Country choices used by the onboarding flow: where a member moved from, and
/// where they live when that is not the United States.
class CountryOption {
  const CountryOption({required this.code, required this.name, required this.flag});

  /// ISO-3166 alpha-2, stored as `origin_country` / `country_code`.
  final String code;

  /// Turkish name, because the whole flow is in Turkish.
  final String name;

  /// Flag emoji — renders everywhere without an image asset.
  final String flag;
}

/// Turkey first: it is the origin of nearly every member. The rest follow the
/// Turkish alphabet.
const List<CountryOption> kCountryOptions = [
  CountryOption(code: 'TR', name: 'Türkiye', flag: '🇹🇷'),
  CountryOption(code: 'DE', name: 'Almanya', flag: '🇩🇪'),
  CountryOption(code: 'US', name: 'Amerika Birleşik Devletleri', flag: '🇺🇸'),
  CountryOption(code: 'AR', name: 'Arjantin', flag: '🇦🇷'),
  CountryOption(code: 'AL', name: 'Arnavutluk', flag: '🇦🇱'),
  CountryOption(code: 'AU', name: 'Avustralya', flag: '🇦🇺'),
  CountryOption(code: 'AT', name: 'Avusturya', flag: '🇦🇹'),
  CountryOption(code: 'AZ', name: 'Azerbaycan', flag: '🇦🇿'),
  CountryOption(code: 'BE', name: 'Belçika', flag: '🇧🇪'),
  CountryOption(code: 'AE', name: 'Birleşik Arap Emirlikleri', flag: '🇦🇪'),
  CountryOption(code: 'BA', name: 'Bosna-Hersek', flag: '🇧🇦'),
  CountryOption(code: 'BR', name: 'Brezilya', flag: '🇧🇷'),
  CountryOption(code: 'BG', name: 'Bulgaristan', flag: '🇧🇬'),
  CountryOption(code: 'DZ', name: 'Cezayir', flag: '🇩🇿'),
  CountryOption(code: 'CN', name: 'Çin', flag: '🇨🇳'),
  CountryOption(code: 'DK', name: 'Danimarka', flag: '🇩🇰'),
  CountryOption(code: 'ID', name: 'Endonezya', flag: '🇮🇩'),
  CountryOption(code: 'AM', name: 'Ermenistan', flag: '🇦🇲'),
  CountryOption(code: 'MA', name: 'Fas', flag: '🇲🇦'),
  CountryOption(code: 'FR', name: 'Fransa', flag: '🇫🇷'),
  CountryOption(code: 'NL', name: 'Hollanda', flag: '🇳🇱'),
  CountryOption(code: 'IN', name: 'Hindistan', flag: '🇮🇳'),
  CountryOption(code: 'GB', name: 'İngiltere', flag: '🇬🇧'),
  CountryOption(code: 'IQ', name: 'Irak', flag: '🇮🇶'),
  CountryOption(code: 'IR', name: 'İran', flag: '🇮🇷'),
  CountryOption(code: 'IE', name: 'İrlanda', flag: '🇮🇪'),
  CountryOption(code: 'ES', name: 'İspanya', flag: '🇪🇸'),
  CountryOption(code: 'IL', name: 'İsrail', flag: '🇮🇱'),
  CountryOption(code: 'SE', name: 'İsveç', flag: '🇸🇪'),
  CountryOption(code: 'CH', name: 'İsviçre', flag: '🇨🇭'),
  CountryOption(code: 'IT', name: 'İtalya', flag: '🇮🇹'),
  CountryOption(code: 'JP', name: 'Japonya', flag: '🇯🇵'),
  CountryOption(code: 'CA', name: 'Kanada', flag: '🇨🇦'),
  CountryOption(code: 'ME', name: 'Karadağ', flag: '🇲🇪'),
  CountryOption(code: 'QA', name: 'Katar', flag: '🇶🇦'),
  CountryOption(code: 'KZ', name: 'Kazakistan', flag: '🇰🇿'),
  CountryOption(code: 'KG', name: 'Kırgızistan', flag: '🇰🇬'),
  CountryOption(code: 'CO', name: 'Kolombiya', flag: '🇨🇴'),
  CountryOption(code: 'XK', name: 'Kosova', flag: '🇽🇰'),
  CountryOption(code: 'KW', name: 'Kuveyt', flag: '🇰🇼'),
  CountryOption(code: 'CY', name: 'Kıbrıs', flag: '🇨🇾'),
  CountryOption(code: 'LB', name: 'Lübnan', flag: '🇱🇧'),
  CountryOption(code: 'HU', name: 'Macaristan', flag: '🇭🇺'),
  CountryOption(code: 'MK', name: 'Kuzey Makedonya', flag: '🇲🇰'),
  CountryOption(code: 'MY', name: 'Malezya', flag: '🇲🇾'),
  CountryOption(code: 'MX', name: 'Meksika', flag: '🇲🇽'),
  CountryOption(code: 'EG', name: 'Mısır', flag: '🇪🇬'),
  CountryOption(code: 'MD', name: 'Moldova', flag: '🇲🇩'),
  CountryOption(code: 'NO', name: 'Norveç', flag: '🇳🇴'),
  CountryOption(code: 'UZ', name: 'Özbekistan', flag: '🇺🇿'),
  CountryOption(code: 'PK', name: 'Pakistan', flag: '🇵🇰'),
  CountryOption(code: 'PL', name: 'Polonya', flag: '🇵🇱'),
  CountryOption(code: 'PT', name: 'Portekiz', flag: '🇵🇹'),
  CountryOption(code: 'RO', name: 'Romanya', flag: '🇷🇴'),
  CountryOption(code: 'RU', name: 'Rusya', flag: '🇷🇺'),
  CountryOption(code: 'RS', name: 'Sırbistan', flag: '🇷🇸'),
  CountryOption(code: 'SA', name: 'Suudi Arabistan', flag: '🇸🇦'),
  CountryOption(code: 'SY', name: 'Suriye', flag: '🇸🇾'),
  CountryOption(code: 'TJ', name: 'Tacikistan', flag: '🇹🇯'),
  CountryOption(code: 'TH', name: 'Tayland', flag: '🇹🇭'),
  CountryOption(code: 'TM', name: 'Türkmenistan', flag: '🇹🇲'),
  CountryOption(code: 'UA', name: 'Ukrayna', flag: '🇺🇦'),
  CountryOption(code: 'JO', name: 'Ürdün', flag: '🇯🇴'),
  CountryOption(code: 'GR', name: 'Yunanistan', flag: '🇬🇷'),
  CountryOption(code: 'NZ', name: 'Yeni Zelanda', flag: '🇳🇿'),
];

CountryOption? countryByCode(String? code) {
  if (code == null) return null;
  final upper = code.toUpperCase();
  for (final option in kCountryOptions) {
    if (option.code == upper) return option;
  }
  return null;
}

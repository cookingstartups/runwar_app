class CityEntry {
  const CityEntry({
    required this.slug,
    required this.name,
    required this.country,
    required this.flag,
    required this.hue,
    required this.lat,
    required this.lng,
    required this.isUnlocked,
    required this.totalTarget,
    required this.tagline,
    this.joinedCount = 0,
  });

  final String slug;
  final String name;
  final String country;
  final String flag;
  final String hue; // "H S% L%" e.g. "20 100% 50%"
  final double lat;
  final double lng;
  final bool isUnlocked;
  final int totalTarget;
  final String tagline;
  final int joinedCount;

  CityEntry copyWith({int? joinedCount}) => CityEntry(
        slug: slug,
        name: name,
        country: country,
        flag: flag,
        hue: hue,
        lat: lat,
        lng: lng,
        isUnlocked: isUnlocked,
        totalTarget: totalTarget,
        tagline: tagline,
        joinedCount: joinedCount ?? this.joinedCount,
      );

  factory CityEntry.fromMap(Map<String, dynamic> m) => CityEntry(
        slug: m['slug'] as String,
        name: m['name'] as String,
        country: m['country'] as String,
        flag: m['flag'] as String,
        hue: m['hue'] as String,
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        isUnlocked: (m['is_unlocked'] as bool?) ?? false,
        totalTarget: (m['total_target'] as int?) ?? 1000,
        tagline: (m['tagline'] as String?) ?? '',
        joinedCount: (m['joined_count'] as int?) ?? 0,
      );
}

const List<CityEntry> kCitiesCatalog = [
  CityEntry(slug: 'valencia',  name: 'Valencia',   country: 'Spain',       flag: '🇪🇸', hue: '20 100% 50%',  lat: 39.4699,  lng: -0.3763,  isUnlocked: true,  totalTarget: 1000, tagline: 'Cradle of the war.'),
  CityEntry(slug: 'new-york',  name: 'New York',   country: 'USA',         flag: '🇺🇸', hue: '210 100% 50%', lat: 40.7128,  lng: -74.0060, isUnlocked: false, totalTarget: 2000, tagline: 'Five boroughs. One throne.'),
  CityEntry(slug: 'bali',      name: 'Bali',       country: 'Indonesia',   flag: '🇮🇩', hue: '160 100% 40%', lat: -8.4095,  lng: 115.1889, isUnlocked: false, totalTarget: 500,  tagline: 'Volcanic ground.'),
  CityEntry(slug: 'seoul',     name: 'Seoul',      country: 'South Korea', flag: '🇰🇷', hue: '290 100% 55%', lat: 37.5665,  lng: 126.9780, isUnlocked: false, totalTarget: 1500, tagline: 'Neon district war.'),
  CityEntry(slug: 'london',    name: 'London',     country: 'UK',          flag: '🇬🇧', hue: '220 80% 45%',  lat: 51.5074,  lng: -0.1278,  isUnlocked: false, totalTarget: 1500, tagline: 'Thames divided.'),
  CityEntry(slug: 'barcelona', name: 'Barcelona',  country: 'Spain',       flag: '🇪🇸', hue: '40 100% 50%',  lat: 41.3851,  lng: 2.1734,   isUnlocked: false, totalTarget: 1000, tagline: 'Mediterranean conquest.'),
];

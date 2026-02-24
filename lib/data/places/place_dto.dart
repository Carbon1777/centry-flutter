class PlaceDto {
  final String id;
  final String title;
  final String type;
  final String address;

  final String cityId;
  final String cityName;

  final String? areaId;
  final String? areaName;

  /// Серверные координаты места
  final double lat;
  final double lng;

  /// Расстояние до места в метрах (серверное)
  final double? distanceM;

  /// === META (vNext) ===

  /// Превью-картинка для списка / карты
  ///
  /// Источник:
  /// - previewMediaUrl: готовый URL (если сервер отдаёт)
  /// - previewStorageKey: storage key в bucket'е (если сервер отдаёт только ключ)
  final String? previewMediaUrl;

  /// Storage key в Supabase Storage (например: "brands/bona.webp", "categories/bar/1.webp")
  final String? previewStorageKey;

  /// Превью — это плейсхолдер (категория), а не реальное фото места
  final bool previewIsPlaceholder;

  /// Ближайшее метро (опционально)
  final String? metroName;

  /// Расстояние до метро в метрах (опционально)
  final int? metroDistanceM;

  /// Рейтинг (пока nullable / placeholder)
  final double? rating;

  /// Лайки / дизлайки
  final int likesCount;
  final int dislikesCount;

  /// Сайт места (nullable)
  final String? websiteUrl;

  PlaceDto({
    required this.id,
    required this.title,
    required this.type,
    required this.address,
    required this.cityId,
    required this.cityName,
    required this.areaId,
    required this.areaName,
    required this.lat,
    required this.lng,
    required this.distanceM,
    required this.previewMediaUrl,
    required this.previewStorageKey,
    required this.previewIsPlaceholder,
    required this.metroName,
    required this.metroDistanceM,
    required this.rating,
    required this.likesCount,
    required this.dislikesCount,
    required this.websiteUrl,
  });

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static int _asInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  static int? _asIntNullable(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  factory PlaceDto.fromJson(Map<String, dynamic> json) {
    return PlaceDto(
      id: json['id'] as String,
      title: json['title'] as String,
      type: json['type'] as String,

      /// Гарантия строки
      address: json['address']?.toString() ?? 'Адрес не указан',

      cityId: json['city_id']?.toString() ?? '',
      cityName: json['city_name']?.toString() ?? '',

      areaId: json['area_id']?.toString(),
      areaName: json['area_name']?.toString(),

      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),

      distanceM: _asDouble(json['distance_m']),

      /// META
      previewMediaUrl: json['preview_media_url']?.toString(),
      previewStorageKey: json['preview_storage_key']?.toString(),
      previewIsPlaceholder: (json['preview_is_placeholder'] as bool?) ?? false,
      metroName: json['metro_name']?.toString(),
      metroDistanceM: _asIntNullable(json['metro_distance_m']),

      /// numeric часто приходит строкой
      rating: _asDouble(json['rating']),

      likesCount: _asInt(json['likes_count'], fallback: 0),
      dislikesCount: _asInt(json['dislikes_count'], fallback: 0),

      websiteUrl: json['website_url']?.toString(),
    );
  }
}

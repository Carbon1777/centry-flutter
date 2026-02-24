import 'package:shared_preferences/shared_preferences.dart';

enum GeoInfoState {
  geoAvailable,
  geoDenied,
  geoTemporarilyUnavailable,
}

class PlacesGeoInfoController {
  static const _prefsKey = 'places_geo_info_never_show';

  Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_prefsKey) ?? false);
  }

  Future<void> markNeverShow() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
  }

  GeoInfoState resolveState({
    required bool permissionGranted,
    required bool hasCurrentPosition,
  }) {
    if (!permissionGranted) {
      return GeoInfoState.geoDenied;
    }

    if (!hasCurrentPosition) {
      return GeoInfoState.geoTemporarilyUnavailable;
    }

    return GeoInfoState.geoAvailable;
  }

  String resolveText(GeoInfoState state) {
    switch (state) {
      case GeoInfoState.geoAvailable:
        return 'Мы отобразили места рядом с вами согласно вашей '
            'гео-позиции. Если хотите изменить настройку — '
            'это можно сделать в фильтрах.';
      case GeoInfoState.geoDenied:
        return 'Вы не дали нам разрешение на определение вашей локации, '
            'список мест отображён с сортировкой по умолчанию. '
            'Изменить настройки отображения можно в фильтрах.';
      case GeoInfoState.geoTemporarilyUnavailable:
        return 'Мы не смогли в текущий момент определить ваше '
            'местоположение, список мест сформирован по вашей '
            'последней геолокации. Порядок отображения можно '
            'изменить в фильтрах.';
    }
  }
}

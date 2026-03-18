import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'places_filters_state.dart';
import 'places_filters_payload.dart';

/// Контроллер фильтров "Места".
///
/// КАНОН:
/// - Хранит только подтверждённое (committed) состояние фильтров.
/// - SharedPreferences: персистентность между сессиями.
/// - Сервер — источник истины для доступных опций (загружается в диалоге).
/// - Контроллер не знает про «доступные» варианты — только про «выбранные».
class PlacesFiltersController extends ChangeNotifier {
  static const _kPrefsKey = 'places_filters_v2';

  PlacesFiltersState _state = PlacesFiltersState.empty();

  // true после первого явного applySelection / resetAll —
  // запрещает авто-применение гео-города при повторном открытии шторки
  bool _wasExplicitlyModified = false;
  bool get wasExplicitlyModified => _wasExplicitlyModified;

  // Кэши display-названий для чипов активных фильтров
  final Map<String, String> _cityTitles = {};
  final Map<String, String> _areaTitles = {};
  final Map<String, String> _typeTitles = {};

  PlacesFiltersState get state => _state;

  // ===========================================================
  // ACTIVE FILTERS (для чипов над списком)
  // ===========================================================

  /// Плоский список активных фильтров — для отображения чипов.
  /// id чипа имеет префикс: 'city:', 'area:', 'type:', 'rating'.
  List<PlaceFilterItem> get activeFilters {
    final items = <PlaceFilterItem>[];

    for (final id in _state.cityIds) {
      items.add(PlaceFilterItem(id: 'city:$id', title: _cityTitles[id] ?? id));
    }
    for (final id in _state.areaIds) {
      items.add(PlaceFilterItem(id: 'area:$id', title: _areaTitles[id] ?? id));
    }
    for (final code in _state.types) {
      items.add(
          PlaceFilterItem(id: 'type:$code', title: _typeTitles[code] ?? code));
    }
    if (_state.minRating != null) {
      items.add(PlaceFilterItem(
        id: 'rating',
        title: '≥ ${_state.minRating!.toStringAsFixed(1)} ★',
      ));
    }

    return items;
  }

  // ===========================================================
  // INIT (SharedPreferences)
  // ===========================================================

  /// Загружает сохранённое состояние фильтров.
  /// Вызывать из [PlacesScreen.initState] fire-and-forget.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPrefsKey);
      if (raw == null || raw.isEmpty) return;

      final json = jsonDecode(raw) as Map<String, dynamic>;

      final cityIds = _readStringList(json['city_ids']);
      final areaIds = _readStringList(json['area_ids']);
      final types = _readStringList(json['types']);
      final minRating = (json['min_rating'] as num?)?.toDouble();

      // was_explicitly_modified намеренно НЕ восстанавливается из prefs:
      // рестарт приложения = возврат в режим по умолчанию (автогео включён).

      _cityTitles
        ..clear()
        ..addAll(Map<String, String>.from(json['city_titles'] as Map? ?? {}));
      _areaTitles
        ..clear()
        ..addAll(Map<String, String>.from(json['area_titles'] as Map? ?? {}));
      _typeTitles
        ..clear()
        ..addAll(Map<String, String>.from(json['type_titles'] as Map? ?? {}));

      _state = PlacesFiltersState(
        cityIds: cityIds,
        areaIds: areaIds,
        types: types,
        minRating: minRating,
      );

      notifyListeners();
    } catch (_) {
      // Игнорируем ошибки персистентности — стартуем с пустым состоянием
    }
  }

  // ===========================================================
  // APPLY SELECTION (вызывается из диалога/шторки)
  // ===========================================================

  /// Фиксирует выбор пользователя из диалога фильтров.
  /// [cityTitles] / [areaTitles] / [typeTitles] — map id→title для чипов.
  void applySelection({
    required List<String> cityIds,
    required Map<String, String> cityTitles,
    required List<String> areaIds,
    required Map<String, String> areaTitles,
    required List<String> types,
    required Map<String, String> typeTitles,
    required double? minRating,
  }) {
    _cityTitles
      ..clear()
      ..addAll(cityTitles);
    _areaTitles
      ..clear()
      ..addAll(areaTitles);
    _typeTitles
      ..clear()
      ..addAll(typeTitles);

    // Авто-гео отключается только когда пользователь явно убрал все города.
    // Если выбрал хоть один город — авто-гео и так не нужен (selection не пуст).
    // Если выбрал нули городов — фиксируем, что это осознанный выбор.
    _wasExplicitlyModified = cityIds.isEmpty;
    _state = PlacesFiltersState(
      cityIds: cityIds,
      areaIds: areaIds,
      types: types,
      minRating: minRating,
    );

    _persist();
    notifyListeners();
  }

  // ===========================================================
  // REMOVE SINGLE FILTER (по нажатию на чип)
  // ===========================================================

  /// Удаляет один фильтр по id чипа (формат: 'city:{id}', 'area:{id}', 'type:{code}', 'rating').
  void removeFilter(String filterId) {
    if (filterId.startsWith('city:')) {
      final id = filterId.substring(5);
      final newCityIds = _state.cityIds.where((e) => e != id).toList();
      _wasExplicitlyModified = newCityIds.isEmpty;
      _state = _state.copyWith(cityIds: newCityIds);
      _cityTitles.remove(id);
    } else if (filterId.startsWith('area:')) {
      final id = filterId.substring(5);
      _state = _state.copyWith(
          areaIds: _state.areaIds.where((e) => e != id).toList());
      _areaTitles.remove(id);
    } else if (filterId.startsWith('type:')) {
      final code = filterId.substring(5);
      _state =
          _state.copyWith(types: _state.types.where((e) => e != code).toList());
      _typeTitles.remove(code);
    } else if (filterId == 'rating') {
      _state = _state.copyWith(minRating: null);
    }

    _persist();
    notifyListeners();
  }

  // ===========================================================
  // RESET ALL
  // ===========================================================

  void resetAll() {
    // Сброс = возврат к умолчанию, авто-гео снова включён
    _wasExplicitlyModified = false;
    _state = PlacesFiltersState.empty();
    _cityTitles.clear();
    _areaTitles.clear();
    _typeTitles.clear();
    _persist();
    notifyListeners();
  }

  // ===========================================================
  // PAYLOAD → SERVER
  // ===========================================================

  PlacesFiltersPayload buildPayload() {
    return PlacesFiltersPayload(
      cityIds: _state.cityIds.isEmpty ? null : _state.cityIds,
      areaIds: _state.areaIds.isEmpty ? null : _state.areaIds,
      types: _state.types.isEmpty ? null : _state.types,
      minRating: _state.minRating,
    );
  }

  // ===========================================================
  // UTILS
  // ===========================================================

  void _persist() {
    SharedPreferences.getInstance().then((prefs) {
      try {
        final data = {
          'city_ids': _state.cityIds,
          'area_ids': _state.areaIds,
          'types': _state.types,
          'min_rating': _state.minRating,
          // was_explicitly_modified не персистим — рестарт = дефолтный режим
          'city_titles': _cityTitles,
          'area_titles': _areaTitles,
          'type_titles': _typeTitles,
        };
        prefs.setString(_kPrefsKey, jsonEncode(data));
      } catch (_) {}
    });
  }

  List<String> _readStringList(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return const [];
  }
}

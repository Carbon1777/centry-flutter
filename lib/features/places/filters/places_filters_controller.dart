import 'package:flutter/foundation.dart';

import 'places_filters_state.dart';
import 'places_filters_payload.dart';

/// Контроллер фильтров "Места".
///
/// КАНОН:
/// - Клиент тупой.
/// - Сервер — источник истины (available + selected).
/// - Контроллер:
///   * хранит выбранные значения
///   * отправляет payload на сервер
///   * применяет состояние, пришедшее с сервера
class PlacesFiltersController extends ChangeNotifier {
  PlacesFiltersState _state = PlacesFiltersState.empty();

  PlacesFiltersState get state => _state;

  // ===========================================================
  // APPLY FROM SERVER (SOURCE OF TRUTH)
  // ===========================================================

  /// Применение server-driven состояния фильтров.
  ///
  /// Ожидаемый формат:
  /// {
  ///   "available": { ... },
  ///   "selected": { cities, areas, types },
  ///   "meta": { auto_applied_city }
  /// }
  void applyServerState(Map<String, dynamic> serverState) {
    final selected = serverState['selected'] as Map<String, dynamic>?;

    _state = _state.copyWith(
      cityIds: _readStringList(selected?['cities']),
      areaIds: _readStringList(selected?['areas']),
      types: _readStringList(selected?['types']),
    );

    notifyListeners();
  }

  // ===========================================================
  // USER INTERACTIONS (UI ONLY)
  // ===========================================================

  /// --- CITY ---
  void toggleCity(String cityId) {
    final next = List<String>.from(_state.cityIds);

    if (next.contains(cityId)) {
      next.remove(cityId);
    } else {
      next.add(cityId);
    }

    // НИКАКОЙ фильтрации районов на клиенте.
    _state = _state.copyWith(
      cityIds: next,
    );

    notifyListeners();
  }

  /// --- AREA ---
  void toggleArea(String areaId) {
    final next = List<String>.from(_state.areaIds);

    if (next.contains(areaId)) {
      next.remove(areaId);
    } else {
      next.add(areaId);
    }

    _state = _state.copyWith(areaIds: next);
    notifyListeners();
  }

  /// --- TYPE ---
  void toggleType(String type) {
    final next = List<String>.from(_state.types);

    if (next.contains(type)) {
      next.remove(type);
    } else {
      next.add(type);
    }

    _state = _state.copyWith(types: next);
    notifyListeners();
  }

  // ===========================================================
  // PAYLOAD → SERVER
  // ===========================================================

  /// Формирование payload для сервера.
  ///
  /// ВАЖНО:
  /// - пустые списки → null
  /// - сервер решает auto-apply и доступность
  PlacesFiltersPayload buildPayload() {
    return PlacesFiltersPayload(
      cityIds: _state.cityIds.isEmpty ? null : _state.cityIds,
      areaIds: _state.areaIds.isEmpty ? null : _state.areaIds,
      types: _state.types.isEmpty ? null : _state.types,
    );
  }

  // ===========================================================
  // RESET
  // ===========================================================

  /// Полный сброс фильтров (user intent).
  /// После этого сервер может auto-apply город по geo.
  void clear() {
    _state = PlacesFiltersState.empty();
    notifyListeners();
  }

  // ===========================================================
  // UTILS
  // ===========================================================

  List<String> _readStringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return const [];
  }
}

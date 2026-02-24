import 'package:flutter/material.dart';
import 'places_filters_controller.dart';

class PlacesFiltersDialog extends StatefulWidget {
  final PlacesFiltersController controller;
  final List<PlacesFilterItem> initialCities;
  final List<PlacesFilterItem> initialTypes;
  final List<PlacesFilterItem> initialAreas;
  final Future<Map<String, dynamic>> Function() loadServerState;

  const PlacesFiltersDialog({
    super.key,
    required this.controller,
    required this.initialCities,
    required this.initialTypes,
    required this.initialAreas,
    required this.loadServerState,
  });

  @override
  State<PlacesFiltersDialog> createState() => _PlacesFiltersDialogState();
}

class _PlacesFiltersDialogState extends State<PlacesFiltersDialog> {
  List<PlacesFilterItem> _cities = const [];
  List<PlacesFilterItem> _types = const [];
  List<PlacesFilterItem> _areas = const [];

  bool _syncing = false;

  @override
  void initState() {
    super.initState();

    _cities = widget.initialCities
        .map((e) => PlacesFilterItem(id: e.id, title: _cityTitle(e.title)))
        .toList();

    _types = widget.initialTypes
        .map((e) => PlacesFilterItem(id: e.id, title: _typeTitle(e.title)))
        .toList();

    _areas = widget.initialAreas;
  }

  Future<void> _syncFromServer() async {
    if (_syncing) return;
    setState(() => _syncing = true);

    try {
      final serverState = await widget.loadServerState();
      widget.controller.applyServerState(serverState);

      final available = serverState['available'] as Map<String, dynamic>? ?? {};
      final citiesJson = available['cities'] as List? ?? const [];
      final typesJson = available['types'] as List? ?? const [];
      final areasJson = available['areas'] as List? ?? const [];

      setState(() {
        _cities = citiesJson
            .whereType<Map>()
            .map((e) => PlacesFilterItem(
                  id: e['id'].toString(),
                  title: _cityTitle(e['title'].toString()),
                ))
            .toList();

        _types = typesJson
            .whereType<Map>()
            .map((e) => PlacesFilterItem(
                  id: e['type'].toString(),
                  title: _typeTitle(e['type'].toString()),
                ))
            .toList();

        _areas = areasJson
            .whereType<Map>()
            .map((e) => PlacesFilterItem(
                  id: e['id'].toString(),
                  title: e['title'].toString(),
                ))
            .toList();
      });
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Фильтрация мест', style: text.titleMedium),
                ),
                if (_syncing)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 260,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    flex: 3,
                    child: _FilterColumn(
                      title: 'Город',
                      items: _cities,
                      selected: widget.controller.state.cityIds,
                      onTap: _onCityTap,
                      maxLines: 1,
                    ),
                  ),
                  const _VerticalLine(),
                  Flexible(
                    flex: 3,
                    child: _FilterColumn(
                      title: 'Тип',
                      items: _types,
                      selected: widget.controller.state.types,
                      onTap: _onTypeTap,
                      maxLines: 2,
                    ),
                  ),
                  const _VerticalLine(),
                  Flexible(
                    flex: 4,
                    child: _FilterColumn(
                      title: 'Район',
                      items: _areas,
                      selected: widget.controller.state.areaIds,
                      onTap: _onAreaTap,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Готово'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onCityTap(String cityId) async {
    widget.controller.toggleCity(cityId);
    await _syncFromServer();
  }

  Future<void> _onTypeTap(String type) async {
    widget.controller.toggleType(type);
    await _syncFromServer();
  }

  Future<void> _onAreaTap(String areaId) async {
    widget.controller.toggleArea(areaId);
    await _syncFromServer();
  }
}

/// ===== UI helpers =====

class _VerticalLine extends StatelessWidget {
  const _VerticalLine();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: Colors.white24,
    );
  }
}

class _FilterColumn extends StatelessWidget {
  final String title;
  final List<PlacesFilterItem> items;
  final List<String> selected;
  final Future<void> Function(String id) onTap;
  final int maxLines;

  const _FilterColumn({
    required this.title,
    required this.items,
    required this.selected,
    required this.onTap,
    required this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: text.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade200,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: items.map((e) {
                final isActive = selected.contains(e.id);
                final activeColor = colors.primary;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      splashColor: activeColor.withOpacity(0.18),
                      highlightColor: Colors.transparent,
                      overlayColor: MaterialStateProperty.all(
                          activeColor.withOpacity(0.12)),
                      onTap: () => onTap(e.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 6,
                        ),
                        child: Text(
                          e.title,
                          softWrap: true,
                          maxLines: maxLines,
                          overflow: TextOverflow.visible,
                          style: text.bodyMedium?.copyWith(
                            color:
                                isActive ? activeColor : Colors.grey.shade300,
                            fontWeight:
                                isActive ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

/// ===== domain helpers =====

String _cityTitle(String raw) {
  if (raw.toLowerCase().contains('петербург')) return 'СПБ';
  return raw;
}

String _typeTitle(String type) {
  switch (type) {
    case 'bar':
      return 'Бар';
    case 'cinema':
      return 'Кино';
    case 'nightclub':
      return 'Ночной\nклуб';
    case 'restaurant':
      return 'Ресторан';
    case 'theatre':
      return 'Театр';
    default:
      return type;
  }
}

class PlacesFilterItem {
  final String id;
  final String title;
  const PlacesFilterItem({required this.id, required this.title});
}

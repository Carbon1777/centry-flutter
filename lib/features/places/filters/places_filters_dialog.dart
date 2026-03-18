import 'package:flutter/material.dart';

import 'places_filters_controller.dart';

/// Открывает шторку фильтров мест.
///
/// После закрытия вызывающий код должен перезагрузить список,
/// если [PlacesFiltersController.state] изменился.
Future<void> showPlacesFiltersSheet({
  required BuildContext context,
  required PlacesFiltersController controller,
  // cityIds — текущий черновой выбор городов (для динамического обновления районов)
  required Future<Map<String, dynamic>> Function({List<String>? cityIds})
      loadServerState,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // Отключаем drag — шторку можно закрыть только кнопкой или тапом по фону,
    // скролл содержимого не закрывает её случайно.
    enableDrag: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => FractionallySizedBox(
      heightFactor: 0.93,
      child: _PlacesFiltersSheet(
        controller: controller,
        loadServerState: loadServerState,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _PlacesFiltersSheet extends StatefulWidget {
  final PlacesFiltersController controller;
  final Future<Map<String, dynamic>> Function({List<String>? cityIds})
      loadServerState;

  const _PlacesFiltersSheet({
    required this.controller,
    required this.loadServerState,
  });

  @override
  State<_PlacesFiltersSheet> createState() => _PlacesFiltersSheetState();
}

class _PlacesFiltersSheetState extends State<_PlacesFiltersSheet> {
  bool _loading = true;

  // Доступные варианты (от сервера, выбранные — всегда первые)
  List<_FilterOption> _availableCities = const [];
  List<_FilterOption> _availableAreas = const [];
  List<_FilterOption> _availableTypes = const [];
  List<_RatingOption> _availableRatings = const [];

  // Оригинальный серверный порядок — нужен для возврата снятых элементов
  List<_FilterOption> _originalCities = const [];
  List<_FilterOption> _originalAreas = const [];
  List<_FilterOption> _originalTypes = const [];

  // Локальный черновик выбора (до нажатия «Применить»)
  final Set<String> _selectedCityIds = {};
  final Set<String> _selectedAreaIds = {};
  final Set<String> _selectedTypes = {};
  double? _selectedRating;

  // Кэши display-названий для применения
  final Map<String, String> _cityTitles = {};
  final Map<String, String> _areaTitles = {};
  final Map<String, String> _typeTitles = {};

  @override
  void initState() {
    super.initState();
    // Инициализируем черновик из текущего состояния контроллера
    final s = widget.controller.state;
    _selectedCityIds.addAll(s.cityIds);
    _selectedAreaIds.addAll(s.areaIds);
    _selectedTypes.addAll(s.types);
    _selectedRating = s.minRating;

    _loadAvailable();
  }

  // ── Сортировка: выбранные вперёд, остальные в исходном порядке ──────────────

  List<_FilterOption> _sortSelected(
      List<_FilterOption> original, Set<String> selected) {
    return [
      ...original.where((o) => selected.contains(o.id)),
      ...original.where((o) => !selected.contains(o.id)),
    ];
  }

  // ── Загрузка всех доступных опций при открытии ───────────────────────────────

  Future<void> _loadAvailable() async {
    setState(() => _loading = true);
    try {
      final serverState =
          await widget.loadServerState(cityIds: null); // начальная загрузка
      final available =
          serverState['available'] as Map<String, dynamic>? ?? {};

      final citiesJson = available['cities'] as List? ?? const [];
      final areasJson = available['areas'] as List? ?? const [];
      final typesJson = available['types'] as List? ?? const [];
      final ratingsJson = available['ratings'] as List? ?? const [];

      final meta = serverState['meta'] as Map<String, dynamic>? ?? {};
      final autoAppliedCity = meta['auto_applied_city'] as bool? ?? false;

      final cities = citiesJson
          .whereType<Map>()
          .map((e) => _FilterOption(
                id: e['id'].toString(),
                title: e['title'].toString(),
              ))
          .toList();

      final areas = areasJson
          .whereType<Map>()
          .map((e) => _FilterOption(
                id: e['id'].toString(),
                title: e['title'].toString(),
              ))
          .toList();

      final types = typesJson
          .whereType<Map>()
          .map((e) => _FilterOption(
                id: e['code'].toString(),
                title: e['display_name'].toString(),
              ))
          .toList();

      final ratings = ratingsJson
          .whereType<Map>()
          .map((e) {
            final value = (e['value'] as num).toDouble();
            return _RatingOption(
              value: value,
              label: value == 5.0 ? '= 5.0' : e['label'].toString(),
            );
          })
          .toList();

      setState(() {
        // Строим кэши display-названий
        for (final c in cities) { _cityTitles[c.id] = c.title; }
        for (final a in areas) { _areaTitles[a.id] = a.title; }
        for (final t in types) { _typeTitles[t.id] = t.title; }

        // Если сервер авто-применил город по гео И пользователь ещё
        // ни разу явно не применял фильтры — предзаполняем черновик.
        // Если wasExplicitlyModified = true, значит пользователь уже
        // сознательно снял город — авто-гео не применяем.
        if (autoAppliedCity &&
            _selectedCityIds.isEmpty &&
            !widget.controller.wasExplicitlyModified) {
          final selectedFromServer =
              serverState['selected'] as Map<String, dynamic>? ?? {};
          final serverCities =
              selectedFromServer['cities'] as List? ?? const [];
          for (final c in serverCities.whereType<Map>()) {
            _selectedCityIds.add(c['id'].toString());
          }
        }

        // Сохраняем оригинальный порядок от сервера
        _originalCities = cities;
        _originalAreas = areas;
        _originalTypes = types;

        // Выбранные — первыми
        _availableCities = _sortSelected(_originalCities, _selectedCityIds);
        _availableAreas = _sortSelected(_originalAreas, _selectedAreaIds);
        _availableTypes = _sortSelected(_originalTypes, _selectedTypes);
        _availableRatings = ratings;

        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Обновление районов при смене городов ─────────────────────────────────────

  Future<void> _refreshAreas() async {
    try {
      final serverState = await widget.loadServerState(
        cityIds: _selectedCityIds.toList(),
      );
      final available =
          serverState['available'] as Map<String, dynamic>? ?? {};
      final areasJson = available['areas'] as List? ?? const [];

      final newAreas = areasJson
          .whereType<Map>()
          .map((e) => _FilterOption(
                id: e['id'].toString(),
                title: e['title'].toString(),
              ))
          .toList();

      setState(() {
        for (final a in newAreas) { _areaTitles[a.id] = a.title; }

        // Сохраняем оригинальный порядок районов
        _originalAreas = newAreas;

        // Снимаем районы, которых больше нет в доступных
        final availableIds = newAreas.map((a) => a.id).toSet();
        _selectedAreaIds.removeWhere((id) => !availableIds.contains(id));

        // Выбранные — первыми
        _availableAreas = _sortSelected(_originalAreas, _selectedAreaIds);
      });
    } catch (_) {
      // молча игнорируем
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────

  void _apply() {
    widget.controller.applySelection(
      cityIds: _selectedCityIds.toList(),
      cityTitles: Map.from(_cityTitles),
      areaIds: _selectedAreaIds.toList(),
      areaTitles: Map.from(_areaTitles),
      types: _selectedTypes.toList(),
      typeTitles: Map.from(_typeTitles),
      minRating: _selectedRating,
    );
    Navigator.of(context).pop();
  }

  void _resetAll() {
    widget.controller.resetAll();
    Navigator.of(context).pop();
  }

  bool get _hasAnySelection =>
      _selectedCityIds.isNotEmpty ||
      _selectedAreaIds.isNotEmpty ||
      _selectedTypes.isNotEmpty ||
      _selectedRating != null;

  void _toggleSet(Set<String> set, String id) {
    if (set.contains(id)) {
      set.remove(id);
    } else {
      set.add(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Column(
      children: [
        // ── Шапка ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Фильтры',
                  style:
                      text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (_hasAnySelection)
                TextButton(
                  onPressed: _resetAll,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.onSurface.withValues(alpha: 0.5),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('Сбросить всё'),
                ),
              IconButton(
                icon: Icon(Icons.close,
                    size: 20,
                    color: colors.onSurface.withValues(alpha: 0.4)),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),

        Divider(height: 1, color: colors.outline.withValues(alpha: 0.2)),

        // ── Тело ─────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  children: [
                    if (_availableCities.isNotEmpty) ...[
                      const _SectionHeader(title: 'Город'),
                      const SizedBox(height: 8),
                      _ChipGroup(
                        options: _availableCities,
                        selected: _selectedCityIds,
                        onToggle: (id) {
                          setState(() {
                            _toggleSet(_selectedCityIds, id);
                            _availableCities = _sortSelected(
                                _originalCities, _selectedCityIds);
                          });
                          _refreshAreas();
                        },
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (_availableTypes.isNotEmpty) ...[
                      const _SectionHeader(title: 'Тип заведения'),
                      const SizedBox(height: 8),
                      _ChipGroup(
                        options: _availableTypes,
                        selected: _selectedTypes,
                        onToggle: (id) => setState(() {
                          _toggleSet(_selectedTypes, id);
                          _availableTypes =
                              _sortSelected(_originalTypes, _selectedTypes);
                        }),
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (_availableAreas.isNotEmpty) ...[
                      const _SectionHeader(title: 'Район'),
                      const SizedBox(height: 8),
                      _ChipGroup(
                        options: _availableAreas,
                        selected: _selectedAreaIds,
                        onToggle: (id) => setState(() {
                          _toggleSet(_selectedAreaIds, id);
                          _availableAreas =
                              _sortSelected(_originalAreas, _selectedAreaIds);
                        }),
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (_availableRatings.isNotEmpty) ...[
                      const _SectionHeader(title: 'Рейтинг'),
                      const SizedBox(height: 8),
                      _RatingChipGroup(
                        options: _availableRatings,
                        selected: _selectedRating,
                        onSelect: (v) =>
                            setState(() => _selectedRating = v),
                      ),
                    ],
                  ],
                ),
        ),

        // ── Кнопка «Применить» ───────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(
              top: BorderSide(
                  color: colors.outline.withValues(alpha: 0.15)),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _apply,
              child: const Text('Применить'),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.onSurface.withValues(alpha: 0.45),
            letterSpacing: 0.6,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

// ─── Multi-select chip group ──────────────────────────────────────────────────

class _ChipGroup extends StatelessWidget {
  final List<_FilterOption> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const _ChipGroup({
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final isSelected = selected.contains(opt.id);
        return FilterChip(
          label: Text(opt.title,
              style: const TextStyle(fontSize: 13)),
          selected: isSelected,
          onSelected: (_) => onToggle(opt.id),
          showCheckmark: false,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          labelPadding: const EdgeInsets.symmetric(horizontal: 2),
        );
      }).toList(),
    );
  }
}

// ─── Single-select rating chip group ─────────────────────────────────────────

class _RatingChipGroup extends StatelessWidget {
  final List<_RatingOption> options;
  final double? selected;
  final ValueChanged<double?> onSelect;

  const _RatingChipGroup({
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final isSelected = selected == opt.value;
        return ChoiceChip(
          label: Text(opt.label,
              style: const TextStyle(fontSize: 13)),
          selected: isSelected,
          showCheckmark: false,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          labelPadding: const EdgeInsets.symmetric(horizontal: 2),
          // Повторное нажатие на выбранный — снимает фильтр
          onSelected: (_) => onSelect(isSelected ? null : opt.value),
        );
      }).toList(),
    );
  }
}

// ─── Models ───────────────────────────────────────────────────────────────────

class _FilterOption {
  final String id;
  final String title;
  const _FilterOption({required this.id, required this.title});
}

class _RatingOption {
  final double value;
  final String label;
  const _RatingOption({required this.value, required this.label});
}

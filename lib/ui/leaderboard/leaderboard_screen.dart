import 'package:flutter/material.dart';

import '../../data/leaderboard/leaderboard_dto.dart';
import '../../data/leaderboard/leaderboard_repository.dart';
import '../shared/spinning_logo.dart';

const _kGold = Color(0xFFFFD700);
const _kSilver = Color(0xFFB8C4CE);
const _kBronze = Color(0xFFCD8B4A);

// Цвета вкладок
const _kActivityColor = Color(0xFFFF7043);
const _kSympathyColor = Color(0xFF66BB6A);

class LeaderboardScreen extends StatefulWidget {
  final LeaderboardRepository repository;
  final String appUserId;

  const LeaderboardScreen({
    super.key,
    required this.repository,
    required this.appUserId,
  });

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  int _tabIndex = 0; // 0 = Активность, 1 = Симпатии

  late Future<LeaderboardSnapshotDto> _activityFuture;
  Future<SympathyLeaderboardSnapshotDto>? _sympathyFuture;

  @override
  void initState() {
    super.initState();
    _activityFuture =
        widget.repository.getSnapshot(appUserId: widget.appUserId);
  }

  void _reloadActivity() => setState(() {
        _activityFuture =
            widget.repository.getSnapshot(appUserId: widget.appUserId);
      });

  void _reloadSympathy() => setState(() {
        _sympathyFuture =
            widget.repository.getSympathySnapshot(appUserId: widget.appUserId);
      });

  void _ensureSympathyLoaded() {
    _sympathyFuture ??=
        widget.repository.getSympathySnapshot(appUserId: widget.appUserId);
  }

  void _switchTab(int index) {
    if (index == _tabIndex) return;
    if (index == 1) _ensureSympathyLoaded();
    setState(() => _tabIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Рейтинг')),
      body: Column(
        children: [
          // ── Закладки ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: _TabButton(
                    label: 'Активность',
                    color: _kActivityColor,
                    isActive: _tabIndex == 0,
                    onTap: () => _switchTab(0),
                  ),
                ),
                Expanded(
                  child: _TabButton(
                    label: 'Симпатии',
                    color: _kSympathyColor,
                    isActive: _tabIndex == 1,
                    onTap: () => _switchTab(1),
                  ),
                ),
              ],
            ),
          ),

          // ── Контент ──
          Expanded(
            child: _tabIndex == 0
                ? FutureBuilder<LeaderboardSnapshotDto>(
                    future: _activityFuture,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (snap.hasError || !snap.hasData) {
                        return _ErrorState(onRetry: _reloadActivity);
                      }
                      return _ActivityBody(snapshot: snap.data!);
                    },
                  )
                : FutureBuilder<SympathyLeaderboardSnapshotDto>(
                    future: _sympathyFuture,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (snap.hasError || !snap.hasData) {
                        return _ErrorState(onRetry: _reloadSympathy);
                      }
                      return _SympathyBody(snapshot: snap.data!);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// =======================
// Закладка-таб
// =======================

class _TabButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool isActive;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.color,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(vertical: isActive ? 11 : 7),
        margin: EdgeInsets.only(top: isActive ? 0 : 10),
        decoration: BoxDecoration(
          color: isActive
              ? color.withValues(alpha: 0.7)
              : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: isActive
              ? Border.all(color: color.withValues(alpha: 0.5), width: 1)
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: isActive ? 14 : 13,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive
                ? Colors.white
                : color.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}

// =======================
// Тело: Активность (Токены + Активность)
// =======================

class _ActivityBody extends StatelessWidget {
  final LeaderboardSnapshotDto snapshot;

  const _ActivityBody({required this.snapshot});

  String _fmt(int score) {
    if (score >= 10000) return '${(score / 1000).toStringAsFixed(0)}k';
    return '$score';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _ColumnCard(
                      title: 'Токены',
                      subtitle:
                          'Рейтинг по количеству заработанных токенов.',
                      icon: Icons.monetization_on_outlined,
                      accentColor: const Color(0xFFFFD700),
                      column: snapshot.tokens,
                      scoreLabel: _fmt,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ColumnCard(
                      title: 'Активность',
                      subtitle:
                          'Рейтинг по количеству завершенных планов.',
                      icon: Icons.local_fire_department_outlined,
                      accentColor: _kActivityColor,
                      column: snapshot.activity,
                      scoreLabel: _fmt,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Expanded(
            flex: 1,
            child: Center(child: SpinningLogo()),
          ),
        ],
      ),
    );
  }
}

// =======================
// Тело: Симпатии (Получено + Отправлено)
// =======================

class _SympathyBody extends StatelessWidget {
  final SympathyLeaderboardSnapshotDto snapshot;

  const _SympathyBody({required this.snapshot});

  String _fmt(int score) {
    if (score >= 10000) return '${(score / 1000).toStringAsFixed(0)}k';
    return '$score';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _ColumnCard(
                      title: 'Получено',
                      subtitle:
                          'Рейтинг полученных знаков симпатии.',
                      icon: Icons.favorite_outline,
                      accentColor: _kSympathyColor,
                      column: snapshot.received,
                      scoreLabel: _fmt,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ColumnCard(
                      title: 'Отправлено',
                      subtitle:
                          'Рейтинг отправленных знаков симпатии.',
                      icon: Icons.send_outlined,
                      accentColor: const Color(0xFF42A5F5),
                      column: snapshot.sent,
                      scoreLabel: _fmt,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Expanded(
            flex: 1,
            child: Center(child: SpinningLogo()),
          ),
        ],
      ),
    );
  }
}

// =======================
// Карточка-колонка с обводкой
// =======================

class _ColumnCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final LeaderboardColumnDto column;
  final String Function(int) scoreLabel;

  const _ColumnCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.column,
    required this.scoreLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final entries = column.top10;
    final myEntry = column.myEntry;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: colors.surface,
        border: Border.all(
          color: accentColor.withValues(alpha: 0.22),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Шапка ──
          Container(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
            decoration: BoxDecoration(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              color: accentColor.withValues(alpha: 0.08),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(width: 4),
                    Icon(icon, size: 17, color: accentColor),
                    const SizedBox(width: 6),
                    Text(
                      title,
                      style: text.bodySmall?.copyWith(
                        color: accentColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(width: 17),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(
                    color: accentColor.withValues(alpha: 0.65),
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: accentColor.withValues(alpha: 0.12),
          ),

          // ── Список ──
          if (entries.isEmpty)
            Expanded(
                child: Center(child: _EmptyColumn(accentColor: accentColor)))
          else
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                child: Column(
                  children: [
                    ...List.generate(
                      entries.length,
                      (i) => Expanded(
                        child: _EntryRow(
                          entry: entries[i],
                          scoreLabel: scoreLabel,
                          accentColor: accentColor,
                          showDivider: i < entries.length - 1,
                        ),
                      ),
                    ),
                    if (myEntry != null) ...[
                      const SizedBox(height: 6),
                      _MyEntryBlock(
                        entry: myEntry,
                        scoreLabel: scoreLabel,
                        accentColor: accentColor,
                      ),
                      const SizedBox(height: 2),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// =======================
// Строка участника
// =======================

class _EntryRow extends StatelessWidget {
  final LeaderboardEntryDto entry;
  final String Function(int) scoreLabel;
  final Color accentColor;
  final bool showDivider;

  const _EntryRow({
    required this.entry,
    required this.scoreLabel,
    required this.accentColor,
    this.showDivider = false,
  });

  Color _medalColor(int place) {
    switch (place) {
      case 1:
        return _kGold;
      case 2:
        return _kSilver;
      case 3:
        return _kBronze;
      default:
        return Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final place = entry.place;
    final isTop3 = place <= 3;
    final medalColor = _medalColor(place);

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Место / медаль
              SizedBox(
                width: 22,
                child: isTop3
                    ? Icon(
                        Icons.workspace_premium,
                        size: 18,
                        color: medalColor,
                      )
                    : Text(
                        '$place',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colors.onSurface.withValues(alpha: 0.35),
                        ),
                      ),
              ),
              const SizedBox(width: 4),

              // Аватар
              SizedBox(
                width: 28,
                height: 28,
                child: _MiniAvatar(
                  url: entry.avatarUrl,
                  size: 28,
                  borderColor: isTop3
                      ? medalColor.withValues(alpha: 0.6)
                      : colors.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              const SizedBox(width: 6),

              // Ник + город — FittedBox чтобы автомасштабировалось под высоту
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.nickname.isNotEmpty
                            ? entry.nickname
                            : 'Пользователь',
                        style: text.bodySmall?.copyWith(
                          fontSize: 13,
                          fontWeight:
                              isTop3 ? FontWeight.w700 : FontWeight.w400,
                          color: isTop3
                              ? medalColor
                              : colors.onSurface.withValues(alpha: 0.9),
                          height: 1.05,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      if (entry.city != null && entry.city!.isNotEmpty)
                        Text(
                          entry.city!,
                          style: text.bodySmall?.copyWith(
                            fontSize: 10,
                            color: colors.onSurface.withValues(alpha: 0.35),
                            height: 1.0,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                    ],
                  ),
                ),
              ),

              // Счёт
              Text(
                entry.score > 0 ? scoreLabel(entry.score) : '—',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isTop3
                      ? medalColor
                      : colors.onSurface.withValues(alpha: 0.65),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 0.5,
            color: colors.outlineVariant.withValues(alpha: 0.15),
          ),
      ],
    );
  }
}

// =======================
// Мини-аватар
// =======================

class _MiniAvatar extends StatelessWidget {
  final String? url;
  final double size;
  final Color borderColor;

  const _MiniAvatar({
    this.url,
    required this.size,
    this.borderColor = Colors.transparent,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasBorder = borderColor != Colors.transparent;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        border: hasBorder ? Border.all(color: borderColor, width: 1.5) : null,
        color: colors.surfaceContainerHighest,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(hasBorder ? 5.5 : 7),
        child: _content(colors),
      ),
    );
  }

  Widget _content(ColorScheme colors) {
    if (url != null && url!.isNotEmpty) {
      return Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.person_outline, size: size * 0.5, color: colors.outline),
      );
    }
    return Icon(Icons.person_outline, size: size * 0.5, color: colors.outline);
  }
}

// =======================
// Блок "Ваше место"
// =======================

class _MyEntryBlock extends StatelessWidget {
  final LeaderboardEntryDto entry;
  final String Function(int) scoreLabel;
  final Color accentColor;

  const _MyEntryBlock({
    required this.entry,
    required this.scoreLabel,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: accentColor.withValues(alpha: 0.07),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              color: accentColor.withValues(alpha: 0.15),
            ),
            child: Text(
              'Вы',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: accentColor,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '#${entry.place}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: accentColor,
            ),
          ),
          const SizedBox(width: 7),
          _MiniAvatar(
            url: entry.avatarUrl,
            size: 26,
            borderColor: accentColor.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 7),
          const Spacer(),
          Text(
            entry.score > 0 ? scoreLabel(entry.score) : '—',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: accentColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// =======================
// Пустая колонка
// =======================

class _EmptyColumn extends StatelessWidget {
  final Color accentColor;

  const _EmptyColumn({required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          'Нет данных',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: accentColor.withValues(alpha: 0.3),
              ),
        ),
      ),
    );
  }
}

// =======================
// Ошибка
// =======================

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Не удалось загрузить рейтинг',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('Повторить')),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

class PlanChatAvatar extends StatelessWidget {
  final String userId;
  final String nickname;
  final double size;

  const PlanChatAvatar({
    super.key,
    required this.userId,
    required this.nickname,
    this.size = 38,
  });

  static const List<Color> _palette = <Color>[
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFF0891B2),
    Color(0xFF0F766E),
    Color(0xFF15803D),
    Color(0xFFB45309),
    Color(0xFFBE123C),
    Color(0xFF4F46E5),
    Color(0xFF9333EA),
    Color(0xFF1D4ED8),
    Color(0xFF047857),
    Color(0xFFC2410C),
  ];

  String get _initial {
    final trimmed = nickname.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.substring(0, 1).toUpperCase();
  }

  Color _backgroundColor() {
    final source = userId.trim().isEmpty ? nickname.trim() : userId.trim();
    final hash = source.hashCode.abs();
    return _palette[hash % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _backgroundColor(),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _initial,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

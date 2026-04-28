import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'leisure_constants.dart';

class LeisureEditScreen extends StatefulWidget {
  final List<String> restPreferences;
  final List<String> restDislikes;
  final String? socialFormat;
  final String? restTempo;
  final List<String> meetingTimePreferences;
  final String? vibe;
  final String? shortBio;

  const LeisureEditScreen({
    super.key,
    required this.restPreferences,
    required this.restDislikes,
    this.socialFormat,
    this.restTempo,
    required this.meetingTimePreferences,
    this.vibe,
    this.shortBio,
  });

  @override
  State<LeisureEditScreen> createState() => _LeisureEditScreenState();
}

class _LeisureEditScreenState extends State<LeisureEditScreen> {
  late List<String> _restPreferences;
  late List<String> _restDislikes;
  String? _socialFormat;
  String? _restTempo;
  late List<String> _meetingTimePreferences;
  String? _vibe;
  late TextEditingController _bioCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _restPreferences = List.from(widget.restPreferences);
    _restDislikes = List.from(widget.restDislikes);
    _socialFormat = widget.socialFormat;
    _restTempo = widget.restTempo;
    _meetingTimePreferences = List.from(widget.meetingTimePreferences);
    _vibe = widget.vibe;
    _bioCtrl = TextEditingController(text: widget.shortBio ?? '');
  }

  @override
  void dispose() {
    _bioCtrl.dispose();
    super.dispose();
  }

  void _toggleMulti(List<String> list, String key, int maxCount) {
    setState(() {
      if (list.contains(key)) {
        list.remove(key);
      } else if (list.length < maxCount) {
        list.add(key);
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final bio = _bioCtrl.text.trim();
      await Supabase.instance.client.rpc('set_profile_leisure', params: {
        'p_rest_preferences': _restPreferences,
        'p_rest_dislikes': _restDislikes,
        'p_social_format': _socialFormat,
        'p_rest_tempo': _restTempo,
        'p_meeting_time_preferences': _meetingTimePreferences,
        'p_vibe': _vibe,
        'p_short_bio': bio.isEmpty ? null : bio,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Стиль отдыха'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Сохранить'),
            ),
          ),
        ],
      ),
      body: ListView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
        children: [
          _buildMultiSection(
            title: 'Как люблю отдыхать',
            maxCount: 3,
            options: LeisureConstants.restPreferences,
            selected: _restPreferences,
            onToggle: (key) => _toggleMulti(_restPreferences, key, 3),
          ),
          const SizedBox(height: 28),
          _buildMultiSection(
            title: 'Что не люблю',
            maxCount: 3,
            options: LeisureConstants.restDislikes,
            selected: _restDislikes,
            onToggle: (key) => _toggleMulti(_restDislikes, key, 3),
          ),
          const SizedBox(height: 28),
          _buildSingleSection(
            title: 'Комфортный формат компании',
            options: LeisureConstants.socialFormats,
            selected: _socialFormat,
            onSelect: (key) =>
                setState(() => _socialFormat = _socialFormat == key ? null : key),
          ),
          const SizedBox(height: 28),
          _buildSingleSection(
            title: 'Темп отдыха',
            options: LeisureConstants.restTempos,
            selected: _restTempo,
            onSelect: (key) =>
                setState(() => _restTempo = _restTempo == key ? null : key),
          ),
          const SizedBox(height: 28),
          _buildMultiSection(
            title: 'Когда удобнее встречаться',
            maxCount: 2,
            options: LeisureConstants.meetingTimes,
            selected: _meetingTimePreferences,
            onToggle: (key) => _toggleMulti(_meetingTimePreferences, key, 2),
          ),
          const SizedBox(height: 28),
          _buildSingleSection(
            title: 'Мой вайб',
            options: LeisureConstants.vibes,
            selected: _vibe,
            onSelect: (key) =>
                setState(() => _vibe = _vibe == key ? null : key),
          ),
          const SizedBox(height: 28),
          _buildBioSection(),
        ],
      ),
    );
  }

  Widget _buildMultiSection({
    required String title,
    required int maxCount,
    required List<LeisureOption> options,
    required List<String> selected,
    required void Function(String) onToggle,
  }) {
    final atLimit = selected.length >= maxCount;
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              'до $maxCount',
              style: textTheme.bodySmall?.copyWith(
                color: atLimit ? colors.primary : colors.outline,
                fontWeight: atLimit ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...options.map((opt) {
          final isSelected = selected.contains(opt.key);
          final isDisabled = atLimit && !isSelected;
          return _OptionTile(
            option: opt,
            isSelected: isSelected,
            isDisabled: isDisabled,
            onTap: isDisabled ? null : () => onToggle(opt.key),
          );
        }),
      ],
    );
  }

  Widget _buildSingleSection({
    required String title,
    required List<LeisureOption> options,
    required String? selected,
    required void Function(String) onSelect,
  }) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ...options.map((opt) => _OptionTile(
              option: opt,
              isSelected: selected == opt.key,
              isDisabled: false,
              onTap: () => onSelect(opt.key),
            )),
      ],
    );
  }

  Widget _buildBioSection() {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final len = _bioCtrl.text.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Коротко о себе',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _bioCtrl,
          maxLength: 160,
          maxLines: 3,
          minLines: 2,
          decoration: const InputDecoration(
            hintText: 'Например: люблю спокойные бары, вечерние прогулки и людей без лишнего пафоса',
            border: OutlineInputBorder(),
            counterText: '',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '$len / 160',
            style: textTheme.bodySmall?.copyWith(color: colors.outline),
          ),
        ),
      ],
    );
  }
}

// =======================
// Option tile widget
// =======================

class _OptionTile extends StatelessWidget {
  final LeisureOption option;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback? onTap;

  const _OptionTile({
    required this.option,
    required this.isSelected,
    required this.isDisabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Opacity(
      opacity: isDisabled ? 0.4 : 1.0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          child: Row(
            children: [
              TwemojiIcon(assetPath: option.assetPath, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(option.label, style: textTheme.bodyMedium),
                    if (option.subLabel.isNotEmpty)
                      Text(
                        option.subLabel,
                        style: textTheme.bodySmall
                            ?.copyWith(color: colors.outline),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                size: 20,
                color: isSelected ? colors.primary : colors.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

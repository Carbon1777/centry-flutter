import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppVersionLabel extends StatefulWidget {
  const AppVersionLabel({super.key});

  @override
  State<AppVersionLabel> createState() => _AppVersionLabelState();
}

class _AppVersionLabelState extends State<AppVersionLabel> {
  late final Future<String?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<String?> _load() async {
    try {
      final data = await Supabase.instance.client
          .rpc('get_app_version_v1') as Map<String, dynamic>?;
      if (data == null) return null;
      final phase = data['phase'] as String? ?? '';
      final version = data['version'] as String? ?? '';
      final build = data['build'] as int? ?? 0;
      return '$phase $version.$build';
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _future,
      builder: (context, snapshot) {
        final label = snapshot.data;
        if (label == null) return const SizedBox.shrink();
        return Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.3),
                ),
          ),
        );
      },
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'email_screen.dart';

enum _PermissionStep {
  intro,
  location,
  notifications,
}

class PermissionsScreen extends StatefulWidget {
  final Map<String, dynamic> bootstrapResult;
  final void Function(Map<String, dynamic> result) onDone;

  const PermissionsScreen({
    super.key,
    required this.bootstrapResult,
    required this.onDone,
  });

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  PermissionStatus? _locationStatus;
  PermissionStatus? _notificationStatus;

  bool _loading = false;
  _PermissionStep _step = _PermissionStep.intro;

  Timer? _introTimer;

  @override
  void initState() {
    super.initState();

    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _next();
      });
      return;
    }

    _refreshStatuses();

    _introTimer = Timer(const Duration(milliseconds: 4500), () {
      if (!mounted) return;
      setState(() {
        _step = _PermissionStep.location;
      });
    });
  }

  @override
  void dispose() {
    _introTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshStatuses() async {
    final loc = await Permission.location.status;
    final noti = await Permission.notification.status;
    if (!mounted) return;

    setState(() {
      _locationStatus = loc;
      _notificationStatus = noti;
    });
  }

  Future<void> _requestPermission(
    Permission permission,
    void Function(PermissionStatus) saveStatus,
  ) async {
    if (_loading) return;

    setState(() => _loading = true);

    final result = await permission.request();
    if (!mounted) return;

    setState(() {
      saveStatus(result);
      _loading = false;
    });

    _goNextStep();
  }

  void _skip() {
    _goNextStep();
  }

  void _goNextStep() {
    if (!mounted) return;

    setState(() {
      if (_step == _PermissionStep.location) {
        _step = _PermissionStep.notifications;
      } else {
        _next();
      }
    });
  }

  void _next() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => EmailScreen(
          bootstrapResult: widget.bootstrapResult,
          onDone: widget.onDone,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final _ = _locationStatus?.isGranted == true ||
        _notificationStatus?.isGranted == true;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            children: [
              Expanded(
                child: Align(
                  alignment: const Alignment(0, -0.25),
                  child: _buildContent(context),
                ),
              ),
              _buildSkip(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (_step) {
      case _PermissionStep.intro:
        return const _IntroText();

      case _PermissionStep.location:
        return _PermissionCard(
          title: 'Геопозиция',
          description:
              'Ваша локация нужна, чтобы подбирать события, места и интересные активности рядом с вами.',
          actionLabel: 'Разрешить',
          loading: _loading,
          onAction: () => _requestPermission(
            Permission.location,
            (s) => _locationStatus = s,
          ),
        );

      case _PermissionStep.notifications:
        return _PermissionCard(
          title: 'Уведомления',
          description:
              'Разрешение на уведомления нужно, чтобы вовремя сообщать об интересных событиях, ивентах, приглашениях и активности ваших друзей.',
          actionLabel: 'Разрешить',
          loading: _loading,
          onAction: () => _requestPermission(
            Permission.notification,
            (s) => _notificationStatus = s,
          ),
        );
    }
  }

  Widget _buildSkip() {
    if (_step == _PermissionStep.intro) {
      return const SizedBox.shrink();
    }

    return Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _skip,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            'Пропустить',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
        ),
      ),
    );
  }
}

class _IntroText extends StatelessWidget {
  const _IntroText();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        SizedBox(height: 40),
        Text(
          'Для полноценной работы всех фукций приложения\n'
          'нам необходимы ваши разрешения',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final String title;
  final String description;
  final String actionLabel;
  final bool loading;
  final VoidCallback onAction;

  const _PermissionCard({
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.loading,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 40),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          description,
          style: TextStyle(
            fontSize: 15,
            color: colors.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: loading ? null : onAction,
            child: Text(actionLabel),
          ),
        ),
      ],
    );
  }
}

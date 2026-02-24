import 'dart:async';
import 'package:flutter/material.dart';

Future<void> showCenterToast(
  BuildContext context, {
  required String message,
  bool isError = false,
  Duration duration = const Duration(seconds: 2),
}) async {
  final rootNav = Navigator.maybeOf(context, rootNavigator: true);
  if (rootNav == null) return;

  final timer = Timer(duration, () {
    if (rootNav.canPop()) rootNav.pop();
  });

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'toast',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (ctx, anim1, anim2) {
      final theme = Theme.of(ctx);

      final bg = isError ? const Color(0xFF2A1212) : const Color(0xFF14161A);
      final border =
          isError ? const Color(0xFF5C2A2A) : const Color(0xFF2A2E36);
      final icon = isError ? Icons.error_outline : Icons.check_circle_outline;
      final iconColor =
          isError ? const Color(0xFFFF6B6B) : const Color(0xFF7EE787);

      return SafeArea(
        child: Center(
          child: Material(
            type: MaterialType.transparency,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border, width: 1),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 18,
                      offset: Offset(0, 10),
                      color: Color(0x66000000),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: iconColor, size: 20),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        message,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFE6EAF2),
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim, secAnim, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  ).whenComplete(() {
    if (timer.isActive) timer.cancel();
  });
}

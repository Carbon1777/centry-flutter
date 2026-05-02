// Apple Guideline 1.2 (Safety / UGC) — универсальный bottom-sheet «Заблокировать пользователя».
// Используется на чужом профиле, в чате плана, приватном чате, друзьях.
// См. /TZ_apple_ugc_compliance.md разделы 3.2, 3.3.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/blocks/blocks_repository_impl.dart';
import 'center_toast.dart';

class BlockUserSheet {
  BlockUserSheet._();

  /// Показывает подтверждение и блокирует юзера.
  ///
  /// [appUserId] — текущий юзер (блокирующий).
  /// [targetUserId] — кого блокируем.
  /// [targetNickname] — для отображения в заголовке. Если null/пусто — будет «этого пользователя».
  /// Возвращает `true` при успешной блокировке.
  static Future<bool> show(
    BuildContext context, {
    required String appUserId,
    required String targetUserId,
    String? targetNickname,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _BlockSheet(
        appUserId: appUserId,
        targetUserId: targetUserId,
        targetNickname: targetNickname,
      ),
    );
    return result == true;
  }
}

class _BlockSheet extends StatefulWidget {
  final String appUserId;
  final String targetUserId;
  final String? targetNickname;

  const _BlockSheet({
    required this.appUserId,
    required this.targetUserId,
    this.targetNickname,
  });

  @override
  State<_BlockSheet> createState() => _BlockSheetState();
}

class _BlockSheetState extends State<_BlockSheet> {
  late final _repo = BlocksRepositoryImpl(Supabase.instance.client);
  bool _busy = false;

  Future<void> _block() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final result = await _repo.blockUser(
        appUserId: widget.appUserId,
        targetUserId: widget.targetUserId,
      );

      if (!mounted) return;

      if (result.isSuccess) {
        Navigator.of(context).pop(true);
        await showCenterToast(
          context,
          message: 'Пользователь заблокирован',
        );
        return;
      }

      setState(() => _busy = false);
      await showCenterToast(
        context,
        message: result.error ?? 'Не удалось заблокировать',
        isError: true,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      await showCenterToast(
        context,
        message: 'Нет связи с сервером',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final nick = (widget.targetNickname ?? '').trim();
    final title = nick.isEmpty
        ? 'Заблокировать этого пользователя?'
        : 'Заблокировать $nick?';

    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF14161A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3F4A),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFE6EAF2),
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Вы перестанете видеть этого пользователя — его профиль, сообщения, фото и планы. '
              'Он не сможет связаться с вами или видеть ваш контент.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF8B92A0),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _busy ? null : _block,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE74C3C),
                  disabledBackgroundColor: const Color(0xFF2A2E36),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: const Color(0xFF6B7280),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation(Color(0xFFE6EAF2)),
                        ),
                      )
                    : const Text(
                        'Заблокировать',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: TextButton(
                onPressed:
                    _busy ? null : () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFE6EAF2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Отмена',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

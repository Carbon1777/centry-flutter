import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

/// Экран с видео-интро, показывается один раз при первом запуске.
class IntroVideoScreen extends StatefulWidget {
  final VoidCallback onDone;

  const IntroVideoScreen({super.key, required this.onDone});

  /// Ключ в SharedPreferences для отметки «видео уже показано».
  static const _kSeenKey = 'intro_video_seen';

  /// Проверяет, нужно ли показывать видео (ещё не видел).
  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_kSeenKey) ?? false);
  }

  /// Помечает видео как просмотренное.
  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSeenKey, true);
  }

  @override
  State<IntroVideoScreen> createState() => _IntroVideoScreenState();
}

class _IntroVideoScreenState extends State<IntroVideoScreen> {
  static const _videoUrl =
      'https://lqgzvolirohuettizkhx.supabase.co/storage/v1/object/public/brand-media/intro.mp4';

  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(_videoUrl))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _initialized = true);
        _controller.play();
      }).catchError((_) {
        if (!mounted) return;
        setState(() => _hasError = true);
      });

    _controller.addListener(_onVideoEnd);
  }

  void _onVideoEnd() {
    if (_controller.value.isCompleted) {
      _skip();
    }
  }

  Future<void> _skip() async {
    await IntroVideoScreen.markSeen();
    if (!mounted) return;
    widget.onDone();
  }

  @override
  void dispose() {
    _controller.removeListener(_onVideoEnd);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // --- Видео / загрузка / ошибка ---
          if (_hasError)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline,
                      color: Colors.white.withValues(alpha: 0.5), size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Не удалось загрузить видео',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            )
          else if (!_initialized)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          else
            Center(
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              ),
            ),

          // --- Кнопка «Пропустить» ---
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: SafeArea(
              top: false,
              child: TextButton(
                onPressed: _skip,
                style: TextButton.styleFrom(
                  backgroundColor: Colors.black45,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  'Пропустить',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

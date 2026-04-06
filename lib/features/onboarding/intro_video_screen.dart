import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

/// Экран с видео-интро, показывается один раз при первом запуске.
/// По окончании видео — автоматический переход к следующему шагу онбординга.
class IntroVideoScreen extends StatefulWidget {
  final VoidCallback onDone;

  const IntroVideoScreen({super.key, required this.onDone});

  static const _kSeenKey = 'intro_video_seen';

  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_kSeenKey) ?? false);
  }

  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSeenKey, true);
  }

  @override
  State<IntroVideoScreen> createState() => _IntroVideoScreenState();
}

class _IntroVideoScreenState extends State<IntroVideoScreen> {
  static const _videoUrl =
      'https://lqgzvolirohuettizkhx.supabase.co/storage/v1/object/public/brand-media/intro1.mp4';

  late final VideoPlayerController _controller;
  bool _done = false;
  bool _initialized = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    _controller = VideoPlayerController.networkUrl(Uri.parse(_videoUrl));

    _controller.addListener(_onVideoUpdate);

    try {
      await _controller.initialize().timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() => _initialized = true);
      await _controller.play();
    } catch (e) {
      debugPrint('IntroVideo: init error — $e');
      if (!mounted) return;
      // Если видео не загрузилось — пропускаем, не блокируем онбординг
      setState(() => _error = true);
      Future.delayed(const Duration(seconds: 2), _skip);
    }
  }

  void _onVideoUpdate() {
    if (_done || !_controller.value.isInitialized) return;

    // Автопереход по окончании видео
    final position = _controller.value.position;
    final duration = _controller.value.duration;
    if (duration > Duration.zero && position >= duration) {
      _skip();
    }
  }

  Future<void> _skip() async {
    if (_done) return;
    _done = true;
    await IntroVideoScreen.markSeen();
    if (!mounted) return;
    widget.onDone();
  }

  @override
  void dispose() {
    _controller.removeListener(_onVideoUpdate);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // --- Видео ---
          if (_initialized)
            Center(
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              ),
            )
          else if (_error)
            const Center(
              child: Text(
                'Не удалось загрузить видео',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white24),
            ),

          // --- Кнопка «Пропустить» ---
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 40,
            right: 0,
            left: 0,
            child: Center(
              child: TextButton(
                onPressed: _skip,
                style: TextButton.styleFrom(
                  backgroundColor: Colors.black45,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: Text(
                  'Пропустить',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
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

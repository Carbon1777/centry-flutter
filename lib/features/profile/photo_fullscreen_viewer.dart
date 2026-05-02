import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/profile_photos/profile_photo_dto.dart';
import '../../data/profile_photos/profile_photos_repository_impl.dart';
import '../../data/reports/report_dto.dart';
import '../../ui/common/center_toast.dart';
import '../../ui/common/report_content_sheet.dart';
import 'photo_crop_screen.dart';

/// Fullscreen просмотр фото альбома.
///
/// [isOwner] — если true, показываются кнопки «Кадрировать» и «Заменить» в AppBar.
/// [onPhotoReplaced] — вызывается после успешной замены/кадрирования фото,
/// чтобы родительская сетка перезагрузила данные с сервера.
class PhotoFullscreenViewer extends StatefulWidget {
  final List<ProfilePhotoDto> photos;
  final int initialIndex;
  final bool isOwner;
  final VoidCallback? onPhotoReplaced;

  const PhotoFullscreenViewer({
    super.key,
    required this.photos,
    required this.initialIndex,
    this.isOwner = false,
    this.onPhotoReplaced,
  });

  @override
  State<PhotoFullscreenViewer> createState() => _PhotoFullscreenViewerState();
}

class _PhotoFullscreenViewerState extends State<PhotoFullscreenViewer> {
  late final PageController _pageController;
  late List<ProfilePhotoDto> _photos;
  late int _currentIndex;

  final Map<int, TransformationController> _transformControllers = {};
  Offset _doubleTapLocalPosition = Offset.zero;
  bool _isProcessing = false;

  final _repo = ProfilePhotosRepositoryImpl();

  @override
  void initState() {
    super.initState();
    _photos = List.from(widget.photos);
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _transformControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TransformationController _controllerFor(int index) =>
      _transformControllers.putIfAbsent(index, TransformationController.new);

  void _resetZoom(int index) {
    _transformControllers[index]?.value = Matrix4.identity();
  }

  void _handleDoubleTap(int index) {
    final controller = _controllerFor(index);
    final isZoomed = controller.value != Matrix4.identity();
    if (isZoomed) {
      controller.value = Matrix4.identity();
    } else {
      const scale = 2.5;
      final tx = _doubleTapLocalPosition.dx * (1 - scale);
      final ty = _doubleTapLocalPosition.dy * (1 - scale);
      final matrix = Matrix4.diagonal3Values(scale, scale, 1.0);
      matrix.setTranslationRaw(tx, ty, 0.0);
      controller.value = matrix;
    }
  }

  void _goTo(int index) {
    _resetZoom(_currentIndex);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  // ── Кадрирование текущего фото ──

  Future<void> _cropCurrentPhoto() async {
    if (_isProcessing) return;

    final currentPhoto = _photos[_currentIndex];

    // Скачиваем байты текущего фото из storage
    setState(() => _isProcessing = true);
    late final Uint8List originalBytes;
    try {
      originalBytes = await Supabase.instance.client.storage
          .from('profile-photos')
          .download(currentPhoto.storageKey);
    } catch (_) {
      if (mounted) {
        showCenterToast(context, message: 'Не удалось загрузить фото', isError: true);
        setState(() => _isProcessing = false);
      }
      return;
    }
    setState(() => _isProcessing = false);

    if (!mounted) return;

    // Открываем кроп с уже загруженным фото
    final croppedBytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => PhotoCropScreen(imageBytes: originalBytes)),
    );
    if (croppedBytes == null || !mounted) return;

    await _uploadProcessedPhoto(croppedBytes);
  }

  // ── Замена фото (выбор нового из галереи) ──

  Future<void> _replaceCurrentPhoto() async {
    if (_isProcessing) return;

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
    );
    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    // Кроп (опционально, пользователь может отменить)
    final croppedBytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => PhotoCropScreen(imageBytes: bytes)),
    );
    if (croppedBytes == null || !mounted) return;

    await _uploadProcessedPhoto(croppedBytes);
  }

  // ── Общая логика: сжать → загрузить → обновить запись → удалить старый файл ──

  Future<void> _uploadProcessedPhoto(Uint8List croppedBytes) async {
    setState(() => _isProcessing = true);
    try {
      final client = Supabase.instance.client;
      final authUserId = client.auth.currentUser?.id;
      if (authUserId == null) return;

      // Сжимаем в WebP
      final webpBytes = await FlutterImageCompress.compressWithList(
        croppedBytes,
        minWidth: 1920,
        minHeight: 1920,
        quality: 88,
        format: CompressFormat.webp,
        keepExif: false,
      );

      final currentPhoto = _photos[_currentIndex];
      final oldStorageKey = currentPhoto.storageKey;
      final newStoragePath = '$authUserId/${_generateUuid()}.webp';

      // Загружаем новый файл в storage
      await client.storage.from('profile-photos').uploadBinary(
        newStoragePath,
        webpBytes,
        fileOptions: const FileOptions(contentType: 'image/webp'),
      );

      // Обновляем запись в БД
      final updated = await _repo.updatePhoto(
        photoId: currentPhoto.id,
        newStorageKey: newStoragePath,
        oldStorageKey: oldStorageKey,
        sizeBytes: webpBytes.length,
      );

      // Удаляем старый файл из storage на клиенте
      client.storage.from('profile-photos').remove([oldStorageKey]).ignore();

      if (!mounted) return;

      // Обновляем локальный список в viewer
      setState(() {
        _photos = List.from(_photos)..[_currentIndex] = updated;
      });

      // Сбрасываем зум для этой страницы
      _resetZoom(_currentIndex);

      // Уведомляем родительскую сетку
      widget.onPhotoReplaced?.call();

      showCenterToast(context, message: 'Фото обновлено');
    } catch (_) {
      if (mounted) {
        showCenterToast(context, message: 'Ошибка обновления фото', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Apple Guideline 1.2: Жалоба на чужое фото ──

  Future<void> _reportCurrentPhoto() async {
    if (_photos.isEmpty) return;
    final photo = _photos[_currentIndex];
    await ReportContentSheet.show(
      context,
      targetType: ReportTargetType.photo,
      targetId: photo.id,
      targetTypeLabel: 'на фото',
    );
  }

  static String _generateUuid() {
    final rng = Random.secure();
    final b = List<int>.generate(16, (_) => rng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}'
        '-${h.substring(16, 20)}-${h.substring(20)}';
  }

  @override
  Widget build(BuildContext context) {
    final hasPrev = _currentIndex > 0;
    final hasNext = _currentIndex < _photos.length - 1;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          title: _photos.length > 1
              ? Text(
                  '${_currentIndex + 1} / ${_photos.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                )
              : null,
          actions: [
            if (widget.isOwner)
              _isProcessing
                  ? const Padding(
                      padding: EdgeInsets.only(right: 16),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.crop_outlined),
                          tooltip: 'Кадрировать',
                          onPressed: _cropCurrentPhoto,
                        ),
                        IconButton(
                          icon: const Icon(Icons.sync_outlined),
                          tooltip: 'Заменить фото',
                          onPressed: _replaceCurrentPhoto,
                        ),
                      ],
                    )
            else
              // Apple Guideline 1.2: Report для чужих фото
              IconButton(
                icon: const Icon(Icons.flag_outlined),
                tooltip: 'Пожаловаться на фото',
                onPressed: _reportCurrentPhoto,
              ),
          ],
        ),
        body: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: _photos.length,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
              },
              itemBuilder: (context, index) {
                final photo = _photos[index];
                final transformController = _controllerFor(index);

                return GestureDetector(
                  onDoubleTapDown: (d) {
                    _doubleTapLocalPosition = d.localPosition;
                  },
                  onDoubleTap: () => _handleDoubleTap(index),
                  child: InteractiveViewer(
                    transformationController: transformController,
                    minScale: 1.0,
                    maxScale: 5.0,
                    clipBehavior: Clip.none,
                    child: Center(
                      child: CachedNetworkImage(
                        // key нужен чтобы сбросить кэш после замены/кадрирования
                        key: ValueKey(photo.storageKey),
                        imageUrl: photo.publicUrl,
                        fit: BoxFit.contain,
                        placeholder: (_, __) => const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white54,
                            strokeWidth: 2,
                          ),
                        ),
                        errorWidget: (_, __, ___) => const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white38,
                            size: 56,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            // Стрелка влево
            if (hasPrev)
              Positioned(
                left: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _NavArrow(
                    icon: Icons.chevron_left_rounded,
                    onTap: () => _goTo(_currentIndex - 1),
                  ),
                ),
              ),

            // Стрелка вправо
            if (hasNext)
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _NavArrow(
                    icon: Icons.chevron_right_rounded,
                    onTap: () => _goTo(_currentIndex + 1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _NavArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }
}

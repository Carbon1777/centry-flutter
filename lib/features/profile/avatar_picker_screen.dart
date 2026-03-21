import 'dart:async';
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AvatarPickerScreen extends StatefulWidget {
  const AvatarPickerScreen({super.key});

  @override
  State<AvatarPickerScreen> createState() => _AvatarPickerScreenState();
}

class _AvatarPickerScreenState extends State<AvatarPickerScreen> {
  late Future<List<_SystemAvatar>> _avatarsFuture;

  @override
  void initState() {
    super.initState();
    _avatarsFuture = _loadSystemAvatars();
  }

  Future<List<_SystemAvatar>> _loadSystemAvatars() async {
    final res =
        await Supabase.instance.client.rpc('get_system_avatars');

    if (res == null) return [];

    final list = res as List<dynamic>;
    return list
        .map((e) => _SystemAvatar(
              id: e['id'] as String,
              slug: e['slug'] as String,
              url: e['url'] as String,
            ))
        .toList();
  }

  Future<void> _selectSystemAvatar(_SystemAvatar avatar) async {
    try {
      await Supabase.instance.client.rpc('set_avatar', params: {
        'p_kind': 'system',
        'p_url': avatar.url,
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<void> _pickCustomPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked == null) return;
    if (!mounted) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    final navigator = Navigator.of(context);
    final result = await navigator.push<bool>(
      MaterialPageRoute(
        builder: (_) => _AvatarCropScreen(imageBytes: bytes),
      ),
    );

    if (result == true && mounted) {
      navigator.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Выбор аватара')),
      body: FutureBuilder<List<_SystemAvatar>>(
        future: _avatarsFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snap.hasError) {
            return Center(
              child: Text('Ошибка загрузки аватаров',
                  style: text.bodyMedium),
            );
          }

          final avatars = snap.data ?? [];

          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Загрузить своё фото
                OutlinedButton.icon(
                  onPressed: _pickCustomPhoto,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Загрузить своё фото'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),

                const SizedBox(height: 24),

                Text('Системные аватары', style: text.titleSmall),
                const SizedBox(height: 12),

                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: avatars.length,
                  itemBuilder: (context, index) {
                    final avatar = avatars[index];
                    return GestureDetector(
                      onTap: () => _selectSystemAvatar(avatar),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          avatar.url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: colors.surfaceContainerHighest,
                            child: Icon(Icons.broken_image_outlined,
                                color: colors.outline),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// =======================
// Crop screen
// =======================

class _AvatarCropScreen extends StatefulWidget {
  final Uint8List imageBytes;

  const _AvatarCropScreen({required this.imageBytes});

  @override
  State<_AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<_AvatarCropScreen> {
  final _cropController = CropController();
  bool _isSaving = false;

  Future<void> _confirmCrop() async {
    setState(() => _isSaving = true);
    _cropController.crop();
  }

  void _onCropped(CropResult result) {
    if (result is CropSuccess) {
      _uploadCroppedBytes(result.croppedImage);
    } else {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка кадрирования')),
      );
    }
  }

  Future<void> _uploadCroppedBytes(Uint8List croppedBytes) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw StateError('no auth user');

      final webpBytes = await FlutterImageCompress.compressWithList(
        croppedBytes,
        minWidth: 512,
        minHeight: 512,
        quality: 85,
        format: CompressFormat.webp,
      );

      final path = 'custom/$userId/avatar.webp';

      await client.storage.from('avatars').uploadBinary(
            path,
            webpBytes,
            fileOptions: const FileOptions(
              contentType: 'image/webp',
              upsert: true,
            ),
          );

      final url = client.storage.from('avatars').getPublicUrl(path);

      await client.rpc('set_avatar', params: {
        'p_kind': 'custom',
        'p_url': url,
      });

      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Ошибка сохранения: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Подгонка фото'),
        actions: [
          if (_isSaving)
            const Padding(
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
          else
            TextButton(
              onPressed: _confirmCrop,
              child: const Text(
                'Сохранить',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: Crop(
        image: widget.imageBytes,
        controller: _cropController,
        onCropped: _onCropped,
        aspectRatio: 1,
        withCircleUi: false,
        baseColor: Colors.black,
        maskColor: Colors.black.withValues(alpha: 0.6),
        cornerDotBuilder: (size, edgeAlignment) =>
            const DotControl(color: Colors.white),
      ),
    );
  }
}

// =======================
// Models
// =======================

class _SystemAvatar {
  final String id;
  final String slug;
  final String url;

  const _SystemAvatar({
    required this.id,
    required this.slug,
    required this.url,
  });
}

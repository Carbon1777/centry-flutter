import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

/// Экран кадрирования фото с произвольным aspect ratio.
/// Возвращает [Uint8List] обрезанных байт или null при отмене.
class PhotoCropScreen extends StatefulWidget {
  final Uint8List imageBytes;

  const PhotoCropScreen({super.key, required this.imageBytes});

  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends State<PhotoCropScreen> {
  final _cropController = CropController();
  bool _isSaving = false;

  void _onCrop() {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    _cropController.crop();
  }

  void _onCropped(CropResult result) {
    if (result is CropSuccess) {
      Navigator.of(context).pop(result.croppedImage);
    } else {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка кадрирования')),
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
        title: const Text('Кадрирование'),
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
              onPressed: _onCrop,
              child: const Text(
                'Готово',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: Crop(
        image: widget.imageBytes,
        controller: _cropController,
        onCropped: _onCropped,
        // Без aspectRatio — свободное кадрирование
        withCircleUi: false,
        baseColor: Colors.black,
        maskColor: Colors.black.withValues(alpha: 0.6),
        cornerDotBuilder: (size, edgeAlignment) =>
            const DotControl(color: Colors.white),
      ),
    );
  }
}

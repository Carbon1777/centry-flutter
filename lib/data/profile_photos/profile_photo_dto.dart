import 'package:supabase_flutter/supabase_flutter.dart';

class ProfilePhotoDto {
  final String id;
  final String storageKey;
  final int sortOrder;
  final String status;
  final int? width;
  final int? height;
  final int? sizeBytes;

  const ProfilePhotoDto({
    required this.id,
    required this.storageKey,
    required this.sortOrder,
    required this.status,
    this.width,
    this.height,
    this.sizeBytes,
  });

  factory ProfilePhotoDto.fromJson(Map<String, dynamic> json) {
    return ProfilePhotoDto(
      id: json['id'] as String,
      storageKey: json['storage_key'] as String,
      sortOrder: json['sort_order'] as int,
      status: json['status'] as String? ?? 'ready',
      width: json['width'] as int?,
      height: json['height'] as int?,
      sizeBytes: json['size_bytes'] as int?,
    );
  }

  String get publicUrl => Supabase.instance.client.storage
      .from('profile-photos')
      .getPublicUrl(storageKey);
}

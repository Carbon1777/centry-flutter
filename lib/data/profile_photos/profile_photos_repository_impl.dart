import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile_photo_dto.dart';
import 'profile_photos_repository.dart';

class ProfilePhotosRepositoryImpl implements ProfilePhotosRepository {
  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<List<ProfilePhotoDto>> getPhotos(String appUserId) async {
    final res = await _client.rpc(
      'get_profile_photos',
      params: {'p_target_user_id': appUserId},
    );
    if (res == null) return [];
    final list = res as List<dynamic>;
    return list
        .map((e) => ProfilePhotoDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<ProfilePhotoDto> addPhoto({
    required String storageKey,
    int? width,
    int? height,
    int? sizeBytes,
  }) async {
    final res = await _client.rpc(
      'add_profile_photo',
      params: {
        'p_storage_key': storageKey,
        if (width != null) 'p_width': width,
        if (height != null) 'p_height': height,
        if (sizeBytes != null) 'p_size_bytes': sizeBytes,
      },
    );
    return ProfilePhotoDto.fromJson(res as Map<String, dynamic>);
  }

  @override
  Future<ProfilePhotoDto> updatePhoto({
    required String photoId,
    required String newStorageKey,
    required String oldStorageKey,
    int? width,
    int? height,
    int? sizeBytes,
  }) async {
    final res = await _client.rpc(
      'update_profile_photo',
      params: {
        'p_photo_id': photoId,
        'p_new_storage_key': newStorageKey,
        'p_old_storage_key': oldStorageKey,
        if (width != null) 'p_width': width,
        if (height != null) 'p_height': height,
        if (sizeBytes != null) 'p_size_bytes': sizeBytes,
      },
    );
    return ProfilePhotoDto.fromJson(res as Map<String, dynamic>);
  }

  @override
  Future<void> reorderPhotos({required String idA, required String idB}) async {
    await _client.rpc(
      'reorder_profile_photos',
      params: {'p_id_a': idA, 'p_id_b': idB},
    );
  }

  @override
  Future<void> deletePhotos(List<String> photoIds) async {
    await _client.rpc(
      'delete_profile_photos',
      params: {'p_photo_ids': photoIds},
    );
  }
}

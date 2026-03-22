import 'profile_photo_dto.dart';

abstract class ProfilePhotosRepository {
  Future<List<ProfilePhotoDto>> getPhotos(String appUserId);
  Future<ProfilePhotoDto> addPhoto({
    required String storageKey,
    int? width,
    int? height,
    int? sizeBytes,
  });
  Future<ProfilePhotoDto> updatePhoto({
    required String photoId,
    required String newStorageKey,
    required String oldStorageKey,
    int? width,
    int? height,
    int? sizeBytes,
  });
  Future<void> reorderPhotos({required String idA, required String idB});
  Future<void> deletePhotos(List<String> photoIds);
}

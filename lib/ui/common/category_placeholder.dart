import 'package:supabase_flutter/supabase_flutter.dart';

/// Возвращает публичный URL плейсхолдера из Storage для категории места.
/// Если категория неизвестна — возвращает null (показывать generic asset).
///
/// Выбор изображения детерминированный: один и тот же placeId всегда
/// даёт одно и то же фото — чтобы при скролле и перерендерах не мигало.
String? categoryPlaceholderUrl(String category, String placeId) {
  final folder = _folderFor(category);
  if (folder == null) return null;

  final numbers = _numbersFor(folder);
  if (numbers.isEmpty) return null;

  final index = placeId.hashCode.abs() % numbers.length;
  final ext = _extFor(folder);
  final key = 'categories/$folder/${numbers[index]}.$ext';

  return Supabase.instance.client.storage
      .from('brand-media')
      .getPublicUrl(key);
}

String? _folderFor(String category) {
  switch (category) {
    case 'bar':        return 'bar';
    case 'restaurant': return 'restaurant';
    case 'nightclub':  return 'nightclub';
    case 'cinema':     return 'cinema';
    case 'theatre':    return 'theatre';
    case 'hookah':     return 'hookah';
    case 'karaoke':    return 'karaoke';
    case 'bathhouse':  return 'banya_sauna';
    default:           return null;
  }
}

String _extFor(String folder) {
  switch (folder) {
    case 'hookah':
    case 'karaoke':
    case 'banya_sauna':
      return 'jpg';
    default:
      return 'webp';
  }
}

List<int> _numbersFor(String folder) {
  switch (folder) {
    case 'bar':
      return List.generate(32, (i) => i + 1);
    case 'restaurant':
      // Присутствуют 1-38, отсутствует 8
      return [1,2,3,4,5,6,7,9,10,11,12,13,14,15,16,17,18,19,20,
              21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38];
    case 'nightclub':
      // Присутствуют 1-20, отсутствует 14
      return [1,2,3,4,5,6,7,8,9,10,11,12,13,15,16,17,18,19,20];
    case 'cinema':
      return List.generate(15, (i) => i + 1);
    case 'theatre':
      return List.generate(20, (i) => i + 1);
    case 'hookah':     return [2];
    case 'karaoke':    return [1];
    case 'banya_sauna': return [3];
    default:           return [];
  }
}

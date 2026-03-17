class LegalDocumentDto {
  final String id;
  final String documentType; // 'TERMS' | 'PRIVACY' | 'BONUS_RULES'
  final String version;
  final String title;
  final String content;
  final DateTime publishedAt;

  const LegalDocumentDto({
    required this.id,
    required this.documentType,
    required this.version,
    required this.title,
    required this.content,
    required this.publishedAt,
  });

  factory LegalDocumentDto.fromJson(Map<String, dynamic> json) {
    return LegalDocumentDto(
      id:           json['id'] as String,
      documentType: json['document_type'] as String,
      version:      json['version'] as String,
      title:        json['title'] as String,
      content:      json['content'] as String,
      publishedAt:  DateTime.parse(json['published_at'] as String),
    );
  }
}

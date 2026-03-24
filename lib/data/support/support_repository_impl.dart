import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'support_dto.dart';
import 'support_repository.dart';

class SupportRepositoryImpl implements SupportRepository {
  final SupabaseClient _client;

  SupportRepositoryImpl(this._client);

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw Exception('Expected map response, got: $value');
  }

  @override
  Future<CreateSessionResultDto> createSession(
      {required String direction}) async {
    final response = await _client.rpc(
      'create_support_session_v1',
      params: {'p_direction': direction},
    );
    return CreateSessionResultDto.fromJson(_asMap(response));
  }

  @override
  Future<SupportSessionDetailDto> getSession(
      {required String sessionId}) async {
    final response = await _client.rpc(
      'get_support_session_v1',
      params: {'p_session_id': sessionId},
    );
    return SupportSessionDetailDto.fromJson(_asMap(response));
  }

  @override
  Future<SendQuestionResultDto> sendQuestion({
    required String sessionId,
    required String messageText,
  }) async {
    final response = await _client.functions.invoke(
      'support-send-question',
      body: {
        'session_id': sessionId,
        'message_text': messageText,
      },
    );

    if (response.status != 200) {
      final errorBody = response.data;
      final errorMsg = errorBody is Map
          ? errorBody['error'] ?? 'Unknown error'
          : 'Server error (${response.status})';
      throw Exception(errorMsg);
    }

    final data = response.data is Map<String, dynamic>
        ? response.data as Map<String, dynamic>
        : jsonDecode(response.data as String) as Map<String, dynamic>;

    return SendQuestionResultDto.fromJson(data);
  }

  @override
  Future<SubmitFormResultDto> submitSuggestion({
    required String sessionId,
    required String text,
  }) async {
    final response = await _client.rpc(
      'submit_support_suggestion_v1',
      params: {
        'p_session_id': sessionId,
        'p_text': text,
      },
    );
    return SubmitFormResultDto.fromJson(_asMap(response));
  }

  @override
  Future<SubmitFormResultDto> submitComplaint({
    required String sessionId,
    required String text,
  }) async {
    final response = await _client.rpc(
      'submit_support_complaint_v1',
      params: {
        'p_session_id': sessionId,
        'p_text': text,
      },
    );
    return SubmitFormResultDto.fromJson(_asMap(response));
  }
}

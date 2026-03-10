import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/plans/plan_details_dto.dart';
import '../../data/plans/plans_repository.dart';
import '../../data/places/places_repository_impl.dart';
import '../../features/places/add_place/add_place_dialog.dart';
import '../../features/places/details/place_details_dialog.dart';
import '../../features/places/my_places_screen.dart';
import '../common/center_toast.dart';
import '../places/places_screen.dart';
import 'plan_members_modal.dart';
import 'widgets/add_place_source_modal.dart';
import 'widgets/plan_chat_block.dart';
import 'widgets/plan_dates_block.dart';
import 'widgets/plan_formatters.dart';
import 'widgets/plan_places_block.dart';

class PlanDetailsScreen extends StatefulWidget {
  final String appUserId;
  final String planId;
  final PlansRepository repository;

  const PlanDetailsScreen({
    super.key,
    required this.appUserId,
    required this.planId,
    required this.repository,
  });

  @override
  State<PlanDetailsScreen> createState() => _PlanDetailsScreenState();
}

class _PlanDetailsScreenState extends State<PlanDetailsScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _actionLoading = false;
  bool _visibilityLoading = false;

  PlanDetailsDto? _details;
  String? _error;

  static const Duration _liveRefreshInterval = Duration(seconds: 10);
  Timer? _liveRefreshTimer;
  bool _liveRefreshInFlight = false;

  String _humanizeError(Object e) {
    return _userMessageForError(e);
  }

  bool _canEditTitle(dynamic plan) {
    try {
      return plan.canEditTitle == true;
    } catch (_) {
      return false;
    }
  }

  bool _canEditDescription(dynamic plan) {
    try {
      return plan.canEditDescription == true;
    } catch (_) {
      return false;
    }
  }

  bool _canEditDeadline(dynamic plan) {
    try {
      return plan.canEditDeadline == true;
    } catch (_) {
      return false;
    }
  }

  bool _canUpdateVisibility(dynamic plan) {
    try {
      return plan.canUpdateVisibility == true;
    } catch (_) {
      return false;
    }
  }

  bool _canDeletePlan(dynamic plan) {
    try {
      return plan.canDeletePlan == true;
    } catch (_) {
      return false;
    }
  }

  bool _canLeavePlan(dynamic plan) {
    try {
      return plan.canLeavePlan == true;
    } catch (_) {
      return false;
    }
  }

  Set<String> get _currentPlanPlaceIds {
    final details = _details;
    if (details == null) return <String>{};

    return details.placeVoting.candidates
        .map((item) => item.placeId?.trim())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Set<String> get _currentPlanSubmissionIds {
    final details = _details;
    if (details == null) return <String>{};

    return details.placeVoting.candidates
        .map((item) => item.placeSubmissionId?.trim())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _load(showSpinner: true);
    _startLiveRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopLiveRefresh();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshSilentlyIfPossible());
    }
  }

  void _startLiveRefresh() {
    _liveRefreshTimer?.cancel();
    _liveRefreshTimer = Timer.periodic(_liveRefreshInterval, (_) {
      unawaited(_refreshSilentlyIfPossible());
    });
  }

  void _stopLiveRefresh() {
    _liveRefreshTimer?.cancel();
    _liveRefreshTimer = null;
  }

  String _userMessageForError(Object e) {
    if (e is PostgrestException) {
      final code = (e.code ?? '').toString().toUpperCase();
      final msg = e.message.toString().toLowerCase();
      final details = (e.details ?? '').toString().toLowerCase();

      final isAccessDenied = code == 'P0001' ||
          msg.contains('access denied') ||
          details.contains('access denied');

      if (isAccessDenied) {
        return 'План больше недоступен или у вас нет доступа.';
      }

      return 'Не удалось загрузить план. Попробуйте ещё раз.';
    }

    return 'Не удалось загрузить план. Проверьте соединение и попробуйте ещё раз.';
  }

  Future<void> _refreshSilentlyIfPossible() async {
    if (!mounted) return;
    if (_loading || _actionLoading || _visibilityLoading) return;
    if (_liveRefreshInFlight) return;

    _liveRefreshInFlight = true;
    try {
      await _load(showSpinner: false);
    } finally {
      _liveRefreshInFlight = false;
    }
  }

  Future<void> _load({required bool showSpinner}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      _error = null;
    }

    try {
      final d = await widget.repository.getPlanDetails(
        appUserId: widget.appUserId,
        planId: widget.planId,
      );
      _details = d;
    } catch (e) {
      _details = null;
      _error = _userMessageForError(e);
      debugPrint('[PlanDetailsScreen] load error: $e');
    }

    if (!mounted) return;

    if (showSpinner) {
      setState(() => _loading = false);
    } else {
      setState(() {});
    }
  }

  Future<PlanDetailsDto> _reloadDetails() async {
    return await widget.repository.getPlanDetails(
      appUserId: widget.appUserId,
      planId: widget.planId,
    );
  }

  Future<void> _toggleVisibility() async {
    if (_details == null || _visibilityLoading) return;
    final plan = _details!.plan;
    if (!_canUpdateVisibility(plan)) return;

    final newValue = !_details!.plan.visibleInFeed;

    setState(() => _visibilityLoading = true);

    try {
      await widget.repository.updatePlanVisibility(
        appUserId: widget.appUserId,
        planId: widget.planId,
        visible: newValue,
      );

      await showCenterToast(context, message: newValue ? 'Видим' : 'Не видим');
      await _load(showSpinner: false);
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(context, message: _humanizeError(e), isError: true);
    } finally {
      if (mounted) {
        setState(() => _visibilityLoading = false);
      }
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'OWNER':
        return 'Создатель';
      case 'PARTICIPANT':
        return 'Участник';
      default:
        return role;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'OPEN':
        return 'Открыт';
      case 'VOTING_FINISHED':
        return 'Голосование окончено';
      case 'CLOSED':
        return 'Закрыт';
      default:
        return status;
    }
  }

  String _humanizeRemovePlaceError(Object e) {
    if (e is PostgrestException) {
      final msg = e.message.toString();
      if (msg.trim().isNotEmpty) return msg;
    }
    return 'Не удалось удалить место из плана';
  }

  Future<void> _removePlaceCandidate(PlaceCandidateDto candidate) async {
    if (_actionLoading) return;

    setState(() => _actionLoading = true);
    try {
      await widget.repository.removePlanPlace(
        appUserId: widget.appUserId,
        planId: widget.planId,
        placeId: candidate.placeId,
        placeSubmissionId: candidate.placeSubmissionId,
      );

      if (!mounted) return;
      await _load(showSpinner: false);

      if (!mounted) return;
      await showCenterToast(context, message: 'Удалено из плана');
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(
        context,
        message: _humanizeRemovePlaceError(e),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _actionLoading = false);
      }
    }
  }

  Future<void> _openPlaceCandidateDetails(PlaceCandidateDto candidate) async {
    final dto = candidate.toPlaceDto();

    final result = await showDialog<Object?>(
      context: context,
      builder: (_) {
        if (dto != null) {
          return PlaceDetailsDialog(
            repository: PlacesRepositoryImpl(Supabase.instance.client),
            placeId: dto.id,
            title: dto.title,
            typeLabel: _typeLabelFromCategory(dto.type),
            address: dto.address,
            lat: dto.lat,
            lng: dto.lng,
            websiteUrl: dto.websiteUrl,
            previewMediaUrl: dto.previewMediaUrl,
            previewStorageKey: dto.previewStorageKey,
            previewIsPlaceholder: dto.previewIsPlaceholder,
            metroName: dto.metroName,
            metroDistanceM: dto.metroDistanceM,
            sourcePlanId: widget.planId,
            sourcePlanTitle: _details?.plan.title,
            isAlreadyInCurrentPlan: true,
            onRemoveFromCurrentPlan: candidate.canDelete
                ? () => widget.repository.removePlanPlace(
                      appUserId: widget.appUserId,
                      planId: widget.planId,
                      placeId: candidate.placeId,
                      placeSubmissionId: candidate.placeSubmissionId,
                    )
                : null,
          );
        }

        return _PlanSubmissionCandidateDetailsDialog(
          candidate: candidate,
          typeLabel: _typeLabelFromCategory(candidate.type),
          isAlreadyInCurrentPlan: true,
          onRemoveFromCurrentPlan: candidate.canDelete
              ? () => widget.repository.removePlanPlace(
                    appUserId: widget.appUserId,
                    planId: widget.planId,
                    placeId: candidate.placeId,
                    placeSubmissionId: candidate.placeSubmissionId,
                  )
              : null,
        );
      },
    );

    if (!mounted) return;

    if (result != null) {
      await _load(showSpinner: false);
    }
  }

  String _typeLabelFromCategory(String type) {
    switch (type) {
      case 'restaurant':
        return 'Ресторан';
      case 'bar':
        return 'Бар';
      case 'nightclub':
        return 'Ночной клуб';
      case 'cinema':
        return 'Кинотеатр';
      case 'theatre':
        return 'Театр';
      default:
        return 'Место';
    }
  }

  Future<void> _onPrimaryAction() async {
    if (_details == null || _actionLoading) return;

    final plan = _details!.plan;
    final canDeletePlan = _canDeletePlan(plan);
    final canLeavePlan = _canLeavePlan(plan);
    if (!canDeletePlan && !canLeavePlan) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(canDeletePlan ? 'Удалить план?' : 'Выйти из плана?'),
        content: Text(
          canDeletePlan
              ? 'План будет удалён без возможности восстановления.'
              : 'Вы перестанете участвовать в этом плане.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _actionLoading = true);

    try {
      if (canDeletePlan) {
        await widget.repository.deletePlan(
          appUserId: widget.appUserId,
          planId: widget.planId,
        );
      } else {
        await widget.repository.leavePlan(
          appUserId: widget.appUserId,
          planId: widget.planId,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(context, message: _humanizeError(e), isError: true);
    } finally {
      if (mounted) {
        setState(() => _actionLoading = false);
      }
    }
  }

  Future<void> _removeMemberDirect(String memberAppUserId) async {
    if (_details == null || _actionLoading) return;

    setState(() => _actionLoading = true);

    try {
      await widget.repository.removeMember(
        ownerAppUserId: widget.appUserId,
        planId: widget.planId,
        memberAppUserId: memberAppUserId,
      );

      if (!mounted) return;
      await _load(showSpinner: false);

      if (!mounted) return;
      await showCenterToast(context, message: 'Участник удалён');
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(context, message: _humanizeError(e), isError: true);
      rethrow;
    } finally {
      if (mounted) {
        setState(() => _actionLoading = false);
      }
    }
  }

  Future<String> _createInvite() async {
    if (_details == null || _actionLoading) {
      throw Exception('Plan details not loaded');
    }

    final token = await widget.repository.createInvite(
      appUserId: widget.appUserId,
      planId: widget.planId,
    );

    return token;
  }

  Future<void> _addMemberByPublicId(String publicId) async {
    if (_details == null || _actionLoading) return;

    final v = publicId.trim();
    if (v.isEmpty) return;

    setState(() => _actionLoading = true);
    try {
      await widget.repository.addMemberByPublicId(
        appUserId: widget.appUserId,
        planId: widget.planId,
        publicId: v,
      );

      if (!mounted) return;
      await showCenterToast(context, message: 'Приглашение отправлено');
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(context, message: _humanizeError(e), isError: true);
    } finally {
      if (mounted) {
        setState(() => _actionLoading = false);
      }
    }
  }

  Future<void> _editTitle() async {
    if (_details == null) return;
    final plan = _details!.plan;
    if (!_canEditTitle(plan)) return;

    final controller = TextEditingController(text: plan.title);

    final newValue = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Редактировать название'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Название плана'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                final v = controller.text.trim();
                if (v.isEmpty) return;
                Navigator.of(dialogContext).pop(v);
              },
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );

    if (newValue == null) return;

    final trimmed = newValue.trim();
    if (trimmed.isEmpty || trimmed == plan.title) return;

    try {
      await widget.repository.updatePlanTitle(
        appUserId: widget.appUserId,
        planId: widget.planId,
        title: trimmed,
      );
      await _load(showSpinner: false);
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(context, message: _humanizeError(e), isError: true);
    }
  }

  Future<void> _editDescription() async {
    if (_details == null) return;
    final plan = _details!.plan;
    if (!_canEditDescription(plan)) return;

    final controller = TextEditingController(text: plan.description ?? '');

    String current = controller.text.trim();
    bool canSave() => current.length >= 10;

    final newValue = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Редактировать описание'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    maxLines: 4,
                    onChanged: (v) {
                      setLocalState(() {
                        current = v.trim();
                      });
                    },
                    decoration: const InputDecoration(
                      hintText: 'Описание (минимум 10 символов)',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${current.length.clamp(0, 10)}/10',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            canSave() ? Colors.grey.shade400 : Colors.redAccent,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Отмена'),
                ),
                TextButton(
                  onPressed: canSave()
                      ? () => Navigator.of(dialogContext)
                          .pop(controller.text.trim())
                      : null,
                  style: TextButton.styleFrom(
                    foregroundColor:
                        canSave() ? const Color(0xFF3B82F6) : Colors.grey,
                  ),
                  child: const Text('Сохранить'),
                ),
              ],
            );
          },
        );
      },
    );

    if (newValue == null) return;

    final trimmed = newValue.trim();
    if (trimmed.length < 10) return;
    if ((plan.description ?? '').trim() == trimmed) return;

    try {
      await widget.repository.updatePlanDescription(
        appUserId: widget.appUserId,
        planId: widget.planId,
        description: trimmed,
      );
      await _load(showSpinner: false);
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(context, message: _humanizeError(e), isError: true);
    }
  }

  Future<void> _editVotingDeadline() async {
    if (_details == null) return;
    final plan = _details!.plan;
    if (!_canEditDeadline(plan)) return;

    final picked = await _pickDateTime(
      initial: plan.votingDeadlineAt,
    );

    if (picked == null) return;

    try {
      await widget.repository.updatePlanDeadline(
        appUserId: widget.appUserId,
        planId: plan.id,
        votingDeadlineAt: picked,
      );
      await _load(showSpinner: false);
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(context, message: _humanizeError(e), isError: true);
    }
  }

  Future<void> _addPlanDateCandidate() async {
    if (_details == null || _actionLoading) return;

    final picked = await _pickDateTime();
    if (picked == null) return;

    setState(() => _actionLoading = true);
    try {
      await widget.repository.addPlanDate(
        appUserId: widget.appUserId,
        planId: widget.planId,
        dateAt: picked,
      );
      await _load(showSpinner: false);
      if (!mounted) return;
      await showCenterToast(context, message: 'Дата добавлена');
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(context, message: _humanizeError(e), isError: true);
    } finally {
      if (mounted) {
        setState(() => _actionLoading = false);
      }
    }
  }

  Future<void> _votePlanDate(DateTime dateAt) async {
    if (_details == null || _actionLoading) return;

    setState(() => _actionLoading = true);
    try {
      await widget.repository.votePlanDate(
        appUserId: widget.appUserId,
        planId: widget.planId,
        dateAt: dateAt,
      );
      await _load(showSpinner: false);
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(context, message: _humanizeError(e), isError: true);
    } finally {
      if (mounted) {
        setState(() => _actionLoading = false);
      }
    }
  }

  Future<void> _unvotePlanDate(DateTime _) async {
    if (_details == null || _actionLoading) return;

    setState(() => _actionLoading = true);
    try {
      await widget.repository.unvotePlanDate(
        appUserId: widget.appUserId,
        planId: widget.planId,
      );
      await _load(showSpinner: false);
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(context, message: _humanizeError(e), isError: true);
    } finally {
      if (mounted) {
        setState(() => _actionLoading = false);
      }
    }
  }

  Future<void> _deletePlanDate(DateTime dateAt) async {
    if (_details == null || _actionLoading) return;

    setState(() => _actionLoading = true);
    try {
      await widget.repository.deletePlanDate(
        appUserId: widget.appUserId,
        planId: widget.planId,
        dateAt: dateAt,
      );
      await _load(showSpinner: false);
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(context, message: _humanizeError(e), isError: true);
    } finally {
      if (mounted) {
        setState(() => _actionLoading = false);
      }
    }
  }

  Future<void> _votePlanPlaceCandidate(PlaceCandidateDto candidate) async {
    if (_details == null || _actionLoading) return;

    setState(() => _actionLoading = true);
    try {
      if (candidate.isSubmissionPlace) {
        final submissionId = candidate.placeSubmissionId;
        if (submissionId == null || submissionId.isEmpty) {
          throw Exception('Некорректный кандидат места');
        }
        await widget.repository.votePlanPlaceSubmission(
          appUserId: widget.appUserId,
          planId: widget.planId,
          placeSubmissionId: submissionId,
        );
      } else {
        final placeId = candidate.placeId;
        if (placeId == null || placeId.isEmpty) {
          throw Exception('Некорректный кандидат места');
        }
        await widget.repository.votePlanPlace(
          appUserId: widget.appUserId,
          planId: widget.planId,
          placeId: placeId,
        );
      }
      await _load(showSpinner: false);
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(context, message: _humanizeError(e), isError: true);
    } finally {
      if (mounted) {
        setState(() => _actionLoading = false);
      }
    }
  }

  Future<void> _unvotePlanPlaceCandidate(PlaceCandidateDto _) async {
    if (_details == null || _actionLoading) return;

    setState(() => _actionLoading = true);
    try {
      await widget.repository.unvotePlanPlace(
        appUserId: widget.appUserId,
        planId: widget.planId,
      );
      await _load(showSpinner: false);
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(context, message: _humanizeError(e), isError: true);
    } finally {
      if (mounted) {
        setState(() => _actionLoading = false);
      }
    }
  }

  Future<void> _choosePlanPlaceOwnerPriority(
    PlaceCandidateDto candidate,
  ) async {
    if (_details == null || _actionLoading) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Подтвердите выбор'),
        content: Text(candidate.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _actionLoading = true);
    try {
      await widget.repository.choosePlanPlaceOwnerPriority(
        appUserId: widget.appUserId,
        planId: widget.planId,
        placeId: candidate.placeId,
        placeSubmissionId: candidate.placeSubmissionId,
      );
      await _load(showSpinner: false);
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(context, message: _humanizeError(e), isError: true);
    } finally {
      if (mounted) {
        setState(() => _actionLoading = false);
      }
    }
  }

  Future<void> _clearPlanPlaceOwnerPriority() async {
    if (_details == null || _actionLoading) return;

    setState(() => _actionLoading = true);
    try {
      await widget.repository.clearPlanPlaceOwnerPriority(
        appUserId: widget.appUserId,
        planId: widget.planId,
      );
      await _load(showSpinner: false);
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(context, message: _humanizeError(e), isError: true);
    } finally {
      if (mounted) {
        setState(() => _actionLoading = false);
      }
    }
  }

  String _mapDialogTypeToServerCategory(String typeLabel) {
    switch (typeLabel) {
      case 'Бар':
        return 'bar';
      case 'Ночной клуб':
        return 'nightclub';
      case 'Ресторан':
        return 'restaurant';
      case 'Кино':
        return 'cinema';
      case 'Театр':
        return 'theatre';
      default:
        return 'restaurant';
    }
  }

  bool _asBoolValue(dynamic value) {
    if (value == true) return true;
    if (value == false) return false;
    if (value is num) return value != 0;
    if (value is String) {
      final lower = value.trim().toLowerCase();
      return lower == 'true' || lower == '1' || lower == 't';
    }
    return false;
  }

  String _humanizePlanAddError(String message) {
    switch (message) {
      case 'Place already added to plan':
        return 'Место уже добавлено';
      case 'Plan already has 5 places':
        return 'В плане уже 5 мест';
      case 'Plan is not open':
        return 'План закрыт';
      case 'Not a member of plan':
        return 'Нет доступа к плану';
      case 'Rejected place cannot be added to new plan':
        return 'Отклонённое место нельзя добавить в новый план';
      case 'Place not found':
      case 'Place submission not found':
        return 'Место не найдено';
      default:
        return message.isEmpty ? 'Не удалось добавить место в план' : message;
    }
  }

  Future<void> _openCreateOwnPlaceFlow() async {
    final placesRepository = PlacesRepositoryImpl(Supabase.instance.client);

    final rawResult = await showDialog<Object?>(
      context: context,
      builder: (_) => AddPlaceDialog(
        onSubmit: (form) {
          return placesRepository.createPlaceSubmissionAndAddToPlan(
            planId: widget.planId,
            title: form.name,
            category: _mapDialogTypeToServerCategory(form.typeLabel),
            city: form.city,
            street: form.street,
            house: form.house,
            website: form.website,
          );
        },
      ),
    );

    if (!mounted || rawResult == null) return;

    final result = rawResult is Map<String, dynamic>
        ? rawResult
        : rawResult is Map
            ? Map<String, dynamic>.from(rawResult)
            : null;

    if (result == null) {
      return;
    }

    final addedToPlan = _asBoolValue(result['added_to_plan']);
    if (addedToPlan) {
      await _load(showSpinner: false);
      return;
    }

    final errorMessage = result['add_to_plan_error']?.toString().trim() ?? '';
    await showCenterToast(
      context,
      message: _humanizePlanAddError(errorMessage),
      isError: true,
    );
  }

  Future<void> _openAddPlaceSourceFlow() async {
    if (_details == null || _actionLoading) return;
    if (_details!.plan.status != 'OPEN') return;

    final source = await PlanPlaceAddSourceModal.show(
      context,
      planTitle: _details!.plan.title,
    );

    if (!mounted || source == null) return;

    switch (source) {
      case PlanPlaceAddSource.generalList:
        final generalResult = await Navigator.of(context).push<Object?>(
          MaterialPageRoute<Object?>(
            builder: (_) => PlacesScreen(
              sourcePlanId: widget.planId,
              sourcePlanTitle: _details!.plan.title,
              currentPlanPlaceIds: _currentPlanPlaceIds,
            ),
          ),
        );

        if (!mounted) return;
        if (generalResult != null) {
          await _load(showSpinner: false);
        }
        return;

      case PlanPlaceAddSource.myPlaces:
        final myPlacesResult = await Navigator.of(context).push<Object?>(
          MaterialPageRoute<Object?>(
            builder: (_) => MyPlacesScreen(
              repository: PlacesRepositoryImpl(Supabase.instance.client),
              sourcePlanId: widget.planId,
              sourcePlanTitle: _details!.plan.title,
              currentPlanPlaceIds: _currentPlanPlaceIds,
              currentPlanSubmissionIds: _currentPlanSubmissionIds,
            ),
          ),
        );

        if (!mounted) return;
        if (myPlacesResult != null) {
          await _load(showSpinner: false);
        }
        return;

      case PlanPlaceAddSource.createOwnPlace:
        await _openCreateOwnPlaceFlow();
        return;
    }
  }

  Future<void> _choosePlanDateOwnerPriority(DateTime dateAt) async {
    if (_details == null || _actionLoading) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Подтвердите выбор'),
        content: Text(formatPlanDateTime(dateAt)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _actionLoading = true);
    try {
      await widget.repository.choosePlanDateOwnerPriority(
        appUserId: widget.appUserId,
        planId: widget.planId,
        dateAt: dateAt,
      );
      await _load(showSpinner: false);
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(context, message: _humanizeError(e), isError: true);
    } finally {
      if (mounted) {
        setState(() => _actionLoading = false);
      }
    }
  }

  Future<void> _clearPlanDateOwnerPriority() async {
    if (_details == null || _actionLoading) return;

    setState(() => _actionLoading = true);
    try {
      await widget.repository.clearPlanDateOwnerPriority(
        appUserId: widget.appUserId,
        planId: widget.planId,
      );
      await _load(showSpinner: false);
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(context, message: _humanizeError(e), isError: true);
    } finally {
      if (mounted) {
        setState(() => _actionLoading = false);
      }
    }
  }

  Future<DateTime?> _pickDateTime({DateTime? initial}) async {
    final now = DateTime.now();
    final initialDate = (initial ?? now.add(const Duration(days: 1)));
    final safeInitialDate = initialDate.isBefore(now) ? now : initialDate;

    final date = await showDatePicker(
      context: context,
      locale: const Locale('ru'),
      initialDate: safeInitialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null) return null;

    final selectedTime = await _showWheelTimePicker(
      initial: initial != null
          ? TimeOfDay(hour: initial.hour, minute: initial.minute)
          : const TimeOfDay(hour: 20, minute: 0),
    );
    if (selectedTime == null) return null;

    return DateTime(
      date.year,
      date.month,
      date.day,
      selectedTime.hour,
      selectedTime.minute,
    );
  }

  Future<TimeOfDay?> _showWheelTimePicker({required TimeOfDay initial}) async {
    int hour = initial.hour;
    int minute = initial.minute;

    return showDialog<TimeOfDay>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: SizedBox(
            height: 320,
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Text(
                  'Выберите время',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 100,
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(
                            initialItem: hour,
                          ),
                          itemExtent: 40,
                          onSelectedItemChanged: (index) {
                            hour = index;
                          },
                          children: List.generate(
                            24,
                            (index) => Center(
                              child: Text(
                                index.toString().padLeft(2, '0'),
                                style: const TextStyle(fontSize: 20),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        ':',
                        style: TextStyle(fontSize: 22),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 100,
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(
                            initialItem: minute,
                          ),
                          itemExtent: 40,
                          onSelectedItemChanged: (index) {
                            minute = index;
                          },
                          children: List.generate(
                            60,
                            (index) => Center(
                              child: Text(
                                index.toString().padLeft(2, '0'),
                                style: const TextStyle(fontSize: 20),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Отмена'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(
                            dialogContext,
                            TimeOfDay(hour: hour, minute: minute),
                          );
                        },
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final plan = _details?.plan;
    final canEditTitle = plan != null && _canEditTitle(plan);
    final canEditDescription = plan != null && _canEditDescription(plan);
    final canEditDeadline = plan != null && _canEditDeadline(plan);
    final canUpdateVisibility = plan != null && _canUpdateVisibility(plan);
    final canDeletePlan = plan != null && _canDeletePlan(plan);
    final canLeavePlan = plan != null && _canLeavePlan(plan);
    final hasPrimaryAction = canDeletePlan || canLeavePlan;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Детали плана'),
        actions: [
          if (!_loading && _details != null && canUpdateVisibility)
            IconButton(
              onPressed: _visibilityLoading ? null : _toggleVisibility,
              icon: Icon(
                _details!.plan.visibleInFeed
                    ? Icons.visibility
                    : Icons.visibility_off,
              ),
            ),
          if (!_loading && _details != null && hasPrimaryAction)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: OutlinedButton(
                onPressed: _actionLoading ? null : _onPrimaryAction,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(width: 1.2, color: Colors.white),
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
                child: _actionLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        canDeletePlan ? 'Удалить план' : 'Выйти из плана',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _details == null
              ? _ErrorState(
                  userMessage: _error ?? 'Не удалось загрузить план.',
                  onRetry: () => _load(showSpinner: true),
                )
              : _Body(
                  details: _details!,
                  appUserId: widget.appUserId,
                  roleLabel: _roleLabel(_details!.plan.role),
                  statusLabel: _statusLabel(_details!.plan.status),
                  canEditTitle: canEditTitle,
                  canEditDescription: canEditDescription,
                  canEditDeadline: canEditDeadline,
                  actionsDisabled: _actionLoading || _visibilityLoading,
                  onEditTitle: _editTitle,
                  onEditDescription: _editDescription,
                  onEditDeadline: _editVotingDeadline,
                  onAddDateCandidate: _addPlanDateCandidate,
                  onVoteDate: _votePlanDate,
                  onUnvoteDate: _unvotePlanDate,
                  onDeleteDate: _deletePlanDate,
                  onAddPlaceCandidate: _openAddPlaceSourceFlow,
                  onOpenPlaceDetails: _openPlaceCandidateDetails,
                  onRemovePlaceCandidate: _removePlaceCandidate,
                  onVotePlace: _votePlanPlaceCandidate,
                  onUnvotePlace: _unvotePlanPlaceCandidate,
                  onChooseOwnerPriorityPlace: _choosePlanPlaceOwnerPriority,
                  onClearOwnerPriorityPlace: _clearPlanPlaceOwnerPriority,
                  onChooseOwnerPriorityDate: _choosePlanDateOwnerPriority,
                  onClearOwnerPriorityDate: _clearPlanDateOwnerPriority,
                  onRemoveMember: _removeMemberDirect,
                  onCreateInvite: _createInvite,
                  onAddByPublicId: _addMemberByPublicId,
                  onReloadDetails: _reloadDetails,
                ),
    );
  }
}

class _PlanSubmissionCandidateDetailsDialog extends StatefulWidget {
  const _PlanSubmissionCandidateDetailsDialog({
    required this.candidate,
    required this.typeLabel,
    this.isAlreadyInCurrentPlan = false,
    this.onRemoveFromCurrentPlan,
  });

  final PlaceCandidateDto candidate;
  final String typeLabel;
  final bool isAlreadyInCurrentPlan;
  final Future<void> Function()? onRemoveFromCurrentPlan;

  @override
  State<_PlanSubmissionCandidateDetailsDialog> createState() =>
      _PlanSubmissionCandidateDetailsDialogState();
}

class _PlanSubmissionCandidateDetailsDialogState
    extends State<_PlanSubmissionCandidateDetailsDialog> {
  bool _actionLoading = false;

  bool get _showRemoveFromPlanAction => widget.isAlreadyInCurrentPlan;

  String get _primaryActionLabel {
    if (_showRemoveFromPlanAction) {
      return widget.onRemoveFromCurrentPlan != null
          ? 'Удалить из плана'
          : 'В плане';
    }
    return 'Добавить в план';
  }

  String get _moderationStatusLabel {
    if (widget.candidate.isRejected) return 'Отклонено';
    if (widget.candidate.isPendingModeration) return 'На модерации';
    final raw = widget.candidate.moderationStatus?.trim();
    if (raw == null || raw.isEmpty) return 'На модерации';
    return raw;
  }

  Color _statusColor(BuildContext context) {
    if (widget.candidate.isRejected) {
      return Theme.of(context).colorScheme.error;
    }
    return Colors.amber.shade700;
  }

  Color _statusBackgroundColor(BuildContext context) {
    if (widget.candidate.isRejected) {
      return Theme.of(context).colorScheme.error.withOpacity(0.12);
    }
    return Colors.amber.withOpacity(0.14);
  }

  Future<void> _onPrimaryPressed() async {
    if (_actionLoading || !_showRemoveFromPlanAction) return;
    if (widget.onRemoveFromCurrentPlan == null) return;

    setState(() => _actionLoading = true);

    try {
      await widget.onRemoveFromCurrentPlan!.call();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _actionLoading = false);
      await showCenterToast(
        context,
        message: 'Не удалось удалить место из плана',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(context);
    final statusBgColor = _statusBackgroundColor(context);

    const addToPlanFillColor = Color(0xFF19D3C5);
    const addToPlanTextColor = Color(0xFF081217);
    final secondaryButtonBorderColor = Colors.white.withOpacity(0.82);
    const secondaryButtonTextColor = Color(0xFF4E8DFF);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: theme.colorScheme.surface,
          child: Stack(
            children: [
              SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: 1.35,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset(
                            'assets/images/place_placeholder.png',
                            fit: BoxFit.cover,
                          ),
                          Positioned(
                            right: 12,
                            bottom: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.55),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Плейсхолдер. Фото добавятся позже',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.typeLabel,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  widget.candidate.title,
                                  style:
                                      theme.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: statusBgColor,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  _moderationStatusLabel,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: statusColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (widget.candidate.cityName.trim().isNotEmpty) ...[
                            Text(
                              widget.candidate.cityName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.grey.shade400,
                              ),
                            ),
                            const SizedBox(height: 6),
                          ],
                          if (widget.candidate.address.trim().isNotEmpty)
                            Text(
                              widget.candidate.address,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.grey.shade400,
                              ),
                            ),
                          const SizedBox(height: 16),
                          Text(
                            'Статус',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.grey.shade400,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _moderationStatusLabel,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 22),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: FilledButton(
                              onPressed:
                                  (_actionLoading || !_showRemoveFromPlanAction)
                                      ? null
                                      : _onPrimaryPressed,
                              style: FilledButton.styleFrom(
                                elevation: 0,
                                backgroundColor: addToPlanFillColor,
                                foregroundColor: addToPlanTextColor,
                                disabledBackgroundColor:
                                    addToPlanFillColor.withOpacity(0.45),
                                disabledForegroundColor:
                                    addToPlanTextColor.withOpacity(0.75),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: _actionLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: addToPlanTextColor,
                                      ),
                                    )
                                  : Text(
                                      _primaryActionLabel,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: OutlinedButton(
                              onPressed: _actionLoading
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: secondaryButtonTextColor,
                                side: BorderSide(
                                  color: secondaryButtonBorderColor,
                                  width: 1.4,
                                ),
                                backgroundColor: Colors.transparent,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Text(
                                'Закрыть',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Material(
                  color: Colors.black45,
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    color: Colors.white,
                    onPressed: _actionLoading
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final PlanDetailsDto details;
  final String appUserId;
  final String roleLabel;
  final String statusLabel;

  final bool canEditTitle;
  final bool canEditDescription;
  final bool canEditDeadline;
  final bool actionsDisabled;
  final VoidCallback onEditTitle;
  final VoidCallback onEditDescription;
  final VoidCallback onEditDeadline;
  final Future<void> Function() onAddDateCandidate;
  final Future<void> Function(DateTime dateAt) onVoteDate;
  final Future<void> Function(DateTime dateAt) onUnvoteDate;
  final Future<void> Function(DateTime dateAt) onDeleteDate;
  final Future<void> Function() onAddPlaceCandidate;
  final ValueChanged<PlaceCandidateDto> onOpenPlaceDetails;
  final ValueChanged<PlaceCandidateDto> onRemovePlaceCandidate;
  final Future<void> Function(PlaceCandidateDto candidate) onVotePlace;
  final Future<void> Function(PlaceCandidateDto candidate) onUnvotePlace;
  final Future<void> Function(PlaceCandidateDto candidate)
      onChooseOwnerPriorityPlace;
  final Future<void> Function() onClearOwnerPriorityPlace;
  final Future<void> Function(DateTime dateAt) onChooseOwnerPriorityDate;
  final Future<void> Function() onClearOwnerPriorityDate;
  final Future<void> Function(String memberAppUserId) onRemoveMember;

  final Future<String> Function() onCreateInvite;
  final Future<void> Function(String publicId) onAddByPublicId;
  final Future<PlanDetailsDto> Function() onReloadDetails;

  const _Body({
    required this.details,
    required this.appUserId,
    required this.roleLabel,
    required this.statusLabel,
    required this.canEditTitle,
    required this.canEditDescription,
    required this.canEditDeadline,
    required this.actionsDisabled,
    required this.onEditTitle,
    required this.onEditDescription,
    required this.onEditDeadline,
    required this.onAddDateCandidate,
    required this.onVoteDate,
    required this.onUnvoteDate,
    required this.onDeleteDate,
    required this.onAddPlaceCandidate,
    required this.onOpenPlaceDetails,
    required this.onRemovePlaceCandidate,
    required this.onVotePlace,
    required this.onUnvotePlace,
    required this.onChooseOwnerPriorityPlace,
    required this.onClearOwnerPriorityPlace,
    required this.onChooseOwnerPriorityDate,
    required this.onClearOwnerPriorityDate,
    required this.onRemoveMember,
    required this.onCreateInvite,
    required this.onAddByPublicId,
    required this.onReloadDetails,
  });

  Color _roleColor(String role) =>
      role == 'OWNER' ? const Color(0xFF3B82F6) : const Color(0xFF14B8A6);

  Color _statusColor(String status) {
    switch (status) {
      case 'OPEN':
        return const Color(0xFF22C55E);
      case 'VOTING_FINISHED':
        return const Color(0xFFFACC15);
      case 'CLOSED':
        return const Color(0xFFEF4444);
      default:
        return Colors.grey.shade400;
    }
  }

  Color _deadlineColor(DateTime? deadline, String status) {
    if (deadline == null) return Colors.grey.shade400;

    final now = DateTime.now();
    final isPastOrNow = !deadline.isAfter(now);

    if ((status == 'VOTING_FINISHED' || status == 'CLOSED') && isPastOrNow) {
      return Colors.grey.shade400;
    }

    final hours = deadline.difference(now).inHours;

    if (hours >= 120) return const Color(0xFF22C55E);
    if (hours >= 72) return const Color(0xFFFACC15);
    if (hours >= 24) return const Color(0xFFFB923C);
    return const Color(0xFFEF4444);
  }

  String? _buildDateVotingHelperText() {
    final snapshot = details.dateVoting;
    final isFinalizedWithWinner = snapshot.finalWinnerCandidateId != null;
    final hasOwnerPriorityChoice = snapshot.candidates.any(
      (c) => c.isOwnerPriorityChoice,
    );

    if (snapshot.postDeadlineGraceActive) {
      return 'Голосование завершено. Победитель пока не определен.';
    }

    if (hasOwnerPriorityChoice && !isFinalizedWithWinner) {
      return 'Создатель поставил свой приоритет по дате.';
    }

    if (snapshot.ownerChoiceModeActive) {
      return 'Доступен приоритетный выбор создателя.';
    }

    if (snapshot.candidatesCount < 2) {
      return 'Голосование станет доступно, когда появится минимум 2 даты.';
    }

    return null;
  }

  TextStyle? _buildDateVotingHelperStyle(BuildContext context) {
    final snapshot = details.dateVoting;
    final isFinalizedWithWinner = snapshot.finalWinnerCandidateId != null;
    final hasOwnerPriorityChoice = snapshot.candidates.any(
      (c) => c.isOwnerPriorityChoice,
    );

    if (hasOwnerPriorityChoice && !isFinalizedWithWinner) {
      return Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.amber,
            fontWeight: FontWeight.w700,
          );
    }

    return Theme.of(context).textTheme.bodySmall;
  }

  @override
  Widget build(BuildContext context) {
    final plan = details.plan;

    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          height: 1.0,
        );

    final descValueColor = Theme.of(context).textTheme.bodyMedium?.color;
    final dateVotingHelperText = _buildDateVotingHelperText();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(plan.title, style: titleStyle)),
              if (canEditTitle)
                _EditPencilButton(
                  onPressed: onEditTitle,
                  tooltip: 'Редактировать название',
                ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withOpacity(0.18)),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: Theme.of(context).textTheme.bodyMedium,
                      children: [
                        const TextSpan(
                          text: 'Описание: ',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text: (plan.description ?? '').trim(),
                          style: TextStyle(color: descValueColor),
                        ),
                      ],
                    ),
                  ),
                ),
                if (canEditDescription)
                  _EditPencilButton(
                    onPressed: onEditDescription,
                    tooltip: 'Редактировать описание',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          _KeyValueLine(
            label: 'Роль',
            value: roleLabel,
            valueColor: _roleColor(plan.role),
          ),
          _KeyValueLine(
            label: 'Статус',
            value: statusLabel,
            valueColor: _statusColor(plan.status),
          ),
          if (plan.votingDeadlineAt != null)
            _KeyValueLine(
              label: 'Дедлайн голосования',
              value: formatPlanDateTime(plan.votingDeadlineAt),
              valueColor: _deadlineColor(plan.votingDeadlineAt, plan.status),
              trailing: canEditDeadline
                  ? _EditPencilButton(
                      onPressed: onEditDeadline,
                      tooltip: 'Редактировать дедлайн',
                    )
                  : null,
            ),
          if (plan.eventAt != null)
            _HighlightedEventLine(
              label: 'Событие',
              value: formatPlanDateTime(plan.eventAt),
            ),
          const SizedBox(height: 2),
          const Divider(height: 1, thickness: 1),
          InkWell(
            onTap: () {
              if (details.ownerMember == null) return;
              final isArchiveReadOnly =
                  details.plan.status.toString().trim().toUpperCase() ==
                      'CLOSED';
              showDialog(
                context: context,
                builder: (dialogContext) => PlanMembersModal(
                  appUserId: appUserId,
                  planId: details.plan.id,
                  ownerMember: details.ownerMember!,
                  members: details.members,
                  canAddMembers: details.plan.canAddMembers,
                  isReadOnly: isArchiveReadOnly,
                  onRemoveMember: (memberAppUserId) async {
                    await onRemoveMember(memberAppUserId);
                  },
                  onCreateInvite: () async {
                    return await onCreateInvite();
                  },
                  onAddByPublicId: (publicId) async {
                    await onAddByPublicId(publicId);
                  },
                  onReloadDetails: onReloadDetails,
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Участники',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  Row(
                    children: [
                      Text(
                        details.plan.membersCount.toString(),
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right, size: 20),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 1),
          const Divider(height: 1, thickness: 1),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Голосование по датам',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 21,
                        height: 1.0,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Дат ${details.dateVoting.candidatesCount}/3',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.color
                            ?.withOpacity(0.88),
                        height: 1.0,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (dateVotingHelperText != null) ...[
            Text(
              dateVotingHelperText,
              style: _buildDateVotingHelperStyle(context),
            ),
            const SizedBox(height: 8),
          ] else
            const SizedBox(height: 6),
          PlanDatesBlock(
            items: details.dateCandidates,
            dateVoting: details.dateVoting,
            onAddCandidate: onAddDateCandidate,
            onVote: onVoteDate,
            onUnvote: onUnvoteDate,
            onDelete: onDeleteDate,
            onChooseOwnerPriority: onChooseOwnerPriorityDate,
            onClearOwnerPriority: onClearOwnerPriorityDate,
            actionsDisabled: actionsDisabled,
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, thickness: 1),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Голосование по местам',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 21,
                        height: 1.0,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Мест ${details.placeVoting.candidatesCount}/5',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.color
                            ?.withOpacity(0.88),
                        height: 1.0,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: PlanPlacesBlock(
                    items: details.placeCandidates,
                    placeVoting: details.placeVoting,
                    onAddCandidate:
                        plan.status == 'OPEN' ? onAddPlaceCandidate : null,
                    actionsDisabled: actionsDisabled,
                    onOpenDetails: onOpenPlaceDetails,
                    onRemoveCandidate: onRemovePlaceCandidate,
                    onVote: onVotePlace,
                    onUnvote: onUnvotePlace,
                    onChooseOwnerPriority: onChooseOwnerPriorityPlace,
                    onClearOwnerPriority: onClearOwnerPriorityPlace,
                  ),
                ),
                const SizedBox(height: 10),
                const Divider(height: 1, thickness: 1),
                const _SectionTitle('Чат'),
                const SizedBox(height: 6),
                PlanChatBlock(items: details.chat),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditPencilButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String tooltip;

  const _EditPencilButton({
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Align(
        alignment: Alignment.centerRight,
        child: IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          icon: const Icon(Icons.edit, size: 18),
        ),
      ),
    );
  }
}

class _KeyValueLine extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final Widget? trailing;

  const _KeyValueLine({
    required this.label,
    required this.value,
    this.valueColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 0),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: valueColor),
            ),
          ),
          if (trailing != null)
            SizedBox(
              width: 40,
              height: 40,
              child: Align(
                alignment: Alignment.centerRight,
                child: trailing,
              ),
            ),
        ],
      ),
    );
  }
}

class _HighlightedEventLine extends StatelessWidget {
  final String label;
  final String value;

  const _HighlightedEventLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final valueStyle = Theme.of(context).textTheme.bodySmall;
    return Container(
      margin: const EdgeInsets.only(bottom: 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.green, width: 2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: valueStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleMedium);
  }
}

class _ErrorState extends StatelessWidget {
  final String userMessage;
  final VoidCallback onRetry;

  const _ErrorState({required this.userMessage, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Не удалось загрузить план'),
            const SizedBox(height: 10),
            Text(
              userMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            ElevatedButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

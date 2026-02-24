import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/plans/plans_repository.dart';
import '../../data/plans/plans_repository_impl.dart';
import '../../data/plans/plan_summary_dto.dart';
import '../../data/local/user_snapshot_storage.dart';

import '../../features/profile/profile_email_modal.dart';
import '../../features/plans/create_plan_dialog.dart';
import 'plan_details_screen.dart';
import 'widgets/plan_card.dart';

class PlansScreen extends StatefulWidget {
  final String appUserId;

  const PlansScreen({
    super.key,
    required this.appUserId,
  });

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen>
    with SingleTickerProviderStateMixin {
  late final PlansRepository _repo;
  late final TabController _tabController;

  bool _loadingActive = true;
  bool _loadingArchive = true;

  List<PlanSummaryDto> _activePlans = [];
  List<PlanSummaryDto> _archivePlans = [];

  @override
  void initState() {
    super.initState();
    _repo = PlansRepositoryImpl(Supabase.instance.client);
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  Future<Map<String, dynamic>?> _getDomainUserJson() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return null;

    final res = await Supabase.instance.client.rpc(
      'get_domain_user_by_auth_user_id',
      params: {'p_auth_user_id': session.user.id},
    );

    if (res is Map<String, dynamic>) {
      return res;
    }

    return null;
  }

  Future<String?> _resolveDomainAppUserId() async {
    final domainJson = await _getDomainUserJson();
    final id = domainJson?['id'];

    if (id is String && id.isNotEmpty) {
      return id;
    }

    final snapshot = await UserSnapshotStorage().read();
    return snapshot?.id ?? widget.appUserId;
  }

  Future<String?> _resolveDomainUserState() async {
    final domainJson = await _getDomainUserJson();
    final state = domainJson?['state'];

    if (state is String && state.isNotEmpty) {
      return state;
    }

    final snapshot = await UserSnapshotStorage().read();
    return snapshot?.state;
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadActive(), _loadArchive()]);
  }

  Future<void> _loadActive() async {
    setState(() => _loadingActive = true);

    try {
      final appUserId = await _resolveDomainAppUserId();
      if (appUserId != null) {
        _activePlans = await _repo.getMyPlans(appUserId: appUserId);
      } else {
        _activePlans = [];
      }
    } catch (e) {
      debugPrint('[PlansScreen] getMyPlans error: $e');
      _activePlans = [];
    }

    if (!mounted) return;
    setState(() => _loadingActive = false);
  }

  Future<void> _loadArchive() async {
    setState(() => _loadingArchive = true);

    try {
      final appUserId = await _resolveDomainAppUserId();
      if (appUserId != null) {
        _archivePlans = await _repo.getMyPlansArchive(appUserId: appUserId);
      } else {
        _archivePlans = [];
      }
    } catch (e) {
      debugPrint('[PlansScreen] getMyPlansArchive error: $e');
      _archivePlans = [];
    }

    if (!mounted) return;
    setState(() => _loadingArchive = false);
  }

  Future<void> _openDetails(PlanSummaryDto plan) async {
    final appUserId = await _resolveDomainAppUserId();
    if (appUserId == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlanDetailsScreen(
          appUserId: appUserId,
          planId: plan.id,
          repository: _repo,
        ),
      ),
    );

    await _loadAll();
  }

  Future<void> _createPlan() async {
    final serverState = await _resolveDomainUserState();

    // Если не USER — запускаем регистрацию
    if (serverState != 'USER') {
      if (!mounted) return;

      final shouldRegister = await showDialog<bool>(
        context: context,
        builder: (_) => const _RegistrationRequiredDialog(),
      );

      if (shouldRegister != true) return;

      final snapshot = await UserSnapshotStorage().read();
      if (snapshot == null) return;

      await showDialog(
        context: context,
        builder: (_) => ProfileEmailModal(
          bootstrapResult: {
            'id': snapshot.id,
            'public_id': snapshot.publicId,
            'nickname': snapshot.nickname,
          },
        ),
      );

      // После возврата — заново проверяем сервер
      final newState = await _resolveDomainUserState();
      if (newState != 'USER') return;

      // ✅ Ключевой фикс: после апгрейда (GUEST → USER) принудительно обновляем списки
      await _loadAll();
      if (!mounted) return;
    }

    // USER → открываем диалог создания
    final dialogResult = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const CreatePlanDialog(),
    );

    if (dialogResult == null) return;

    try {
      final appUserId = await _resolveDomainAppUserId();
      if (appUserId == null) return;

      final planId = await _repo.createPlan(
        appUserId: appUserId,
        title: dialogResult['title'] as String,
        description: dialogResult['description'] as String,
        votingDeadlineAt: dialogResult['deadline'] as DateTime,
      );

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlanDetailsScreen(
            appUserId: appUserId,
            planId: planId,
            repository: _repo,
          ),
        ),
      );

      await _loadAll();
    } catch (e) {
      debugPrint('[PlansScreen] createPlan error: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Планы'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Активные'),
            Tab(text: 'Архив'),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: OutlinedButton(
                onPressed: _createPlan,
                child: const Text('Создать план'),
              ),
            ),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _PlansList(
            loading: _loadingActive,
            plans: _activePlans,
            emptyText: 'Нет активных планов',
            onTap: _openDetails,
          ),
          _PlansList(
            loading: _loadingArchive,
            plans: _archivePlans,
            emptyText: 'Архив пуст',
            onTap: _openDetails,
          ),
        ],
      ),
    );
  }
}

class _RegistrationRequiredDialog extends StatelessWidget {
  const _RegistrationRequiredDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Требуется регистрация',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            const Text(
              'Создание планов доступно только зарегистрированным пользователям.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Отмена'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Зарегистрироваться'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlansList extends StatelessWidget {
  final bool loading;
  final List<PlanSummaryDto> plans;
  final String emptyText;
  final ValueChanged<PlanSummaryDto> onTap;

  const _PlansList({
    required this.loading,
    required this.plans,
    required this.emptyText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (plans.isEmpty) {
      return Center(child: Text(emptyText));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      itemCount: plans.length,
      itemBuilder: (context, index) {
        final plan = plans[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: PlanCard(
            plan: plan,
            onTap: () => onTap(plan),
          ),
        );
      },
    );
  }
}

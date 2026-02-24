import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 3) Добавить по public_id: ввод + RPC (callback).
///
/// Контракт:
/// - Успех: закрываем модалку с result=true.
/// - Ошибка: показываем текст, не закрываем.
class PlanAddByIdModal extends StatefulWidget {
  final Future<void> Function(String publicId) onAddByPublicId;

  const PlanAddByIdModal({
    super.key,
    required this.onAddByPublicId,
  });

  @override
  State<PlanAddByIdModal> createState() => _PlanAddByIdModalState();
}

class _PlanAddByIdModalState extends State<PlanAddByIdModal> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _humanizeError(Object e) {
    if (e is PostgrestException) return e.message; // ✅ human server message
    return e.toString();
  }

  Future<void> _submit() async {
    final v = _controller.text.trim();
    if (v.isEmpty) return;

    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await widget.onAddByPublicId(v);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _humanizeError(e));
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.8;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Добавить по ID',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          labelText: 'public_id',
                          hintText: 'Например: nytaak6v',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_error != null) ...[
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                        const SizedBox(height: 12),
                      ],
                      OutlinedButton(
                        onPressed: _loading ? null : _submit,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _loading ? 'Добавляем…' : 'Добавить',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
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

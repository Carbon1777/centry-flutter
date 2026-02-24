import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class CreatePlanDialog extends StatefulWidget {
  const CreatePlanDialog({super.key});

  @override
  State<CreatePlanDialog> createState() => _CreatePlanDialogState();
}

class _CreatePlanDialogState extends State<CreatePlanDialog> {
  static const int _minDescriptionLength = 10;

  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  DateTime? _deadline;

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _descriptionController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }

  bool get _canSubmit {
    final descLength = _descriptionController.text.trim().length;
    return descLength >= _minDescriptionLength &&
        _titleController.text.trim().isNotEmpty &&
        _deadline != null &&
        !_submitting;
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();

    final date = await showDatePicker(
      context: context,
      locale: const Locale('ru'),
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );

    if (date == null) return;

    final selectedTime = await _showWheelTimePicker();
    if (selectedTime == null) return;

    setState(() {
      _deadline = DateTime(
        date.year,
        date.month,
        date.day,
        selectedTime.hour,
        selectedTime.minute,
      );
    });
  }

  Future<TimeOfDay?> _showWheelTimePicker() async {
    int hour = 20;
    int minute = 0;

    return showDialog<TimeOfDay>(
      context: context,
      builder: (context) {
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
                          scrollController:
                              FixedExtentScrollController(initialItem: hour),
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
                      const Text(':', style: TextStyle(fontSize: 22)),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 100,
                        child: CupertinoPicker(
                          scrollController:
                              FixedExtentScrollController(initialItem: minute),
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
                            context,
                            TimeOfDay(hour: hour, minute: minute),
                          );
                        },
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDeadline() {
    if (_deadline == null) return '';
    return '${_deadline!.day.toString().padLeft(2, '0')}.'
        '${_deadline!.month.toString().padLeft(2, '0')}.'
        '${_deadline!.year} '
        '${_deadline!.hour.toString().padLeft(2, '0')}:'
        '${_deadline!.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    final result = {
      'title': _titleController.text.trim(),
      'description': _descriptionController.text.trim(),
      'deadline': _deadline,
    };

    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context)
            .inputDecorationTheme
            .enabledBorder
            ?.borderSide
            .color ??
        Colors.grey;

    final currentLength = _descriptionController.text.trim().length;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Создание плана',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _titleController,
                      decoration: _inputDecoration('Название плана'),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 3,
                      decoration: _inputDecoration('Описание плана').copyWith(
                        counterText: '$currentLength/$_minDescriptionLength',
                        counterStyle: TextStyle(
                          color: currentLength >= _minDescriptionLength
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: _submitting ? null : _pickDateTime,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 18),
                        decoration: BoxDecoration(
                          border: Border.all(color: borderColor),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          _deadline == null
                              ? 'Дата окончания голосования'
                              : _formatDeadline(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: FractionallySizedBox(
                        widthFactor: 0.6,
                        child: OutlinedButton(
                          onPressed: _canSubmit ? _submit : null,
                          child: const Text(
                            'Создать',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Material(
              color: Colors.black.withOpacity(0.4),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.of(context).pop(),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.close, size: 20, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


class AddPlaceDialogResult {
  const AddPlaceDialogResult({
    required this.name,
    required this.typeLabel,
    required this.city,
    required this.street,
    required this.house,
    required this.website,
  });

  final String name;
  final String typeLabel;
  final String city;
  final String street;
  final String house;
  final String? website;
}

typedef AddPlaceDialogSubmit = Future<Object?> Function(
  AddPlaceDialogResult result,
);

class AddPlaceDialog extends StatefulWidget {
  const AddPlaceDialog({
    super.key,
    this.onSubmit,
  });

  final AddPlaceDialogSubmit? onSubmit;

  @override
  State<AddPlaceDialog> createState() => _AddPlaceDialogState();
}

class _AddPlaceDialogState extends State<AddPlaceDialog> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _streetController = TextEditingController();
  final _houseController = TextEditingController();
  final _linkController = TextEditingController();

  String? _selectedType;
  String? _selectedCity;
  bool _submitting = false;

  final List<String> _types = const [
    'Бар',
    'Ресторан',
    'Ночной клуб',
    'Кинотеатр',
    'Карaоке',
    'Кальянная',
    'Баня / Сауна',
  ];

  final List<String> _cities = const [
    'Москва',
    'Санкт-Петербург',
    'Казань',
    'Нижний Новгород',
    'Краснодар',
    'Ростов-на-Дону',
    'Новосибирск',
    'Сочи',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _streetController.dispose();
    _houseController.dispose();
    _linkController.dispose();
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

  bool _isValidUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return false;
    try {
      final normalized =
          trimmed.startsWith('http') ? trimmed : 'https://$trimmed';
      final uri = Uri.parse(normalized);
      return uri.host.isNotEmpty && uri.host.contains('.');
    } catch (_) {
      return false;
    }
  }

  String _humanizeSubmitError(Object error) {
    if (error is PostgrestException) {
      final message = error.message.trim();
      if (message.isNotEmpty) {
        return message;
      }
    }

    final text = error.toString().replaceFirst('Exception: ', '').trim();
    if (text.isNotEmpty) {
      return text;
    }

    return 'Не удалось добавить место';
  }

  Future<void> _openInputDialog(
    TextEditingController targetController,
    String label,
  ) async {
    if (_submitting) return;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _AddPlaceTextInputDialog(
        label: label,
        initialValue: targetController.text,
      ),
    );

    if (!mounted) return;
    if (result == null) return;

    setState(() {
      targetController.text = result;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedType == null || _selectedCity == null) return;

    final websiteRaw = _linkController.text.trim();

    final result = AddPlaceDialogResult(
      name: _nameController.text.trim(),
      typeLabel: _selectedType!,
      city: _selectedCity!,
      street: _streetController.text.trim(),
      house: _houseController.text.trim(),
      website: websiteRaw,
    );

    if (widget.onSubmit == null) {
      Navigator.of(context).pop(result);
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      final submitResult = await widget.onSubmit!(result);

      if (!mounted) return;

      Navigator.of(context).pop(submitResult);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_humanizeSubmitError(e))),
      );

      setState(() {
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    const Text(
                      'Добавление места',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Если в списке мест вы не нашли нужного вам, можно добавить его. '
                      'Для этого заполните данные ниже.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade500,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _nameController,
                      readOnly: true,
                      onTap: _submitting
                          ? null
                          : () => _openInputDialog(_nameController, 'Название'),
                      decoration: _inputDecoration('Название'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Обязательное поле'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedType,
                      decoration: _inputDecoration('Тип'),
                      items: _types
                          .map(
                            (e) => DropdownMenuItem<String>(
                              value: e,
                              child: Text(e),
                            ),
                          )
                          .toList(),
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() => _selectedType = value),
                      validator: (v) => v == null ? 'Выберите тип' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCity,
                      decoration: _inputDecoration('Город'),
                      items: _cities
                          .map(
                            (e) => DropdownMenuItem<String>(
                              value: e,
                              child: Text(e),
                            ),
                          )
                          .toList(),
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() => _selectedCity = value),
                      validator: (v) => v == null ? 'Выберите город' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _streetController,
                      readOnly: true,
                      onTap: _submitting
                          ? null
                          : () => _openInputDialog(_streetController, 'Улица'),
                      decoration: _inputDecoration('Улица'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Обязательное поле'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _houseController,
                      readOnly: true,
                      onTap: _submitting
                          ? null
                          : () => _openInputDialog(_houseController, '№ дома'),
                      decoration: _inputDecoration('№ дома'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Обязательное поле'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _linkController,
                      readOnly: true,
                      onTap: _submitting
                          ? null
                          : () => _openInputDialog(_linkController, 'Сайт'),
                      decoration: _inputDecoration('Сайт'),
                      validator: (v) {
                        final val = v?.trim() ?? '';
                        if (val.isEmpty) return 'Обязательное поле';
                        if (!_isValidUrl(val)) {
                          return 'Укажите адрес сайта (например: site.ru)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 28),
                    Center(
                      child: FractionallySizedBox(
                        widthFactor: 0.6,
                        child: OutlinedButton(
                          onPressed: _submitting ? null : _submit,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Добавить место',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
            top: 8,
            right: 8,
            child: Material(
              color: Colors.black45,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close),
                color: Colors.white,
                onPressed:
                    _submitting ? null : () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddPlaceTextInputDialog extends StatefulWidget {
  const _AddPlaceTextInputDialog({
    required this.label,
    required this.initialValue,
  });

  final String label;
  final String initialValue;

  @override
  State<_AddPlaceTextInputDialog> createState() =>
      _AddPlaceTextInputDialogState();
}

class _AddPlaceTextInputDialogState extends State<_AddPlaceTextInputDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            MediaQuery.of(context).size.height * 0.14,
            20,
            0,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Material(
              color: theme.colorScheme.surface,
              elevation: 18,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.label,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: widget.label,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton(
                        onPressed: _submit,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Готово',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

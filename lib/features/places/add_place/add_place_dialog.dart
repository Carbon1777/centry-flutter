import 'package:flutter/material.dart';

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

class AddPlaceDialog extends StatefulWidget {
  const AddPlaceDialog({super.key});

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

  final List<String> _types = const [
    'Бар',
    'Ночной клуб',
    'Ресторан',
    'Кино',
    'Театр',
  ];

  final List<String> _cities = const [
    'Москва',
    'Санкт-Петербург',
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

  Future<void> _openInputDialog(
    TextEditingController targetController,
    String label,
  ) async {
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

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedType == null || _selectedCity == null) return;

    Navigator.of(context).pop(
      AddPlaceDialogResult(
        name: _nameController.text.trim(),
        typeLabel: _selectedType!,
        city: _selectedCity!,
        street: _streetController.text.trim(),
        house: _houseController.text.trim(),
        website: _linkController.text.trim().isEmpty
            ? null
            : _linkController.text.trim(),
      ),
    );
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
                      onTap: () =>
                          _openInputDialog(_nameController, 'Название'),
                      decoration: _inputDecoration('Название'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Обязательное поле'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _selectedType,
                      decoration: _inputDecoration('Тип'),
                      items: _types
                          .map(
                            (e) => DropdownMenuItem<String>(
                              value: e,
                              child: Text(e),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _selectedType = value),
                      validator: (v) => v == null ? 'Выберите тип' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _selectedCity,
                      decoration: _inputDecoration('Город'),
                      items: _cities
                          .map(
                            (e) => DropdownMenuItem<String>(
                              value: e,
                              child: Text(e),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _selectedCity = value),
                      validator: (v) => v == null ? 'Выберите город' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _streetController,
                      readOnly: true,
                      onTap: () => _openInputDialog(_streetController, 'Улица'),
                      decoration: _inputDecoration('Улица'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Обязательное поле'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _houseController,
                      readOnly: true,
                      onTap: () => _openInputDialog(_houseController, '№ дома'),
                      decoration: _inputDecoration('№ дома'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Обязательное поле'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _linkController,
                      readOnly: true,
                      onTap: () => _openInputDialog(_linkController, 'Сайт'),
                      decoration: _inputDecoration('Сайт'),
                    ),
                    const SizedBox(height: 28),
                    Center(
                      child: FractionallySizedBox(
                        widthFactor: 0.6,
                        child: OutlinedButton(
                          onPressed: _submit,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'Добавить место',
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
                onPressed: () => Navigator.of(context).pop(),
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
          padding: const EdgeInsets.fromLTRB(20, 118, 20, 0),
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

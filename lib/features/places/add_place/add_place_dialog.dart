import 'package:flutter/material.dart';

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

  OverlayEntry? _keyboardOverlay;

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
    _keyboardOverlay?.remove();
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

  void _openKeyboardOverlay(
      TextEditingController targetController, String label) {
    _keyboardOverlay?.remove();

    final focusNode = FocusNode();
    final tempController = TextEditingController(text: targetController.text);

    _keyboardOverlay = OverlayEntry(
      builder: (context) {
        final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

        return Positioned(
          left: 0,
          right: 0,
          bottom: keyboardHeight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 20,
                    color: Colors.black54,
                  ),
                ],
              ),
              child: TextField(
                controller: tempController,
                focusNode: focusNode,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  targetController.text = tempController.text;
                  _closeOverlay();
                },
                decoration: InputDecoration(
                  labelText: label,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_keyboardOverlay!);

    Future.delayed(const Duration(milliseconds: 50), () {
      focusNode.requestFocus();
    });
  }

  void _closeOverlay() {
    _keyboardOverlay?.remove();
    _keyboardOverlay = null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop();

    Future.microtask(() {
      showDialog(
        context: context,
        builder: (_) => const _AddPlaceModeDialog(),
      );
    });
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
                          _openKeyboardOverlay(_nameController, 'Название'),
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
                              (e) => DropdownMenuItem(value: e, child: Text(e)))
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
                              (e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _selectedCity = value),
                      validator: (v) => v == null ? 'Выберите город' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _streetController,
                      readOnly: true,
                      onTap: () =>
                          _openKeyboardOverlay(_streetController, 'Улица'),
                      decoration: _inputDecoration('Улица'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Обязательное поле'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _houseController,
                      readOnly: true,
                      onTap: () =>
                          _openKeyboardOverlay(_houseController, '№ дома'),
                      decoration: _inputDecoration('№ дома'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Обязательное поле'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _linkController,
                      readOnly: true,
                      onTap: () =>
                          _openKeyboardOverlay(_linkController, 'Сайт'),
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

class _AddPlaceModeDialog extends StatelessWidget {
  const _AddPlaceModeDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 44, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Выберите как вы хотите добавить место',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: () {},
              child: const Text('Добавить в общий список мест'),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {},
              child: const Text('Добавить в Мои места'),
            ),
          ],
        ),
      ),
    );
  }
}

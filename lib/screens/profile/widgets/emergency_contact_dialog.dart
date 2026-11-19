import 'package:flutter/material.dart';

import '../../../models/emergency_contact.dart';
import '../../../widgets/br_input_formatters.dart';

/// Dialog para criar/editar um contato de emergência.
class EmergencyContactDialog extends StatefulWidget {
  const EmergencyContactDialog({super.key, this.contact});

  final EmergencyContact? contact;

  @override
  State<EmergencyContactDialog> createState() => _EmergencyContactDialogState();
}

class _EmergencyContactDialogState extends State<EmergencyContactDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nomeController;
  late final TextEditingController _parentescoController;
  late final TextEditingController _telefoneController;

  bool get _isEditing => widget.contact != null;

  @override
  void initState() {
    super.initState();
    _nomeController = TextEditingController(text: widget.contact?.nome ?? '');
    _parentescoController = TextEditingController(
      text: widget.contact?.parentesco ?? '',
    );
    _telefoneController = TextEditingController(
      text: widget.contact?.telefone ?? '',
    );
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _parentescoController.dispose();
    _telefoneController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final contact = _isEditing
        ? widget.contact!.copyWith(
            nome: _nomeController.text.trim(),
            parentesco: _parentescoController.text.trim(),
            telefone: _telefoneController.text.trim(),
          )
        : EmergencyContact.create(
            nome: _nomeController.text.trim(),
            parentesco: _parentescoController.text.trim(),
            telefone: _telefoneController.text.trim(),
          );
    Navigator.of(context).pop(contact);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Editar contato' : 'Adicionar contato'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nomeController,
                decoration: const InputDecoration(
                  labelText: 'Nome *',
                  hintText: 'Ex: Maria Silva',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Informe o nome';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _parentescoController,
                decoration: const InputDecoration(
                  labelText: 'Parentesco',
                  hintText: 'Ex: Cônjuge, filho(a), amigo(a)',
                  prefixIcon: Icon(Icons.family_restroom_outlined),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _telefoneController,
                decoration: const InputDecoration(
                  labelText: 'Telefone *',
                  hintText: '(11) 91234-5678',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
                inputFormatters: [PhoneInputFormatter()],
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Informe o telefone';
                  }
                  final digits = value.replaceAll(RegExp(r'\D'), '');
                  if (digits.length < 10 || digits.length > 11) {
                    return 'Telefone deve ter 10 ou 11 dígitos';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_isEditing ? 'Salvar' : 'Adicionar'),
        ),
      ],
    );
  }
}

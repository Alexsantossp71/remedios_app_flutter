import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../../../core/design/record_card.dart';
import '../../../models/user_profile.dart';
import '../../../widgets/br_input_formatters.dart';
import '../../../widgets/privacy_notice.dart';
import 'string_list_editor.dart';

/// Card "Dados pessoais": formulário completo do perfil.
///
/// Os controllers e as GlobalKeys de campo pertencem ao estado da
/// ProfileScreen (sobrevivem a rebuilds, permitem a rolagem até o
/// primeiro erro); este widget é a apresentação pura desses campos.
class ProfileFormCard extends StatelessWidget {
  const ProfileFormCard({
    super.key,
    required this.nomeFieldKey,
    required this.nomeController,
    required this.cpfFieldKey,
    required this.cpfController,
    required this.telefoneFieldKey,
    required this.telefoneController,
    required this.pesoFieldKey,
    required this.pesoController,
    required this.alturaFieldKey,
    required this.alturaController,
    required this.observacoesController,
    required this.dataNascimento,
    required this.tipoSanguineo,
    required this.alergias,
    required this.condicoesCronicas,
    required this.consentGranted,
    required this.consentAt,
    required this.onTipoSanguineoChanged,
    required this.onAlergiasChanged,
    required this.onCondicoesCronicasChanged,
    required this.onConsentChanged,
    required this.onSelectBirthDate,
    required this.onSave,
    required this.onInvalidField,
    required this.validateCpf,
    required this.validateTelefone,
    required this.validatePeso,
    required this.validateAltura,
    this.saveLabel = 'Salvar perfil',
  });

  final GlobalKey nomeFieldKey;
  final TextEditingController nomeController;
  final GlobalKey cpfFieldKey;
  final TextEditingController cpfController;
  final GlobalKey telefoneFieldKey;
  final TextEditingController telefoneController;
  final GlobalKey pesoFieldKey;
  final TextEditingController pesoController;
  final GlobalKey alturaFieldKey;
  final TextEditingController alturaController;
  final TextEditingController observacoesController;
  final DateTime? dataNascimento;
  final TipoSanguineo? tipoSanguineo;
  final List<String> alergias;
  final List<String> condicoesCronicas;
  final bool consentGranted;
  final DateTime? consentAt;
  final ValueChanged<TipoSanguineo?> onTipoSanguineoChanged;
  final ValueChanged<List<String>> onAlergiasChanged;
  final ValueChanged<List<String>> onCondicoesCronicasChanged;
  final ValueChanged<bool?> onConsentChanged;
  final VoidCallback onSelectBirthDate;
  final VoidCallback onSave;
  final void Function(GlobalKey fieldKey) onInvalidField;
  final String? Function(String?) validateCpf;
  final String? Function(String?) validateTelefone;
  final String? Function(String?) validatePeso;
  final String? Function(String?) validateAltura;

  /// Rótulo do botão de salvar — o convite de perfil pós-cofre usa
  /// "Salvar e começar"; a aba Perfil mantém o padrão "Salvar perfil".
  final String saveLabel;

  /// Formatação da data de nascimento exibida no campo (pt_BR).
  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy', 'pt_BR');

  // ── Campos extraídos para suportar 2-col no desktop ──────────────

  Widget _cpfField() => TextFormField(
        key: cpfFieldKey,
        controller: cpfController,
        decoration: const InputDecoration(
          labelText: 'CPF',
          hintText: '000.000.000-00',
          prefixIcon: Icon(Icons.badge_outlined),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [CpfInputFormatter()],
        validator: validateCpf,
      );

  Widget _birthDateField(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onSelectBirthDate,
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Data de nascimento',
            prefixIcon: Icon(Icons.cake_outlined),
            suffixIcon: Icon(Icons.calendar_today_outlined),
          ),
          child: Text(
            dataNascimento != null
                ? _dateFormat.format(dataNascimento!)
                : 'Toque para selecionar',
            style: dataNascimento != null
                ? null
                : TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
          ),
        ),
      );

  Widget _telefoneField() => TextFormField(
        key: telefoneFieldKey,
        controller: telefoneController,
        decoration: const InputDecoration(
          labelText: 'Telefone',
          hintText: '(11) 91234-5678',
          prefixIcon: Icon(Icons.phone_outlined),
        ),
        keyboardType: TextInputType.phone,
        inputFormatters: [PhoneInputFormatter()],
        validator: validateTelefone,
      );

  Widget _bloodTypeField() => DropdownButtonFormField<TipoSanguineo>(
        initialValue: tipoSanguineo,
        decoration: const InputDecoration(
          labelText: 'Tipo sanguíneo',
          prefixIcon: Icon(Icons.bloodtype_outlined),
        ),
        items: TipoSanguineo.values
            .map((tipo) =>
                DropdownMenuItem(value: tipo, child: Text(tipo.value)))
            .toList(),
        onChanged: onTipoSanguineoChanged,
      );

  @override
  Widget build(BuildContext context) {
    // Design audit: desktop (>=900px) usa 2 colunas para aproveitar horizontal.
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    return RecordCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Linha 1: Nome (full width — campo longo)
            TextFormField(
              key: nomeFieldKey,
              controller: nomeController,
              decoration: const InputDecoration(
                labelText: 'Nome',
                hintText: 'Como você quer ser chamado',
                prefixIcon: Icon(Icons.person_outline),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  onInvalidField(nomeFieldKey);
                  return 'Informe seu nome';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            // Linha 2: CPF + Data nascimento (2 colunas no desktop)
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _cpfField()),
                  const SizedBox(width: 12),
                  Expanded(child: _birthDateField(context)),
                ],
              )
            else ...[
              _cpfField(),
              const SizedBox(height: 16),
              _birthDateField(context),
            ],
            const SizedBox(height: 16),
            // Linha 3: Telefone + Tipo sanguíneo (2 colunas no desktop)
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _telefoneField()),
                  const SizedBox(width: 12),
                  Expanded(child: _bloodTypeField()),
                ],
              )
            else ...[
              _telefoneField(),
              const SizedBox(height: 16),
              _bloodTypeField(),
            ],
            const SizedBox(height: 16),
            const SizedBox(height: 16),
            StringListEditor(
              label: 'Alergias',
              icon: Icons.warning_amber_outlined,
              hint: 'Ex: Dipirona, frutos do mar',
              values: alergias,
              onChanged: onAlergiasChanged,
            ),
            const SizedBox(height: 16),
            StringListEditor(
              label: 'Condições crônicas',
              icon: Icons.monitor_heart_outlined,
              hint: 'Ex: Hipertensão, diabetes',
              values: condicoesCronicas,
              onChanged: onCondicoesCronicasChanged,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: pesoFieldKey,
                    controller: pesoController,
                    decoration: const InputDecoration(
                      labelText: 'Peso (kg)',
                      hintText: 'Ex: 70',
                      prefixIcon: Icon(Icons.monitor_weight_outlined),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: validatePeso,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: alturaFieldKey,
                    controller: alturaController,
                    decoration: const InputDecoration(
                      labelText: 'Altura (m)',
                      hintText: 'Ex: 1.70',
                      prefixIcon: Icon(Icons.height_outlined),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: validateAltura,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: observacoesController,
              decoration: const InputDecoration(
                labelText: 'Observações',
                hintText: 'Informações relevantes sobre sua saúde',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 20),
            const PrivacyNoticeCard(),
            const SizedBox(height: 12),
            ConsentCheckbox(
              value: consentGranted,
              grantedAt: consentAt,
              onChanged: onConsentChanged,
            ),
            const SizedBox(height: 12),
            // Design audit: full-width para ser mais discoverable.
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.save_outlined),
                label: Text(saveLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

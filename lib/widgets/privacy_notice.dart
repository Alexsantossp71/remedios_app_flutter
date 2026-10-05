import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Aviso de privacidade (LGPD) com finalidade, base legal, controlador,
/// armazenamento e direitos do titular.
class PrivacyNoticeCard extends StatelessWidget {
  const PrivacyNoticeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget row(String label, String text) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: RichText(
          text: TextSpan(
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
            children: [
              TextSpan(
                text: '$label: ',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(text: text),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.privacy_tip_outlined,
                  size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Aviso de privacidade',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          row(
            'Finalidade',
            'guardar e exibir seus dados de saúde neste dispositivo '
                '(lembretes e cartão de emergência).',
          ),
          row(
            'Base legal',
            'seu consentimento — dados sensíveis de saúde exigem '
                'consentimento específico (art. 11 da LGPD).',
          ),
          row(
            'Controlador',
            'Remédio na Hora (Alexsantossp71), contato pelo repositório '
                'GitHub do projeto.',
          ),
          row(
            'Armazenamento',
            'os dados ficam salvos somente neste dispositivo (banco de '
                'dados local). Nada é enviado a servidores, exceto quando '
                'você opta por enviar a imagem do cartão do plano: nessa '
                'opção a foto é enviada ao servidor do app, onde é lida por '
                'um mecanismo de reconhecimento de texto (OCR) e descartada '
                'logo após a leitura. O cartão não é repassado a nenhum '
                'fornecedor ou serviço de terceiros.',
          ),
          row(
            'Seus direitos',
            'acesso, correção, eliminação e revogação do consentimento '
                '(art. 18 da LGPD). Para apagar tudo, use “Apagar meus '
                'dados” na seção Dados e privacidade.',
          ),
        ],
      ),
    );
  }
}

/// Consentimento específico e destacado para o tratamento de dados
/// sensíveis de saúde. Uma vez registrado ([grantedAt] != null), o
/// checkbox fica marcado e desabilitado — a revogação é feita apagando
/// os dados (“Apagar meus dados”).
class ConsentCheckbox extends StatelessWidget {
  const ConsentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.grantedAt,
  });

  /// Estado atual do checkbox.
  final bool value;

  /// Chamado quando o usuário marca/desmarca (null quando desabilitado).
  final ValueChanged<bool?>? onChanged;

  /// Data/hora em que o consentimento foi registrado (se já foi).
  final DateTime? grantedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final locked = grantedAt != null;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.7),
          width: 1.5,
        ),
      ),
      child: CheckboxListTile(
        value: value,
        onChanged: locked ? null : onChanged,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        checkboxShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        title: Text(
          'Autorizo o tratamento dos meus dados sensíveis de saúde '
          '(tipo sanguíneo, alergias, condições crônicas, peso, altura, '
          'observações e contatos de emergência), conforme o aviso de '
          'privacidade acima.',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
        subtitle: locked
            ? Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Consentimento registrado em '
                  '${DateFormat('dd/MM/yyyy HH:mm').format(grantedAt!.toLocal())}. '
                  'Para revogar, use “Apagar meus dados”.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

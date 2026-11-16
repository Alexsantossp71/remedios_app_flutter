import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Aviso de privacidade (LGPD) com finalidade, fluxos de compartilhamento,
/// armazenamento, limites de segurança e direitos do titular.
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
              Icon(
                Icons.privacy_tip_outlined,
                size: 20,
                color: colorScheme.primary,
              ),
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
            'organizar tratamentos, doses, consultas, exames e informações '
                'de saúde para exibição, histórico e lembretes. O app não '
                'substitui orientação de médico ou farmacêutico.',
          ),
          row(
            'Base legal',
            'o uso de dados sensíveis depende da hipótese legal aplicável '
                'e de consentimento específico quando solicitado pelo app. '
                'Este aviso não substitui uma avaliação jurídica da operação.',
          ),
          row(
            'Controlador e contato',
            'Remédio na Hora (Alexsantossp71). Para solicitações sobre dados, '
                'utilize os canais de contato publicados no repositório do projeto.',
          ),
          row(
            'Armazenamento local',
            'os registros são mantidos no armazenamento do dispositivo ou '
                'navegador. Isso não equivale a armazenamento criptografado: '
                'proteja o aparelho, a sessão e os arquivos exportados.',
          ),
          row(
            'Recursos conectados',
            'quando você escolhe recursos de IA, os dados necessários à '
                'solicitação — que podem incluir medicamentos, doses, '
                'instruções e imagens de documentos de saúde — são enviados '
                'pela internet ao proxy do projeto e ao provedor de IA '
                'configurado (atualmente NVIDIA). Não envie informações que '
                'não sejam necessárias. As políticas desses serviços também '
                'se aplicam. A leitura de cartão por OCR envia a imagem ao '
                'servidor do projeto para processamento; confira os dados '
                'reconhecidos antes de salvá-los.',
          ),
          row(
            'Backup e compartilhamento',
            'os backups são arquivos JSON legíveis e não criptografados pelo '
                'app. Guarde-os em local protegido e não os compartilhe. '
                'O cartão de emergência pode conter dados pessoais quando '
                'você escolhe compartilhá-lo.',
          ),
          row(
            'Seus direitos',
            'você pode solicitar acesso, correção, eliminação e informações '
                'sobre o tratamento, nos termos do art. 18 da LGPD e conforme aplicável. '
                'Use “Apagar meus dados” na seção Dados '
                'e privacidade para remover os registros locais; isso não '
                'apaga cópias que você já exportou ou dados enviados a serviços externos.',
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

  final bool value;
  final ValueChanged<bool?>? onChanged;
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
      child: Material(
        type: MaterialType.transparency,
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
      ),
    );
  }
}

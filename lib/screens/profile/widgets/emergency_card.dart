import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

import '../../../core/design/brand_colors.dart';
import '../../../core/design/record_card.dart';
import '../../../models/emergency_contact.dart';
import '../../../models/user_profile.dart';
import '../../../services/emergency_card_share_service.dart';
import '../../../widgets/app_snack_bar.dart';

/// Cartão de emergência com resumo rápido do perfil.
///
/// Recebe os valores ao vivo do formulário (não o perfil salvo), para que
/// o resumo reaja na hora em que o usuário edita alergias, condições
/// crônicas ou tipo sanguíneo — antes de apertar "Salvar perfil".
///
/// O botão de compartilhar captura o próprio cartão como imagem PNG
/// (RepaintBoundary) e abre a folha de compartilhamento do sistema; no
/// navegador, quando não há suporte a compartilhar arquivos, o PNG é
/// baixado direto.
class EmergencyCard extends StatefulWidget {
  const EmergencyCard({
    super.key,
    required this.tipoSanguineo,
    required this.alergias,
    required this.condicoesCronicas,
    required this.contacts,
  });

  final TipoSanguineo? tipoSanguineo;
  final List<String> alergias;
  final List<String> condicoesCronicas;
  final List<EmergencyContact> contacts;

  @override
  State<EmergencyCard> createState() => _EmergencyCardState();
}

class _EmergencyCardState extends State<EmergencyCard> {
  /// RepaintBoundary que delimita o que entra na imagem compartilhada.
  final _boundaryKey = GlobalKey();

  /// True enquanto a imagem está sendo gerada/compartilhada.
  bool _compartilhando = false;

  Future<void> _compartilharComoImagem() async {
    if (_compartilhando) return;
    final boundary =
        _boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;

    // A captura acontece ANTES do spinner: a imagem é sempre do cartão
    // completo, nunca com o indicador de progresso por cima.
    final Uint8List pngBytes;
    try {
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('Falha ao codificar PNG do cartão de emergência');
      }
      pngBytes = byteData.buffer.asUint8List();
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          'Não foi possível gerar a imagem do cartão.',
          type: AppSnackType.error,
        );
      }
      return;
    }

    setState(() => _compartilhando = true);
    try {
      final agora = DateTime.now();
      await shareEmergencyCardImage(
        pngBytes: pngBytes,
        fileName: 'cartao-emergencia-${_stampArquivo(agora)}.png',
        sharePositionOrigin: _rectDaTela(),
      );
      if (mounted) {
        showAppSnackBar(
          context,
          'Imagem do cartão gerada — compartilhe ou salve onde quiser.',
          type: AppSnackType.success,
        );
      }
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          'Não foi possível compartilhar o cartão agora.',
          type: AppSnackType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _compartilhando = false);
    }
  }

  /// Retângulo do cartão em coordenadas globais — âncora do popover de
  /// compartilhamento no iPad/macOS; ignorado nas demais plataformas.
  Rect? _rectDaTela() {
    final box = _boundaryKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    final position = box.localToGlobal(Offset.zero);
    return position & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;
    final inkColor = isDark ? BrandColors.darkInk : BrandColors.ink;
    final mutedColor = isDark ? BrandColors.darkMuted : BrandColors.muted;
    final mainContact = widget.contacts.isNotEmpty
        ? widget.contacts.first
        : null;

    return RecordCard(
      // Acento vermelho da marca: cartão de emergência pede atenção —
      // o mesmo papel do errorContainer antes da migração.
      accentColor: BrandColors.red,
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          // A captura (RepaintBoundary) cobre o conteúdo inteiro do cartão,
          // com fundo sólido — assim o PNG não sai com fundo transparente
          // e leva título, linhas e rodapé prontos para quem receber.
          RepaintBoundary(
            key: _boundaryKey,
            child: Container(
              color: isDark ? BrandColors.darkSurface : Colors.white,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.medical_information_outlined,
                        color: BrandColors.red,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Cartão de emergência',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: inkColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _EmergencyRow(
                    label: 'Tipo sanguíneo',
                    value: widget.tipoSanguineo?.value ?? 'Não informado',
                  ),
                  const SizedBox(height: 6),
                  _EmergencyRow(
                    label: 'Alergias',
                    value: _resumoLista(widget.alergias),
                  ),
                  const SizedBox(height: 6),
                  _EmergencyRow(
                    label: 'Condições crônicas',
                    value: _resumoLista(widget.condicoesCronicas),
                  ),
                  const SizedBox(height: 6),
                  _EmergencyRow(
                    label: 'Contato de emergência',
                    value: mainContact != null
                        ? '${mainContact.nome} — ${mainContact.telefone}'
                        : 'Nenhum cadastrado',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    // Design audit: "Atualizado em" + date only (sem hora)
                    // — antes era "Gerado em dd/MM/yyyy HH:mm" que parecia
                    // timestamp interno de debug.
                    'Remédio na Hora • Atualizado em ${_stampRodape(DateTime.now())}',
                    style: textTheme.bodySmall?.copyWith(
                      color: mutedColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: _compartilhando
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  )
                : IconButton(
                    tooltip: 'Compartilhar como imagem',
                    icon: const Icon(Icons.ios_share_outlined),
                    color: BrandColors.red,
                    onPressed: _compartilharComoImagem,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Resumo compacto de uma lista do cartão: 'Nenhuma' quando vazia,
/// itens separados por vírgula e "(+N)" quando passa de dois.
String _resumoLista(List<String> valores) {
  if (valores.isEmpty) return 'Nenhuma';
  if (valores.length <= 2) return valores.join(', ');
  return '${valores.take(2).join(', ')} (+${valores.length - 2})';
}

/// Carimbo para o nome do arquivo: YYYYMMDD-HHMMSS.
///
/// Formatação manual (sem intl) para não depender do locale inicializado.
String _stampArquivo(DateTime d) {
  String p2(int v) => v.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}${p2(d.month)}${p2(d.day)}'
      '-${p2(d.hour)}${p2(d.minute)}${p2(d.second)}';
}

/// Carimbo legível para o rodapé da imagem: dd/MM/yyyy HH:mm.
String _stampRodape(DateTime d) {
  String p2(int v) => v.toString().padLeft(2, '0');
  return '${p2(d.day)}/${p2(d.month)}/${d.year}';
}

class _EmergencyRow extends StatelessWidget {
  const _EmergencyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isDark ? BrandColors.darkMuted : BrandColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isDark ? BrandColors.darkInk : BrandColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

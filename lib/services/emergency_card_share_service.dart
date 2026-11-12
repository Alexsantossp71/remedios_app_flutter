import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:share_plus/share_plus.dart';

/// Compartilha a imagem PNG do cartão de emergência.
///
/// No navegador usa a Web Share API quando o navegador suporta
/// compartilhar arquivos; quando não suporta (ou o usuário cancela o
/// suporte), o share_plus cai para download do PNG — a imagem chega ao
/// usuário de um jeito ou de outro. No celular (APK), abre a folha de
/// compartilhamento do sistema (WhatsApp, e-mail, salvar na galeria...).
///
/// Lança exceção quando o compartilhamento falha: quem chama decide como
/// avisar o usuário.
Future<void> shareEmergencyCardImage({
  required Uint8List pngBytes,
  required String fileName,
  Rect? sharePositionOrigin,
}) {
  return SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(pngBytes, mimeType: 'image/png', name: fileName),
      ],
      title: 'Cartão de emergência',
      subject: 'Cartão de emergência — Remédio na Hora',
      // Âncora do popover no iPad/macOS; ignorado nas demais plataformas.
      sharePositionOrigin: sharePositionOrigin,
    ),
  );
}

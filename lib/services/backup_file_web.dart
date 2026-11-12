import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'backup_service.dart';

/// Salva o backup disparando o download do navegador (blob + âncora) e
/// retorna o nome do arquivo gerado.
Future<String> saveBackupJson(String jsonText) async {
  final name = BackupService.backupFileName();
  final bytes = utf8.encode(jsonText);
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  // O download já começou; liberar o blob depois de uma folga.
  Future.delayed(const Duration(seconds: 10), () {
    web.URL.revokeObjectURL(url);
  });
  return name;
}

/// Abre o seletor de arquivos do navegador via <input type="file"> e
/// retorna o conteúdo do .json escolhido (null = usuário cancelou).
Future<String?> pickBackupJsonText() {
  final completer = Completer<String?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.json,application/json';

  void finish(String? text) {
    if (!completer.isCompleted) completer.complete(text);
  }

  input.addEventListener('change', (() async {
    final files = input.files;
    final file = (files == null || files.length == 0) ? null : files.item(0);
    if (file == null) {
      finish(null);
      return;
    }
    try {
      final text = await file.text().toDart;
      finish(text.toDart);
    } catch (_) {
      finish(null);
    }
  }).toJS);

  input.addEventListener('cancel', (() {
    finish(null);
  }).toJS);

  // Precisa estar no DOM para o click abrir o diálogo em todos os browsers.
  web.document.body?.appendChild(input);
  input.click();
  input.remove();

  return completer.future;
}

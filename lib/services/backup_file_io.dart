import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'backup_service.dart';

/// Salva o backup em arquivo no Documents do app e retorna o caminho
/// completo (mostrado ao usuário no SnackBar de sucesso).
Future<String> saveBackupJson(String jsonText) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/${BackupService.backupFileName()}');
  await file.writeAsString(jsonText, flush: true);
  return file.path;
}

/// Abre o seletor de arquivos do sistema e retorna o conteúdo do .json
/// escolhido (null = usuário cancelou).
Future<String?> pickBackupJsonText() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
    withData: true,
  );
  final picked = result?.files.single;
  if (picked == null) return null;

  final bytes = picked.bytes;
  if (bytes != null) return utf8.decode(bytes, allowMalformed: true);

  final path = picked.path;
  if (path == null) return null;
  return File(path).readAsString();
}

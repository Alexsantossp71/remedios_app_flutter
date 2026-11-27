import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database_encryption/database_encryption_service.dart'
    show kEncryptionStateStorageKey;
import 'database_factory_io.dart' show initializeDatabaseFactory;

/// NATIVO (Android/iOS/macOS/desktop): apaga o arquivo de banco [name] nos
/// locais possíveis — databasesPath do sqflite (banco criptografado) e
/// documentsDirectory (local alternativo do banco legado). Ausência do
/// arquivo é sucesso — o apagamento é best-effort por contrato.
Future<void> deletePlatformDatabase(String name) async {
  initializeDatabaseFactory();

  // 1. databasesPath: onde o sqflite resolve nomes relativos — é onde o
  //    banco criptografado (remedios_app_enc.db) é criado.
  try {
    await deleteDatabase(name);
  } catch (_) {
    // Arquivo ausente ou já removido.
  }

  // 2. documentsDirectory: o banco legado (remedios_app.db) pode ter sido
  //    criado ali pela versão pré-migração.
  try {
    final documents = await getApplicationDocumentsDirectory();
    await deleteDatabase(p.join(documents.path, name));
  } catch (_) {
    // Diretório indisponível ou arquivo ausente.
  }
}

/// NATIVO: remove marcadores locais do cofre (metadata de migração em
/// SharedPreferences). Nunca remove material de chaves — isso é papel do
/// [DatabaseKeyService.deleteVault].
Future<void> clearVaultMarkers() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kEncryptionStateStorageKey);
  } catch (_) {
    // Best-effort: metadata não afeta a segurança do estado zerado.
  }
}

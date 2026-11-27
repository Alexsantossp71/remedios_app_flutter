import 'database_encryption/database_encryption_service.dart'
    show kEncryptionStateStorageKey;
import 'database_factory_web.dart';
import 'database_key/web_local_storage_binding.dart';

/// WEB: apaga o banco lógico [name] do armazenamento do navegador
/// (IndexedDB/OPFS via worker SQLite3MC). Ausência do banco é sucesso —
/// o apagamento é best-effort por contrato.
Future<void> deletePlatformDatabase(String name) async {
  try {
    await databaseFactoryWeb.deleteDatabase(name);
  } catch (_) {
    // Banco ausente ou já removido: nada a fazer.
  }
}

/// WEB: remove marcadores locais do cofre (metadata de migração) do
/// localStorage. Nunca remove material de chaves — isso é papel do
/// [DatabaseKeyService.deleteVault].
Future<void> clearVaultMarkers() async {
  try {
    const LocalStorageKeyValueStorage().removeItem(kEncryptionStateStorageKey);
  } catch (_) {
    // Best-effort: metadata não afeta a segurança do estado zerado.
  }
}

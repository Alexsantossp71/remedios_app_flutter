import 'package:flutter/foundation.dart' show visibleForTesting;

import 'app_reset_platform_web.dart'
    if (dart.library.io) 'app_reset_platform_io.dart';
import 'database_encryption/database_encryption_service.dart'
    show kEncryptedDatabaseName, kLegacyDatabaseName;
import 'database_key/database_key_service.dart';
import 'database_service.dart';
import 'web_reminder_service.dart';

/// Apagamento completo do app no aparelho (LGPD + reinício como novo).
///
/// Diferente de `UserProfileProvider.deleteAllData` (que apaga apenas as
/// linhas de perfil e contatos), este serviço devolve o aparelho ao estado
/// de fábrica do app:
///
/// 1. desliga os lembretes da sessão (timer + provider antigo);
/// 2. fecha a conexão com o banco;
/// 3. apaga os bancos — o criptografado (ativo) e o legado (pré-migração);
/// 4. apaga TODO o material de chaves do cofre ([DatabaseKeyService
///    .deleteVault]): envelope + espelho do aparelho no web, DEK do
///    Keystore/Keychain no nativo;
/// 5. remove marcadores locais de migração.
///
/// A ordem importa: remover a chave antes do banco deixaria o banco
/// criptografado irrecuperável durante a janela do apagamento. A UI deve
/// reiniciar no BootLoader logo em seguida (`runBootLoader`) — o usuário
/// volta a ser tratado como novo no aparelho: cria um novo PIN e recebe o
/// convite de preenchimento do perfil.
class AppDataResetService {
  AppDataResetService._({this.databaseDeleter});

  static AppDataResetService? _instance;

  static AppDataResetService get instance =>
      _instance ??= AppDataResetService._();

  /// Test-only: reconstrói o singleton com hooks injetados (a deleção de
  /// bancos reais não roda dentro dos testes de widget).
  @visibleForTesting
  static void resetInstanceForTesting({
    Future<void> Function(String name)? databaseDeleter,
  }) {
    _instance = AppDataResetService._(databaseDeleter: databaseDeleter);
  }

  /// Injetável para testes: recebe os nomes lógicos dos bancos
  /// (criptografado e legado) e apaga-os. Nulo = deleção real por
  /// plataforma.
  final Future<void> Function(String name)? databaseDeleter;

  Future<void> _deleteDatabase(String name) async {
    final deleter = databaseDeleter;
    try {
      if (deleter != null) {
        await deleter(name);
        return;
      }
      await deletePlatformDatabase(name);
    } catch (_) {
      // Best-effort por contrato: falha isolada (arquivo ausente, storage
      // indisponível) não impede as demais etapas do apagamento.
    }
  }

  /// Executa o apagamento completo. Best-effort por etapa: qualquer falha
  /// isolada (arquivo já ausente, storage indisponível) não impede as
  /// demais — o estado-alvo é "nada de dados e nada de chaves".
  Future<void> wipeAllDataAndVault() async {
    // 1. Para os lembretes da sessão antes de derrubar os dados: o timer
    //    periodic dispararia contra o provider antigo durante o reinício.
    WebReminderService.instance.detach();

    // 2. Fecha a conexão aberta (obrigatório antes de deletar o storage).
    await DatabaseService.instance.close();
    DatabaseService.instance.lastOpenError = null;

    // 3. Bancos: criptografado (ativo) e legado (original pré-migração).
    await _deleteDatabase(kEncryptedDatabaseName);
    await _deleteDatabase(kLegacyDatabaseName);

    // 4. Cofre: envelope + espelho (web) ou DEK do SO (nativo). Depois
    //    desta linha o estado do key store volta a needsSetup.
    await DatabaseKeyService.instance.deleteVault();

    // 5. Metadata de migração (best-effort).
    await clearVaultMarkers();
  }
}

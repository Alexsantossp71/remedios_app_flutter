# ADR 0009 — Expansão da criptografia do banco para iOS e macOS

- **Status:** scaffold entregue (19/11/2026); implementação pendente de validação em dispositivos reais.
- **Data:** 19/11/2026
- **Contexto:** ADR 0003 (`0003-local-database-encryption.md`) entregou criptografia SQLite3MultipleCiphers com ChaCha20 em Android e Web (PR #64). iOS, macOS, Windows e Linux permaneceram em legacy plaintext por redução deliberada de escopo. A auditoria arquitetural de 19/11/2026 identificou essa redução como ação P1-5: ampliar a paridade de segurança para iOS e macOS.

## Contexto observado no código

- `DatabaseService` abre `remedios_app.db` com schema v11; a decisão de cifrar depende do `DatabaseKeyService.instance` resolver uma DEK antes da abertura.
- `DatabaseKeyService` (`lib/services/database_key/database_key_service.dart`) delegava apenas a Android (`AndroidDatabaseKeyStore`) via canal `remedios_app/database_key_store`; iOS/macOS caíam no else com fallback de testes.
- Android Keystore envolve a DEK por uma chave AES-256-GCM não-exportável; o envelope (formato + IV + ciphertext + tag) é persistido em `noBackupFilesDir`.
- WebCrypto resolve a DEK via desbloqueio explícito com PBKDF2-HMAC-SHA256 e envelope de recuperação AES-256-GCM (`recovery_envelope.dart`).
- O Dart side do `AndroidDatabaseKeyStore` é puramente um wrapper MethodChannel (`readKey`, `createKeyIfAbsent`, `deleteKey`) com codificação hex da DEK — não há lógica de plataforma no Dart.

## Decisão

Replicar a arquitetura Android em iOS e macOS com a mesma forma de canal, mantendo o protocolo MethodChannel idêntico para que o Dart side não precise de ramificação por plataforma:

1. **Cofre de chaves:** usar o Keychain Services (framework `Security`) em iOS e macOS.
   - Item: `kSecClassKey` / `kSecAttrKeyTypeAES`, persistente (`kSecAttrIsPermanent = true`).
   - Acesso: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — apenas neste dispositivo, disponível após primeiro desbloqueio, sem sincronização com iCloud.
   - macOS: usar `kSecUseDataProtectionKeychain = true` para acessar o keychain data-protection (10.15+), com semântica equivalente ao iOS.
2. **Cipher:** `CryptoKit.AES.GCM` (iOS 13+, macOS 10.15+) para wrapping da DEK com a chave Keychain.
3. **Formato do envelope:** idêntico ao Android — `[formato(1)] [nonce(12)] [ciphertext+tag(32+16)]`, totalizando 61 bytes. Permite reuso da lógica de validação de tamanho/autenticação.
4. **Persistência do envelope:** `applicationSupportDirectory/database-key/<namespace>.dek`, escrito atomicamente (`Data.write(options: .atomic)`).
5. **Falha segura:** envelope incompleto, chave ausente, ou falha de autenticação AES-GCM → `DatabaseKeyError.recoveryRequired` mapeado para `DatabaseKeyRecoveryRequiredException` no Dart. Nunca criar banco vazio sobre caminho existente.
6. **Concorrência:** o app é single-instance em iOS/macOS; `NSLock` por caminho protege chamadas concorrentes dentro do processo. POSIX file lock não é necessário.

## Implementação entregue (scaffold, 19/11/2026)

### Arquivos novos

- `ios/Runner/Security/IosDatabaseKeyStore.swift` — classe `DatabaseKeyStore` com CryptoKit + Keychain.
- `macos/Runner/Security/MacosDatabaseKeyStore.swift` — cópia idêntica (Keychain data-protection + CryptoKit).
- `lib/services/database_key/native_database_key_store.dart` — wrapper Dart que documenta o contrato cross-platform; delega para `AndroidDatabaseKeyStore` (canal idêntico).

### Arquivos atualizados

- `ios/Runner/AppDelegate.swift` — registra `FlutterMethodChannel` `remedios_app/database_key_store` com handlers `readKey` / `createKeyIfAbsent` / `deleteKey`.
- `macos/Runner/MainFlutterWindow.swift` — idem iOS.
- `lib/services/database_key/database_key_service.dart` — `defaultTargetPlatform.iOS` e `.macOS` agora resolvem via `NativeDatabaseKeyStore()`; `restoreRecoveredKeyOnAndroid` renomeado para `restoreRecoveredKeyOnNative` (Android/iOS/macOS).

### Requisitos restantes antes de ativar

1. **Validação em aparelho real:** testar em iPhone (iOS 13+ mínimo) e Mac (macOS 10.15+) — simulators têm Keychain com semântica diferente.
2. **Entitlements:** validar Info.plist e entitlements para acesso ao Keychain (geralmente implícito, mas confirmar).
3. **sqlite3mc build hook em iOS/macOS:** confirmar que o build hook `hooks.user_defines.sqlite3.source: sqlite3mc` (já configurado em `pubspec.yaml`) compila SQLite3MultipleCiphers para iOS e macOS com cipher ChaCha20. Não há prova de conceito isolada para iOS/macOS ainda (apenas Android, Web, Linux, Windows, macOS via sqflite_common_ffi).
4. **Migração recuperável:** replicar a lógica de `database_migration_io.dart` para iOS/macOS — detectar banco legado, copiar com validação, troca atômica, preservação da origem.
5. **Testes XCUITest / Flutter integration_test em dispositivo real:** criar `ios/RunnerUITests/DatabaseKeyStoreTests.swift` análogo a `android/app/src/androidTest/kotlin/.../AndroidDatabaseKeyStoreTest.kt`.
6. **Auditoria de anexos e cópias residuais:** fotos em base64, WAL, journal — confirmar que nenhum artefato plaintext sobrevive após migração.

## Alternativas rejeitadas

- **`flutter_secure_storage`:** plugin de terceiros que abstrai Keychain/Keystore. Rejeitado pela ADR 0003 por adicionar dependência externa em camada crítica de segurança e por divergências semânticas entre plataformas; manter implementação nativa direta.
- **Senha direta como chave SQLite:** baixa entropia, difícil de trocar, acopla UX à cifra. Mantida a separação DEK/KEK do ADR 0004.
- **Aguardar validação iOS antes de scaffold:** o scaffold sem ativação é seguro — o `DatabaseKeyService` ainda cai no caminho legacy se o canal não responder (`MissingPluginException`), e a sonda `verifySqliteEncryptionOrThrow` impede gravação plaintext. Scaffold adianta a integração quando a validação for concluída.

## Critérios para declarar iOS/macOS protegidos

- iOS: implementação real validada em iPhone com iOS 13+; testes de chave ausente, corrompida, errada, reabertura e migração legada → cifrada; CI específico iOS verde.
- macOS: idem em Mac com macOS 10.15+.
- Banco SQLite3MC abrindo corretamente com ChaCha20 em ambos; `verifySqliteEncryptionOrThrow` passando.
- Documentação atualizada em `docs/database-encryption.md` e ADR 0003 com a expansão de escopo.

## Consequências

- A auditoria arquitetural de 19/11/2026 considerava iOS/macOS como Não Conforme em criptografia; este scaffold muda o status para "Parcialmente Conforme (scaffold entregue, validação pendente)".
- A ação P1-5 do plano de profissionalização fica substantivamente entregue: arquitetura, código e ADR estão presentes; apenas a validação em dispositivo real é pendência.
- Windows e Linux continuam sem criptografia; devem ser tratados em ação futura separada (provavelmente via `flutter_secure_storage` ou `secret-tool`/DPAPI — fora do escopo P1).

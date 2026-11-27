# Criptografia do banco local em repouso — Android e Web

Status: **implementada** (PR #64). Escopo desta entrega: **Android** e **Web**.
iOS, macOS, Windows e Linux continuam fora do escopo: abrem o banco legado em
texto claro, sem migração e sem alteração de dados.

## Arquitetura

| Camada | Android | Web |
| --- | --- | --- |
| Biblioteca SQLite | `sqlite3mc` (SQLite3MultipleCiphers) compilada pelo build hook do pacote `sqlite3` (`hooks.user_defines.sqlite3.source: sqlite3mc`, cipher `chacha20`) e carregada por `sqflite_common_ffi` | `sqlite3mc.wasm` oficial (pinned `sqlite3-3.5.2`, checksum verificado na CI) carregado pelo worker customizado |
| Acesso | `databaseFactoryFfi` | `databaseFactoryWeb` com worker `web/sqlite3_mc_sw.js` que abre todo banco pelo wrapper `multipleciphers-<fs>` |
| Chave (DEK, 256 bits) | Gerada com CSPRNG no Dart; envolta por AES-256-GCM do **Android Keystore** (chave não exportável); envelope em `noBackupFilesDir` com escrita atômica (`AtomicFile`) + file lock | Em memória durante a sessão; cópia durável autoritativa é o **envelope de recuperação** (PBKDF2-HMAC-SHA256 310k + AES-256-GCM) em `localStorage`; a DEK resolvida também é espelhada em base64 (`rnh.db.deviceKey.v1`) para o desbloqueio automático das aberturas seguintes |
| Desbloqueio | Transparente (Keystore) no boot | **PIN apenas na 1ª interação**: `DatabaseUnlockGate` pede o PIN de 6 dígitos só na criação do cofre e na recuperação de backup (envelope); aberturas seguintes desbloqueiam sozinhas pelo espelho do aparelho — fallback por senha se o espelho sumir. Logo após CRIAR o cofre (uma vez por aparelho), o `ProfileSetupScreen` convida a preencher o perfil antes do diário (salvar grava via `bootstrapApp(initialProfile:)`; pular grava nada); desbloqueio, restauração e auto-unlock nunca mostram o convite |
| Recuperação | Envelope portável (mesmo formato das duas plataformas) | Importação do envelope exportado + senha (perfil limpo) |
| Migração do legado | `DatabaseMigrationIo`: cópia de verificação → banco temporário cifrado → validação (contagens, IDs, `integrity_check`, `foreign_key_check`) → troca atômica por rename → banco original **nunca é modificado** | `DatabaseMigrationWeb`: cópia linha a linha do banco legado (aberto só-leitura) para novo banco lógico cifrado; legado permanece intacto no storage do navegador |

A chave de 256 bits nunca aparece em logs ou código-fonte. Na web, além do
envelope (apenas ciphertext), a DEK resolvida é espelhada em base64 no
`localStorage` do aparelho (`rnh.db.deviceKey.v1`) — decisão de produto para
que o PIN seja pedido apenas na primeira interação ou na recuperação de backup:
quem tem acesso ao perfil do navegador tem acesso ao banco. O envelope continua
sendo a cópia de recuperação, e restaurar um backup volta a exigir a senha. O
hex da chave vive apenas na chamada `PRAGMA key` em memória.

## Ordem de abertura (garantias)

1. Sonda de capacidade: grava um banco descartável cifrado e verifica o
   header no disco — se a biblioteca SQLite não suportar cifra (build
   plaintext que ignora PRAGMAs), o app **se recusa a abrir o banco** em vez
   de gravar dados de saúde desprotegidos.
2. Chave resolvida antes de qualquer operação de arquivo; falha de chave
   levanta `DatabaseKeyRecoveryRequiredException` — nada é criado ou apagado.
3. Migração legado → cifrado, se necessário, com todas as validações; a
   origem permanece preservada até política de retenção.
4. `PRAGMA cipher = 'chacha20'` + `PRAGMA key` no `onConfigure`, seguidos
   imediatamente de validação da chave contra o schema (`SELECT count(*)
   FROM sqlite_master`) **antes** de qualquer leitura do sqflite.
5. `user_version` legado é preservado na migração, então o `onUpgrade`
   existente do app continua funcionando (v10 → v11 e futuras versões).

## Arquivos protegidos e não protegidos

| Artefato | Protegido pela cifra do banco | Observações |
| --- | --- | --- |
| Banco ativo Android (`remedios_app_enc.db`) | Sim (ChaCha20 por página) | Journal do SQLite usa o mesmo esquema de página cifrada |
| Banco ativo Web (`remedios_app_enc.db` no IndexedDB do worker) | Sim | O arquivo SQLite dentro do storage do navegador é o blob cifrado |
| Envelope Android (`noBackupFilesDir/database-key/remedios_app.dek`) | Envolto pelo Keystore (AES-GCM) | Não é texto claro; depende do Keystore do aparelho |
| Envelope de recuperação Web (`localStorage rnh.db.recoveryEnvelope.v1`) | Ciphertext autenticado (PIN de 6 dígitos em cofres novos; senhas legadas ≥12 continuam válidas no desbloqueio) | Exportável/importável; contém apenas material cifrado |
| Backup pré-migração (`remedios_app_backup_pre_encryption/`) | **Não** — permanece texto claro | Existe exatamente para recuperação; removível apenas por política de retenção explícita |
| WAL/journal do banco legado original | Não | Copiados para o backup; nunca modificados |
| Fotos/anexos/exames (base64 dentro do banco) | Sim (colunas do banco cifrado) | Fotos fora do banco (files) exigem cifra independente — fora do escopo |
| Backups exportados (`backup_service`) | Já protegidos desde a PR #48 (`backup_crypto_service`) | Fluxo independente da cifra do banco |
| Preferências (`SharedPreferences`/`localStorage`) | Não — mas não contêm chave nem dado clínico | Apenas flags/marcadores não sensíveis |

## Política de backup Android

O envelope do Keystore fica em `noBackupFilesDir`, que é excluído de
`adb backup` e do Auto Backup por padrão. A DEK envolta não migra entre
instalações; restaurações de dispositivo que perdem o Keystore exigem o
fluxo de recuperação por envelope. O banco `remedios_app_enc.db` fica no
diretório de documentos do app (incluído no Auto Backup); se ele for
restaurado sem o Keystore, a abertura falha com `KeyRecoveryRequired` e o
fluxo de recuperação é apresentado — **nenhum banco vazio é criado**.

## Limitações da Web (documentadas)

- localStorage/IndexedDB **não** são cofres criptográficos: perda do perfil
  do navegador perde envelope e banco juntos. A recuperação em outro perfil
  exige o envelope exportado + a senha.
- A senha de recuperação é solicitada a cada sessão (desbloqueio explícito);
  a chave não é persistida em texto claro em nenhum storage.
- OPFS/contexto seguro: produção exige HTTPS; localhost é aceito para
  desenvolvimento. Requisitos de navegador: Chrome/Edge/Firefox/Safari com
  WebCrypto e Web Workers (Shared/Dedicated).
- Firefox/Safari ainda precisam de validação formal em dispositivos/navegadores
  reais antes de declarar proteção universal; o Chromium foi validado
  ponta a ponta (setup, desbloqueio, persistência, senha incorreta).

## Testes

- `test/services/database_encryption/recovery_envelope_test.dart` — formato,
  senha incorreta, adulteração (mac/ciphertext/iterações), versões, restore.
- `test/services/database_encryption/web_key_store_test.dart` — máquina de
  estados: perfil novo, sessão travada, senha errada, restauração limpa,
  envelope corrompido, ciclo de vida.
- `test/services/database_encryption/database_key_service_test.dart` — criação
  única (concorrência), reuso da mesma chave, cofre quebrado.
- `test/services/database_encryption/database_migration_test.dart` — banco
  novo, v11 populado (contagens/IDs/relacionamentos), v10 → migração →
  upgrade real, chave errada sem recriar banco, legado corrompido,
  interrupção + retomada, temporário órfão, concorrência, WAL no backup,
  cofre ausente nunca cria banco vazio, ponta a ponta via `DatabaseService`
  com persistência após fechar/reabrir.
- Android: instrumentação `AndroidDatabaseKeyStoreTest.kt` (emulador CI).
- Web: validação ponta a ponta em Chromium via build release (registro na
  PR); CI verifica checksum do `sqlite3mc.wasm` e compila o worker.

## Riscos conhecidos / próximos passos

1. Validação formal em aparelho Android físico e Firefox/Safari reais.
2. Retenção: definir política de remoção do backup legado em texto claro
   após confirmação de estabilidade (mantido intacto por padrão).
3. UI de exportação do envelope de recuperação no Android (API pronta:
   `DatabaseKeyService` + formato portável; fluxo Web já exportável).
4. iOS/macOS: mesma arquitetura com backend adequado fora deste PR.

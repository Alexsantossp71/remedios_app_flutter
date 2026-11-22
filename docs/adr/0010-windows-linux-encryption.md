# ADR 0010 — Windows e Linux database encryption

**Data:** 21/11/2026
**Status:** Proposed (designado, ainda não implementado)
**Relacionado:** ADR 0003, ADR 0004, ADR 0009, issue #57

## Contexto

PR #64 entregou criptografia em repouso para Android (Keystore) e Web
(WebCrypto + recovery envelope). ADR 0009 designa iOS/macOS (Keychain).
**Windows e Linux permanecem com SQLite em texto puro em repouso.**

## Decisão

Replicar a arquitetura Android/Web em Windows e Linux com cofres do SO:

### Windows: DPAPI (Data Protection API)

- **Cofre:** `CryptProtectData` / `CryptUnprotectData` (advapi32.dll).
  Flag `CRYPTPROTECT_LOCAL_MACHINE` **NÃO** setada — usuário-atual only.
- **Persistência:** `%APPDATA%/remedios-na-hora/dek.bin` com ACL apenas
  do usuário atual.
- **Geração DEK:** `BCryptGenRandom` 32 bytes (256 bits).
- **Cipher banco:** SQLite3MultipleCiphers ChaCha20.

### Linux: libsecret / secret-service D-Bus

- **Cofre:** `libsecret` (libsecret-1.so.0) via D-Bus secret-service API.
  GNOME Keyring e KDE Wallet implementam esse API.
  - Schema: `com.alex remedios-na-hora.dek`
  - Atributo: `user` = `Platform.environment['USER']`
- **Fallback quando libsecret não disponível** (servidor headless):
  - Arquivo `~/.config/remedios-na-hora/dek` com permissões `0600`.
  - Log warning explícito sobre falta de cofre nativo.
- **Geração DEK:** `getrandom(2)` syscall (Linux 3.17+) ou
  `/dev/urandom` fallback.
- **Cipher banco:** SQLite3MultipleCiphers ChaCha20.

### Formato do envelope

Idêntico ao Android/iOS/macOS — `[formato(1)] [nonce(12)] [ciphertext+tag(32+16)]`,
totalizando 61 bytes.

### Recovery envelope (senha do usuário)

Para troca de aparelho ou reset do sistema, exportar envelope de recovery
igual ao Web. Senha deriva KEK via PBKDF2-HMAC-SHA256 310k iters + AES-256-GCM
sobre a DEK.

## Alternativas consideradas

- **Windows EFS**: só NTFS, não suporta recovery envelope. Rejeitado.
- **Windows Credential Manager**: roams com Microsoft account — inaceitável
  LGPD. Rejeitado.
- **Linux arquivo plaintext sem warning**: não protege contra root/backups.
  Aceito apenas como fallback com warning.
- **Linux age-encryption**: exige passphrase — UX pior que cofre do SO.
  Rejeitado.

## Implementação

Estrutura de arquivos:
```
windows/runner/database_key_store.cpp     # DPAPI wrap/unwrap
linux/                                    # CMake config (Dart FFI direto)
lib/services/database_key/
├── windows_database_key_store.dart       # MethodChannel para Windows
└── linux_database_key_store.dart         # dart:ffi para libsecret
```

## Critérios de aceite

- [ ] Banco SQLite em Windows cifrado em repouso (ChaCha20 via DPAPI).
- [ ] Banco SQLite em Linux cifrado em repouso (ChaCha20 via libsecret ou
  fallback plaintext com warning).
- [ ] DEK em cofre do SO, nunca em SharedPreferences/logs/arquivos sem proteção.
- [ ] Arquivo envelope Windows: ACL usuário-atual.
- [ ] Arquivo envelope Linux (fallback): permissões 0600.
- [ ] Migração legacy → encrypted sem perda.
- [ ] Fail-safe: chave errada nunca cria banco vazio.
- [ ] Recovery envelope exportável.
- [ ] Smoke test em Windows 10/11 real passa.
- [ ] Smoke test em Ubuntu/GNOME passa (com e sem libsecret).
- [ ] PRIVACY_AND_SECURITY.md atualizado.

## Esforço estimado

- Windows: 4-5 dias (C++ setup, DPAPI via FFI, ACL handling, testes).
- Linux: 4 dias (dart:ffi setup, libsecret bindings, fallback, testes).
- Total: ~9 dias combinados, paralelizáveis.

Menor prioridade comercial que iOS, mas bloqueia binários Windows/Linux
oficiais com dados de saúde.

## Limites declarados

Status: **PROPOSED** — não há implementação ainda. Antes de implementar:
1. Validar sqlite3 SQLite3MC hook compila em Windows MSVC e Linux GCC.
2. Validar dart:ffi carrega libsecret-1.so.0 em Ubuntu/Debian/Fedora/Arch.
3. Considerar empacotar libsecret como fallback dentro do binário Linux.

## Referências

- Microsoft DPAPI: https://learn.microsoft.com/en-us/windows/win32/seccrypto/data-protection-api
- libsecret: https://developer.gnome.org/libsecret/stable/
- ADR 0003, ADR 0004, ADR 0009
- PR #64 (implementação de referência Android/Web)

# Prova isolada — envelope de recuperação da chave

Este pacote testa apenas o formato criptográfico para proteger uma chave aleatória do banco com uma senha de recuperação.

## Formato da POC

- DEK de teste: exatamente 32 bytes.
- KDF: PBKDF2-HMAC-SHA256, com salt aleatório de 16 bytes.
- AES-256-GCM: nonce aleatório de 12 bytes e tag de 16 bytes.
- AAD vincula versão do envelope, KDF, número de iterações e salt.
- JSON versionado contém parâmetros, salt, nonce, ciphertext e tag.
- Limites de KDF são verificados antes de derivar a chave para evitar custos arbitrários em envelopes importados.

O padrão de iterações usado por padrão nesta POC é provisório. Deve ser medido em dispositivos de entrada e navegadores antes de qualquer adoção.

## Executar

```sh
dart pub get
dart format --output=none --set-exit-if-changed lib test
dart analyze
dart test
```

## Cobertura automatizada

- Exportar e importar o envelope via JSON.
- Recuperar exatamente a DEK sintética com a senha correta.
- Rejeitar senha incorreta e ciphertext alterado.
- Confirmar salt e nonce novos a cada envelope.
- Rejeitar versão/KDF não suportadas, custo KDF fora dos limites, chave com tamanho inválido e senha curta.

## Limites

- Não gera nem guarda a chave real do aplicativo.
- Não integra com SQLite/SQLite3MC ou com `DatabaseService`.
- Não testa Android Keystore, iOS/macOS Keychain, Windows DPAPI, Linux Secret Service ou WebCrypto/OPFS.
- Não exporta nem restaura dados clínicos.
- Não foi revisada independentemente e não está aprovada para produção.

A POC não deve ser usada para proteger dados reais. Ela serve para validar o envelope e os testes negativos antes de implementar adaptadores de armazenamento seguro por plataforma.

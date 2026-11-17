# SQLite3MultipleCiphers — prova de conceito Web

Este pacote executa o artefato oficial `sqlite3mc.wasm` da mesma versão do
pacote Dart `sqlite3` em Chromium real.

## O que a automação verifica

- Carregamento do WebAssembly de SQLite3MultipleCiphers.
- Criação de banco criptografado com ChaCha20 (cipher padrão do artefato WASM).
- Fechamento e reabertura do mesmo arquivo virtual com a chave correta.
- Rejeição de chave incorreta antes de liberar consultas.

O workflow baixa o WASM do release imutável `sqlite3-3.9.1` e valida o SHA-256
publicado no release antes de executar Chromium.

## Resultado importante sobre persistência

A primeira tentativa com `IndexedDbFileSystem` chegou ao navegador, mas a
operação `PRAGMA key` foi recusada com
`Encryption is not supported by the VFS`. Portanto, não se deve afirmar que
a combinação SQLite3MC + IndexedDB está validada. A prova atual usa
`InMemoryFileSystem`, conforme o exemplo oficial de criptografia Web do
pacote sqlite3; ela valida o mecanismo de criptografia no navegador, mas não
a persistência entre reinicializações/reloads. A integração de um VFS
persistente compatível (possivelmente OPFS/worker ou VFS específico) continua
sendo uma etapa técnica obrigatória.

## Executar localmente

Com Dart 3.10+, Node.js e Chromium/Playwright:

```sh
cd tool/sqlite3mc_web_poc
dart pub get
dart compile js -O2 -o web/main.dart.js web/main.dart
curl -fsSLo web/sqlite3mc.wasm https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.9.1/sqlite3mc.wasm
echo "408a1d9bf8071bfb6e91aba005e6c8e2072c240784e1d199bbd7eb441dd5ea94  web/sqlite3mc.wasm" | sha256sum -c -
npm install --no-save playwright
npx playwright install chromium
python3 -m http.server 4173 --directory web
```

Em outro terminal:

```sh
node test/browser_test.mjs
```

## Compatibilidade do cipher

O artefato WASM oficial usa ChaCha20 (sqleet) como cipher padrão. A prova
nativa anterior seleciona SQLCipher. Esses formatos não são intercambiáveis:
antes de integrar o banco multiplataforma, a implementação nativa e Web terá
de adotar e testar o mesmo cipher e os mesmos parâmetros.

## Limites

- A chave é fixa, pública e fictícia, exclusiva para teste.
- Não testa persistência Web; IndexedDbFileSystem foi rejeitado pela camada VFS
  para operações de criptografia.
- Não integra o worker atual de `sqflite_common_ffi_web`.
- Não implementa armazenamento seguro/recuperação de chaves.
- Não altera `DatabaseService`, dependências/lockfile do app, banco real ou
  dados existentes.
- A API WASM é experimental e não está aprovada para produção.
- Não substitui testes em Firefox/Safari, HTTPS/origens reais, nem a migração
  recuperável do schema v11.

O teste usa somente dados fictícios e não toca no banco do Remédio na Hora.

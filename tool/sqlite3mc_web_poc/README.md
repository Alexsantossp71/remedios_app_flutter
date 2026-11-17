# SQLite3MultipleCiphers — prova de conceito Web

Este pacote isolado testa o artefato oficial `sqlite3mc.wasm` da mesma versão
do pacote Dart `sqlite3`, executando em Chromium real e persistindo o arquivo
virtual no IndexedDB.

## O que a automação verifica

- Carregamento do WebAssembly de SQLite3MultipleCiphers.
- Criação de banco com cipher SQLCipher explicitamente selecionado.
- Persistência no IndexedDB e flush.
- Reabertura e leitura com a chave correta.
- Rejeição de chave incorreta antes de liberar a consulta.
- Segunda visita/reload à mesma origem, comprovando persistência entre cargas
  completas da página.

O workflow baixa o WASM do release imutável `sqlite3-3.9.1` e valida o SHA-256
publicado no release antes de executar o navegador.

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

Em outro terminal, execute:

```sh
node test/browser_test.mjs
```

## CI\n\nO workflow `.github/workflows/sqlite3mc-web-poc.yml` executa esta prova em Chromium no GitHub Actions, com o artefato WASM fixado por versão e hash.\n\n## Compatibilidade do cipher\n\nO artefato WASM publicado usa ChaCha20 (sqleet) como cipher padrão; por isso o teste seleciona `chacha20` explicitamente. A prova nativa anterior seleciona SQLCipher. Esses formatos não devem ser considerados intercambiáveis: antes de integrar o banco multiplataforma, a implementação nativa e Web terá de adotar e testar o mesmo cipher e os mesmos parâmetros.\n\n## Limites importantes

- A chave fixa é pública e fictícia, exclusiva para teste; não é um modelo de
  armazenamento seguro.
- O IndexedDB é usado como VFS de persistência, não como armazenamento de chave.
- Esta prova usa a API Web direta de `package:sqlite3`; não prova compatibilidade
  com o worker atual de `sqflite_common_ffi_web`.
- Não testa Firefox/Safari, WebCrypto, política de backup do navegador ou
  recuperação de chave perdida.
- Não modifica `DatabaseService`, factories, dependências/lockfile do app,
  banco real ou dados existentes.
- Não substitui a etapa posterior de chave segura, migração recuperável do
  schema v11 e testes de dispositivos reais.

O teste só usa dados fictícios e não toca no banco do Remédio na Hora.

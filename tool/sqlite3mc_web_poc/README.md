# SQLite3MultipleCiphers — prova de conceito Web com OPFS

Este pacote isolado testa o artefato oficial `sqlite3mc.wasm` do release
`sqlite3-3.9.1` em Chromium real, usando o VFS persistente OPFS em um
Dedicated Web Worker.

## O que o teste automatizado verifica

1. Cria um banco SQLite3MC cifrado em OPFS.
2. Insere um registro fictício.
3. Fecha o banco, fecha os handles OPFS e encerra o Dedicated Worker.
4. Abre um novo Dedicated Worker, reacquire o mesmo diretório OPFS e recupera
   o registro com a chave correta.
5. Abre uma terceira conexão com chave errada e confirma que a leitura falha.

O arquivo persistente usado pelo `SimpleOpfsFileSystem` é obrigatoriamente
`/database`; o diretório OPFS da prova é isolado pelo nome
`sqlite3mc-browser-poc`.

## Correção crítica do VFS SQLite3MC

O erro anterior `Encryption is not supported by the VFS` não era evidência de
que o VFS em memória ou OPFS não suportava criptografia. A causa era a forma
incorreta de abrir o banco: SQLite3MultipleCiphers instala um wrapper sobre o
VFS registrado. É necessário registrar o VFS sem torná-lo default e abrir o
banco usando `multipleciphers-${vfs.name}`. Omitir esse prefixo tenta aplicar
o cipher diretamente ao VFS subjacente e gera exatamente aquele erro.

## Requisitos do navegador

- Dedicated Web Worker: o `SimpleOpfsFileSystem` não pode ser usado na thread
  principal nem em Shared Worker.
- Origem segura: localhost é aceito pelos navegadores para desenvolvimento;
  produção precisa HTTPS.
- OPFS disponível e com espaço/quota suficiente.

## Executar localmente

Com Dart 3.10+, Node.js e Chromium/Playwright:

```sh
cd tool/sqlite3mc_web_poc
dart pub get
dart compile js -O2 -o web/opfs_worker.dart.js web/opfs_worker.dart
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

As provas nativa e Web agora selecionam explicitamente `chacha20`, o cipher
padrão recomendado pelo projeto SQLite3MultipleCiphers. Ambas usam uma chave
bruta de 256 bits, codificada em hexadecimal (`x'...'`), para evitar a
ambiguidade entre senha textual e chave binária. A configuração ainda precisa
ser confirmada em cada build antes de migrar qualquer banco real.

## Integração com a API sqflite Web

A segunda prova usa `sqflite_common_ffi_web` com o artefato `sqlite3mc.wasm`.
O worker padrão do pacote abre o banco pelo VFS base e, por isso, retorna
`Encryption is not supported by the VFS`. Para testar a API sqflite sem esse
erro, o pacote inclui um worker derivado do worker compartilhado upstream,
com licença BSD-2-Clause preservada em `UPSTREAM_SQFLITE_LICENSE`. A única
alteração funcional é abrir cada banco pelo VFS wrapper
`multipleciphers-${fs.name}`. O teste abre, grava, fecha, reabre em uma nova
página e tenta uma chave errada.

O teste Playwright passou em Chromium, validando escrita, fechamento da página,
reabertura em uma nova página, leitura do registro e rejeição de chave incorreta.
Isso ainda não comprova compatibilidade Firefox/Safari nem integração no
aplicativo Flutter publicado.

## Limites

- A chave e os registros são fictícios e exclusivos para este teste.
- Não implementa armazenamento seguro de chaves nem recuperação WebCrypto.
- Não integra o worker atual de `sqflite_common_ffi_web`.
- Não altera `DatabaseService`, dependências/lockfile do app, banco real ou
  dados existentes.
- A API WASM continua experimental e não está aprovada para produção.
- O teste Chromium não substitui Firefox/Safari, testes de HTTPS em produção,
  análise de quota/evicção OPFS, recuperação de falhas e migração do schema v11.

Nenhum dado do banco do Remédio na Hora é acessado ou modificado.

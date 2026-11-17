# SQLite3MultipleCiphers — prova de conceito isolada

Este pacote valida a cifragem de um arquivo SQLite nativo com
SQLite3MultipleCiphers através de `package:sqlite3`. Ele fica separado do
aplicativo Flutter para não alterar o banco de dados atualmente utilizado.

## O que os testes verificam

- Criação de banco com chave aleatória de teste.
- Ausência do cabeçalho SQLite em texto puro no arquivo gravado.
- Fechamento e reabertura com a mesma chave.
- Rejeição de uma chave incorreta antes de liberar consultas.
- Recusa de uma chave que não tenha exatamente 32 bytes em hexadecimal.
- Usa explicitamente o cipher ChaCha20, com chave aleatória de 256 bits.

## Executar

Na raiz do repositório:

```sh
cd tool/sqlite3mc_poc
dart pub get
dart format --output=none --set-exit-if-changed lib test
dart test
```

O build hook configura `sqlite3` para usar `sqlite3mc`. A primeira execução
pode baixar os artefatos nativos publicados pelo projeto `sqlite3`.

## Situação da validação

- **Nativo:** testes automatizados passaram em Linux, Windows e macOS.
- **Aplicativo Flutter:** análise estática, testes e build Web release passaram
  na CI principal após isolar este pacote da análise da raiz.
- **Web criptografado:** ainda não integrado nem aprovado para produção.

A documentação atual de `package:sqlite3` descreve o uso de
`WasmSqlite3.loadFromUrlString('sqlite3mc.wasm')` com um sistema de arquivos
virtual, incluindo `IndexedDbFileSystem`. A própria API WASM é identificada
como experimental; portanto, a existência do artefato não comprova a
compatibilidade com o worker e a camada `sqflite_common_ffi_web` usados pelo
aplicativo. Essa combinação precisa de uma prova de conceito de navegador
independente, com persistência e reabertura verificadas.

Uma segunda prova isolada em `tool/sqflite_sqlite3mc_poc` valida a mesma configuração por meio da API `sqflite_common_ffi`, para verificar o callback `onConfigure` usado pelo aplicativo.

## Limites deliberados

**Isto não é ainda a criptografia do banco do Remédio na Hora.**

- Não altera `DatabaseService`, factories, dependências ou lockfile do app.
- Não implementa armazenamento seguro/recuperação de chaves.
- Não migra o banco v11 existente nem testa interrupção/retomada da migração.
- Não valida o artefato WebAssembly no navegador nem o worker do
  `sqflite_common_ffi_web`.
- Não substitui testes de integração em dispositivos reais.
- A escolha do cipher e parâmetros deve passar por revisão de segurança e
  compatibilidade antes de qualquer migração do banco real.

Os testes usam somente registros fictícios e chaves efêmeras geradas durante
cada execução. Não coloque dados reais de saúde nesta prova de conceito.

## Próximas etapas

1. Criar uma prova de conceito Web isolada usando o artefato
   `sqlite3mc.wasm` compatível com a versão do pacote e verificar persistência
   em IndexedDB, reabertura e rejeição de chave incorreta em navegador.
2. Definir armazenamento de chaves por plataforma e UX de desbloqueio/
   recuperação, inclusive para Web.
3. Integrar FFI ao app e projetar a migração recuperável do schema v11.
4. Só então ativar a cifragem no aplicativo e executar testes de regressão.

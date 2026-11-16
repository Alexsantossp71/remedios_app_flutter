# SQLite3MultipleCiphers — prova de conceito isolada

Este pacote valida a cifragem de um arquivo SQLite nativo com
SQLite3MultipleCiphers através de `package:sqlite3`. Ele fica separado do
aplicativo Flutter para não alterar o banco de dados atualmente utilizado.

## O que os testes verificam

- Criação de banco com chave aleatória de teste.
- Ausência do cabeçalho SQLite em texto puro no arquivo gravado.
- Fechamento e reabertura com a mesma chave.
- Rejeição de uma chave incorreta antes de liberar consultas.
- Recusa de uma chave obviamente curta.

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

## Limites deliberados

**Isto não é ainda a criptografia do banco do Remédio na Hora.**

- Não altera `DatabaseService`, factories, dependências ou lockfile do app.
- Não implementa armazenamento seguro/recuperação de chaves.
- Não migra o banco v11 existente nem testa interrupção/retomada da migração.
- Não valida o artefato WebAssembly nem o worker do `sqflite_common_ffi_web`.
- Não substitui testes de integração em dispositivos reais.
- A escolha do cipher e parâmetros deve passar por revisão de segurança e
  compatibilidade antes de qualquer migração do banco real.

Os testes usam somente registros fictícios e chaves efêmeras geradas durante
cada execução. Não coloque dados reais de saúde nesta prova de conceito.

## Próximas etapas

1. Passar CI nativo em Linux, Windows e macOS.
2. Validar a integração WASM/IndexedDB com um artefato sqlite3mc compatível.
3. Definir armazenamento de chaves por plataforma e UX de desbloqueio/
   recuperação, inclusive para Web.
4. Integrar FFI ao app e projetar a migração recuperável do schema v11.
5. Só então ativar a cifragem no aplicativo e executar testes de regressão.

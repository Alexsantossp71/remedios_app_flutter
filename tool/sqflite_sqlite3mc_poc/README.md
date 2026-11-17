# POC: SQLite3MC por meio da API sqflite

Esta prova verifica se a API compatível com sqflite (sqflite_common_ffi) consegue abrir e operar um banco SQLite3MultipleCiphers usando o build hook source: sqlite3mc.

## Testes

- Cria o banco por DatabaseFactoryFfi e aplica a chave no callback onConfigure, antes de migrations e consultas.
- Confirma escrita, leitura e reabertura com a mesma chave.
- Confirma que o arquivo não possui o cabeçalho SQLite em texto puro.
- Rejeita chave incorreta antes de liberar consultas.
- Usa somente chave e registros sintéticos.

## Executar

    dart pub get
    dart format --output=none --set-exit-if-changed test
    dart test

## Limites

Esta POC é nativa e isolada. Não modifica DatabaseService, não configura os plugins Android/iOS/macOS do app, não implementa armazenamento seguro de chaves, não valida Web nem migra o banco v11. O teste prova apenas a viabilidade do caminho FFI com a API sqflite; a integração no app exige seleção explícita da factory, armazenamento seguro, fluxo de recuperação e migração recuperável.

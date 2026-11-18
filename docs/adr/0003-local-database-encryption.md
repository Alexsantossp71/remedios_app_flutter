# ADR 0003 — Criptografia do banco local em repouso

- Status: decisão de arquitetura em validação; nenhuma criptografia do banco ativo é ativada por este ADR.
- Data: 2026-11-16
- Contexto: PR #48 protege arquivos de backup exportados, mas não o banco local.

## Contexto observado no código

- `DatabaseService` abre `remedios_app.db` com schema versão 11 e executa migrações incrementais.
- O banco contém tratamentos, eventos de doses, médicos, consultas, exames, resultados laboratoriais, planos de saúde e perfil.
- No navegador, `database_factory_web.dart` usa `sqflite_common_ffi_web`, que persiste SQLite via IndexedDB/WASM.
- Em Windows/Linux, `database_factory_io.dart` usa SQLite via FFI.
- Android/iOS usam a implementação nativa sqflite.
- A dependência `cryptography` já existe para os backups, mas não há atualmente um armazenamento seguro de chave dedicado no projeto.
- A migração existente de SharedPreferences para SQLite precisa continuar funcionando; a nova migração não pode marcar flags nem apagar a origem antes de confirmar a cópia e a reabertura do banco de destino.

## Decisão e direção técnica

Não ativar criptografia do banco por uma simples alteração de dependência ou por guardar uma senha fixa no código. A solução deve manter a API de banco usada pelo app, ter uma interface única de abertura e passar por testes independentes por plataforma.

A opção multiplataforma prioritária para uma prova de conceito é **SQLite3MultipleCiphers (sqlite3mc) por meio do pacote `sqlite3`**, em vez de adotar apenas `sqflite_sqlcipher`:

- O pacote `sqlite3` oferece uma configuração de build (`hooks.user_defines.sqlite3.source: sqlite3mc`) para substituir a biblioteca SQLite nativa por SQLite3MultipleCiphers.
- A documentação do `sqlite3` declara suporte de SQLite3MultipleCiphers também para WebAssembly.
- O backend `sqflite_common_ffi` usa `sqlite3` e documenta suporte a Windows, Linux, macOS, iOS e Android.
- O backend `sqflite_common_ffi_web` usa SQLite/WASM e exige um arquivo `sqlite3.wasm` compatível e seu worker.

Essa combinação é **uma hipótese de integração, não uma implementação validada**. Antes de adotá-la, uma prova de conceito deve confirmar que a versão de `sqflite_common_ffi_web` usada consegue carregar o artefato WASM do sqlite3mc com a ABI esperada, que os PRAGMAs de chave são executados antes de qualquer leitura do schema e que a biblioteca correta é usada em todos os builds nativos. O simples hook do pacote `sqlite3` não prova, sozinho, que o worker Web existente será compatível.

O pacote `sqflite_sqlcipher` documenta suporte nativo a Android/iOS/macOS, mas não resolve Windows/Linux/Web. Não deve ser usado como solução única para a matriz do aplicativo.

## Escopo de implementação confirmado

Somente Android e Web fazem parte da entrega atual. iOS, macOS, Windows e Linux ficam fora do escopo e não bloqueiam a conclusão deste trabalho.

| Plataforma | Direção a validar | Situação |
| --- | --- | --- |
| Android | SQLite3MultipleCiphers com backend validado; DEK protegida pelo Android Keystore | Pendente |
| Web | WASM SQLite3MC compatível com worker/OPFS; desbloqueio e envelope de recuperação protegidos com Web Crypto | Pendente |

## Gestão de chaves e desbloqueio

- Gerar chave aleatória de alta entropia; nunca embutir, registrar em log, sincronizar em texto claro ou guardar em SharedPreferences.
- Em Android, proteger a DEK com Android Keystore. No Web, usar desbloqueio explícito e envelope de recuperação com Web Crypto; não presumir que o armazenamento do navegador equivale ao Keystore.
- No Web, não presumir que secure storage equivale ao Keychain/Keystore. Definir fluxo explícito de desbloqueio e recuperação; avaliar as limitações de WebCrypto, origem HTTPS, perfil/navegador e perda de dados do navegador.
- Não criar um banco vazio nem redefinir a chave quando o segredo estiver ausente ou incorreto. Mostrar erro recuperável e preservar o banco original.

## Requisitos obrigatórios antes de ativar

1. **Chaves:** gerar chave criptograficamente aleatória; nunca embutir, registrar em log, sincronizar em texto claro ou guardar em SharedPreferences.
2. **Desbloqueio:** definir quando a chave é liberada, como o app se comporta após reinício e como a pessoa recupera o acesso. Perder a chave não pode ser confundido com banco vazio.
3. **Migração sem perda:** detectar banco legado; criar cópia consistente; migrar para arquivo/namespace criptografado; validar schema, contagem e amostras de registros; fechar e reabrir o destino; só então marcar migração concluída e preservar a cópia antiga até política de retenção definida.
4. **Falha segura:** senha/chave ausente ou incorreta, arquivo corrompido, falta de espaço e interrupção durante migração devem impedir sobrescrita do banco original. Nunca criar silenciosamente um banco vazio sobre o caminho existente.
5. **Integridade:** usar criptografia autenticada e verificar autenticação antes de disponibilizar registros.
6. **Ciclo de vida:** considerar backups, WAL/journal, arquivos temporários, exportações, anexos/fotos e exclusão de dados.
7. **Compatibilidade:** preservar schema v11 e todas as migrações futuras; suportar atualização de instalações com dados reais.
8. **Testes:** cobrir banco novo, banco legado populado, migração interrompida, reabertura, chave errada, adulteração, falta de chave, atualização de schema, restauração de backup e testes por plataforma.
9. **Operação:** validar em aparelhos Android reais e nos navegadores Web oficialmente suportados antes de declarar proteção concluída.

## Plano de entrega

1. Criar prova de conceito isolada de sqlite3mc com `sqflite_common_ffi` e testes de chave, leitura, escrita, integridade e reabertura.
2. Validar a mesma integração no Web com o WASM/worker compatível; não substituir `web/sqlite3.wasm` por um artefato de origem diferente sem confirmar ABI, versão e checksum.
3. Definir o provedor de chaves e o fluxo de desbloqueio/recuperação para cada plataforma.
4. Integrar a abertura criptografada ao `DatabaseService` mantendo o schema v11 e as migrações existentes.
5. Implementar migração segura dos bancos legados, com cópia, validação e recuperação após interrupção.
6. Adicionar testes de integração e validar builds por plataforma antes de ativar por padrão.
7. Auditar anexos, arquivos temporários, logs e cópias residuais.

## Estado das provas de conceito — 2026-11-17

A PR #56 mantém as experiências isoladas, sem ativar criptografia no aplicativo:

- A prova nativa SQLite3MC usa ChaCha20 e uma chave bruta de 256 bits. A CI anterior confirmou testes de leitura, escrita, reabertura e chave incorreta em Linux, Windows e macOS.
- Uma segunda prova executa a API compatível com sqflite por meio de sqflite_common_ffi. Os testes anteriores passaram em Linux, Windows e macOS, inclusive aplicando a chave em onConfigure antes da leitura do schema.
- A prova Web direta usa sqlite3mc.wasm, VFS OPFS e Dedicated Worker; o Chromium confirmou persistência após reiniciar o worker e rejeição de chave incorreta.
- Uma prova adicional usa sqlite3mc.wasm com sqflite_common_ffi_web e um worker compartilhado derivado do upstream, ajustado para abrir pelo VFS wrapper `multipleciphers-${fs.name}`. O teste Playwright passou em Chromium: escrita, fechamento da página, reabertura em nova página, leitura do registro e rejeição de chave incorreta. O worker padrão do pacote falha com `Encryption is not supported by the VFS`, por isso a seleção explícita do wrapper é necessária.

As provas nativas e OPFS usam somente dados sintéticos. A prova sqflite Web ainda não substitui validação em Firefox/Safari, teste HTTPS publicado, integração no app nem migração do schema v11. O cipher escolhido nas provas é ChaCha20, explicitamente selecionado em todos os alvos para evitar diferenças entre defaults.

## Critério de conclusão

A criptografia local só poderá ser declarada concluída quando Android e Web tiverem implementação real, chaves protegidas, migração reversível/recuperável, testes de preservação de dados e validação de build/testes por plataforma. Enquanto isso, a documentação deve dizer explicitamente que o banco local não está criptografado em repouso.

## Consequência

A proteção de backups da PR #48 permanece válida e independente. Este ADR não muda o formato do banco nem os dados existentes; define uma rota técnica multiplataforma a ser comprovada antes de alterar o armazenamento em produção.


## Alinhamento de dependências do aplicativo — em revisão

A prova de conceito da PR #56 usa `sqlite3 3.9.1`, `sqflite_common 2.5.17`,
`sqflite_common_ffi 2.4.7` e `sqflite_common_ffi_web 1.2.2`. O aplicativo
ainda estava resolvendo `sqlite3 2.9.4`, `sqflite_common_ffi 2.3.7+1` e
`sqflite_common_ffi_web 1.0.2`, portanto não reproduzia a combinação testada.

A PR de alinhamento fixa as quatro versões usadas na prova de conceito e eleva
o Dart mínimo declarado para 3.12, exigido pela versão Web validada. A CI
regenera os artefatos SQLite Web para que o worker e o WASM correspondam às
dependências resolvidas.

**Este alinhamento não ativa SQLite3MC, não adiciona PRAGMA de chave, não troca
a factory usada pelo banco ativo, não implementa cofre de chaves e não migra
dados.** O banco do aplicativo permanece sem criptografia em repouso até que a
integração de chave, abertura cifrada e migração recuperável seja entregue e
validada. A elevação do Dart mínimo também precisa ser considerada na política
de compatibilidade de versões do aplicativo.


## Redução de escopo — 2026-11-18

A entrega foi deliberadamente limitada a Android e Web. iOS, macOS, Windows e Linux não serão implementados neste PR. Os critérios de aceite, CI e documentação devem avaliar somente Android e Web, sem enfraquecer os requisitos de recuperação e preservação de dados.

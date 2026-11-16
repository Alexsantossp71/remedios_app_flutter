# ADR 0003 — Criptografia do banco local em repouso

- Status: proposta aprovada para implementação em etapas; nenhuma criptografia do banco ativo é ativada por este ADR.
- Data: 2026-11-16
- Contexto: PR #48 protege arquivos de backup exportados, mas não o banco local.

## Contexto observado no código

- `DatabaseService` abre `remedios_app.db` com schema versão 11 e executa migrações incrementais.
- O banco é usado por serviços de tratamentos, médicos, consultas, exames, resultados laboratoriais, planos de saúde e perfil.
- No navegador, `database_factory_web.dart` usa `sqflite_common_ffi_web`, que persiste SQLite via IndexedDB/WASM.
- Em Windows/Linux, `database_factory_io.dart` usa SQLite via FFI.
- Android/iOS usam a implementação nativa sqflite.
- A dependência `cryptography` já existe para os backups, mas não há atualmente um armazenamento seguro de chave dedicado no projeto.
- A migração existente de SharedPreferences para SQLite precisa continuar funcionando; a nova migração não pode marcar flags nem apagar a origem antes de confirmar a cópia e a reabertura do banco de destino.

## Decisão

Não ativar criptografia do banco por uma simples alteração de dependência ou por guardar uma senha fixa no código. A solução deve ser específica por plataforma, com uma interface única de abertura do banco e testes de migração independentes.

### Matriz de implementação

| Plataforma | Estratégia necessária | Situação |
| --- | --- | --- |
| Android | SQLCipher + chave aleatória guardada no Android Keystore por plugin de armazenamento seguro | Pendente |
| iOS | SQLCipher + chave aleatória guardada no Keychain | Pendente |
| macOS | SQLCipher + Keychain, se o alvo for oficialmente suportado | Pendente |
| Windows/Linux | Avaliar SQLite com extensão de criptografia compatível com FFI e distribuição/licenciamento verificáveis; não usar banco plaintext como fallback silencioso | Pendente |
| Web | Criptografia autenticada dos dados antes da persistência em IndexedDB, chave derivada de segredo do usuário ou chave protegida pelo navegador; definir UX de desbloqueio e recuperação | Pendente |

O pacote `sqflite_sqlcipher` publicado documenta suporte nativo a Android/iOS/macOS, não a Windows/Linux/Web. Ele é um fork do sqflite e exige análise de compatibilidade de dependências e imports antes de ser adotado. Portanto, não resolve sozinho a matriz multiplataforma.

## Requisitos obrigatórios antes de ativar

1. **Chaves:** gerar chave criptograficamente aleatória; nunca embutir, registrar em log, sincronizar em texto claro ou guardar em SharedPreferences.
2. **Desbloqueio:** definir quando a chave é liberada, como o app se comporta após reinício e como a pessoa recupera o acesso. Perder a chave não pode ser confundido com banco vazio.
3. **Migração sem perda:** detectar banco legado; criar cópia consistente; migrar para arquivo/namespace criptografado; validar schema, contagem e amostras de registros; fechar e reabrir o destino; só então marcar migração concluída e preservar a cópia antiga até política de retenção definida.
4. **Falha segura:** senha/chave ausente ou incorreta, arquivo corrompido, falta de espaço e interrupção durante migração devem impedir sobrescrita do banco original. Nunca criar silenciosamente um banco vazio sobre o caminho existente.
5. **Integridade:** usar criptografia autenticada e verificar autenticação antes de disponibilizar registros.
6. **Ciclo de vida:** considerar backups, WAL/journal, arquivos temporários, exportações, anexos/fotos e exclusão de dados.
7. **Compatibilidade:** preservar schema v11 e todas as migrações futuras; suportar atualização de instalações com dados reais.
8. **Testes:** cobrir banco novo, banco legado populado, migração interrompida, reabertura, chave errada, adulteração, falta de chave, atualização de schema, restauração de backup e testes por plataforma.
9. **Operação:** validar em aparelhos Android/iOS reais e nos navegadores suportados antes de declarar proteção concluída.

## Plano de entrega

1. Extrair uma interface de provedor de chave e uma abstração de abertura do banco, sem alterar ainda o formato persistido.
2. Implementar e testar a migração criptografada nativa em uma PR isolada, mantendo compatibilidade com bancos legados.
3. Implementar a estratégia Windows/Linux em PR separada, sem fallback plaintext.
4. Implementar o armazenamento Web/IndexedDB criptografado em PR separada, incluindo UX de desbloqueio e recuperação.
5. Adicionar auditoria de anexos, arquivos temporários, logs e cópias residuais.
6. Só após todos os alvos suportados passarem nos testes, atualizar a documentação para afirmar criptografia local.

## Critério de conclusão

A criptografia local só poderá ser declarada concluída quando todas as plataformas oficialmente suportadas tiverem implementação real, chaves protegidas, migração reversível/recuperável, testes de preservação de dados e validação de build/testes por plataforma. Enquanto isso, a documentação deve dizer explicitamente que o banco local não está criptografado em repouso.

## Consequência

A proteção de backups da PR #48 permanece válida e independente. Este ADR não muda o formato do banco nem os dados existentes; evita uma migração arriscada e define os critérios verificáveis para a implementação.

# Auditoria crítica e plano de evolução — Remédio na Hora

**Data:** 16/11/2026  
**Escopo:** revisão estática do repositório Flutter, fluxos de persistência, backup/restauração, posologia, lembretes, IA, privacidade e automação de qualidade. Esta revisão não equivale a pentest, parecer jurídico, validação clínica nem teste em aparelhos físicos.

## Resumo executivo

O aplicativo já possui uma base funcional relevante: persistência SQLite/IndexedDB, histórico de doses, médicos, consultas, exames, laudos, recursos de IA e testes automatizados. A revisão encontrou uma falha concreta de integridade de dados no backup: as tabelas `exams` e `lab_results`, adicionadas ao banco nas versões 9 e 10, não faziam parte da exportação nem da restauração. Isso poderia levar à perda silenciosa desses registros ao trocar de aparelho ou restaurar um backup.

A falha foi corrigida nesta entrega: as duas tabelas agora participam do backup/restauração, a versão de schema do backup foi alinhada à versão atual do banco (11), e os testes cobrem registros reais de exames e laudos no round-trip.

Também foi corrigida a divergência entre o teste do aviso de privacidade e o texto apresentado: o aviso agora referencia o art. 18 da LGPD ao descrever os direitos do titular.

## Achados priorizados

| Prioridade | Área | Achado / risco | Situação |
|---|---|---|---|
| **P0 — dados** | Backup/restauração | `exams` e `lab_results` estavam ausentes das listas de exportação e restauração. | **Corrigido** |
| **P1 — privacidade** | Dados locais | SQLite/IndexedDB e backups JSON não têm criptografia em repouso demonstrada no repositório. Um acesso ao dispositivo/arquivo pode expor dados sensíveis. | Pendente de projeto técnico e migração segura |
| **P1 — privacidade** | IA/OCR | Dados clínicos e imagens podem ser transmitidos ao proxy e a provedores externos. O código cliente não comprova retenção, região de processamento, controles de acesso ou exclusão no operador. | Limites documentados; auditoria do backend/contratos necessária |
| **P1 — segurança clínica** | Posologia | O modelo atual representa frequência diária, dias úteis, dias alternados e dias específicos da semana; não representa explicitamente SOS/PRN, intervalos variáveis, titulação, dose por peso ou unidades estruturadas. | Não ampliar automaticamente sem especificação clínica |
| **P1 — lembretes** | Notificações | O agendamento móvel depende de permissões, política de alarmes, economia de bateria, reinício e comportamento de cada fabricante. A execução CI não valida alarmes reais. | Teste físico Android/iOS necessário |
| **P1 — confiabilidade** | IDs de alarmes | O identificador usava `String.hashCode`, sem garantia contratual de estabilidade entre processos/execuções. | **Corrigido** com hash determinístico e teste de valor fixo |
| **P2 — qualidade** | Formatação/análise | Havia divergência de formatação em 112 arquivos e 87 diagnósticos informativos do analyzer. O CI foi ajustado para reportar a formatação, tolerar infos e continuar bloqueando warnings/erros. | Ajustado; limpeza de estilo gradual recomendada |
| **P2 — cobertura** | Testes | A suíte cobre modelos, serviços e widgets, mas não substitui integração em aparelhos, cenários de fuso horário, permissões revogadas, reinicialização e restauração em instalação limpa. | Ampliar em ciclos |
| **P2 — acessibilidade** | Interface | Acessibilidade com leitor de tela, contraste, escala de texto, foco/teclado e alvos de toque precisa de validação sistemática em dispositivos. | Auditoria manual pendente |
| **P3 — evolução** | Observabilidade | Não há evidência suficiente nesta revisão de telemetria de falhas com minimização de dados sensíveis, métricas de sucesso de notificações ou trilha de auditoria operacional. | Definir política antes de instrumentar |

## Alterações implementadas nesta entrega

1. Incluídas as tabelas `exams` e `lab_results` na exportação e na restauração transacional.
2. Incluídas as chaves mínimas de validação dessas tabelas.
3. Incluídos contadores de exames, laudos e registros de receita no resumo da restauração.
4. Substituído `String.hashCode` dos alarmes por hash determinístico independente de processo, com teste de regressão de valor fixo.
5. Alinhada a versão de schema do backup à versão atual do banco de dados (11); backups antigos com schema inferior continuam aceitos.
6. Ampliados os testes para semear um exame e um laudo, exportar, restaurar e conferir os dados.
7. Atualizado o texto do aviso de privacidade com referência ao art. 18 da LGPD.
8. Atualizada a documentação do CI para refletir as verificações realmente executadas.

## Plano de evolução recomendado

### Etapa 1 — Proteção e integridade de dados
- Projetar criptografia em repouso para SQLite e backups, incluindo armazenamento seguro de chaves por plataforma, recuperação, rotação e migração sem perda.
- Definir formato de backup versionado, integridade criptográfica, proteção por senha/chave e compatibilidade de restauração.
- Auditar o Worker de IA, OCR, limites, autenticação, rate limiting, logs, retenção e exclusão; nunca registrar conteúdo clínico em logs.
- Criar consentimento específico por finalidade/serviço e caminho manual equivalente quando o usuário não autorizar o envio.
- Fazer revisão de dependências e análise automatizada de vulnerabilidades.

### Etapa 2 — Tratamentos e lembretes
- Evoluir o modelo de posologia com tipos explícitos e validação: dose/unidade, via, frequência, intervalo, duração, SOS/PRN e esquemas variáveis, sem inferir dose a partir de texto livre.
- Preservar histórico imutável de alterações da prescrição e registrar a origem dos dados (manual, receita digitalizada, profissional).
- Substituir IDs de notificação por identificadores determinísticos e resistentes a reinicializações.
- Testar permissões, alarmes exatos/inexatos, reinicialização, alteração de fuso, horário de verão, economia de bateria, atualização e remoção de tratamentos em aparelhos reais.
- Exibir claramente quando lembretes do sistema não estiverem autorizados ou não puderem ser agendados.

### Etapa 3 — Qualidade, desempenho e acessibilidade
- Adicionar matriz de testes Android/iOS/web, migrações de banco de cada versão suportada e restauração com backups históricos.
- Cobrir fluxos completos: cadastro → agendamento → dose tomada/pulada → histórico → backup → restauração.
- Medir inicialização, consultas SQLite, renderização de listas extensas e uso de memória antes de otimizações.
- Executar auditoria WCAG/Material: semântica, leitor de tela, contraste, tamanho de fonte, foco, teclado e alvos de toque.
- Fazer limpeza de formatação/lints em PR dedicada, mantendo CI rigoroso para novos arquivos e alterações.

### Etapa 4 — Funcionalidades e acabamento
- Melhorar exportação seletiva e visualização/validação prévia de restauração.
- Permitir revisão de dados extraídos por IA/OCR com comparação lado a lado e confirmação campo a campo.
- Disponibilizar histórico de alterações e status verificável de sincronização dos lembretes.
- Atualizar guias do usuário, recuperação de conta/dispositivo e procedimentos de suporte.

## Critérios para considerar o aplicativo pronto para produção

- Backup/restauração comprovadamente completos em todas as tabelas e em versões antigas suportadas.
- Dados sensíveis protegidos em repouso e em trânsito, com gestão de chaves testada.
- Fluxos externos de IA/OCR transparentes, consentidos e com retenção documentada.
- Posologia validada por profissionais e modelo de dados sem ambiguidades clínicas.
- Notificações verificadas em dispositivos reais e falhas comunicadas ao usuário.
- CI verde, testes de migração/integração, revisão de acessibilidade e análise de dependências concluídas.
- Revisão independente de segurança e privacidade; avaliação jurídica da operação LGPD.

## Limitações desta auditoria

A revisão foi baseada no código e na automação disponível no GitHub. Não houve acesso a segredos/ambiente do Worker, inspeção de dados reais, pentest, análise forense, avaliação jurídica, validação por profissional de saúde nem testes físicos Android/iOS. Portanto, esta entrega corrige uma falha concreta de backup e melhora a rastreabilidade, mas não deve ser interpretada como certificação de segurança, conformidade LGPD ou segurança clínica.

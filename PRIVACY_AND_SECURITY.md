# Privacidade e segurança — Remédio na Hora

Este documento descreve o comportamento observado no código e as medidas
mínimas recomendadas para uso e manutenção. Não é parecer jurídico nem
certificação de conformidade com a LGPD.

## Fluxos de dados

| Recurso | Dados envolvidos | Destino |
| --- | --- | --- |
| Cadastro, agenda e histórico | Tratamentos, doses, médicos, consultas, exames e perfil | Banco local SQLite no nativo; armazenamento do navegador na web |
| Recursos de IA | Texto clínico fornecido ao recurso, como medicamentos, doses, instruções, adesão e exames | Proxy remoto do projeto e provedor de IA configurado (atualmente NVIDIA) |
| Análise/leitura por imagem com IA | Imagem/documento enviado pelo usuário e instrução da tarefa | Proxy remoto e provedor de IA |
| OCR do cartão do plano | Imagem do cartão | Endpoint serverless do projeto para OCR |
| Backup | Linhas exportadas das tabelas do app | Arquivo JSON no local escolhido pelo usuário |
| Cartão de emergência | Campos escolhidos pelo usuário | Compartilhamento externo iniciado pelo usuário |

Os dados enviados variam conforme a funcionalidade escolhida. O usuário deve
revisar o conteúdo antes do envio e conferir os campos extraídos antes de salvar.

## Controles atuais e limites conhecidos

- **Android e Web**: o banco local agora é criptografado em repouso com SQLite3MultipleCiphers (ChaCha20) — DEK de 256 bits protegida pelo Android Keystore (Android) ou por senha de recuperação com WebCrypto + envelope autenticado (Web). Detalhes, limites e arquivos auxiliares em [docs/database-encryption.md](docs/database-encryption.md).
- iOS, macOS, Windows e Linux permanecem fora do escopo: o armazenamento local nessas plataformas não deve ser tratado como criptografado em repouso.
- Novos backups exportados pelo app usam AES-256-GCM com chave derivada da senha por PBKDF2-HMAC-SHA256 (310.000 iterações), salt e nonce aleatórios e autenticação de integridade. A senha não é armazenada nem enviada a servidores; sem ela, o backup não pode ser recuperado.
- Backups JSON antigos, sem criptografia, continuam aceitos para restauração por compatibilidade. Proteja esses arquivos como dados sensíveis e gere um novo backup criptografado.
- A criptografia do arquivo de backup é independente da cifra do banco ativo; no Android e na Web o banco já é cifrado em repouso (ADR 0003 implementada), com o banco legado preservado em texto claro até a política de retenção removê-lo. O backup cifrado continua recomendado para portabilidade.
- O cliente Flutter chama um proxy remoto de IA. Não coloque segredos de
  provedor no aplicativo; credenciais devem permanecer no ambiente do servidor.
- Excluir os dados locais não revoga nem elimina cópias previamente exportadas
  ou informações já transmitidas a serviços remotos.
- Não use dados reais em testes automatizados, logs, screenshots ou issues.

## Política de retenção do proxy de IA e OCR

Documenta o comportamento esperado dos serviços remotos que processam dados
clínicos enviados pelo app.

### Funções serverless do projeto (Vercel api/)

- **Payload**: decodificado em memória, descartado quando função retorna. Sem persistência.
- **Logs**: console.error apenas em falha, sem conteúdo de imagem ou campos extraídos.
- **Rate limiting**: janela 24h por IP em memória do Lambda.
- **Retenção**: zero. Sem analytics, sem tracing de payload.
- **Auditabilidade**: logs Vercel por 7 dias, IP mascarado por default.

### Proxy de IA (Cloudflare Worker / NVIDIA)

- **Payload enviado ao proxy**: prompt textual + instrução de sistema.
- **Retenção no proxy**: não persiste payload. Logs só metadados (timestamp, endpoint, status).
- **Retenção no provedor NVIDIA**: depende da política NIM API. Não persiste por default
  em tier gratuito/pay-as-you-go (Janeiro 2026), mas **deve ser confirmada com NVIDIA
  antes de uso em produção com dados reais**.

### Recomendações para produção com dados reais

1. Confirmar com NVIDIA política zero-persistence.
2. Contratar DPA com provedor.
3. Habilitar WAF Cloudflare.
4. Janela máxima retenção logs proxy: 30 dias.
5. Documentar base legal LGPD (art. 7 consentimento, art. 11 contrato).
6. Designar DPO e publicar contato.
7. Criar ROPA listando dados/finalidade/base legal/operadores/retenção/transferência.

### Limites declarados

Esta política é o **comportamento esperado** do código. A auditoria técnica não comprovou:
- NVIDIA efetivamente não persiste prompts no tier gratuito.
- Logs Cloudflare Worker não incluem payload por default.
- Vercel não armazena payloads em intermediário de Lambda.

Confirmações devem ser obtidas e documentadas em `docs/security/` antes de produção.

## Recomendações operacionais

1. Manter o sistema operacional, navegador e aplicativo atualizados.
2. Usar bloqueio de tela e não compartilhar dispositivos/sessões.
3. Armazenar backups em local privado; apagar cópias antigas com segurança.
4. Solicitar consentimento claro e específico antes de cada envio de dados
   sensíveis a serviços externos, com opção de continuar manualmente.
5. Documentar finalidade, base legal, operadores, retenção, contato do titular
   e processo de atendimento a solicitações LGPD.
6. Revisar dependências e alertas de segurança regularmente.

## Próximas etapas técnicas

- Concluir a validação de gestão e recuperação de chaves conforme ADR 0004 e o plano em `docs/security/database-key-management-test-plan.md` (formato de envelope e fluxos de recuperação já implementados no PR #64; falta UI de exportação no Android).
- Criptografia em repouso para SQLite/Web implementada (PR #64); pendências operacionais: validação em aparelho físico, Firefox/Safari reais e política de retenção do backup legado.
- Implementar controles explícitos de consentimento por categoria de envio,
  revogação e registro auditável.
- Definir política de retenção e exclusão no proxy, OCR e provedor de IA.
- Adicionar testes de integração para exportação/restauração, notificações e
  fluxos de consentimento.
- Realizar revisão independente de segurança, privacidade e adequação legal.

## Segurança clínica

O app não deve alterar automaticamente prescrições. Horários, doses,
intervalos, interações e resultados de IA precisam ser confirmados pelo
usuário com profissional habilitado. Testes automatizados não substituem
validação clínica ou testes de alarmes em aparelhos reais.

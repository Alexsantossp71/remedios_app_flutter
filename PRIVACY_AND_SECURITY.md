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

- O armazenamento local não deve ser tratado como criptografado em repouso.
- Novos backups exportados pelo app usam AES-256-GCM com chave derivada da senha por PBKDF2-HMAC-SHA256 (310.000 iterações), salt e nonce aleatórios e autenticação de integridade. A senha não é armazenada nem enviada a servidores; sem ela, o backup não pode ser recuperado.
- Backups JSON antigos, sem criptografia, continuam aceitos para restauração por compatibilidade. Proteja esses arquivos como dados sensíveis e gere um novo backup criptografado.
- A criptografia do arquivo de backup não cifra o banco SQLite/IndexedDB ativo; a proteção em repouso desse armazenamento permanece pendente de uma migração específica por plataforma. Os requisitos e critérios de segurança estão definidos em [ADR 0003](docs/adr/0003-local-database-encryption.md).
- O cliente Flutter chama um proxy remoto de IA. Não coloque segredos de
  provedor no aplicativo; credenciais devem permanecer no ambiente do servidor.
- A política de retenção e processamento do proxy/provedor deve ser confirmada
  com os operadores dos serviços. Este repositório não comprova retenção zero.
- Excluir os dados locais não revoga nem elimina cópias previamente exportadas
  ou informações já transmitidas a serviços remotos.
- Não use dados reais em testes automatizados, logs, screenshots ou issues.

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

- Avaliar criptografia em repouso para SQLite, armazenamento web e backups,
  incluindo gestão segura de chaves e migração sem perda de dados.
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

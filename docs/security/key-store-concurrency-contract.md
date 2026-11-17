# Contrato de concorrência para criação da chave do banco

**Status:** teste de contrato isolado; não é adaptador de armazenamento seguro.

## Invariante obrigatória

Para uma DEK de exatamente 32 bytes, qualquer número de chamadas simultâneas a
`createKeyIfAbsent` deve produzir exatamente um vencedor. Todas as demais
chamadas retornam `false`, e a chave armazenada permanece exatamente igual à
chave vencedora. Uma chamada de primeira inicialização nunca substitui uma
chave existente.

A implementação também deve:
- retornar `null` quando a chave estiver ausente, sem gerar uma substituta;
- retornar cópias defensivas na leitura;
- rejeitar comprimentos diferentes de 32 bytes;
- não registrar a chave em logs, exceções ou telemetria;
- falhar de forma explícita quando o cofre do sistema estiver indisponível;
- manter o comportamento entre processos/isolates conforme o modelo de cada
  plataforma, não apenas entre chamadas no mesmo isolate Dart.

## O que este teste prova

O teste novo dispara 32 chamadas concorrentes no fake em memória e confirma que
exatamente uma delas cria a chave. Ele protege o contrato esperado pelos
consumidores e detecta regressões no fake.

**Limite importante:** o fake executa em memória e não valida concorrência real
entre processos, armazenamento persistente, Android Keystore, Apple Keychain,
Windows, Secret Service ou o plugin `flutter_secure_storage`. Portanto, um
teste verde aqui não aprova nenhum adaptador de produção.

## Portões obrigatórios antes de integrar um adaptador

1. Testes unitários e instrumentados do backend real por plataforma.
2. Duas ou mais inicializações concorrentes (incluindo processos/isolate
   separados quando aplicável) nunca substituem a primeira chave.
3. Matar o processo entre criação e confirmação não resulta em chave parcial,
   chave substituída ou banco vazio silencioso.
4. Cofre ausente, bloqueado, corrompido ou sem sessão gera erro recuperável e
   instrução clara; nunca gera uma DEK nova para banco existente.
5. Reinício, atualização, reinstalação e restauração de backup preservam ou
   recuperam a chave conforme política documentada.
6. A exclusão da chave só ocorre em fluxo explícito após backup/eliminação
   segura do banco correspondente.
7. Testes em dispositivos/VMs de cada SO e revisão independente de segurança.

## Decisão

Não conectar ainda `flutter_secure_storage` ao banco ativo: a avaliação atual
não identificou operação pública atômica compare-and-set/insert-if-absent.
Uma sequência read-then-write não satisfaz este contrato.

Este PR não altera `DatabaseService`, dependências do aplicativo, schema,
banco de dados, flags de migração, catálogo de medicamentos, configurações
nativas ou criptografia ativa. O banco do aplicativo continua sem criptografia
em repouso.

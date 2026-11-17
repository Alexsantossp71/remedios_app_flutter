# ADR 0004 — Gestão e recuperação da chave do banco local

- **Status:** proposta para prova de conceito; não aprovada para produção
- **Data:** 2026-11-17
- **Contexto:** Remédio na Hora, SQLite3MultipleCiphers, armazenamento nativo e Web/OPFS

## Decisão proposta

Separar a chave do banco (DEK) da senha de recuperação (KEK) e nunca codificar uma chave fixa no aplicativo.

1. Gerar uma DEK aleatória e exclusiva para cada instalação/banco, usando gerador criptograficamente seguro. A DEK não é derivada de identificadores do aparelho, usuário, e-mail ou dados previsíveis.
2. Em Android, iOS, macOS, Windows e Linux, guardar a DEK no cofre de credenciais do sistema operacional por meio de uma abstração testável. Avaliar `flutter_secure_storage`, mas validar comportamento e requisitos de cada plataforma antes de adotá-lo. Não copiar a DEK para SharedPreferences, arquivos de configuração, logs ou banco sem proteção.
3. Criar um envelope de recuperação portátil: derivar uma KEK da senha de recuperação escolhida pelo usuário, com KDF versionada e salt aleatório; cifrar a DEK com AES-256-GCM, nonce aleatório e metadados autenticados (AAD). Guardar apenas versão, KDF/parâmetros, salt, nonce, ciphertext e tag. Não guardar a senha nem a KEK.
4. Exigir que o usuário confirme e guarde a senha de recuperação fora do dispositivo. Oferecer exportação do envelope como arquivo e testar importação em instalação limpa. A perda da senha e do cofre local não pode ser contornada pelo aplicativo.
5. No Web, não considerar `flutter_secure_storage`/WebCrypto experimental como única cópia recuperável da chave. A documentação do plugin informa que o backend Web é experimental e vinculado ao navegador/domínio. Usar desbloqueio explícito por senha de recuperação para abrir o envelope, manter a DEK somente em memória enquanto desbloqueado e exigir HTTPS/localhost. Uma cópia do envelope exportada pelo usuário permite recuperar a chave em outro navegador; não recupera, por si só, o arquivo OPFS se o armazenamento local tiver sido apagado.
6. Manter backup de dados separado da recuperação da chave. O envelope recupera a DEK, não os registros. Para perda/evicção do OPFS ou migração para outro dispositivo, restaurar um backup de dados criptografado e importar os registros para um banco recém-criado com nova DEK. Não sincronizar chaves ou dados clínicos para servidor sem projeto explícito e consentimento.

## Regras de segurança obrigatórias

- Não iniciar nem migrar banco se a chave estiver ausente, inválida ou não puder ser recuperada; nunca gerar silenciosamente uma chave nova para abrir um banco existente.
- A inicialização de primeira utilização deve ser atômica e não sobrescrever uma chave existente. A interface da POC usa `createKeyIfAbsent`: devolve sucesso somente quando cria a chave; se já houver uma, mantém a chave original. Rotação/substituição de chave exige operação separada, explícita e recuperável.
- Verificar a chave com operação autenticada/consulta de integridade antes de liberar acesso às tabelas.
- A senha de recuperação deve ser validada com política clara e confirmação; não registrar senha, DEK, KEK, envelope em logs ou telemetria.
- KDF, parâmetros, formato do envelope e versão devem ser explícitos e migráveis. Parâmetros de custo só serão fixados após benchmark nos aparelhos suportados; rejeitar parâmetros fora de limites seguros.
- Usar AES-GCM com nonce único por chave; autenticar versão e metadados relevantes via AAD.
- Implementar bloqueio/limpeza de referências em memória no encerramento/bloqueio quando viável, sem prometer apagamento seguro de memória gerenciada.
- Alteração de senha de recuperação deve reempacotar a mesma DEK sem recriptografar o banco.
- Rotação da DEK exige procedimento separado, transacional e recuperável; não faz parte desta etapa.
- Perda da senha/envelope e do cofre do dispositivo significa perda irrecuperável daquela chave. Informar isso claramente antes de habilitar criptografia.
- XSS, extensão maliciosa, dispositivo comprometido e sessão desbloqueada continuam sendo ameaças; criptografia em repouso não protege contra código malicioso executando na origem.

## Alternativas rejeitadas

- **Chave fixa no código ou derivada do nome do app/dispositivo:** extraível e previsível.
- **SharedPreferences/localStorage em texto puro:** não é cofre de chaves.
- **Somente chave WebCrypto não exportável:** não oferece recuperação independente do navegador/origem e pode tornar dados inacessíveis após perda do perfil.
- **Senha do usuário usada diretamente como chave SQLite:** baixa entropia, difícil de trocar e acopla UX à cifra; usar DEK aleatória e envelope.
- **Sincronização automática em servidor:** aumenta o impacto e exige arquitetura, consentimento, controle de acesso e política de retenção que não existem hoje.

## Dependências ainda não decididas

- Escolher e validar implementação nativa de armazenamento seguro em todas as plataformas suportadas, incluindo requisitos do Windows/Linux e entitlements Apple.
- Validar a KDF interoperável e seus parâmetros em Flutter nativo e Web.
- Confirmar formato e semântica da chave SQLite3MC em todos os alvos; a POC nativa atual e a POC Web ainda não provam interoperabilidade de arquivos/chaves.
- Definir UX de primeiro uso, desbloqueio, bloqueio automático, alteração de senha, exportação/importação do envelope e recuperação por backup.
- Fazer revisão independente de segurança e licenciamento.

## Consequências

Esta ADR define um desenho para prototipagem, não uma implementação. A alteração atual endurece somente o contrato e o fake de testes da POC: não adiciona armazenamento seguro real, não altera `DatabaseService`, não ativa criptografia e não modifica dados. A implementação só pode avançar após os testes do plano associado e revisão do desenho.

# Estratégia de gerenciamento de chaves — requisitos antes da integração

Este documento registra requisitos de projeto. **Não implementa nem seleciona um armazenamento de chaves para o aplicativo.** A integração só deve começar depois de uma prova técnica por plataforma e revisão de segurança.

## Princípios obrigatórios

1. A chave do banco é aleatória, gerada por CSPRNG e nunca derivada de dados pessoais, identificadores do aparelho ou senha curta.
2. A chave não pode aparecer em logs, analytics, mensagens de erro, arquivos temporários, preferências em texto puro ou código-fonte.
3. A chave do banco é diferente da senha usada para proteger um backup.
4. A perda da chave deve produzir uma recuperação guiada e honesta; nunca criar silenciosamente um banco vazio como se os dados antigos estivessem disponíveis.
5. O banco restaurado de um backup deve ser reimportado para uma nova chave local, em vez de depender da portabilidade da chave de um aparelho.
6. Nenhuma migração pode apagar o banco de origem antes de validar o novo arquivo cifrado e confirmar que ele pode ser reaberto.

## Avaliação inicial por plataforma

| Plataforma | Mecanismo a validar | Riscos e pré-requisitos |
| --- | --- | --- |
| Android | Android Keystore por meio de plugin de armazenamento seguro | Testar backup/restauração do sistema e incompatibilidade entre backup do banco e chave local. A documentação do flutter_secure_storage alerta para falha de unwrap quando o Android restaura preferências criptografadas sem a chave original; configurar exclusões de backup e testar upgrade/restauração. |
| iOS | Keychain | Definir acessibilidade e comportamento após reinstalação, troca de aparelho e restauração do backup. |
| macOS | Keychain | Validar entitlements/Keychain Sharing e instalação empacotada. |
| Windows | Windows Credential Manager / mecanismo do plugin | Validar instalação limpa, atualização, perfil sem privilégios elevados e dependências de build/runtime. |
| Linux | Secret Service/libsecret | Validar presença de serviço de chaveiro e comportamento quando o serviço está bloqueado ou indisponível. |
| Web | WebCrypto, somente após prova de conceito | Implementação do flutter_secure_storage é experimental. Os segredos cifrados são vinculados ao mesmo navegador/origem e não são portáveis; requer HTTPS/localhost e cabeçalhos de segurança fortes. Não tratar como equivalente ao Keychain/Keystore. |

## Política de recuperação

- A senha do backup protege somente o arquivo exportado.
- A chave local do banco não deve ser exportada em texto puro.
- A restauração deve validar autenticação/integridade do backup antes de modificar o banco ativo.
- Importação deve ocorrer em arquivo temporário, seguida de validação, transação/renomeação atômica quando suportada e preservação do banco antigo até o sucesso final.
- Se a chave local estiver indisponível, oferecer restauração de backup ou procedimento explícito de recuperação; não há como reconstruir uma chave aleatória perdida apenas a partir do arquivo cifrado.

## Testes de aceitação antes de produção

- Reinício, atualização do app e reinstalação.
- Aparelho novo e restauração de backup do sistema operacional.
- Chaveiro bloqueado, indisponível ou removido.
- Backup criptografado exportado e restaurado em outro aparelho.
- Senha incorreta, arquivo truncado, adulterado e versão futura/desconhecida.
- Falha simulada em cada etapa da migração, inclusive falta de espaço e encerramento forçado do processo.
- Web: HTTPS, mudança de navegador/origem, limpeza de dados do site, modo privado e restauração em outro dispositivo.
- Nunca considerar a Web aprovada apenas porque o teste WASM consegue abrir um banco cifrado em memória.

## Referências técnicas consultadas

- flutter_secure_storage: documentação oficial do pacote em pub.dev, especialmente as notas de Android Auto Backup e implementação WebCrypto experimental.
- sqlite3: documentação oficial em pub.dev, que descreve sqlite3mc.wasm, IndexedDbFileSystem e a API WASM experimental.

Este documento é um checklist de engenharia, não uma declaração de que esses mecanismos já estão implementados ou foram validados no Remédio na Hora.

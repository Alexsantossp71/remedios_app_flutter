# Avaliação do provedor de armazenamento seguro nativo

**Data:** 2026-11-17  
**Resultado:** candidato identificado; ainda não aprovado para integração em produção.

## Candidato avaliado

`flutter_secure_storage 11.2.0`, licença BSD-3-Clause, publicado no pub.dev. A versão declara compatibilidade com Android, iOS, macOS, Windows, Linux e Web, e exige Dart 3.8+, compatível com o mínimo atual do aplicativo (Dart 3.12).

Referências oficiais:
- https://pub.dev/packages/flutter_secure_storage
- https://pub.dev/packages/flutter_secure_storage/changelog
- https://pub.dev/documentation/flutter_secure_storage/latest/flutter_secure_storage/FlutterSecureStorage-class.html

## Resultado por plataforma

| Plataforma | Mecanismo/condição documentada | Pendência obrigatória |
| --- | --- | --- |
| Android | Armazenamento cifrado com chave protegida pelo Android Keystore; API mínima 23. | A política padrão de backup pode restaurar preferências cifradas sem a chave original e causar erro de unwrap. Definir exclusões/backup policy sem descartar dados úteis e testar atualização, reinstalação e restauração. |
| iOS | Keychain. | Definir acessibilidade e testar reinício, primeiro desbloqueio, reinstalação e troca/restauração de aparelho. |
| macOS | Keychain; Data Protection Keychain pode exigir Keychain Sharing e provisioning profile. | Testar build assinado/distribuído. A opção documentada `MacOsOptions(usesDataProtectionKeychain: false)` usa o Keychain legado sem esse entitlement; não escolher sem teste de distribuição. |
| Windows | Plugin nativo com requisito de bibliotecas C++ ATL do Visual Studio Build Tools. | Testar build limpo, ACLs, persistência entre atualização e reinstalação, perfis de usuário e recuperação de falhas. |
| Linux | Secret Service/libsecret. Exige libsecret de desenvolvimento/runtime e um serviço Secret Service (por exemplo, GNOME Keyring ou KWallet). | Testar instalação empacotada e ambiente sem chaveiro, bloqueado ou sem sessão D-Bus. A falha deve ser explícita; nunca usar fallback em texto puro. |
| Web | Implementação WebCrypto experimental, armazenada no contexto do navegador/origem e não portável entre navegadores/máquinas. Requer HTTPS ou localhost e cabeçalhos de segurança fortes. | Não usar como única cópia recuperável da DEK. O caminho Web continua dependente do envelope de recuperação exportável e de testes separados do OPFS. |

## Bloqueio de concorrência: API não atende diretamente ao contrato

A API pública documenta operações de leitura, gravação, exclusão e verificação de existência. Ela não documenta uma operação atômica compare-and-set ou insert-if-absent.

Portanto, implementar `createKeyIfAbsent` com uma sequência simples de `read` seguida de `write` cria uma condição de corrida: duas inicializações podem observar ausência e gravar chaves diferentes. Isso violaria o contrato endurecido na PR #59.

Não será criado um adaptador de produção baseado nessa sequência. Um próximo experimento deverá provar exclusão mútua adequada ao ciclo de vida e modelo de execução de cada alvo, incluindo múltiplas instâncias/processos onde aplicável, ou adotar um backend nativo com criação condicional. O teste deve comprovar que chamadas concorrentes nunca substituem uma chave existente.

## Decisão desta etapa

- Não adicionar ainda `flutter_secure_storage` às dependências do app.
- Não alterar entitlements, Manifest, backup policy, factories ou `DatabaseService`.
- Não ativar PRAGMA de chave, criptografia, migração ou inicialização automática.
- Manter o banco ativo e o schema v11 inalterados.
- Preservar `sqlite_migration_completed_v1` e `assets/data/medicine_catalog.json`.

## Próximo experimento técnico

1. Criar uma prova isolada de adaptador para Android/iOS/macOS/Windows/Linux, com mocks para testes de contrato e testes de integração em runners/plataformas reais.
2. Definir explicitamente a semântica de criação atômica, leitura, perda do cofre e exclusão.
3. Provar a recuperação quando o cofre local não estiver disponível, sem criar chave substituta.
4. Executar matriz de instalação, atualização, reinício, backup/restauração e falhas de chaveiro.
5. Só então decidir se o plugin será adotado ou se serão necessários adaptadores nativos específicos.

Este documento registra uma avaliação de fornecedor, não uma implementação nem uma aprovação de segurança. O banco do Remédio na Hora permanece sem criptografia em repouso.

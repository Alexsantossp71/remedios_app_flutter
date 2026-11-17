# Avaliação do provedor de armazenamento seguro nativo

**Data:** 2026-11-17  
**Resultado:** candidato identificado; ainda não aprovado para integração em produção.

## Candidato avaliado

`flutter_secure_storage 11.2.0`, licença BSD-3-Clause, publicado no pub.dev. A versão declara compatibilidade com Android, iOS, macOS, Windows, Linux e Web, e exige Dart 3.8+, compatível com o mínimo atual do aplicativo (Dart 3.12).

Referências oficiais:
- https://pub.dev/packages/flutter_secure_storage
- https://pub.dev/packages/flutter_secure_storage/changelog
- https://pub.dev/documentation/flutter_secure_storage/latest/flutter_secure_storage/FlutterSecureStorage-class.html
- https://github.com/juliansteenbakker/flutter_secure_storage/releases/tag/flutter_secure_storage-v11.2.0

## Resultado por plataforma

| Plataforma | Mecanismo/condição documentada | Pendência obrigatória |
| --- | --- | --- |
| Android | Armazenamento cifrado com chave protegida pelo Android Keystore; API mínima 23. | A política padrão de backup pode restaurar preferências cifradas sem a chave original e causar erro de unwrap. Definir exclusões/backup policy sem descartar dados úteis e testar atualização, reinstalação e restauração. |
| iOS | Keychain. | Definir acessibilidade e testar reinício, primeiro desbloqueio, reinstalação e troca/restauração de aparelho. |
| macOS | Keychain; Data Protection Keychain pode exigir Keychain Sharing e provisioning profile. | Testar build assinado/distribuído. A opção documentada `MacOsOptions(usesDataProtectionKeychain: false)` usa o Keychain legado sem esse entitlement; não escolher sem teste de distribuição. |
| Windows | DPAPI protege um arquivo JSON local; o plugin usa também uma chave de proteção mantida no Credential Manager para compatibilidade. | Testar build limpo, ACLs, persistência entre atualização e reinstalação, perfis de usuário e recuperação de falhas. O lock observado é local à instância Dart, não uma garantia interprocessos. |
| Linux | Secret Service/libsecret. Exige libsecret de desenvolvimento/runtime e um serviço Secret Service (por exemplo, GNOME Keyring ou KWallet). | Testar instalação empacotada e ambiente sem chaveiro, bloqueado ou sem sessão D-Bus. A falha deve ser explícita; nunca usar fallback em texto puro. |
| Web | Implementação WebCrypto experimental, armazenada no contexto do navegador/origem e não portável entre navegadores/máquinas. Requer HTTPS ou localhost e cabeçalhos de segurança fortes. | Não usar como única cópia recuperável da DEK. O caminho Web continua dependente do envelope de recuperação exportável e de testes separados do OPFS. |

## Auditoria do código-fonte e concorrência

Foi inspecionado o código-fonte publicado na tag `flutter_secure_storage-v11.2.0`, além do changelog dessa versão.

- A API pública oferece `read`, `write`, `delete` e `containsKey`; não oferece uma operação documentada `createIfAbsent`, compare-and-set ou insert-if-absent.
- No backend Windows, `FlutterSecureStorageWindows` usa um `_AsyncLock` Dart para serializar operações da mesma instância do plugin. O lock é um encadeamento de Futures em memória, não um mutex entre processos.
- Ainda no backend Windows, `write` executa carregar mapa → atribuir valor → salvar mapa. Isso não constitui uma transação condicional interprocessos. O código do backend não demonstra uma garantia de que duas instâncias/processos não sobrescreverão uma criação concorrente.
- O changelog 11.0.0 registra correção de uso de mutex em `deleteAll` e `containsKey` no backend Windows. A nota não declara que a operação pública `write` seja uma criação condicional atômica.
- O changelog 11.2.0 registra correções de múltiplas instâncias no Android. Isso é relevante, mas não equivale a uma garantia pública multiplataforma de compare-and-set para o valor armazenado.

Conclusão restrita: o plugin pode continuar sendo candidato para proteção de segredos em repouso, mas a documentação e o código auditados não comprovam o contrato de criação atômica exigido pelo aplicativo em todas as plataformas. Não implementar `createKeyIfAbsent` com uma sequência simples de `read` seguida de `write`.

## Bloqueio de concorrência: API não atende diretamente ao contrato

A API pública documenta operações de leitura, gravação, exclusão e verificação de existência. Ela não documenta uma operação atômica compare-and-set ou insert-if-absent.

Portanto, implementar `createKeyIfAbsent` com uma sequência simples de `read` seguida de `write` cria uma condição de corrida: duas inicializações podem observar ausência e gravar chaves diferentes. Isso violaria o contrato endurecido na PR #62.

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

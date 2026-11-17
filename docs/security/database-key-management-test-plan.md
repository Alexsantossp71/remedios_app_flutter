# Plano de validação — gestão e recuperação da chave do banco

Este plano acompanha a ADR 0004. Todos os testes usam chaves e registros sintéticos.

## Matriz por plataforma

| Plataforma | Cofre a avaliar | Condições obrigatórias |
| --- | --- | --- |
| Android | Android Keystore via plugin | Persistência após reinício; comportamento após reinstalação/backup; bloqueio do dispositivo; falha explícita se chave ausente |
| iOS | Keychain | Acessibilidade escolhida documentada; comportamento em backup/restauração e reinstalação; entitlements corretos |
| macOS | Keychain | Debug/Release entitlements; persistência e recuperação testadas |
| Windows | Cofre/DPAPI suportado pela implementação escolhida | Testar conta Windows, perfil e máquina diferentes; falha controlada sem serviço |
| Linux | Secret Service/libsecret ou alternativa documentada | Testar sessão sem serviço de segredos; não cair silenciosamente para arquivo em texto puro |
| Web Chromium | Envelope cifrado + senha; WebCrypto em HTTPS | Mesmo domínio, novo perfil/navegador, importação do envelope e OPFS ausente |
| Web Firefox/Safari | Envelope cifrado + senha; WebCrypto em HTTPS | Repetir testes; diferenças de API e persistência; sem presumir paridade Chromium |

## Testes de aceitação

1. **Geração:** DEK tem 256 bits de entropia do gerador seguro; duas instalações geram chaves diferentes.
2. **Armazenamento nativo:** DEK sobrevive ao reinício; não aparece em SharedPreferences, arquivos de configuração, banco, logs ou saída de depuração.
3. **Web:** não existe chave fixa no bundle; sem senha/envelope válido o banco não abre. Não depender exclusivamente de chave WebCrypto presa ao perfil.
4. **Envelope:** exportar e importar em instalação limpa; senha correta recupera exatamente a DEK; senha incorreta, ciphertext alterado, tag inválida, AAD alterada, salt/nonce truncados e versão desconhecida são rejeitados.
5. **KDF:** parâmetros são versionados e validados contra limites; medir tempo e memória em aparelhos de entrada e browsers; proteger contra parâmetros extremos fornecidos por envelope malicioso.
6. **Troca de senha:** novo envelope abre a mesma DEK; envelope antigo continua válido até o usuário confirmar substituição e guardar a nova cópia.
7. **Falha de cofre:** chave ausente/corrompida gera fluxo de recuperação; nunca criar outra chave e inicializar banco vazio automaticamente.
8. **Perda de OPFS:** restaurar backup de dados em banco novo; envelope de chave sozinho não deve ser apresentado como backup dos registros.
9. **Ciclo de vida:** bloquear/desbloquear, encerrar app/aba, reiniciar sistema, suspender/retomar, atualizar app e limpar dados do site.
10. **Privacidade:** nenhuma senha, DEK, KEK ou registro clínico fictício em logs, analytics ou crash reports.
11. **Interoperabilidade:** testar o mesmo formato SQLite3MC e parâmetros em cada alvo antes de afirmar compatibilidade multiplataforma.
12. **Regressão:** exportação/restauração de backup existente, migração SharedPreferences, notificações e fluxo clínico continuam funcionando.

## Critério de bloqueio

Qualquer falha que possa criar banco vazio por engano, sobrescrever dados, perder a única cópia da chave, aceitar chave incorreta, ou expor segredos bloqueia a integração.

## Sequência segura de implementação

1. Implementar interface `DatabaseKeyStore` e testes unitários com armazenamento falso.
2. Implementar adaptadores nativos e teste de integração em cada SO.
3. Implementar envelope de recuperação e testes negativos/interoperabilidade.
4. Implementar fluxo Web com senha e envelope exportável em Chromium, Firefox e Safari.
5. Executar testes de recuperação de backup e perda de armazenamento.
6. Só então integrar com o banco e planejar migração recuperável do schema v11.

# Testes e verificações

## Requisitos
- Flutter stable compatível com o SDK declarado em `pubspec.yaml`.
- Dependências instaladas com `flutter pub get`.

## Verificações locais
Execute na raiz do projeto:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --release
```

O build web valida a compilação da plataforma web; ele não substitui testes em
Android/iOS nem valida notificações reais do sistema.

## Testes em dispositivos
- Android: valide permissões de notificação, alarmes exatos e inexatos,
  reinicialização do aparelho, alteração de fuso horário e economia de bateria.
- iOS: valide autorização, apresentação e reagendamento de notificações.
- Web: valide persistência após fechar/reabrir o navegador e comportamento
  em navegação privada ou limpeza de dados.

## Segurança e privacidade
- Não use dados reais de pacientes em testes, issues, logs ou screenshots.
- Novos backups são criptografados com AES-256-GCM e senha do usuário; teste senha correta/incorreta, alteração de ciphertext, salt/nonce únicos e round-trip. Backups JSON antigos continuam importáveis e não são criptografados.
- A criptografia de backups não protege o banco SQLite/IndexedDB ativo, que permanece pendente de migração. Use somente dados fictícios nos testes automatizados e proteja todos os arquivos.
- Recursos de IA e OCR podem transmitir dados e imagens de saúde a serviços
  externos; revise o aviso de privacidade antes de habilitá-los em produção.
- Não considere a análise da IA como diagnóstico, prescrição ou validação
  de interação medicamentosa.

## CI
O workflow `.github/workflows/flutter-ci.yml` informa divergências de
formatação sem bloquear a execução, roda `flutter analyze --no-fatal-infos`
(avisos informativos são tolerados; warnings e erros continuam bloqueando),
testes e build web em pull requests e pushes para `master`/ `main`.
O resultado do CI deve ser verificado antes do merge.

## Limites de validação
Testes automatizados não comprovam segurança clínica, conformidade legal,
ausência de vulnerabilidades ou funcionamento de alarmes em todos os aparelhos.
Esses pontos exigem revisão especializada e testes reais documentados.

# Remédio na Hora 💊

Aplicativo Flutter para organizar medicamentos, tratamentos, lembretes e informações de saúde.

## Funcionalidades
- Cadastro de tratamentos, posologias e horários.
- Agenda, histórico e lembretes locais de doses.
- Cadastro de médicos, consultas, exames e resultados.
- Leitura assistida de documentos e recursos informativos de IA.
- Cartão de emergência e backup/restauração dos dados.
- Interface Flutter para web e plataformas móveis.

## Privacidade e segurança
Os dados de rotina são armazenados localmente no dispositivo/navegador. Recursos
conectados de IA e OCR podem enviar os dados ou imagens necessários ao serviço
remoto correspondente. Backups novos são exportados em envelope JSON com AES-256-GCM e senha definida pelo usuário. Backups antigos em JSON simples continuam importáveis.
Leia [PRIVACY_AND_SECURITY.md](PRIVACY_AND_SECURITY.md) antes de usar esses
recursos com informações reais.

O app é uma ferramenta de organização e não substitui avaliação de médico ou
farmacêutico. Não use respostas geradas por IA como diagnóstico, prescrição ou
confirmação de segurança de medicamentos.

## Desenvolvimento

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --release
```

Consulte [TESTING.md](TESTING.md) para testes locais, CI e validações em aparelhos.

## Deploy
O workflow de deploy existente publica o app web no Vercel quando configurado
com os secrets necessários no repositório.

## Licença
MIT.

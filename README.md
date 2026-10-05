# Remédio na Hora 💊

Um aplicativo Flutter completo para gerenciar medicamentos, terapias e lembretes de doses.

## 🌱 Estado da linha de produto

- ✅ Versão 1: identidade predominantemente verde, estável e pronta para uso.
- 🔵 Versão 2: identidade azul com catálogo local de médicos em desenvolvimento.
- 📦 Metadado atual da app: `2.0.0+2`.

## 📱 Funcionalidades

- ✅ Registro de medicamentos e terapias
- ✅ Catálogo de médicos com especialidade, CRM, endereço, telefone e convênios
- ✅ Atalho gratuito para conferir registro na busca pública do CFM
- ✅ Atalhos para ligar e abrir endereços no Google Maps
- ✅ Sistema de lembretes de doses
- ✅ Acompanhamento de histórico de medicações
- ✅ Visualização do progresso do tratamento
- ✅ Armazenamento local com SharedPreferences
- ✅ Interface responsiva para web, mobile e desktop

## 🚀 Deploy Automático

Este projeto está configurado para deploy automático no **Vercel** a cada push para `main` ou `master`.

**Status do Deploy:** [![Deploy to Vercel](https://github.com/Alexsantossp71/remedios_app_flutter/actions/workflows/deploy-vercel.yml/badge.svg)](https://github.com/Alexsantossp71/remedios_app_flutter/actions/workflows/deploy-vercel.yml)

## 🌐 Acesso Online

[🔗 Acesse a aplicação](https://remedios-app-flutter.vercel.app)

## 🛠️ Tecnologias

- **Flutter (Canal Stable)** - Framework UI Multiplataforma
- **Provider** - State management
- **Table Calendar** - Calendário com lembretes
- **SharedPreferences** - Persistência local
- **url_launcher** - Links para telefone e Google Maps
- **Intl** - Internacionalização

## 📦 Instalação Local

```bash
# Clone o repositório
git clone https://github.com/Alexsantossp71/remedios_app_flutter.git
cd remedios_app_flutter

# Instale as dependências
flutter pub get

# Execute em desenvolvimento
flutter run -d chrome

# Build para produção
flutter build web --release
```

## 📖 Documentação

### Leitura do cartão de plano de saúde (OCR)

A foto do cartão é enviada à função serverless `api/read-card.ts`, que faz o
reconhecimento de texto com **Tesseract.js** dentro do próprio servidor e
interpreta o resultado com regras determinísticas (`api/parse-card.ts`).
**Não existe chave de API**: o modelo de português
(`api/langdata/por.traineddata`) fica no repositório e a imagem não é
repassada a nenhum terceiro.

Como o OCR apenas lê, ele não inventa: um campo que não aparece na imagem fica
vazio e a tela de conferência pede o dado ao usuário. O envio da imagem exige
o consentimento LGPD do usuário (art. 11) e internet; o cadastro manual
funciona sem ambos.

A função depende do runtime Node (`runtime: 'nodejs'`) e do pacote
`tesseract.js`. Secrets do GitHub Actions para deploy: `VERCEL_TOKEN`,
`VERCEL_ORG_ID`, `VERCEL_PROJECT_ID` (obtidos com `vercel link`).

Para mais informações sobre Flutter, acesse:
- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter Cookbook](https://docs.flutter.dev/cookbook)
- [Flutter Documentation](https://docs.flutter.dev/)

## 📄 Licença

Este projeto é de código aberto e disponível sob a licença MIT.

## 👤 Autor

Desenvolvido por **Alexsantossp71**

---

**Nota:** Este é um projeto educacional para gerenciamento de medicamentos. Para questões médicas, consulte sempre um profissional de saúde.

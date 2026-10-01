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

# Testes Automatizados no Browser

Este projeto possui dois tipos de testes automatizados:

## 1. Widget Tests (Simulação)
Testes unitários que simulam a UI Flutter sem um browser real.

**Como rodar:**
```bash
flutter test
```

## 2. Integration Tests (Browser Real com flutter_driver)
Testes E2E que rodam o app no Chrome/Edge de verdade.

### Configuração Necessária

1. **Instalar dependências:**
```bash
flutter pub get
```

2. **Para Web - Usar ChromeDriver:**

   a. Baixe o ChromeDriver compatível com seu Chrome:
   - https://chromedriver.chromium.org/downloads
   - Verifique sua versão do Chrome: `chrome://version`
   
   b. Adicione o ChromeDriver ao PATH

### Como Rodar os Testes E2E

#### Opção 1: Usando flutter drive (Web)
```bash
# Terminal 1 - Inicie o ChromeDriver
chromedriver --port=4444

# Terminal 2 - Rode os testes
flutter drive \
  --driver=test_driver/app_test.dart \
  --target=test_driver/app.dart \
  -d web-server
```

#### Opção 2: Testes integration_test (Android/iOS/Desktop)
```bash
# Android
flutter test integration_test -d android

# Chrome (Desktop)
flutter test integration_test -d chrome

# Edge (Desktop)
flutter test integration_test -d edge
```

**Nota:** `integration_test` no Flutter Web tem suporte limitado. Para testes completos no browser, use `flutter_driver`.

## Estrutura de Testes

### Widget Tests (`test/`)
- `widget_test.dart` - Testes de navegação e formulários
- `medicine_data_test.dart` - Testes de dados de medicamentos
- `doctor_data_test.dart` - Testes de dados de médicos
- `sqlite_storage_test.dart` - Testes de armazenamento

### Integration Tests (`integration_test/`)
Testes que simulam interação do usuário (podem rodar em dispositivos móveis e desktop):
- `app_test.dart` - Navegação e inicialização
- `doctor_flow_test.dart` - Fluxo de cadastro de médicos
- `medicine_flow_test.dart` - Fluxo de adicionar medicamentos
- `consultation_flow_test.dart` - Fluxo de consultas
- `healthplan_flow_test.dart` - Fluxo de planos de saúde

### Driver Tests (`test_driver/`)
Testes E2E que rodam no browser real via WebDriver:
- `app.dart` - Ponto de entrada com driver extension
- `app_test.dart` - Testes de navegação no browser

## Comandos Úteis

```bash
# Rodar apenas widget tests
flutter test

# Rodar teste específico
flutter test test/widget_test.dart

# Rodar com verbose
flutter test --verbose

# Rodar integration tests no Chrome Desktop
flutter test integration_test -d chrome

# Rodar E2E no browser (requer ChromeDriver rodando)
flutter drive --driver=test_driver/app_test.dart --target=test_driver/app.dart -d web-server
```

## CI/CD

Para rodar os testes em CI/CD (GitHub Actions):

```yaml
name: Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      - run: flutter test
      - run: flutter test integration_test
```

## Troubleshooting

### "Web devices are not supported for integration tests yet"
Use `flutter drive` ao invés de `flutter test integration_test -d chrome`.

### ChromeDriver não conecta
- Verifique se o ChromeDriver está rodando: `chromedriver --port=4444`
- Certifique-se de que a versão do ChromeDriver é compatível com seu Chrome
- No Windows, adicione ChromeDriver ao PATH

### Testes falham com timeout
Aumente o timeout nos testes:
```dart
await driver.waitFor(find.text('Texto'), timeout: Duration(seconds: 30));
```

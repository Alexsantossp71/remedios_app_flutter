# Arquitetura — Remédio na Hora

Documento público de referência arquitetural do aplicativo. Para instruções
de setup e processo de PR, veja [`CONTRIBUTING.md`](CONTRIBUTING.md). Para
o glossário de domínio (Medicine, Treatment, Dose, etc.), veja
[`CONTEXT.md`](CONTEXT.md). Para decisões arquiteturais individuais com
contexto e consequências, veja [`docs/adr/`](docs/adr/).

## Visão geral

O Remédio na Hora é um aplicativo Flutter multiplataforma (Android, iOS,
macOS, Windows, Linux, Web) que funciona como organizador pessoal de
medicação, consultas, exames e laudos. Offline-first: todos os dados
clínicos vivem em SQLite local (Android Keystore / WebCrypto + recovery
envelope em Android e Web; plaintext em iOS/macOS/Windows/Linux até
ADR 0009 ser deliverado). Sem nuvem, sem sincronização automática entre
dispositivos. Recursos opcionais de IA e OCR são proxyados via funções
serverless Vercel — nunca no cliente.

Versão atual: 3.2.0 (ver `pubspec.yaml`). Branch ativa: `master`. MIT
License (ver [`LICENSE`](LICENSE)).

## Stack

- **Linguagem**: Dart >= 3.12
- **Framework**: Flutter com `material_ui` 1.11.0 + `cupertino_ui` 1.0.0
  (forks do Material/Cupertino com customizações do projeto)
- **Persistência**: SQLite via `sqflite` family + `sqlite3` 3.5.2 com
  hook SQLite3MultipleCiphers (ChaCha20 cipher em Android/Web)
- **Estado**: `provider` 6.x (ChangeNotifier)
- **DI**: `get_it` 8.x (service locator)
- **Observabilidade**: `sentry_flutter` 10.x (dormant por default,
  PII/PHI scrubbing via `beforeSend`)
- **Notificações mobile**: `flutter_local_notifications` 20.x
- **Criptografia backup**: `cryptography` 2.9.0 (AES-256-GCM)
- **OCR serverless**: Tesseract.js (dentro de Lambda Node.js no Vercel)
- **IA proxy**: servidor Cloudflare Worker / Vercel function, sem chaves
  no cliente

## Estrutura do projeto

```
lib/
├── main.dart                          Entry: main() → Welcome (Web) ou bootstrapApp
├── core/
│   ├── theme/app_theme.dart           V5 ativo + V3 legado + AppSemanticColors
│   ├── design/                        Design system: app_shell, brand_mark,
│                                      brand_colors, dashboard_hero, quick_action,
│                                      record_card, stat_card, app_tokens
│   ├── observability.dart             Sentry + PII/PHI redaction (dormant sem DSN)
│   ├── service_locator.dart           get_it setup
│   └── lab_values.dart                Reference intervals para resultados de lab
├── data/
│   ├── medicine_data.dart             Catálogo estático (assets/data/)
│   └── medical_specialties.dart       Lista de especialidades para form de médico
├── models/                            13 classes Dart puras (sem Flutter dep):
│   consultation, doctor, doctor_draft, dose_event, emergency_contact,
│   exam, health_plan, lab_result, medicine, prescription_record,
│   treatment, treatment_draft, user_profile
├── providers/                         7 ChangeNotifiers (camada de estado):
│   consultation, doctor, exam, health_plan, lab_result, therapy, user_profile
├── screens/                           14 telas:
│   ├── main_shell.dart                Bottom-nav shell (Hoje/Tratamentos/Consultas/Perfil)
│   ├── today_screen.dart              Trilha do dia + timeline + streak
│   ├── treatments_screen.dart         Ativos + arquivados
│   └── ...
├── services/                          48+ serviços, organizados por preocupação:
│   ├── database_service.dart          Singleton SQLite, schema v11, migrations
│   ├── database_encryption/           SQLite3MC open + key pragmas + migration
│   ├── database_key/                  DEK storage (Android Keystore / WebCrypto)
│   ├── backup_service.dart            Export/import com round-trip JSON
│   ├── ai_service.dart                AI summaries (lab, exam, doctor extract)
│   └── ...
└── widgets/                            26+ componentes reutilizáveis

api/                                    Funções serverless Vercel (TS):
├── ping.ts                             Sonda de runtime
├── read-card.ts                        OCR carteirinha (Tesseract.js)
├── read-receita.ts                     OCR receituário
├── places.ts                           Proxy OpenStreetMap Nominatim
└── openapi.yaml                        Contrato OpenAPI 3.1.0
```

## Componentes principais

### 1. main.dart (entry point)

Web boots through `WelcomeScreen` → `DatabaseUnlockGate` (explicit unlock
+ recovery envelope) → `bootstrapApp()`. Native bootstraps directly via
`bootstrapApp()`. `bootstrapApp()` instancia 7 providers, aguarda
`initialize()` sequencial, registra via `MultiProvider` +
`ChangeNotifierProvider.value`, e roda `RemediosApp`.

Em Web (kIsWeb), `main()` chama `SystemChannels.accessibility.send('enable')`
antes do runApp para habilitar semantics desde o primeiro frame.

### 2. Models (13 classes)
Dart puro, sem dependência de Flutter. `copyWith` para updates imutáveis.

### 3. Providers (7 ChangeNotifiers)
Mediam entre services e widgets. Expor `UnmodifiableListView`.

### 4. Services (48+ arquivos)
Persistência, criptografia, IA, OCR, notificações, backup.

### 5. Screens (14)
Roteadas via `MainShell` (bottom-nav). FAB central com menu radial.

### 6. Widgets (26+)
Diálogos, sheets, cards, design-system primitives em `core/design/`.

### 7. Database encryption

**Android + Web (deliverado em PR #64)**: SQLite3MultipleCiphers ChaCha20.
DEK em Android Keystore ou WebCrypto (PBKDF2-HMAC-SHA256 310k iters +
AES-256-GCM recovery envelope).

**iOS / macOS (pendente — ADR 0009)**: plaintext. ADR designado mas não
implementado.

**Windows / Linux (pendente — ADR 0010)**: plaintext. ADR 0010 designa
DPAPI (Windows) e libsecret (Linux) com fallback arquivo 0600.

## Fluxo de dados

1. App starts → `DatabaseService.instance.database` resolve a chave
   (via `DatabaseKeyService` em Android/Web; transparente em native),
   roda migração legacy → encrypted se necessário, abre com PRAGMAs,
   valida a chave, roda migrations de schema v11 → retorna `Database`.
2. Cada provider's `initialize()` carrega registros via o
   `*StorageService` correspondente.
3. UI subscreve via `context.watch<T>()` / lê via `context.read<T>()`.
4. Ação do usuário → método do provider → muta lista in-memory + persiste
   via storage service + `notifyListeners()`.
5. Therapy changes → `_syncDoseNotifications()` replaneja notificações.

## Testes

- Unit/widget tests em `test/` (64+ arquivos)
- Integration tests em `integration_test/` (4 fluxos)
- E2E em Playwright (`e2e/`)
- Database encryption tests em `test/services/database_encryption/`
- Migration tests v9→v11 em `test/database_migration_v9_to_v11_test.dart`

**Não use dados reais de pacientes em testes.**

## CI

`.github/workflows/flutter-ci.yml` roda em ubuntu/macos/windows.
`.github/workflows/deploy-vercel.yml` publica em produção no push para
master, com 8 gates reativos a bugs históricos.

## ADRs

Localizados em `docs/adr/` (0001-0010). Para decisões significativas
novas, adicione um ADR contemporâneo à decisão.

## Padrões de desenvolvimento

### Adicionar nova entidade de domínio
1. Model em `lib/models/`
2. `*StorageService` em `lib/services/`
3. `*Provider` em `lib/providers/`
4. Registrar em `bootstrapApp()` + `setupServiceLocator()`
5. Testes em `test/`
6. Telas/widgets conforme necessário
7. Atualizar `DatabaseService._onCreate` + `_onUpgrade` se precisar de
   nova tabela (bump `_databaseVersion`)
8. ADR se a decisão for significativa

### UI updates
- `context.watch<T>()` para rebuild-on-change
- `context.read<T>()` para one-shot actions

### Persistência
- Sempre via `*StorageService` tipado
- Toda persistência vai por `DatabaseService.instance.database`

### Criptografia (novas plataformas)
Implementar o contract em ADR 0003 + 0004. Ver ADR 0009 (iOS/macOS) e
ADR 0010 (Windows/Linux) para designs específicos.

## Documentação relacionada

- [`README.md`](README.md), [`CONTEXT.md`](CONTEXT.md),
  [`CONTRIBUTING.md`](CONTRIBUTING.md), [`SECURITY.md`](SECURITY.md),
  [`PRIVACY_AND_SECURITY.md`](PRIVACY_AND_SECURITY.md),
  [`TESTING.md`](TESTING.md), [`DEPLOYMENT_GUIDE.md`](DEPLOYMENT_GUIDE.md)
- [`docs/adr/`](docs/adr/) — 10 ADRs
- [`docs/database-encryption.md`](docs/database-encryption.md)
- [`api/openapi.yaml`](api/openapi.yaml) — OpenAPI 3.1.0

## Manutenção

Este arquivo é a **fonte canônica** de arquitetura. `CLAUDE.md` referencia-o
como referência rápida para o agente Claude Code.

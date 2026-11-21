# Contribuindo com o Remédio na Hora

Obrigado pelo interesse em contribuir! Este documento explica como configurar
o ambiente, rodar os testes, e abrir pull requests que passam pelo CI sem
fricção.

## Código de Conduta

Participar deste projeto significa aceitar o [Código de Conduta](CODE_OF_CONDUCT.md).
Comportamento abusivo não será tolerado e resultará em banimento permanente.

## Pré-requisitos

- Flutter estável compatível com o SDK declarado em `pubspec.yaml` (Dart >=3.12).
- Git >= 2.40.
- Para desenvolvimento web: navegador Chromium recente (Firefox e Safari
  ainda precisam de validação — ver `TESTING.md`).
- Para desenvolvimento nativo: Android Studio ou Xcode conforme a plataforma.

## Setup do ambiente

```bash
git clone https://github.com/Alexsantossp71/remedios_app_flutter.git
cd remedios_app_flutter
flutter pub get

# Web: regenera o SQLite3MultipleCiphers WASM + worker (mesmo passo do CI)
dart run sqflite_common_ffi_web:setup --force
curl -fsSLo web/sqlite3.wasm \
  "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.5.2/sqlite3mc.wasm"
echo "62a34ec725631c0438e4255ce0c6059099bf8e7fb331e7d4d91a38e075f43a19  web/sqlite3.wasm" | sha256sum -c -
dart compile js -O2 -o web/sqlite3_mc_sw.js web/sqlite3mc_shared_worker.dart
```

## Rodando localmente

```bash
flutter run -d chrome       # Web
flutter run -d <device-id>  # Android/iOS/desktop
```

## Verificações antes de abrir PR

Execute na raiz antes de commitar. O CI roda as mesmas verificações em
ubuntu/macos/windows:

```bash
flutter pub get --enforce-lockfile   # lockfile reproduzível
dart format lib test                 # formata (CI reporta drift)
flutter analyze --no-fatal-infos     # warnings/erros bloqueiam; infos tolerados
flutter test --coverage              # roda a suíte + gera coverage/lcov.info
flutter build web --release          # valida compilação web
```

O CI completa em ~25 minutos (multi-OS) e deve estar verde antes do merge.

## Estilo de commits

Usamos [Conventional Commits](https://www.conventionalcommits.org/) — o
[Release-Please](https://github.com/googleapis/release-please) gera o
CHANGELOG e version bump automaticamente a partir do histórico.

Formato:

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

Tipos comuns: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`,
`ci`, `perf`, `build`. Scopes típicos: `web`, `security`, `backup`, `ai`,
`ocr`, `notifications`, `db`, `design`, `a11y`.

Exemplos reais do repo:

```
feat(security): integrate SQLite3MultipleCiphers encryption for Android and Web
fix(notifications): use deterministic persisted alarm identifiers
docs(privacy): correct AI proxy retention policy
ci: multi-OS matrix, Playwright e2e workflow, Release-Please
```

Para mudanças que quebram compatibilidade, adicione `!` após o type:
`feat(security)!: drop support for non-encrypted databases` + rodapé
`BREAKING CHANGE: ...`.

## Estrutura do código

Layout em `lib/`:

- `models/` — 13 classes Dart puras (sem Flutter dep). Copy-with para
  updates imutáveis. Convert to/from `Map<String, dynamic>` para SQLite.
- `providers/` — 7 `ChangeNotifier` (camada de estado entre services e
  widgets). Expor `UnmodifiableListView` para evitar mutação externa.
- `services/` — 48 serviços organizados por preocupação. Cada domínio
  tem seu `*StorageService` (tipado) que delega para
  `DatabaseService.instance.database`. Subpastas `database_encryption/`
  e `database_key/` têm variantes platform-aware.
- `screens/` — 14 telas roteadas via `MainShell` (bottom-nav com
  Today/Treatments/Consultations/Profile).
- `widgets/` — 26 componentes reutilizáveis (diálogos, sheets, cards,
  empty states, design-system primitives em `core/design/`).
- `core/` — theme, observability (Sentry), service locator (get_it),
  lab values reference, design tokens.

Para adicionar um novo domínio (entidade nova):

1. Model em `lib/models/` (puro Dart).
2. `*StorageService` em `lib/services/` (tipado, delega a `DatabaseService`).
3. `*Provider` (ChangeNotifier) em `lib/providers/`.
4. Registrar em `main.dart`'s `bootstrapApp()` MultiProvider list e em
   `setupServiceLocator()`.
5. Adicionar `*_storage_service_test.dart` e `*_provider_test.dart`.
6. Adicionar telas/widgets conforme necessário.
7. Atualizar `DatabaseService._onCreate` + `_onUpgrade` se precisar de
   nova tabela (bump `_databaseVersion`).

Decisões arquiteturais são registradas em `docs/adr/` (Architecture
Decision Records). Para decisões significativas, adicione um ADR novo
ou atualize um existente — idealmente contemporâneo à decisão, não
retroativo.

## Abrindo um Pull Request

1. Crie uma branch a partir de `master`:
   `git checkout -b feat/<scope>-<short-description>`.
2. Faça commits pequenos e atômicos, cada um com Conventional Commit.
3. Abra o PR contra `master`. O título deve seguir Conventional Commits
   (o Release-Please usa o título do PR para o CHANGELOG).
4. Preencha o template do PR (será adicionado automaticamente):
   - O que muda e por quê.
   - Issue referenciada (`Closes #N` ou `Refs #N`).
   - Tipo de mudança (feature, fix, breaking).
   - Verificações rodadas localmente.
   - Screenshots se for mudança visual.
5. CI deve estar verde. Se falhar, priorize corrigir o CI em vez de
   adicionar commits de "fix ci".
6. Pelo menos 1 review é necessário para merge em `master`.

Branches devem ser deletadas após merge. Branches `feature/*` órfãs
(sem PR aberto há mais de 30 dias) serão removidas periodicamente.

## Testes

- Unit/widget tests em `test/` (64 arquivos cobrindo models, services,
  providers, widgets).
- Integration tests em `integration_test/` (4 fluxos: consultation,
  healthplan, medicine, app).
- E2E em Playwright (`e2e/`): setup, medicines, consultations,
  health_plans, doctors, diagnose.
- Database encryption tests em
  `test/services/database_encryption/`.

Use `DatabaseService.initInMemoryDatabase()` + overrides `@visibleForTesting`
(`encryptionServiceOverride`, `setDatabaseForTesting`,
`applyUpgradesForTesting`, `createSchemaForTesting`) para testar migrações
sem tocar no disco.

**Não use dados reais de pacientes em testes, issues, logs ou screenshots.**

## Segurança e privacidade

Este aplicativo lida com dados de saúde (PHI) sob LGPD. Leia
[`PRIVACY_AND_SECURITY.md`](PRIVACY_AND_SECURITY.md) antes de contribuir
com features que envolvam:

- Dados clínicos novos (medicamentos, diagnósticos, contatos médicos).
- Fluxos de IA ou OCR (dados podem ir a serviços externos).
- Persistência ou backup (criptografia, retenção).
- Telemetria ou logs (PII/PHI scrubbing obrigatório).

Para reportar vulnerabilidade de segurança, **não abra issue pública**.
Siga [`SECURITY.md`](SECURITY.md).

## Releases

Versionamento via [Release-Please](https://github.com/googleapis/release-please).
Ao merge em `master`, o bot abre um PR `chore(master): release X.Y.Z`
atualizando `pubspec.yaml` (via yaml updater com jsonpath) e `CHANGELOG.md`.
Merge desse PR publica a nova versão e dispara o workflow de deploy no
Vercel.

Versionamento segue [SemVer](https://semver.org/):
- MAJOR: breaking changes (ex.: drop de plataformas suportadas).
- MINOR: feature nova compatível.
- PATCH: bug fix compatível.

## Dúvidas

- Issues técnicas: abra issue no GitHub com label `question`.
- Discussão arquitetural: cite o ADR relevante.
- Para contribuições grandes, abra issue antes de codar para alinhar
  escopo.

Obrigado por contribuir para tornar o cuidado com medicação mais
organizado e seguro no Brasil.

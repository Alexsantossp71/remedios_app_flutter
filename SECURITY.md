# Política de Segurança — Remédio na Hora

## Versões suportadas

| Versão | Suporte | Notas |
|--------|---------|-------|
| 3.2.x  | Ativo   | Branch `master` |
| < 3.0  | Não suportado | Sem patches de segurança |

## Reportando uma vulnerabilidade

**Não abra issue pública para vulnerabilidade de segurança.**

Use um dos canais privados abaixo:

### Canal preferencial: GitHub Security Advisories

1. Acesse https://github.com/Alexsantossp71/remedios_app_flutter/security/advisories/new
2. Clique em **"Report a vulnerability"**.
3. Preencha o template:
   - Título curto da vulnerabilidade.
   - Descrição do impacto (o que um atacante pode fazer).
   - Componentes afetados (arquivo, endpoint, fluxo).
   - Passos para reproduzir (POC se possível).
   - Versão afetada e versão corrigida sugerida.
   - Seu nome/handle para crédito (opcional).
4. Marque como **"Private vulnerability report"**.

### Canal alternativo: email

Se não puder usar GitHub Advisories, envie email para o maintainer
através do perfil público no GitHub
(https://github.com/Alexsantossp71) solicitando canal privado. **Não
inclua detalhes da vulnerabilidade no email de abertura** — apenas
solicite o canal. Os detalhes vão por canal criptografado depois.

## SLA de resposta

| Evento | Prazo |
|--------|-------|
| Confirmação de recebimento | 72h úteis |
| Triagem inicial (validar/severity) | 7 dias |
| Plano de correção comunicado | 14 dias |
| Fix liberado (severity alta/crítica) | 30 dias |
| Fix liberado (severity média) | 60 dias |
| Fix liberado (severity baixa) | Próxima release |

Severity seguirá [CVSS v3.1](https://www.first.org/cvss/). Para
vulnerabilidades que exponham PHI (dados de saúde) ou quebrem a
criptografia em repouso, consideramos **Crítica** independente do CVSS.

## Disclosure coordenado

- Mantemos disclosure coordenado por padrão. O relator é creditado
  (se desejar) no advisory público e no CHANGELOG da release que
  corrige.
- Não publicaremos detalhes técnicos da vulnerabilidade antes do fix
  estar disponível em release pública.
- Após o fix, publicaremos advisory em
  https://github.com/Alexsantossp71/remedios_app_flutter/security/advisories
  com: descrição do impacto, componentes afetados, versão corrigida,
  CVSS, credit.
- O relator pode disclosed a vulnerabilidade publicamente após o fix
  liberado — apreciamos se aguardar 14 dias adicionais para permitir
  adoção da release corrigida.

## Escopo do que consideramos vulnerabilidade

**Sim, reporte:**

- Bypass da criptografia em repouso (SQLite3MultipleCiphers ChaCha20
  em Android/Web).
- Vazamento de DEK (Database Encryption Key) via logs, crash dumps,
  memory dumps, ou shared preferences.
- Falha no rate limiting serverless que permita abuso ou DoS.
- XSS, CSRF, ou injection nas funções serverless (`/api/read-card`,
  `/api/read-receita`, `/api/places`).
- Vazamento de PHI/PII via Sentry (redação insuficiente em
  `redactSentryEvent`).
- Bypass do consentimento LGPD para envio de dados a IA/OCR.
- Falha na restauração de backup que sobrescreva dados existentes.
- Perda silenciosa de dados em migração de schema.

**Não reporte como vulnerabilidade (abra issue comum):**

- Problemas de UX sem impacto de segurança.
- Lints, formatação, melhorias de performance.
- Sugestões de feature.
- Bugs em plataformas explicitamente não suportadas para dados reais
  (iOS/macOS/Windows/Linux enquanto a criptografia em repouso não é
  entregue — documentado em `PRIVACY_AND_SECURITY.md`).
- Vulnerabilidades em dependências sem path de exploração no app
  (use Dependabot alerts para esses).

## Hardening recomendado para deployment próprio

Se você faz fork e deploya sua própria instância:

- Configure `SENTRY_DSN` como GitHub Secret (não como env var da
  Vercel — o CLI local não consegue baixar Vercel Secrets, escreve
  `[SENSITIVE]` como placeholder).
- Rotacione `VERCEL_TOKEN` a cada 90 dias.
- Habilite branch protection em `master`: requer status checks do CI
  verde + pelo menos 1 review.
- Habilite Dependabot security updates no repo.
- Monitore logs do Vercel para 500s em `/api/*` — picos podem indicar
  abuso do rate limiting.
- Faça backup do envelope de recuperação da DEK em local seguro
  offline (não no mesmo dispositivo que o banco).

## Atributos de segurança do app (estado atual)

| Atributo | Android | Web | iOS | macOS | Windows | Linux |
|----------|---------|-----|-----|-------|---------|-------|
| Criptografia em repouso | ✅ ChaCha20 | ✅ ChaCha20 | ❌ Plaintext | ❌ Plaintext | ❌ Plaintext | ❌ Plaintext |
| DEK em cofre do SO | ✅ Keystore | ✅ WebCrypto+envelope | ❌ | ❌ | ❌ | ❌ |
| Backup AES-256-GCM | ✅ PBKDF2 310k | ✅ PBKDF2 310k | ✅ PBKDF2 310k | ✅ PBKDF2 310k | ✅ PBKDF2 310k | ✅ PBKDF2 310k |
| Telemetria PHI-scrubbed | ✅ Sentry dormant | ✅ Sentry dormant | ✅ Sentry dormant | ✅ Sentry dormant | ✅ Sentry dormant | ✅ Sentry dormant |
| OCR local (sem terceiros) | N/A | N/A | N/A | N/A | N/A | N/A |

O OCR roda localmente em Tesseract.js dentro da função serverless
Lambda — a imagem nunca sai da função. Para detalhes, veja
[`PRIVACY_AND_SECURITY.md`](PRIVACY_AND_SECURITY.md) e
[`docs/database-encryption.md`](docs/database-encryption.md).

## Reconhecimentos

Agradecemos a researchers que reportaram responsavelmente:

- _(lista atualizada após disclosure coordenado de cada advisory)_

## Contato

Para questões não-técnicas sobre esta política, abra issue com label
`security-policy`. Para vulnerabilidade, use os canais acima.

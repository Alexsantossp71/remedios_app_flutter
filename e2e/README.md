# E2E Testing with Playwright - Remedios App

Testes end-to-end automatizados completos para o Remedios App Flutter Web usando Playwright.

## 📋 Requisitos

- Node.js 18+ e npm
- Flutter SDK
- Navegador Chromium (instalado automaticamente pelo Playwright)

## 🚀 Instalação

```bash
cd e2e
npm install
npx playwright install
```

## 🧪 Estrutura de Testes

```
e2e/
├── tests/
│   ├── setup.spec.ts              # Navegação e inicialização
│   ├── doctors.spec.ts            # 6 médicos completos
│   ├── medicines.spec.ts          # 7 tratamentos completos
│   ├── consultations.spec.ts      # 5 consultas completas
│   └── health-plans.spec.ts       # 3 planos de saúde
├── fixtures/
│   ├── test-data.json             # Dados de teste (6 médicos, 7 tratamentos, 5 consultas, 3 planos)
│   └── screenshots/               # Screenshots dos testes
├── utils/
│   └── helpers.ts                 # Funções auxiliares
├── playwright.config.ts           # Configuração do Playwright
└── package.json                   # Dependências
```

## 🎯 Cobertura de Testes

### Setup & Navegação (`setup.spec.ts`)
- [x] App carrega com sucesso
- [x] Navegação bottom bar (6 tabs)
- [x] Estado persiste após reload
- [x] Screenshots de todas as telas

### Planos de Saúde (`health-plans.spec.ts`)
- [x] Empty state
- [x] Adicionar 3 planos completos:
  - Unimed (Premium)
  - SulAmérica (Completo)
  - Amil (Básico)
- [x] Editar plano
- [x] Excluir plano

### Médicos (`doctors.spec.ts`)
- [x] Empty state
- [x] Adicionar 6 médicos completos com endereços:
  - Dra. Ana Paula Oliveira (Cardiologia - SP)
  - Dr. Carlos Mendes (Ortopedia - RJ)
  - Dra. Beatriz Santos (Pediatria - MG)
  - Dr. João Silva Neto (Dermatologia - RS)
  - Dra. Fernanda Costa (Ginecologia - DF)
  - Dr. Ricardo Almeida (Psiquiatria - BA)
- [x] Verificar badge CRM
- [x] Editar médico
- [x] Excluir médico

### Tratamentos (`medicines.spec.ts`)
- [x] Empty state
- [x] Adicionar 7 tratamentos completos:
  - Dipirona 500mg
  - Losartana 50mg
  - Omeprazol 20mg
  - Metformina 850mg
  - Prednisona 20mg
  - Insulina NPH 20 unidades
  - Ibuprofeno 400mg
- [x] Buscar no catálogo
- [x] Verificar em "Hoje"
- [x] Editar tratamento
- [x] Excluir tratamento

### Consultas (`consultations.spec.ts`)
- [x] Empty state
- [x] Agendar 5 consultas completas
- [x] Ver detalhes
- [x] Cancelar consulta
- [x] Visualizar no calendário

## 📝 Dados de Teste

Todos os dados estão em `fixtures/test-data.json`:
- **3 planos de saúde** com números de carteirinha reais
- **6 médicos** com CRM, especialidades e endereços completos
- **7 tratamentos** com medicamentos, dosagens e frequências
- **5 consultas** com datas, horários e observações

## 🏃 Como Rodar

### Opção 1: Com servidor automático (recomendado)

```bash
npm test
```

O Playwright vai:
1. Iniciar o Flutter web automaticamente na porta 5000
2. Rodar todos os testes
3. Gerar relatório HTML

### Opção 2: Servidor manual

**Terminal 1 - Iniciar Flutter:**
```bash
cd ..
flutter run -d web-server --web-port=5000
```

**Terminal 2 - Rodar testes:**
```bash
cd e2e
npm test
```

### Opção 3: Scripts prontos

**Windows:**
```powershell
.\run-tests.ps1
```

**Linux/Mac:**
```bash
./run-tests.sh
```

## 🎨 Modos de Execução

```bash
# Todos os testes
npm test

# Modo visual (headed)
npm run test:headed

# Modo debug
npm run test:debug

# Modo UI interativo
npm run test:ui

# Teste específico
npx playwright test tests/doctors.spec.ts

# Com screenshot
npx playwright test --screenshot=on
```

## 📊 Relatórios

Após rodar os testes:

```bash
npm run report
```

Abre navegador com:
- ✅ Testes passados/falhados
- 📸 Screenshots
- 🎥 Vídeos de falhas
- ⏱️ Tempos de execução
- 📋 Trace files para debug

## 🐛 Debug

### Ver teste rodando em tempo real:
```bash
npm run test:headed
```

### Debug passo-a-passo:
```bash
npm run test:debug
```

### UI Mode (melhor para debug):
```bash
npm run test:ui
```

### Gerar novo teste gravando ações:
```bash
npm run codegen
```

## 📸 Screenshots

Todos os screenshots são salvos em `fixtures/screenshots/`:
- `doctors-empty-state.png`
- `doctor-1-oliveira.png` até `doctor-6-almeida.png`
- `doctors-all-6-registered.png`
- `treatment-1-dipirona.png` até `treatment-7-ibuprofeno.png`
- `treatments-all-7-registered.png`
- `consultation-1-oliveira.png` até `consultation-5-costa.png`
- `consultations-all-5-scheduled.png`
- E muitos outros...

## 🔧 Configuração

Edite `playwright.config.ts` para:
- Alterar porta do servidor (default: 5000)
- Adicionar mais browsers (Firefox, Safari)
- Ajustar timeouts
- Configurar retries
- Habilitar/desabilitar screenshots/videos

## ✅ Checklist de Testes

- [x] App carrega
- [x] 6 tabs navegam corretamente
- [x] 3 planos de saúde criados
- [x] 6 médicos cadastrados com endereços completos
- [x] 7 tratamentos adicionados
- [x] 5 consultas agendadas
- [x] Edição funciona
- [x] Exclusão funciona
- [x] Persistência de dados
- [x] Screenshots de evidência
- [x] Validações de formulário

## 🎯 Benefícios

✅ **Cobertura completa** - Todos os fluxos principais  
✅ **Dados reais** - 6 médicos, 7 tratamentos, 5 consultas, 3 planos  
✅ **Screenshots automáticos** - Evidência visual  
✅ **Cross-browser** - Chromium, Firefox, WebKit  
✅ **Auto-wait** - Sem sleeps manuais  
✅ **Debug fácil** - UI mode e trace viewer  
✅ **CI/CD ready** - GitHub Actions compatible  

## 🚨 Troubleshooting

### Porta 5000 em uso
```bash
# Windows
netstat -ano | findstr :5000
taskkill /PID <PID> /F

# Linux/Mac
lsof -ti:5000 | xargs kill
```

### Testes falhando
1. Verifique se Flutter está rodando: http://localhost:5000
2. Limpe o estado do app
3. Rode com `--headed` para ver o que está acontecendo
4. Use `--debug` para pausar e inspecionar

### Browser não encontrado
```bash
npx playwright install
```

## 📚 Documentação

- [Playwright Docs](https://playwright.dev/)
- [Test API](https://playwright.dev/docs/api/class-test)
- [Locators](https://playwright.dev/docs/locators)
- [Assertions](https://playwright.dev/docs/test-assertions)

## 🎉 Resultado Esperado

Ao rodar `npm test`, você verá:

```
Running 25 tests using 1 worker

  ✓ setup.spec.ts:12:3 › app loads successfully (2s)
  ✓ setup.spec.ts:19:3 › navigate to each tab successfully (4s)
  ✓ health-plans.spec.ts:20:3 › should add 3 health plans successfully (8s)
  ✓ doctors.spec.ts:20:3 › should add all 6 doctors with full details (25s)
  ✓ medicines.spec.ts:17:3 › should add all 7 treatments with full details (22s)
  ✓ consultations.spec.ts:47:3 › should schedule all 5 consultations (20s)
  ...

  25 passed (2m 15s)
```

**Todos os 25 testes passando = App funcionando 100%! 🎉**

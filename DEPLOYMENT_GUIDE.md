# Guia de Deploy - Remédio na Hora

## ✅ Configuração Concluída

✅ **Git Repository:** Criado em https://github.com/Alexsantossp71/remedios_app_flutter  
✅ **GitHub Actions:** Workflow configurado em `.github/workflows/deploy-vercel.yml`  
✅ **Vercel Config:** Arquivo `vercel.json` criado  
✅ **README:** Atualizado com informações do projeto  

## 🔐 Configurar Secrets no GitHub

Para que o deploy automático funcione, você precisa configurar o secret `VERCEL_TOKEN` no GitHub:

### 1. **Como Configurar:**
1. Acesse: https://github.com/Alexsantossp71/remedios_app_flutter/settings/secrets/actions
2. Clique em **"New repository secret"**
3. Adicione:
   - **Name:** `VERCEL_TOKEN`
   - **Secret:** *(Seu token pessoal do Vercel - veja abaixo como obter)*
4. Clique em **"Add secret"**

### 2. **Como obter seu VERCEL_TOKEN:**
1. Acesse: https://vercel.com/account/tokens
2. Clique em **"Create Token"**
3. Dê um nome (ex: "GitHub Actions Deploy")
4. Selecione escopo: **Full Account**
5. Copie o token gerado (formato: `vcp_...`)

## 🚀 Primeiro Deploy

O primeiro deploy acontecerá automaticamente em **menos de 5 minutos** após configurar o secret.

Você também pode acionar manualmente:
1. Acesse: https://github.com/Alexsantossp71/remedios_app_flutter/actions
2. Clique em **"Deploy to Vercel"**
3. Clique no botão **"Run workflow"**

## 🌐 Acesso à Aplicação

Após o primeiro deploy, sua aplicação estará disponível em:
- **URL Principal:** https://remedios-app-flutter.vercel.app
- **URL Automática:** https://remedios-app-flutter-{seu-usuario}.vercel.app

## 🔄 Deploy Automático

A cada push para `master` ou `main`, o GitHub Actions irá:
1. Baixar o código
2. Instalar Flutter e dependências (com cache)
3. Build da aplicação web (`flutter build web --release`)
4. Deploy automático no Vercel via `npx vercel deploy build/web --prod --yes`

## 🐛 Troubleshooting

### "Build failed" no Vercel
- Verifique se o `VERCEL_TOKEN` está correto nas secrets do GitHub
- Confirme que o `vercel.json` está no repositório
- Verifique a versão do Flutter (usa canal `stable`)

### "Workflow not triggered"
- Verifique se o arquivo `.github/workflows/deploy-vercel.yml` existe
- Confirme se o push foi feito para a branch `master` ou `main`

### "Vercel deploy failed"
- Verifique se o token tem permissão **Full Account**
- Tente criar um novo token se o antigo expirou
- Verifique se o projeto "remedios-app-flutter" não foi criado manualmente com configuração diferente

## 📞 Suporte

- **GitHub Issues:** https://github.com/Alexsantossp71/remedios_app_flutter/issues
- **Vercel Docs:** https://vercel.com/docs
- **Flutter Web:** https://flutter.dev/web

---

**✨ Pronto!** Seu app Flutter já está configurado para deploy gratuito e automático no Vercel.

**⚠️ Importante:** Nunca commite tokens ou secrets diretamente no código. Use sempre as **GitHub Secrets** para credenciais sensíveis.
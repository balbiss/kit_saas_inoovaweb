# Painel (React / TanStack Start)

O código do painel não é duplicado neste kit — vive no repo `saas-chatwoot`, que já é genérico o bastante (nenhuma lógica de negócio específica da conta atual). Você recebeu acesso a esse repo separadamente.

## Variáveis de ambiente (apontar pro SEU projeto Supabase)

**⚠️ São DOIS conjuntos de variáveis, em momentos diferentes — as duas etapas são obrigatórias, esquecer a segunda é o erro mais comum ao instalar isso (dá tela branca ou erro 500 "supabaseUrl is required", mesmo com o build "certo").**

### 1. Build-time (Vite/client bundle) — GitHub Actions Variables

O build (Vite) lê `VITE_SUPABASE_URL` / `VITE_SUPABASE_PROJECT_ID` / `VITE_SUPABASE_PUBLISHABLE_KEY`. O `Dockerfile` recebe esses 3 valores como **build args** (não fixos no código) — assim seu fork builda automaticamente apontando pro SEU Supabase, sem editar nenhum arquivo:

- **Build automático via GitHub Actions** (recomendado, é o que já roda a cada push na `main`): no seu fork, vá em `Settings → Secrets and variables → Actions → aba "Variables"` (⚠️ não a aba "Secrets" — é um erro fácil de cometer, o workflow lê `vars.X`, se cair em Secrets o build passa "com sucesso" mas embute string vazia) e crie as 3 variáveis com os dados do projeto Supabase que você criou (ver `../supabase/README.md`):
  ```
  VITE_SUPABASE_URL=https://<seu-projeto>.supabase.co
  VITE_SUPABASE_PROJECT_ID=<seu-projeto>
  VITE_SUPABASE_PUBLISHABLE_KEY=<sua anon/publishable key>
  ```
  Feito isso uma vez, todo `git push` na `main` builda sozinho e publica a imagem em `ghcr.io/<seu-usuario>/saas-chatwoot:latest` — não precisa rodar Docker local. Se você criou as Variables DEPOIS de já ter dado push, o build antigo não pega os valores novos — precisa de um push novo (ou vazio: `git commit --allow-empty -m "rebuild" && git push`) pra rebuildar com os valores certos. Confira sempre com `docker buildx imagetools inspect ghcr.io/<seu-usuario>/saas-chatwoot:latest` se pegou um digest novo.
- **Build local** (se quiser testar sem depender do Actions): `docker build --build-arg VITE_SUPABASE_URL=... --build-arg VITE_SUPABASE_PROJECT_ID=... --build-arg VITE_SUPABASE_PUBLISHABLE_KEY=... -t saas-chatwoot .`

### 2. Runtime (servidor SSR do container) — variáveis de ambiente da STACK/compose, não do build

Isso é fácil de esquecer porque o app É Vite, e intuitivamente parece que "build args já resolve tudo". Mas o painel é **TanStack Start com SSR** — o processo Node que roda dentro do container, além de servir o bundle client já buildado, também EXECUTA código server-side a cada request, e esse código lê variáveis de ambiente em runtime, não em build-time:

- `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` — usadas por `src/integrations/supabase/client.server.ts` (client admin, bypassa RLS). Sem isso: erro `supabaseUrl is required` no SSR.
- `VITE_SUPABASE_URL`, `VITE_SUPABASE_PROJECT_ID`, `VITE_SUPABASE_PUBLISHABLE_KEY` — sim, de novo, **mesmo já tendo sido usadas como build arg**. O motivo: o Vite NÃO inlina `import.meta.env.VITE_*` de forma estática no bundle SSR (só faz isso no bundle client/browser) — no bundle server ele vira uma leitura de `process.env.VITE_*` de verdade, resolvida a cada request. Sem isso: mesmo erro `supabaseUrl is required`, mas vindo do client "de navegador" (`src/integrations/supabase/client.ts`) sendo importado por engano/necessidade em algum código que roda em SSR.

Ou seja: na stack/compose de deploy (Portainer, Swarm, o que for), o serviço do painel precisa dessas 5 variáveis de ambiente, com os MESMOS valores usados nos build args:
```yaml
environment:
  - PORT=3000
  - HOST=0.0.0.0
  - SUPABASE_URL=https://<seu-projeto>.supabase.co
  - SUPABASE_SERVICE_ROLE_KEY=<sua service_role key>
  - VITE_SUPABASE_URL=https://<seu-projeto>.supabase.co
  - VITE_SUPABASE_PROJECT_ID=<seu-projeto>
  - VITE_SUPABASE_PUBLISHABLE_KEY=<sua anon/publishable key>
```

## Pontos de rebrand (marca "InoovaWeb" → a sua)

Busca simples e substituição, sem lógica escondida:

- `src/routes/admin/route.tsx`
- `src/routes/auth.tsx`
- `src/routes/_authenticated/agenda.tsx`
- `src/routes/_authenticated/route.tsx`
- `src/routes/__root.tsx`
- `src/assets/inoovaweb-icon.png` — troque pelo ícone/logo da sua marca (mesmo nome de arquivo, ou ajuste os imports)

## Deploy

O repo já tem um `Dockerfile` funcional e um workflow de CI (`.github/workflows/docker.yml`) que builda e publica a imagem no GitHub Container Registry a cada push na `main`. Adapte o registry/imagem pro seu próprio GitHub, e o compose/stack de deploy (fora deste kit, você define como prefere rodar — Portainer, Swarm puro, etc.) pra apontar pra sua imagem.

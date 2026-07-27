# Painel (React / TanStack Start)

O código do painel não é duplicado neste kit — vive no repo `saas-chatwoot`, que já é genérico o bastante (nenhuma lógica de negócio específica da conta atual). Você recebeu acesso a esse repo separadamente.

## Variáveis de ambiente (apontar pro SEU projeto Supabase)

O build (Vite) lê `VITE_SUPABASE_URL` / `VITE_SUPABASE_PROJECT_ID` / `VITE_SUPABASE_PUBLISHABLE_KEY`. O `Dockerfile` recebe esses 3 valores como **build args** (não fixos no código) — assim seu fork builda automaticamente apontando pro SEU Supabase, sem editar nenhum arquivo:

- **Build automático via GitHub Actions** (recomendado, é o que já roda a cada push na `main`): no seu fork, vá em `Settings → Secrets and variables → Actions → aba Variables` e crie as 3 variáveis com os dados do projeto Supabase que você criou (ver `../supabase/README.md`):
  ```
  VITE_SUPABASE_URL=https://<seu-projeto>.supabase.co
  VITE_SUPABASE_PROJECT_ID=<seu-projeto>
  VITE_SUPABASE_PUBLISHABLE_KEY=<sua anon key>
  ```
  Feito isso uma vez, todo `git push` na `main` builda sozinho e publica a imagem em `ghcr.io/<seu-usuario>/saas-chatwoot:latest` — não precisa rodar Docker local.
- **Build local** (se quiser testar sem depender do Actions): `docker build --build-arg VITE_SUPABASE_URL=... --build-arg VITE_SUPABASE_PROJECT_ID=... --build-arg VITE_SUPABASE_PUBLISHABLE_KEY=... -t saas-chatwoot .`

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

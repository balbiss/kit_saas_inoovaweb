# Painel (React / TanStack Start)

O código do painel não é duplicado neste kit — vive no repo `saas-chatwoot`, que já é genérico o bastante (nenhuma lógica de negócio específica da conta atual). Você recebeu acesso a esse repo separadamente.

## Variáveis de ambiente (apontar pro SEU projeto Supabase)

O build (Vite) lê estas variáveis de `VITE_SUPABASE_URL` / `VITE_SUPABASE_PUBLISHABLE_KEY` — definidas tanto no `Dockerfile` (linhas `ENV VITE_SUPABASE_...`) quanto num `.env` na raiz do repo (usado tanto pelo build local quanto pela CLI do Supabase). Troque as duas pelo valores do projeto Supabase que você criou (ver `../supabase/README.md`):

```
VITE_SUPABASE_URL=https://<seu-projeto>.supabase.co
VITE_SUPABASE_PROJECT_ID=<seu-projeto>
VITE_SUPABASE_PUBLISHABLE_KEY=<sua anon key>
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

# Supabase

As migrations e Edge Functions vivem no repo `saas-chatwoot` (pastas `supabase/migrations/` e `supabase/functions/`) — já são genéricas, sem nenhuma referência à conta/domínio atual. Não precisam de nenhuma alteração de código, só serem aplicadas no SEU projeto.

## 1. Criar o projeto

Crie um projeto novo em [supabase.com](https://supabase.com/dashboard). Anote a **URL do projeto**, a **anon/publishable key** (vão pro painel, ver `../painel/README.md`) e gere um **Personal Access Token** (Account → Access Tokens) pra usar via CLI/Management API.

## 2. Aplicar as migrations

Dentro do repo `saas-chatwoot`:

```bash
npx supabase login --token <seu-personal-access-token>
npx supabase link --project-ref <seu-project-ref>
npx supabase db push   # aplica todas as migrations de supabase/migrations/ em ordem
```

(Alternativa usada durante o desenvolvimento deste projeto: `POST https://api.supabase.com/v1/projects/<ref>/database/query` com `{"query": "<conteudo do .sql>"}` e o Personal Access Token no header `Authorization: Bearer`, uma migration de cada vez, na ordem dos nomes de arquivo.)

## 3. Deploy das Edge Functions

```bash
SUPABASE_ACCESS_TOKEN=<seu-personal-access-token> npx supabase functions deploy <nome-da-funcao> --project-ref <seu-project-ref> --no-verify-jwt
```

Repita pra cada pasta dentro de `supabase/functions/` (`admin-create-company`, `admin-update-company`, `admin-delete-company`, `get-metrics`, `clear-chat-memory`, `get-calendar-token`, `save-calendar-token`, `upsert-lead`, etc — confira a lista completa no repo, pode ter crescido).

## 4. Configurar os secrets das Edge Functions

Algumas funções dependem de variáveis de ambiente próprias (além das automáticas `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`, que o Supabase já injeta sozinho):

```bash
npx supabase secrets set N8N_CLEAR_MEMORY_URL=https://<seu-n8n>/webhook/limpar-memoria-ia --project-ref <seu-project-ref>
npx supabase secrets set N8N_CLEAR_MEMORY_SECRET=<escolha um segredo forte> --project-ref <seu-project-ref>
```

(O mesmo `N8N_CLEAR_MEMORY_SECRET` precisa estar configurado no workflow `limpar-memoria-chat` do n8n — ver `../n8n/`.)

## 5. Evitar a pausa por inatividade (plano gratuito)

Se for usar o plano free do Supabase, ele pausa o projeto após 7 dias sem requisição na API. `pg_cron` rodando só dentro do banco **não conta** como atividade pra esse critério (é preciso uma requisição de verdade na API Gateway). O workflow `supabase-keep-alive` do n8n (`../n8n/workflows/supabase-keep-alive.json`) já resolve isso — só ative ele.

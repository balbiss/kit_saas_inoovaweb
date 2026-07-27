# Supabase

As migrations e Edge Functions vivem no repo `saas-chatwoot` (pastas `supabase/migrations/` e `supabase/functions/`) — já são genéricas, sem nenhuma referência à conta/domínio atual. Não precisam de nenhuma alteração de código, só serem aplicadas no SEU projeto.

## 1. Criar o projeto

Crie um projeto novo em [supabase.com](https://supabase.com/dashboard). Anote a **URL do projeto**, o **project ref** (Project Settings → General), a **anon/publishable key** (vão pro painel, ver `../painel/README.md`) e gere um **Personal Access Token** (Account → Access Tokens).

## 2. Rodar o script de setup (automático)

Dentro do repo `saas-chatwoot`:

```bash
cp supabase/setup.env.example supabase/setup.env
# abra supabase/setup.env e preencha com os dados do SEU projeto
bash supabase/setup.sh
```

Esse script faz tudo em uma tacada só: aplica todas as migrations, deploya todas as Edge Functions e configura os secrets que elas precisam. Pode rodar de novo quantas vezes quiser (é seguro repetir). `supabase/setup.env` nunca é commitado (já está no `.gitignore`).

Se preferir fazer manualmente (ou o script falhar em algum passo e quiser rodar só uma parte), os comandos que ele executa por baixo dos panos:

```bash
npx supabase login --token <seu-personal-access-token>
npx supabase link --project-ref <seu-project-ref>
npx supabase db push                                                            # migrations
npx supabase functions deploy <nome-da-funcao> --project-ref <ref> --no-verify-jwt   # uma vez por pasta em supabase/functions/
npx supabase secrets set CHAVE=valor --project-ref <ref>                        # ver lista de secrets no setup.env.example
```

## 3. Evitar a pausa por inatividade (plano gratuito)

Se for usar o plano free do Supabase, ele pausa o projeto após 7 dias sem requisição na API. `pg_cron` rodando só dentro do banco **não conta** como atividade pra esse critério (é preciso uma requisição de verdade na API Gateway). O workflow `supabase-keep-alive` do n8n (`../n8n/workflows/supabase-keep-alive.json`) já resolve isso — só ative ele.

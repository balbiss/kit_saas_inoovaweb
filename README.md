# InoovaWeb — kit de self-host

SaaS multi-tenant de atendimento via WhatsApp com IA (qualquer nicho — clínica, imobiliária, loja, salão, etc). Este kit reúne tudo que é preciso pra rodar uma instância própria e independente, numa VPS própria.

Se você (ou o Claude Code que estiver te ajudando) estiver começando agora, comece lendo `.claude/skills/inoovaweb-saas/SKILL.md` — explica a arquitetura, os padrões técnicos do n8n e as armadilhas já descobertas construindo isso. Economiza bastante retrabalho.

## As 4 partes

1. **Supabase** — banco de dados + Edge Functions. Migrations e código já genéricos, vivem no repo do painel.
2. **Chatwoot + Baileys** — canal de WhatsApp. Compose pronto nesta pasta (`chatwoot/`).
3. **n8n** — toda a lógica de IA/automação. Workflows exportados e parametrizados nesta pasta (`n8n/`).
4. **Painel** — app React onde cada empresa configura tudo. Vive em repo próprio (`saas-chatwoot`), você recebeu acesso separadamente.

## Ordem de instalação

### 1. Supabase
Siga `supabase/README.md`: criar projeto, aplicar migrations, deploy das Edge Functions, configurar secrets.

### 2. Chatwoot + Baileys
Siga `chatwoot/README.md`: buildar a imagem do fork do Chatwoot, preencher `.env`, subir a stack.

### 3. n8n
Suba um n8n limpo (imagem oficial `n8nio/n8n`, qualquer Postgres/SQLite próprio — não precisa ser o mesmo banco de nada). Configure as variáveis de ambiente do container:

```
SUPABASE_URL=https://<seu-projeto>.supabase.co
SUPABASE_SERVICE_KEY=<sua service_role key>
CHATWOOT_URL=https://<seu-dominio-chatwoot>
CHATWOOT_AGENCY_TOKEN=<token de acesso pessoal de um usuario administrador no seu Chatwoot>
N8N_URL=https://<seu-n8n>
GOOGLE_CLIENT_ID=<client id OAuth do Google Cloud Console>
GOOGLE_CLIENT_SECRET=<client secret OAuth do Google Cloud Console>
```

(`GOOGLE_CLIENT_ID`/`SECRET` são de um projeto no Google Cloud Console com a API do Google Calendar habilitada e uma tela de consentimento OAuth configurada — necessário pra função de agendamento.)

Depois: `n8n/import.sh <container>` importa os 23 workflows (preservando os IDs originais, necessário pras referências entre eles funcionarem). Depois do import:
- Recrie a credencial OpenAI na UI do n8n (crie uma vez, com qualquer nome — os workflows referenciam por ID, então depois de importar você precisa abrir cada node de IA e reselecionar a credencial).
- Ative cada um dos 23 workflows manualmente.
- Pegue a URL do webhook do `sdr-agente-dinamico` (é o ponto de entrada — é nele que o Chatwoot vai mandar as mensagens recebidas via automação/webhook).

### 4. Painel
Siga `painel/README.md`: variáveis de build apontando pro seu Supabase, pontos de rebrand, deploy.

### 5. Primeira empresa de teste
Com tudo no ar: crie a primeira empresa pelo painel (fluxo de super-admin → `admin-create-company`, que cria a conta isolada no Chatwoot automaticamente + já provisiona as etiquetas padrão), configure o prompt da IA, conecte o WhatsApp (QR code) e mande uma mensagem de teste de verdade pra validar a cadeia inteira.

## O que NÃO está neste kit (de propósito)

- Nenhum dado de empresas/clientes — é um kit vazio, pronto pra primeira empresa.
- Nenhuma credencial de produção do ambiente original — todo segredo foi trocado por variável de ambiente antes da exportação (ver nota de verificação em `n8n/workflows/` — cada arquivo foi conferido individualmente, incluindo um client secret do Google OAuth que estava fixado em texto puro no original e foi parametrizado).
- Integrações de pagamento (Mercado Pago) — são configuradas por CADA EMPRESA no próprio painel dela (token da própria conta Mercado Pago), não é uma credencial de instalação única.

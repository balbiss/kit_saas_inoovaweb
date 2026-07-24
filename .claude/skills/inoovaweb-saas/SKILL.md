---
name: inoovaweb-saas
description: Arquitetura, padrões e armadilhas do InoovaWeb — SaaS de atendimento via WhatsApp com IA (Chatwoot + Baileys + n8n + Supabase + painel React). Use sempre que for mexer em qualquer parte deste sistema (workflows do n8n, painel, schema do Supabase, Chatwoot).
---

# InoovaWeb — guia operacional

SaaS multi-tenant de atendimento via WhatsApp com IA. Qualquer nicho (clínica, imobiliária, loja, salão, etc.) pode rodar nele — cada empresa é uma conta isolada. Este guia existe pra qualquer sessão do Claude Code que for mexer no sistema não precisar redescobrir do zero como as peças se encaixam.

**Instalando do zero pela primeira vez?** Pare de ler aqui e siga `INSTALACAO.md` — é um manual passo a passo escrito pra você seguir sozinho, parando pra pedir informação ao usuário exatamente nos pontos em que só ele pode fornecer (contas, domínios, credenciais, ações físicas). O resto deste arquivo (e `WORKFLOWS.md`/`GOTCHAS.md`) é referência de arquitetura — útil durante a instalação e depois, pra manutenção.

## As 4 partes do sistema

1. **Painel** — app React (TanStack Start), onde cada empresa configura prompt da IA, agenda, produtos, documentos, leads, métricas e pagamento (Mercado Pago). Repo próprio, deploy como imagem Docker.
2. **Chatwoot + Baileys** — canal de WhatsApp. Fork do Chatwoot (`fazer-ai/chatwoot`) com um bridge Baileys (`ghcr.io/fazer-ai/baileys-api`, imagem pública) plugado via a integração de canal customizada do fork. Cada empresa = uma CONTA Chatwoot isolada (não um inbox dentro de conta compartilhada).
3. **n8n** — TODA a lógica de IA e automação mora aqui: o agente principal (`SDR AGENTE - DINAMICO`), agendamento (Google Calendar), catálogo de produtos, pagamento via Pix (Mercado Pago), follow-up, reengajamento, lembretes. Fala com o Supabase via REST (PostgREST), nunca via Postgres direto.
4. **Supabase** — banco de dados (`companies`, `products`, `leads`, `appointments`, `resources`, `pedidos`, `agendamento_pagamentos`, etc.) com RLS, mais Edge Functions pra tudo que precisa rodar server-side com privilégio (criar empresa isolada no Chatwoot, métricas, limpar memória da IA, tokens do Google Calendar).

Ver `WORKFLOWS.md` neste skill pro mapa completo dos workflows do n8n e o que cada um faz. Ver `GOTCHAS.md` pros padrões técnicos e armadilhas já descobertas — leia antes de editar qualquer workflow.

## Como editar um workflow do n8n com segurança (o fluxo usado o tempo todo)

A UI do n8n é lenta pra edições grandes/repetitivas. O fluxo que funciona:

1. `GET /rest/workflows/{id}` (autenticado por cookie de sessão — login normal na UI e reaproveitar o cookie, não existe API key separada pra isso) pra pegar o JSON completo do workflow.
2. Editar o JSON localmente (node/script), tipicamente fazendo substituição de string em `parameters.jsCode` (Code nodes) ou `parameters.url`/`jsonBody` (HTTP Request nodes) — mais confiável que tentar reconstruir o node inteiro.
3. `PATCH /rest/workflows/{id}` com `{name, nodes, connections, settings}` de volta.
4. **Sempre** `POST /rest/workflows/{id}/deactivate` seguido de `POST /rest/workflows/{id}/activate` com o `versionId` retornado pelo deactivate. Sem isso, o n8n continua rodando o código ANTIGO em cache mesmo o PATCH tendo retornado sucesso — esse passo não é opcional.
5. Depois de editar um Code node, vale rodar `node --check arquivo.js` no conteúdo extraído do `jsCode` antes de publicar — pega erro de sintaxe introduzido por substituição de string mal calculada.

## Testando

- `POST /rest/workflows/{id}/run` (execução manual) **não é confiável** pra este projeto — erro genérico ou ignora `pinData` mesmo quando o workflow funciona de verdade. Pra testar de verdade: mandar mensagem real via WhatsApp de um número de teste, ou (pra Schedule Trigger) baixar o intervalo pra 1 minuto temporariamente e reverter depois.
- Pra decidir SE algo é usado de verdade (antes de mexer ou de considerar remover), não confiar só no nome: puxar o histórico real de execuções (`GET /rest/executions?filter={"workflowId":"..."}`) E checar se o workflow fala com o Supabase via REST (`httpRequest` com URL do projeto) — um sistema antigo/paralelo pode continuar rodando de verdade e ainda assim não ser a arquitetura atual.

## Reaproveitar antes de criar

Antes de escrever lógica nova, procurar se já existe um padrão pra isso: busca fuzzy por nome (ver `GOTCHAS.md`), geração/confirmação de Pix (`pagamentos-gerar-pix.json` + `pagamentos-webhook-mercadopago.json`), atribuição de time (`atendimento-transferir-humano.json`), trava de estado via etiqueta do Chatwoot (`followup_ativo`, `aguardando_pagamento` — ver como o follow-up usa isso pra não disparar em paralelo).

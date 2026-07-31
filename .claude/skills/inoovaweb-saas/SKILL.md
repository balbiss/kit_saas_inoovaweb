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

## Prefira sempre o MCP do n8n quando disponível

Se essa instância do n8n já tem um servidor MCP conectado (`claude mcp list` mostra ele "Connected"), **use as ferramentas MCP em vez de montar chamadas REST cruas** pra ler/editar/ativar workflows, credenciais e execuções — é mais confiável e menos sujeito a erro de payload do que os scripts REST abaixo. Só caia pro REST cru (o resto desta seção) se o MCP não estiver disponível/conectado pra essa instância, ou se a ferramenta MCP não cobrir o que você precisa fazer.

Cada instalação nova precisa do próprio servidor MCP registrado (não é compartilhado entre clientes): gerar o token via `GET /rest/mcp/api-key` (cria automaticamente se não existir) + `POST /rest/mcp/api-key/rotate` (retorna o JWT completo, só aparece uma vez), depois `claude mcp add-json <nome> '{"type":"http","url":"https://<n8n-do-cliente>/mcp-server/http","headers":{"Authorization":"Bearer <token>"}}'`. **Se der erro `"MCP access is disabled"` mesmo com o token certo**: 🛑 PARE E PEÇA pro usuário habilitar em `Settings → Instance-level MCP` (toggle "Enabled" + aba "Workflows" → selecionar tudo → "Enable workflows", clicando em cada workflow no modal de busca) — ver `GOTCHAS.md` ("MCP nativo do n8n") pro passo a passo exato. Isso é uma etapa manual na UI, não tem endpoint REST conhecido pra automatizar.

## Como editar um workflow do n8n com segurança (o fluxo usado o tempo todo)

A UI do n8n é lenta pra edições grandes/repetitivas. Sem MCP disponível, o fluxo REST que funciona:

1. `GET /rest/workflows/{id}` (autenticado por cookie de sessão — login normal na UI e reaproveitar o cookie, não existe API key separada pra isso) pra pegar o JSON completo do workflow.
2. Editar o JSON localmente (node/script), tipicamente fazendo substituição de string em `parameters.jsCode` (Code nodes) ou `parameters.url`/`jsonBody` (HTTP Request nodes) — mais confiável que tentar reconstruir o node inteiro.
3. `PATCH /rest/workflows/{id}` com `{name, nodes, connections, settings}` de volta.
4. **Sempre** re-publicar depois: `GET /rest/workflows/{id}` pra pegar o `versionId` atual, depois `POST /rest/workflows/{id}/activate` com `{"versionId": "<esse valor>"}`. **`PATCH .../workflows/{id}` com `{"active":true}` sozinho NÃO é suficiente nas versões recentes do n8n** — retorna 200 mas o workflow continua com `active:false`/`triggerCount:0` de verdade (webhook nem responde). Se o workflow chamar sub-workflows, publicar pode falhar pedindo pra publicar as dependências primeiro — ver `GOTCHAS.md` ("n8n exige publicar workflow") pro script que resolve isso em rounds.
5. Depois de editar um Code node, vale rodar `node --check arquivo.js` no conteúdo extraído do `jsCode` antes de publicar — pega erro de sintaxe introduzido por substituição de string mal calculada.

## Testando

- `POST /rest/workflows/{id}/run` (execução manual) **não é confiável** pra este projeto — erro genérico ou ignora `pinData` mesmo quando o workflow funciona de verdade. Pra testar de verdade: mandar mensagem real via WhatsApp de um número de teste, ou (pra Schedule Trigger) baixar o intervalo pra 1 minuto temporariamente e reverter depois.
- Pra decidir SE algo é usado de verdade (antes de mexer ou de considerar remover), não confiar só no nome: puxar o histórico real de execuções (`GET /rest/executions?filter={"workflowId":"..."}`) E checar se o workflow fala com o Supabase via REST (`httpRequest` com URL do projeto) — um sistema antigo/paralelo pode continuar rodando de verdade e ainda assim não ser a arquitetura atual.

## Reaproveitar antes de criar

Antes de escrever lógica nova, procurar se já existe um padrão pra isso: busca fuzzy por nome (ver `GOTCHAS.md`), geração/confirmação de Pix (`pagamentos-gerar-pix.json` + `pagamentos-webhook-mercadopago.json`), atribuição de time (`atendimento-transferir-humano.json`), trava de estado via etiqueta do Chatwoot (`followup_ativo`, `aguardando_pagamento` — ver como o follow-up usa isso pra não disparar em paralelo).

## Buffer de mensagens (debounce de 8s) no `SDR AGENTE - DINAMICO`

Antes de responder, o SDR agrupa mensagens seguidas do mesmo contato numa janela de 8 segundos, em vez de responder cada mensagem separada (evita a IA "cortar" o cliente no meio de uma sequência rápida de mensagens — ex: "oi" + "tudo bem?" + "queria saber sobre X" mandadas em 3 segundos geravam 3 respostas fragmentadas antes desse patch). Tabela `message_buffer` (`conversation_id` PK, `messages` jsonb, `last_message_at`) guarda o acumulado por conversa; só o `service_role` (n8n) mexe nela.

Fluxo (entre `SALVAR LEAD` e `AI Agent  SDR`): grava a mensagem atual no buffer (append) → espera 8s (node Wait) → reconsulta o buffer → **se `last_message_at` ainda é o mesmo que a gente escreveu**, essa é a última mensagem da janela: junta tudo com `\n`, limpa o buffer, segue pro AI Agent. **Se mudou** (chegou mensagem nova durante a espera), aborta em silêncio — a execução disparada pela mensagem mais nova é quem vai responder por todo o grupo. Mesmo princípio de "comparar timestamp pra saber se ainda sou o mais recente" que a idempotência usa pra message_id (ver acima), aplicado a debounce em vez de dedup.

Se for portar esse padrão pra outro workflow que responde por webhook, os nodes começam com prefixo `BUFFER -` — copiar a cadeia inteira (`BUFFER - BUSCAR ATUAL` → `BUFFER - SALVAR MENSAGEM` → `BUFFER - AGUARDAR 8s` → `BUFFER - CONFIRMAR ULTIMA` → `BUFFER - E O ULTIMO?` → `BUFFER - CONSOLIDAR MENSAGEM` → `BUFFER - LIMPAR`) é mais seguro que reescrever do zero.

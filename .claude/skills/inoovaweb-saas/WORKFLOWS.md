# Mapa dos workflows do n8n

Os 23 workflows deste kit (pasta `n8n/workflows/`), com o que cada um faz e quem chama quem. Todos falam com o Supabase via REST usando `{{ $env.SUPABASE_URL }}` / `{{ $env.SUPABASE_SERVICE_KEY }}` (configurar essas variáveis de ambiente no n8n antes de importar — ver README da raiz do kit).

## Núcleo do agente

- **sdr-agente-dinamico** — o agente principal (LangChain Agent). Webhook que recebe toda mensagem do WhatsApp (via Chatwoot), monta contexto (empresa, prompt, histórico), decide quais tools chamar, gera a resposta. Todas as "tools" abaixo são workflows separados chamados por ele via `toolWorkflow`/`executeWorkflow`.
- **enviar-mensagens-crm** — recebe o texto final da IA e quebra em mensagens curtas e naturais antes de mandar pro Chatwoot (em vez de um bloco de texto único).
- **qualificar-lead-matriz-crm** — tool `qualificar_lead`: registra o nível de interesse/qualificação do lead.

## Catálogo de produtos

- **catalogo-buscar-produto** — tool `buscar_produto`: busca um produto específico por nome (fuzzy matching). Retorna também `midias` (galeria de fotos/vídeos adicionais além da foto de capa, tabela `product_media`).
- **catalogo-enviar-foto** — tool `enviar_foto`: envia a foto de um produto já identificado.
- **catalogo-buscar-e-enviar** — tool `buscar_e_enviar`: busca por palavra-chave livre no catálogo (ou lista tudo) e manda o resultado. Se o produto encontrado tiver galeria (`product_media`) além da foto de capa, manda a capa + todos os itens da galeria em sequência automaticamente (fan-out interno, a IA não precisa chamar nada extra).
- **catalogo-buscar-e-enviar-documento** — tool `buscar_e_enviar_documento`: mesma lógica pra documentos/PDFs cadastrados.

## Agendamento (Google Calendar)

- **calendario-verificar-disponibilidade** — tool `verificar_disponibilidade`: checa se um horário está livre pra um profissional/recurso, considerando configuração de agenda e bloqueios. Também avisa se aquele profissional exige pagamento antes de confirmar (`exige_pagamento`/`valor_sinal`/`tipo_cobranca`).
- **calendario-agendar** — tool `agendar`: cria o evento no Google Calendar e salva em `appointments`. Se o profissional exigir pagamento e ainda não foi confirmado, NÃO cria o evento ainda — gera um Pix (ver seção Pagamentos) e retorna aguardando. Aceita `pagamento_confirmado: true` + `resource_id_direto` pra ser rechamado internamente pelo webhook do Mercado Pago depois que o pagamento é aprovado.
- **calendario-confirmar** — tool `confirmar_agendamento`: marca que o lead confirmou presença.
- **calendario-reagendar** — tool `reagendar`: muda data/hora de um agendamento existente.
- **calendario-link-auth** — webhook `GET /calendario-auth`, chamado direto pelo painel (botão "Conectar Google Calendar"): gera o link de autorização OAuth do Google.
- **calendario-callback** — webhook `GET /calendario-callback`: recebe o `code` do Google, troca por `refresh_token`, salva via edge function `save-calendar-token`.
- **lembrete-verificar** / **lembrete-gerar-e-enviar** — rodam em schedule, verificam agendamentos próximos e mandam lembrete pro cliente.

## Pagamentos (Mercado Pago Pix)

- **pagamentos-gerar-pix** — tool `gerar_pagamento_pix`: resolve o produto por nome, checa estoque, cria linha em `pedidos`, gera cobrança Pix real via API do Mercado Pago (token da PRÓPRIA empresa, configurado no painel), manda QR + código copia-cola.
- **pagamentos-webhook-mercadopago** — webhook que recebe a notificação do Mercado Pago. NUNCA confia só na notificação — sempre reconsulta `GET /v1/payments/{id}` na API do MP antes de considerar pago. Tem duas ramificações: pagamento de produto (`pedidos`) e pagamento de sinal/agendamento (`agendamento_pagamentos`, roteado por `?tipo=agendamento` na query string do `notification_url`). Também roda em schedule (15 em 15 min) mandando lembrete de Pix expirado sem pagar.

## Atendimento e relacionamento

- **atendimento-transferir-humano** — tool `transferir_humano`: atribui a conversa a um TIME do Chatwoot (respeitando horário de atendimento configurável por empresa), escolhe e atribui um AGENTE do time (prefere online, depois ocupado, depois o primeiro do time) e define prioridade alta. **Nota de API do Chatwoot**: `team_id` e `assignee_id` precisam ir em duas chamadas POST `/assignments` separadas — mandados juntos na mesma chamada, o Chatwoot só aplica o `assignee_id` e descarta o `team_id` silenciosamente (sem erro nenhum). Também adiciona a etiqueta `falar_humano`, que já bloqueia a IA de continuar respondendo (ver `sdr-agente-dinamico`) e também para qualquer follow-up automático já agendado pra essa conversa.
- **reagir-mensagem** — tool `reagir_mensagem`: reage com emoji numa mensagem do Chatwoot.
- **limpar-memoria-chat** — webhook chamado pela edge function `clear-chat-memory` (botão "Limpar memória" no painel, por contato): apaga só o histórico daquele telefone+empresa (nunca a tabela inteira).
- **followup-automatico** — sequência de follow-up quando o lead não responde (tentativas configuráveis por empresa). Usa a etiqueta `followup_ativo` como trava pra nunca rodar duas sequências em paralelo pro mesmo contato, e decide via IA (lendo o histórico) se ainda faz sentido insistir antes de gerar a mensagem. Para automaticamente se a conversa tiver `agente_off`, `falar_humano`, `pago` ou `confirmado` (objetivo já alcançado ou humano assumiu) — se um agente quiser que a IA/follow-up volte a agir, basta remover a etiqueta manualmente no Chatwoot.
- **reengajamento-lead-frio** — roda 1x/dia, reengaja conversas frias/nunca qualificadas.

## Infra

- **supabase-keep-alive** — roda 2x/semana (`0 9 * * 1,4`), faz um GET simples na API do Supabase só pra esse projeto não pausar por inatividade no plano gratuito (`pg_cron` sozinho NÃO resolve isso — o critério de pausa do Supabase é requisição na API Gateway, não job interno do banco).

## Etiquetas usadas como "estado" da conversa

`agendado`, `confirmado`, `aguardando_confirmacao`, `reagendado`, `lead_quente`, `lead_frio`, `desqualificado`, `agente_off`, `falar_humano`, `pago`, `reengajado_frio`, `aguardando_nps`, `followup_ativo`, `aguardando_pagamento` — todas precisam existir na conta do Chatwoot de cada empresa (criadas automaticamente na hora de provisionar uma empresa nova, ver edge function `admin-create-company` no repo do painel).

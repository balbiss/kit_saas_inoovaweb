# Manual de instalação — siga passo a passo

Este arquivo é escrito PRA VOCÊ (Claude Code), não pro humano ler. É um roteiro sequencial: execute cada etapa marcada como **EXECUTAR** sozinho; quando chegar numa etapa marcada **🛑 PARE E PERGUNTE**, pare exatamente ali, peça ao usuário exatamente a informação/ação listada, e só continue depois de receber a resposta — nunca invente, adivinhe ou pule uma etapa dessas.

Use a ferramenta de todo-list (TodoWrite ou equivalente) pra marcar cada etapa numerada abaixo como pendente/em andamento/concluída conforme avança — isso ajuda o usuário a acompanhar onde você está caso a instalação seja interrompida e retomada depois.

Antes de começar, leia `SKILL.md` (arquitetura geral), `WORKFLOWS.md` (o que cada workflow do n8n faz) e `GOTCHAS.md` (armadilhas técnicas) — este manual assume que você já sabe o que está em todos os três.

---

## Etapa 0 — Pré-requisitos

**🛑 PARE E PERGUNTE**: confirme com o usuário, antes de qualquer coisa:
1. Ele já tem uma VPS com Docker instalado e Swarm inicializado (`docker swarm init`)? Se não, ele precisa fazer isso primeiro (você pode ajudar a rodar os comandos se tiver acesso via terminal à VPS).
2. Ele tem um proxy reverso com TLS automático já configurado (Traefik é o que o compose deste kit assume)? Se usar outro, os `labels` do `chatwoot/docker-compose.yml` precisam ser adaptados.
3. Quais domínios/subdomínios ele vai usar? Você vai precisar de pelo menos 3: um pro Chatwoot, um pro n8n, um pro painel. Confirme que o DNS de cada um já aponta pra IP da VPS (ou peça pra ele configurar antes de continuar).
4. Ele tem (ou vai criar agora) conta na OpenAI, no Supabase, e um projeto no Google Cloud Console com a API do Google Calendar habilitada?

Não prossiga pra Etapa 1 sem essas respostas.

## Etapa 1 — Clonar os repositórios

**EXECUTAR**: os 3 repositórios são públicos, não precisa de autenticação.
```bash
git clone https://github.com/balbiss/kit_saas_inoovaweb.git
git clone https://github.com/balbiss/saas-chatwoot.git
git clone https://github.com/balbiss/chatwoot_innovaweb.git
```

## Etapa 2 — Supabase

1. **🛑 PARE E PERGUNTE**: peça pro usuário criar um projeto novo em supabase.com/dashboard (você não consegue criar conta em nome dele) e te passar: a URL do projeto, o project ref, a anon/publishable key, e um Personal Access Token (Account → Access Tokens).
2. **EXECUTAR**: com o token em mãos, siga `kit_saas_inoovaweb/supabase/README.md` — aplique as migrations (`supabase db push` ou via Management API) e faça deploy de todas as Edge Functions de `saas-chatwoot/supabase/functions/`.
3. **EXECUTAR**: ative o workflow `supabase-keep-alive` mais tarde (depois que o n8n estiver no ar, Etapa 4) — anote isso e não esqueça.
4. Os secrets `N8N_CLEAR_MEMORY_URL`/`N8N_CLEAR_MEMORY_SECRET` dependem do domínio do n8n, que só existe depois da Etapa 4 — pode deixar um valor provisório agora e voltar aqui depois de configurar o n8n.

## Nota sobre acesso à VPS: Docker CLI local vs. só Portainer

Duas situações bem diferentes, adapte os comandos EXECUTAR abaixo conforme o caso:

- **Você tem SSH/terminal na VPS**: use `docker build`, `docker exec`, `docker cp`, `docker stack deploy` normalmente como os exemplos abaixo mostram.
- **Você só tem acesso ao painel Portainer** (caso mais comum pra aluno numa VPS gerenciada, sem SSH): tudo dá pra fazer via API do Portainer, que é um proxy pra API do Docker Engine. Ver `GOTCHAS.md` ("Instalando com Portainer/Swarm SEM Docker CLI local") pros equivalentes exatos: criar/atualizar stack é `POST/PUT /api/stacks/...`, `docker cp` vira `PUT /api/endpoints/{id}/docker/containers/{cid}/archive?path=...` (manda um `.tar`), `docker exec` vira `POST .../exec` + `POST .../exec/{execId}/start`. Login em `POST /api/auth` retorna um JWT que vai no header `Authorization: Bearer` de toda chamada seguinte.

## Etapa 3 — Chatwoot + Baileys

1. **EXECUTAR**: builde a imagem a partir de `chatwoot_innovaweb` (`docker build -t <algo>/chatwoot-inoovaweb:latest .`) — ou, se o repo já tem `.github/workflows/docker.yml` fazendo isso sozinho a cada push (ver `chatwoot/README.md`), só reaproveitar a imagem já publicada em `ghcr.io/.../chatwoot_innovaweb_v2:latest`, sem rebuildar (essa imagem NÃO leva segredo nenhum do dono embutido — pode ser reaproveitada por qualquer instalação, só o `.env`/environment muda).
2. **🛑 PARE E PERGUNTE**: peça a chave da OpenAI (se ainda não tiver) e as informações de SMTP (endereço, usuário, senha) — se ele não usa SMTP ainda, pergunte se quer pular esse pedaço por enquanto (o Chatwoot funciona sem, só não manda e-mail de convite/reset de senha).
3. **EXECUTAR**: gere as senhas/chaves novas (`openssl rand ...`, ver comentários em `chatwoot/.env.example`) — NUNCA reaproveitar de outra instalação —, monte o compose (rede externa `inoovawebpro` ou o nome que a VPS já usa, labels do Traefik com o `certresolver` certo pra essa VPS), suba a stack.
4. **🛑 PARE E PERGUNTE**: peça pro usuário confirmar no navegador que `https://<domínio do Chatwoot>` está respondendo antes de continuar.
5. **EXECUTAR**: crie o primeiro usuário administrador via `rails runner` dentro do container `chatwoot_web` (via `docker exec` ou o equivalente Portainer da nota acima):
   ```
   bundle exec rails runner "puts AccountBuilder.new(account_name: '<nome>', email: '<email>', user_full_name: '<nome>', user_password: '<senha>', confirmed: true, super_admin: true).perform.inspect"
   ```
   **A chave certa é `confirmed`, não `confirm_email`** (`ArgumentError: Got unknown keys` se errar isso — ver `GOTCHAS.md`). Depois, gere os dois tokens que as próximas etapas precisam, no mesmo `rails runner`:
   - Token pessoal (vai virar `CHATWOOT_AGENCY_TOKEN` na Etapa 4 e `CHATWOOT_API_TOKEN` no secret do Supabase): `User.find(1).access_token.token`
   - Token da Platform API (vai virar `CHATWOOT_PLATFORM_TOKEN` no secret do Supabase, usado por `admin-create-company` pra criar contas isoladas): `PlatformApp.create!(name: '<qualquer nome>').access_token.token`
6. **EXECUTAR**: volte na Etapa 2 e preencha `CHATWOOT_BASE_URL`, `CHATWOOT_API_TOKEN`, `CHATWOOT_PLATFORM_TOKEN`, `CHATWOOT_AGENCY_USER_ID=1` nos secrets do Supabase agora que já existem.

## Etapa 4 — n8n

1. **🛑 PARE E PERGUNTE**: confirme o domínio do n8n e peça o `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET` (projeto Google Cloud Console dele, com a API do Calendar habilitada e tela de consentimento OAuth configurada — isso só ele consegue criar; se ele quiser pular por enquanto, deixe em branco e avise que agendamento via Google Calendar não vai funcionar até configurar depois). A URL de redirect a cadastrar no Google Console é `https://<domínio-do-n8n>/webhook/calendario-callback`.
2. **EXECUTAR**: suba um n8n limpo (imagem oficial `n8nio/n8n`, com Postgres próprio dedicado — não precisa ser o mesmo banco de nada), configure as variáveis de ambiente do container: `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`, `CHATWOOT_URL`, `CHATWOOT_AGENCY_TOKEN` (token da Etapa 3), `N8N_URL`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, e **`N8N_BLOCK_ENV_ACCESS_IN_NODE=false`** (sem isso os workflows não conseguem ler `$env.*`, erro `ExpressionError: access to env vars denied`).
3. **EXECUTAR**: importe os 23 workflows preservando os IDs. Se tiver Docker CLI: `kit_saas_inoovaweb/n8n/import.sh <container>`. Sem CLI (via Portainer): suba a pasta `n8n/workflows/` como um `.tar` pro `/tmp` do container (ver nota de Portainer acima) e rode dentro do container: `n8n import:workflow --separate --input=/tmp/workflows`.
4. **EXECUTAR** (via REST API do n8n, não precisa de humano): crie a credencial OpenAI (`POST /rest/credentials`, tipo `openAiApi`, usando a chave já passada na Etapa 3) e a credencial `postgres` apontando pro banco do Chatwoot (mesmo host/senha/db do compose da Etapa 3 — usada pelo node "Postgres Chat Memory"). Depois, em cada workflow que referenciava a credencial ANTIGA (a que veio no export, procure `"openAiApi"`/`"postgres"` nos JSONs pra saber quais são — normalmente `sdr-agente-dinamico`, `reengajamento-lead-frio`, `enviar-mensagens-crm`, `followup-automatico`, `lembrete-gerar-e-enviar`, `atendimento-transferir-humano` pro OpenAI; `sdr-agente-dinamico`, `catalogo-buscar-e-enviar`, `catalogo-buscar-produto`, `limpar-memoria-chat`, `calendario-callback` pro postgres), fazer `GET /rest/workflows/{id}` → substituir o bloco de credencial nos nodes → `PATCH /rest/workflows/{id}` com `{name, nodes, connections, settings}`.
5. **EXECUTAR — publicar, não só "ativar"** (⚠️ o passo que mais trava instalação nova): `PATCH .../workflows/{id}` com `{"active":true}` sozinho NÃO ativa de verdade nessa versão do n8n (retorna 200 mas fica `active:false`/`triggerCount:0`, webhook nunca responde). O jeito certo: pegar o `versionId` atual (`GET /rest/workflows/{id}`) e chamar `POST /rest/workflows/{id}/activate` com `{"versionId": "<esse valor>"}`. Como os 23 workflows chamam uns aos outros (`executeWorkflow`), publicar pode falhar pedindo pra publicar as dependências primeiro — publicar TODOS em rounds (tentar os 23, guardar quem falhou, tentar de novo só os que falharam, repetir até a lista de pendentes esvaziar — 2-3 rounds resolve). Confirmar no final: cada workflow com `active:true` e `triggerCount >= 1`, e testar a URL do webhook do SDR direto (`curl -X POST https://<n8n>/webhook/sdr_agente_dinamico_crm_visita_ia` deve dar 200, não 404).
6. **EXECUTAR**: volte na Etapa 2 e finalize os secrets `N8N_SDR_WEBHOOK_URL` (path do node webhook do `SDR AGENTE - DINAMICO`, normalmente `sdr_agente_dinamico_crm_visita_ia`), `N8N_CLEAR_MEMORY_URL`/`N8N_CLEAR_MEMORY_SECRET` (path e secret do workflow `limpar-memoria-chat` — o secret está hardcoded no Code node "VALIDAR" desse workflow, não é env var) agora que o domínio do n8n existe.
7. **🛑 PARE E PERGUNTE (opcional, não bloqueante)**: se quiser conectar esse n8n como servidor MCP (recomendado — mais confiável que REST cru pras próximas edições), peça pro usuário entrar em `Settings → Instance-level MCP` na UI, ligar o toggle "Enabled", ir na aba "Workflows", selecionar tudo e clicar "Enable workflows" (clicando em cada workflow no modal de busca, repetindo por página). Ver `GOTCHAS.md` ("MCP nativo do n8n") — não tem endpoint REST conhecido pra automatizar esse passo específico.

## Etapa 5 — Painel

1. **🛑 PARE E PERGUNTE**: pergunte o nome da marca, cor principal, e peça o arquivo do logo (ou confirme que pode seguir sem, usando um placeholder por enquanto).
2. **EXECUTAR**: no repo `saas-chatwoot` (fork do cliente, ver Etapa 1), troque a marca "InoovaWeb" nos arquivos listados em `kit_saas_inoovaweb/painel/README.md`.
3. **🛑 PARE E PERGUNTE**: se for build automático via GitHub Actions (recomendado), peça pro usuário criar as 3 **Repository Variables** (`Settings → Secrets and variables → Actions → aba "Variables"`, ⚠️ NÃO a aba "Secrets" — erro comum, o build "passa com sucesso" mesmo errado e só quebra depois em runtime): `VITE_SUPABASE_URL`, `VITE_SUPABASE_PROJECT_ID`, `VITE_SUPABASE_PUBLISHABLE_KEY`, com os valores da Etapa 2, e habilitar o Actions no repo (desativado por padrão em fork novo). Se as Variables já existiam quando o primeiro push foi feito, tudo certo; se foram criadas DEPOIS, disparar um rebuild com `git commit --allow-empty -m "rebuild" && git push` e conferir o digest novo com `docker buildx imagetools inspect`.
4. **🛑 PARE E PERGUNTE**: confirme o domínio do painel.
5. **EXECUTAR — deploy da stack com as env vars de RUNTIME também** (⚠️ segundo passo que mais trava, além do publish do n8n): não basta a imagem ter sido buildada com os 3 `VITE_*` certos. O container em runtime (é TanStack Start com SSR, não é um site estático) precisa, na `environment:` da stack, de **5 variáveis**, os MESMOS valores dos build args: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (nova, service_role da Etapa 2), e de novo `VITE_SUPABASE_URL`/`VITE_SUPABASE_PROJECT_ID`/`VITE_SUPABASE_PUBLISHABLE_KEY` (sim, repetidas — o bundle SSR lê `process.env.VITE_*` em runtime, não fica gravado estático como no bundle do navegador). Sem isso: painel sobe, responde HTTP mas com erro 500 `supabaseUrl is required`. Ver `painel/README.md` ("Runtime") e `GOTCHAS.md` pro detalhe técnico completo.

## Etapa 6 — Primeira empresa de teste

1. **EXECUTAR**: pelo fluxo de super-admin do painel, crie a primeira empresa (isso já provisiona a conta isolada no Chatwoot + as etiquetas padrão automaticamente) — **use uma conta separada do login do super-admin pra isso**, não confunda a conta Chatwoot "1" (a da agência/dono do kit, criada na Etapa 3) com a conta isolada de uma empresa real; se o super-admin logar no painel como se fosse "dono de empresa" sem passar pelo fluxo de provisionamento, cria uma linha solta em `companies` sem conta Chatwoot vinculada.
2. **🛑 PARE E PERGUNTE**: peça pro usuário escanear o QR Code de conexão do WhatsApp com o celular da empresa (ação física, só ele faz) em Chatwoot → Configurações → Caixas de entrada → a inbox criada.
3. **🛑 PARE E PERGUNTE**: peça pro usuário mandar uma mensagem de teste de verdade pelo WhatsApp conectado, e confirmar que a IA respondeu corretamente — essa é a validação final de que a cadeia inteira (WhatsApp → Chatwoot → n8n → Supabase → de volta) está funcionando. **Se a mensagem chegar no Chatwoot mas a IA não responder**, o suspeito nº1 é o workflow não estar de verdade `active`/publicado (ver Etapa 4.5) — conferir `GET /rest/executions?filter={"workflowId":"..."}` no `SDR AGENTE - DINAMICO`: se não tem execução nenhuma, o webhook não disparou (problema de publish); se tem execução com erro, é outra coisa (credencial, Supabase, etc). Também vale checar se o WhatsApp não colocou uma restrição temporária de "novas conversas" nesse número (comum em número recém-conectado via Baileys) — aparece como aviso vermelho no topo da conversa no Chatwoot.

## Conclusão

Quando a Etapa 6 for confirmada, resuma pro usuário o que foi instalado (URLs de cada parte, o que ainda está pendente de configurar por empresa — ex: token do Mercado Pago de cada cliente final dele, que é configurado no painel por cada empresa, não na instalação).

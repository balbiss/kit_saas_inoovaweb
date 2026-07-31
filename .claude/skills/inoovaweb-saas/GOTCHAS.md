# Armadilhas técnicas do n8n descobertas construindo este sistema

Leia antes de editar qualquer workflow deste kit. Todas foram descobertas ao vivo, em produção, com bugs reais.

## Item-splitting de array em resposta de `httpRequest`

Quando um node `httpRequest` recebe um array JSON com N elementos (comum em respostas do PostgREST/Supabase), o n8n divide automaticamente em N ITENS separados — não um item só contendo o array inteiro. Um Code node seguinte que faz `$('Node').item.json` (singular) só vê o item PAREADO com o caminho de execução atual — para uma empresa com 2+ registros (recursos, documentos, produtos), isso trunca silenciosamente pra só 1.

**Como aplicar**: usar `$('NomeDoNode').all().map(i => i.json)` pra pegar TODOS os itens, nunca `.item.json` quando o node anterior pode retornar mais de 1 registro.

**Caso N=1 é o mais traiçoeiro** (bug real no buffer de mensagens, ver `SKILL.md`): pra uma resposta com EXATAMENTE 1 elemento, o n8n desembrulha em 1 item cujo `.json` já É o objeto diretamente — `$('Node').item.json[0]` (indexando de novo, "pra garantir") é o erro oposto e igualmente silencioso: `.json[0]` num objeto retorna `undefined`, cai em qualquer fallback (`|| {}`, `|| []`) sem erro nenhum, e o bug fica invisível porque tudo continua rodando "com sucesso" — só o RESULTADO fica sempre vazio/errado. Regra geral: depois de um `httpRequest` que bate numa tabela via `select=`, `.item.json` já é o registro (se 1) ou o node não teve item nenhum (se 0, ver `alwaysOutputData` abaixo) — nunca indexar com `[0]` a não ser que esteja explicitamente iterando `.all()`.

## Code node em `runOnceForEachItem` não pode fazer fan-out

Se o código faz `return arrayDeVariosItens` tentando expandir 1 item de entrada em N de saída, o n8n quebra com erro tipo "A 'json' property isn't an object", mesmo com o código sintaticamente correto.

**Como aplicar**: quando o Code node precisa OLHAR PARA TODOS os itens de uma vez (comparar, escolher o melhor, agregar), usar `mode: "runOnceForAllItems"` e `$input.all()` — nunca `runOnceForEachItem` nesse caso.

## `valor || padrao` trata `0` como falsy

`const dias = config.dias_inativo || 3` vira `3` mesmo quando `dias_inativo` foi propositalmente configurado como `0`.

**Como aplicar**: usar `??` (nullish coalescing) sempre que `0` for um valor válido possível: `config.dias_inativo ?? 3`.

## `typeVersion` errado em nodes LangChain causa erros crípticos

Nodes `@n8n/n8n-nodes-langchain.agent` / `.lmChatOpenAi` com `typeVersion` "razoável" mas errado causam erros internos tipo `"model.includes is not a function"`, sem relação óbvia com a causa real.

**Como aplicar**: ao criar QUALQUER node LangChain novo, copiar o `typeVersion` exato de um node do MESMO tipo que já roda em produção neste kit (`agent` = `3`, `lmChatOpenAi` = `1.3`), nunca inventar/assumir o número.

## Busca fuzzy por nome — sempre sobreposição de palavras, nunca `ilike` de frase inteira

Técnica usada em todo lugar que a IA precisa resolver "qual X o cliente quer" a partir de linguagem natural (profissional/recurso, produto, documento):

1. Buscar TODOS os registros da empresa (sem filtro de banco por nome).
2. Normalizar o termo de busca E o nome de cada registro: `.normalize('NFD').replace(/[̀-ͯ]/g,'').toLowerCase()`, remover tudo que não for `a-z0-9`, dividir em palavras de 2+ caracteres.
3. Contar quantas palavras batem (overlap) entre busca e cada registro.
4. Pegar o de maior overlap. Se o maior overlap for 0, ou houver empate entre 2+ registros, NÃO adivinhar — pedir pra IA perguntar ao cliente qual ele quer, listando as opções.

`ilike '*frase inteira*'` falha toda vez que a ordem das palavras é diferente da cadastrada (ex: "vídeo da aula de teste" não bate com o registro "AULA DE TESTE"; "Dra Vera" não bate com "Dª Vera - Dentista").

## `/rest/workflows/{id}/run` não é confiável pra testar

Retorna erro genérico (`Cannot read properties of undefined reading 'nodeName'`) ou ignora `pinData` silenciosamente, mesmo quando o workflow funciona perfeitamente em execução real.

**Como aplicar**: pra testar Schedule Trigger, mudar o intervalo pra 1 minuto temporariamente (+ ampliar filtro de data se precisar), esperar o ciclo real disparar, reverter depois. Pra testar tool/workflow chamado pela IA, mandar mensagem real via WhatsApp de teste.

## Sempre reciclar depois de PATCH num workflow ativo

`deactivate` → `activate` (com o `versionId` retornado pelo deactivate) depois de QUALQUER `PATCH` num workflow ativo. Sem isso, o n8n continua rodando o código ANTIGO em cache mesmo a API confirmando `"active": true` e o PATCH retornando sucesso.

## Idempotência em webhook de pagamento (Mercado Pago)

O Mercado Pago manda a notificação de pagamento MAIS DE UMA VEZ (comportamento normal). Nunca confiar só na notificação — sempre reconsultar `GET /v1/payments/{id}` na API do MP com o token da própria empresa antes de considerar pago. E o UPDATE que marca como pago precisa ser um PATCH atômico com o filtro de status embutido na própria URL (`?id=eq.X&status=eq.pendente`) — se outra execução concorrente já processou, o PATCH atualiza 0 linhas, o node `httpRequest` emite 0 itens de saída, e a cadeia de entrega simplesmente não roda de novo (comportamento padrão do n8n pra resposta vazia, sem precisar de node IF extra). Sem isso, notificações duplicadas entregam o produto/confirmam o agendamento duas vezes.

## Decodificar execução do n8n via script de dedup tem falso-positivo conhecido

Se algum dia for necessário decodificar o JSON de uma execução do n8n via um script que resolve índices de array deduplicado, saiba que campos legítimos só-de-dígitos (ex: `chatwoot_account_id: "1"`) podem ficar corrompidos no dump (viram objetos aleatórios do array de dedup), mesmo os dados reais em produção estando certos. Ao ver um campo obviamente errado no dump decodificado, suspeitar do script antes de assumir bug real — conferir direto via chamada de API quando a dúvida for sobre um valor simples.

## Chatwoot: atribuição de time + agente precisa de duas chamadas separadas

`POST /api/v1/accounts/{id}/conversations/{id}/assignments` aceita `team_id` e `assignee_id`, mas mandados **juntos na mesma chamada**, só o `assignee_id` é aplicado — o `team_id` fica silenciosamente `nil`, mesmo com HTTP 200 e a resposta parecendo de sucesso. Sempre fazer duas chamadas POST separadas (uma só com `team_id`, a próxima só com `assignee_id`).

Também: `PATCH /conversations/{id}` (o endpoint genérico de update) aceita `team_id` no corpo e devolve 200, mas o Rails ignora silenciosamente esse parâmetro por não estar nos strong params dessa action — nunca funciona pra atribuir time, só o endpoint `/assignments` funciona.

Se a dúvida for "isso realmente gravou?" e a resposta da API não expuser o campo de volta, confirmar via Rails console (`bundle exec rails runner "puts Conversation.find(id).team_id"`, rodado dentro do container via `docker exec`/Portainer) em vez de confiar só no HTTP 200.

## Chatwoot: agente precisa ser membro do TIME e da CAIXA DE ENTRADA (são coisas separadas)

Um agente pode estar corretamente atribuído a uma conversa (`assignee_id` certo no banco) e mesmo assim não aparecer como "assignable" pra aquela caixa de entrada, ou não conseguir interagir direito com a conversa, se ele não for membro da **inbox** também. São duas permissões independentes no Chatwoot — adicionar num time (`POST/PATCH /team_members`) não adiciona na caixa de entrada. Pra adicionar: `POST /api/v1/accounts/{id}/inbox_members` com `{inbox_id, user_ids: [...]}`.

**Correção (confirmado lendo o código-fonte do fork em `app/controllers/api/v1/accounts/inbox_members_controller.rb` + `app/models/inbox.rb#add_members`)**: esse endpoint é **aditivo, não substitui a lista** — o controller faz `@inbox.add_members(user_ids - current_agents_ids)`, ou seja, só ADICIONA quem ainda não está lá; nunca remove quem já era membro, mesmo que a lista enviada não inclua esses IDs. Não existe rota de `update`/replace para `inbox_members`, só `create` (aditivo) e um `destroy` de coleção pra remover explicitamente. Uma nota anterior deste arquivo dizia o contrário (que precisava reenviar a lista inteira) — estava errada.

## Campo de expressão do n8n sem `=` na frente vira texto literal pra sempre

Quando um campo de node (`value` de `headerParameters`/assignment, `token`, etc.) contém SÓ uma expressão (`{{ $env.ALGO }}`), falta o `=` no começo (`={{ $env.ALGO }}`) faz o n8n tratar o campo inteiro como STRING LITERAL — nunca avalia a expressão, e em runtime o valor é literalmente o texto `{{ $env.ALGO }}`. Isso é diferente de um campo que MISTURA texto com expressão (`"Olá {{ $json.nome }}"`), que sempre precisa do `=` também, mas o sintoma ali é mais óbvio. Esse bug foi encontrado em 16 dos 23 workflows deste kit (headers de `apikey`/`Authorization`, campo `token` do Mercado Pago, `CHATWOOT_URL`) — introduzido por um script de exportação/scrub que fazia substituição de string ingênua (`texto.split(valorAntigo).join('{{ $env.VAR }}')`) sem checar se o campo original já começava com `=`.

**Como aplicar**: depois de QUALQUER substituição de string em massa num JSON de workflow (scrub de segredo, rename de variável), rodar `grep -oP '"(value|token|url|jsonBody)": "\{\{ \$env\.' *.json` nos arquivos afetados — se aparecer alguma linha, faltou o `=`. Testar de verdade mandando uma mensagem real depois (erro típico: `Invalid URL: {{ $env.X }}/...` ou uma chamada de API 401/403 silenciosa que ninguém nota porque o resto do fluxo não quebra).

## Webhook do Chatwoot pode reentregar mensagem antiga — sempre ter guarda de idempotência por `message_id`

Webhooks são "at-least-once", não "exactly-once": se a entrega falhar (ex: o n8n estava com o workflow desativado pra edição, ou reiniciando), o Chatwoot reenfileira e reentrega depois — inclusive minutos/horas depois, misturado com mensagens novas. Sem uma trava de "já processei esse `message_id`", cada reentrega dispara uma resposta NOVA da IA pra uma mensagem ANTIGA, e a pessoa vê o agente "mandando mensagem várias vezes" do nada, sem ter mandado nada de novo.

**Como aplicar**: logo depois do node `INFORMAÇÕES` (que já extrai `MESSAGE_ID`/`ID_CONTA`) e antes de `PREOCESSAR MENSAGEM`, inserir um `httpRequest` POST pra uma tabela `processed_messages(message_id bigint primary key, account_id int, processed_at timestamptz default now())` no Supabase, com headers `Prefer: resolution=ignore-duplicates,return=representation`. Se o `message_id` já existia, o Postgres ignora o insert e o PostgREST devolve `[]` — o n8n automaticamente para de propagar aquele item (0 itens de saída = ramo do workflow simplesmente para, sem precisar de node IF extra, mesmo padrão já usado no webhook do Mercado Pago acima). Lembrar de ajustar `PREOCESSAR MENSAGEM` pra referenciar `$('INFORMAÇÕES').item.json...` em vez de `$json...`, já que o node imediatamente anterior deixa de ser `INFORMAÇÕES`.

## Chatwoot: VAPID (push notification) é guardado no banco, não lido de env var toda vez

`VapidService` (`/app/lib/vapid_service.rb`) só lê a variável de ambiente `VAPID_PUBLIC_KEY`/`VAPID_PRIVATE_KEY` na primeira vez que precisa gerar o par de chaves — depois disso salva num registro `InstallationConfig` (`name: "VAPID_KEYS"`) e usa esse pra sempre, ignorando a env var completamente em qualquer deploy futuro. Se precisar trocar a chave VAPID depois da instalação inicial, mudar a env var não faz nada — precisa atualizar/apagar esse registro direto no banco.

Além disso, aceitar a permissão de notificação no navegador **não é suficiente** pro Chatwoot mandar push de verdade — a conta do usuário também precisa ter a flag do evento específico marcada em `notification_settings` (`push_flags`, um bitmask via FlagShihTzu que **vem zerado por padrão** pra qualquer usuário novo). As duas coisas são independentes: permissão do navegador (`Notification.permission`) e preferência da conta (`selected_push_flags`).

## Instalando com Coolify em vez de Portainer/Swarm

O `INSTALACAO.md` foi escrito pensando em Portainer/Swarm. Rodando numa VPS com Coolify, a ordem e a lógica geral continuam as mesmas, mas a mecânica de deploy muda — armadilhas encontradas na primeira instalação real com Coolify:

- **"Services" (compose multi-container) não entram sozinhos na rede compartilhada `coolify`, "Applications" (uma imagem só) entram.** O stack do Chatwoot+Baileys (Postgres+Redis+web+sidekiq+Baileys) precisa ser um "Service" no Coolify (`POST /api/v1/services` com `docker_compose_raw`), mas o Coolify não conecta esse tipo de recurso à rede do Traefik de forma confiável — o domínio custom fica dando 503 "no available server" mesmo com o container saudável e respondendo internamente. **Correção que funcionou**: declarar os labels do Traefik direto no `docker_compose_raw` do serviço `chatwoot_web` (`traefik.enable=true`, router com `Host()`, `tls.certresolver=letsencrypt` — esse é o nome do resolver do próprio Coolify, não `letsencryptresolver` como no Swarm de outros produtos do usuário — e `traefik.docker.network=coolify`), em vez de depender das variáveis mágicas `SERVICE_FQDN_*`/`SERVICE_URL_*` do Coolify (que resetam pro domínio sslip.io toda vez que o `docker_compose_raw` é reenviado, mesmo marcando `is_literal: true` via `PATCH .../envs`). Depois disso, um ciclo completo de `/stop` (esperar TODOS os containers ficarem `Exited`) seguido de `/start` — não simplesmente `/restart` — foi o que finalmente fez o Coolify reconectar o container nas duas redes (a do projeto E a `coolify`) automaticamente.
- **n8n e painel devem ser "Applications"** (`POST /api/v1/applications/dockerimage`), não "Services" — essas entram na rede `coolify` sem problema nenhum e o roteamento de domínio (`PATCH .../applications/{uuid}` com `{"domains": "https://..."}`) funciona de primeira.
- **n8n mais novo bloqueia `{{ $env.* }}` por padrão** (`ExpressionError: access to env vars denied`) — setar `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` na Application do n8n.
- **Volume do n8n com permissão errada**: `POST .../applications/{uuid}/storages` cria o diretório do bind-mount como `root`, mas a imagem oficial do n8n roda como uid 1000 — sem `chown -R 1000:1000 <caminho>` via SSH antes de subir, o n8n entra em crash-loop (`EACCES ... /home/node/.n8n/config`).
- **n8n e Chatwoot ficam em redes Docker isoladas por padrão** (cada "Service"/"Application" do Coolify tem sua própria rede de projeto) — o node "Postgres Chat Memory" do workflow principal não alcança o `chatwoot_db` até rodar `docker network connect <rede-do-projeto-chatwoot> <container-do-n8n>` via SSH.
- **A imagem `ghcr.io/balbiss/saas-chatwoot:latest` tem o Supabase do DONO do kit embutido no build** (`VITE_SUPABASE_URL`/`VITE_SUPABASE_PUBLISHABLE_KEY` são lidas em build-time pelo Vite, e o `docker.yml` desse repo específico usa as GitHub Actions Variables do repo do dono). O design já correto do kit (ver `painel/README.md`) é o CLIENTE **forkar** `saas-chatwoot`, configurar as 3 Variables no PRÓPRIO fork (`Settings → Secrets and variables → Actions → Variables`) e deixar o `docker.yml` DELE buildar `ghcr.io/<usuario-do-cliente>/saas-chatwoot:latest` sozinho a cada push — nesse fluxo o bug não existe. **Mas se for uma instalação "chave na mão" feita pelo próprio operador do kit** (o cliente não forkou nada, só recebeu acesso), apontar o Coolify pra `ghcr.io/balbiss/saas-chatwoot:latest` direto reproduz exatamente esse bug: painel loga contra o Supabase ERRADO (do dono, não do cliente) — sintoma: "Invalid login credentials" mesmo com email confirmado e senha certa. Nesse caso, não tem solução só de configuração no Coolify (env var em runtime não adianta, o valor já foi cravado no bundle JS no build) — a saída é buildar manualmente uma imagem com os build-args do cliente e publicar sob uma TAG PRÓPRIA no mesmo repo do dono (`docker build --build-arg VITE_SUPABASE_URL=... --build-arg VITE_SUPABASE_PUBLISHABLE_KEY=... -t ghcr.io/balbiss/saas-chatwoot:<tag-do-cliente> . && docker push ...`), e apontar a Application do Coolify pra essa tag em vez de `:latest`.

## Instalando com Portainer/Swarm SEM Docker CLI local (sem SSH, tudo via API)

Primeira instalação "chave na mão" real via Portainer puro (VPS de terceiro, acesso só ao painel Portainer, sem SSH nem Docker CLI local) — 2026-07-31. Diferente da seção "Coolify" acima; aqui a API é a do Portainer (proxy pra API do Docker Engine).

- **Criar stack**: `POST /api/stacks/create/swarm/string?endpointId=1` com body `{Name, StackFileContent, SwarmID, Env: []}` — pegar o `SwarmID` de `GET /api/endpoints/{id}` (campo `Snapshots[0].DockerSnapshotRaw...` não, vem em `Snapshots` só resumido; o jeito confiável é olhar o `SwarmId` de qualquer stack já existente via `GET /api/stacks`). Atualizar stack existente: `PUT /api/stacks/{stackId}?endpointId=1` com `{StackFileContent, Env: [], Prune: false}` (não precisa do SwarmID de novo).
- **`docker cp` equivalente** (pra importar os workflows do n8n sem SSH): a API do Docker Engine tem `PUT /containers/{id}/archive?path=<destino>`, que aceita um TAR (não precisa gzip) no body e extrai no container — Portainer expõe isso raw em `PUT /api/endpoints/{id}/docker/containers/{containerId}/archive?path=/tmp`. `tar cf arquivo.tar pasta/` local, manda o binário como body com `Content-Type: application/x-tar`.
- **`docker exec` equivalente**: `POST /api/endpoints/{id}/docker/containers/{containerId}/exec` com `{AttachStdout:true, AttachStderr:true, Cmd:[...]}` retorna um `Id`; depois `POST /api/endpoints/{id}/docker/exec/{execId}/start` com `{Detach:false, Tty:false}` retorna o output (vem com alguns bytes de framing binário no início de cada linha — ignorar, dá pra ler o texto normalmente). Usado pra rodar `n8n import:workflow` dentro do container do n8n e o `rails runner` dentro do container do Chatwoot.
- **Criar o primeiro admin do Chatwoot via `rails runner`** (sem UI, sem SMTP): `AccountBuilder.new(account_name: "...", email: "...", user_full_name: "...", user_password: "...", confirmed: true, super_admin: true).perform`. **A chave certa é `confirmed`, não `confirm_email`** — passar `confirm_email` derruba com `ArgumentError: Got unknown keys`. Gerar o token de acesso pessoal depois com `User.find(1).access_token.token`, e o token da Platform API com `PlatformApp.create!(name: "...").access_token.token`.

## n8n exige "publicar" workflow, não só "ativar" — ativação simples via PATCH não faz nada de verdade

Em versões recentes do n8n (confirmado na 2.32.6), existe um sistema de versionamento/publicação por trás da ativação. `PATCH /rest/workflows/{id}` com `{"active": true}` **retorna 200 sem erro, mas não ativa de verdade** — o campo `active` continua `false` numa consulta seguinte, e `triggerCount` fica `0` (nenhum trigger registrado, webhook não responde, dá 404 na URL do webhook).

**Sintoma**: workflow "ativado com sucesso" segundo a API, mensagem real chega no Chatwoot, mas a IA nunca responde — porque o webhook nunca foi registrado de verdade.

**Como ativar de verdade**: usar o endpoint de publicação, que exige o `versionId` atual do workflow:
```
GET /rest/workflows/{id}                        -> pegar o campo "versionId"
POST /rest/workflows/{id}/activate               body: {"versionId": "<versionId>"}
```
Se o workflow chama sub-workflows (`executeWorkflow`/`toolWorkflow`, como o `SDR AGENTE - DINAMICO` faz com `Enviar Mensagens - CRM` e `FOLLOW-UP AUTOMATICO`), a publicação **falha com 400** se o sub-workflow referenciado ainda não estiver publicado: `"Cannot publish workflow: Node \"X\" references workflow Y which is not published"`. Como os 23 workflows deste kit têm dependências cruzadas, publicar numa ordem fixa não funciona sempre — a solução robusta é publicar TODOS em rounds, removendo da lista de pendentes quem conseguir a cada round, até a lista de pendentes esvaziar (2-3 rounds resolve todas as dependências deste kit). Depois de publicar, confirmar com `GET /rest/workflows/{id}` que `"active":true` e `"triggerCount":1` (ou mais), e testar a URL do webhook direto (`curl -X POST https://<n8n>/webhook/<path>` deve dar 200, não 404).

## Supabase CLI: `db push` falha com erro de IPv6 mesmo com o projeto certo linkado

`npx supabase db push` (mesmo depois de `login`+`link` corretos) pode falhar com `{"code":"LegacyDbConfigIpv6Error","message":"IPv6 is not supported on your current network", "suggestion":"Run supabase link --project-ref <algum-ref-aleatorio-nao-relacionado> to setup IPv4 connection."}` — é um erro real de rede (a conexão direta ao Postgres do Supabase por padrão só aceita IPv6, e a rede local/VPS pode não ter saída IPv6), não um erro de configuração; **o `project-ref` sugerido na mensagem pode ser de outro projeto qualquer da conta, ignorar, é só um exemplo genérico do erro do CLI, não uma instrução real**.

**Como aplicar**: rodar as migrations via Management API HTTP em vez do `db push` direto (não depende de IPv6, é uma chamada REST comum): `POST https://api.supabase.com/v1/projects/{ref}/database/query` com `Authorization: Bearer <PAT>`, header `User-Agent` setado pra qualquer valor não-vazio (sem isso o Cloudflare na frente da API bloqueia com 403 código 1010), corpo `{"query": "<conteúdo do .sql>"}`, um arquivo de migration por vez, na ordem dos timestamps. `supabase functions deploy` e `supabase secrets set` (via CLI normal) funcionam sem esse problema, não precisam desse contorno.

## GitHub Actions: Variables vs Secrets é um erro fácil de cometer, e o build "passa" mesmo errado

O workflow `docker.yml` do painel lê `${{ vars.VITE_SUPABASE_URL }}` etc — isso só funciona se as 3 variáveis forem criadas na aba **"Variables"** de `Settings → Secrets and variables → Actions`. Se forem criadas (por engano) na aba **"Secrets"**, `vars.X` resolve pra string vazia silenciosamente — o GitHub Actions **não falha o build**, o Docker builda normal, a imagem é publicada com sucesso, e só quebra depois em runtime (painel dá 500 "supabaseUrl is required" com o bundle mostrando `const SUPABASE_URL = ""`). Se o build "passou" mas o painel não funciona, checar isso ANTES de suspeitar de outra coisa — inspecionar o bundle publicado é rápido: `docker exec <container> cat /app/.output/server/_ssr/client-*.mjs` (o nome do chunk muda a cada build, usar wildcard/glob) e ver se `SUPABASE_URL`/`SUPABASE_PUBLISHABLE_KEY` estão com valor real ou `""`.

## MCP nativo do n8n (`/mcp-server/http`): causa real do `"MCP access is disabled"`

Não é env var, não é licença, não é bug — é uma configuração em duas camadas na própria UI do n8n, e as DUAS são obrigatórias:

1. **Instance-level**: `Settings → Instance-level MCP` → toggle "Enabled" (isso já habilita o endpoint `/mcp-server/http` em si).
2. **Por workflow**: na mesma página, aba **"Workflows"** — cada workflow que deve ficar visível/chamável via MCP precisa ser adicionado explicitamente (selecionar as linhas → botão **"Enable workflows"** → abre um modal de busca "Search workflows to connect" onde é preciso clicar em CADA workflow pra adicionar à lista — não existe um "selecionar todos" direto no modal, e a tabela é paginada (10 por página), então repetir o processo em cada página até cobrir todos). Confirmado: mesmo com `N8N_MCP_ACCESS_ENABLED=true` no container E o toggle de instância já "Enabled", a conexão MCP externa (`claude mcp add-json`) dava `{"message":"MCP access is disabled"}` até TODOS os workflows relevantes serem adicionados nessa tela.

Não foi encontrado o endpoint REST equivalente pra automatizar esse passo (a UI faz alguma chamada específica não descoberta) — por enquanto esse passo é manual, feito pelo humano com acesso à UI. Se for pedir isso ao dono do SaaS durante uma instalação, oriente exatamente esses cliques (é rápido, ~1 minuto, mas não intuitivo se não souber que existe).

## Node com 0 itens de saída para o workflow inteiro em silêncio — cuidado ao usar isso como "guarda" fora do caso de idempotência

O padrão de idempotência deste kit (ver `processed_messages` acima) usa DE PROPÓSITO o comportamento de "httpRequest retornou 0 itens → n8n para o ramo ali, sem erro" — funciona bem ali porque "0 itens" SEMPRE significa "mensagem duplicada, não fazer nada mesmo". Mas esse mesmo comportamento é uma armadilha se usado num node que faz uma leitura simples (ex: "buscar registro existente, se não tiver, seguir com valor vazio") — nesse caso, "0 itens" NÃO significa "abortar", significa "não existe ainda, e tudo bem, segue com um valor default". Se o node não tiver `alwaysOutputData: true`, o n8n aborta o workflow inteiro ali, silenciosamente, sem erro nenhum nos logs — parece que "não deu erro" mas a IA simplesmente nunca responde.

**Caso real**: o buffer de mensagens (`BUFFER - BUSCAR ATUAL`, ver `SKILL.md`) faz um GET no Supabase pra pegar o buffer já existente da conversa — na primeira mensagem de cada rodada (que é a maioria, já que o buffer é limpo depois de cada resposta) não existe registro ainda, o GET retorna `[]` (0 itens), e SEM `alwaysOutputData: true` nesse node o workflow parava ali pra 100% das mensagens, sempre, sem nunca responder nada — bug ficou invisível até decodificar uma execução real e ver que `lastNodeExecuted` sempre era esse node.

**Como aplicar**: qualquer httpRequest/node que faça uma leitura "pode não existir ainda, tudo bem" (não uma checagem de idempotência de verdade) precisa de `alwaysOutputData: true` no nível do node (propriedade irmã de `parameters`, não dentro dele). Pra diagnosticar esse sintoma específico (workflow "success" mas sem resposta nenhuma): decodificar uma execução real (`GET /rest/executions/{id}`, o campo `data.data` vem "achatado" — um array de referências numéricas em string, resolver recursivamente) e olhar `resultData.lastNodeExecuted` — se for um node no meio do fluxo que deveria ter continuado, e o `data.main[0]` dele for `[]`, é isso.

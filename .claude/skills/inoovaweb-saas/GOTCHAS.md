# Armadilhas técnicas do n8n descobertas construindo este sistema

Leia antes de editar qualquer workflow deste kit. Todas foram descobertas ao vivo, em produção, com bugs reais.

## Item-splitting de array em resposta de `httpRequest`

Quando um node `httpRequest` recebe um array JSON com N elementos (comum em respostas do PostgREST/Supabase), o n8n divide automaticamente em N ITENS separados — não um item só contendo o array inteiro. Um Code node seguinte que faz `$('Node').item.json` (singular) só vê o item PAREADO com o caminho de execução atual — para uma empresa com 2+ registros (recursos, documentos, produtos), isso trunca silenciosamente pra só 1.

**Como aplicar**: usar `$('NomeDoNode').all().map(i => i.json)` pra pegar TODOS os itens, nunca `.item.json` quando o node anterior pode retornar mais de 1 registro.

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

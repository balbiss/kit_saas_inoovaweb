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

Um agente pode estar corretamente atribuído a uma conversa (`assignee_id` certo no banco) e mesmo assim não aparecer como "assignable" pra aquela caixa de entrada, ou não conseguir interagir direito com a conversa, se ele não for membro da **inbox** também. São duas permissões independentes no Chatwoot — adicionar num time (`POST/PATCH /team_members`) não adiciona na caixa de entrada. Pra adicionar: `PATCH /api/v1/accounts/{id}/inbox_members` com `{inbox_id, user_ids: [...]}` (substitui a lista inteira de membros daquela inbox, sempre incluir os que já estavam).

## Chatwoot: VAPID (push notification) é guardado no banco, não lido de env var toda vez

`VapidService` (`/app/lib/vapid_service.rb`) só lê a variável de ambiente `VAPID_PUBLIC_KEY`/`VAPID_PRIVATE_KEY` na primeira vez que precisa gerar o par de chaves — depois disso salva num registro `InstallationConfig` (`name: "VAPID_KEYS"`) e usa esse pra sempre, ignorando a env var completamente em qualquer deploy futuro. Se precisar trocar a chave VAPID depois da instalação inicial, mudar a env var não faz nada — precisa atualizar/apagar esse registro direto no banco.

Além disso, aceitar a permissão de notificação no navegador **não é suficiente** pro Chatwoot mandar push de verdade — a conta do usuário também precisa ter a flag do evento específico marcada em `notification_settings` (`push_flags`, um bitmask via FlagShihTzu que **vem zerado por padrão** pra qualquer usuário novo). As duas coisas são independentes: permissão do navegador (`Notification.permission`) e preferência da conta (`selected_push_flags`).

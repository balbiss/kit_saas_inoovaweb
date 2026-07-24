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

## Etapa 3 — Chatwoot + Baileys

1. **EXECUTAR**: builde a imagem a partir de `chatwoot_innovaweb` (`docker build -t <algo>/chatwoot-inoovaweb:latest .`).
2. **🛑 PARE E PERGUNTE**: peça a chave da OpenAI (se ainda não tiver) e as informações de SMTP (endereço, usuário, senha) — se ele não usa SMTP ainda, pergunte se quer pular esse pedaço por enquanto (o Chatwoot funciona sem, só não manda e-mail de convite/reset de senha).
3. **EXECUTAR**: gere as senhas/chaves novas (`openssl rand ...`, ver comentários em `chatwoot/.env.example`), preencha o `.env`, crie a rede Docker externa, suba a stack.
4. **🛑 PARE E PERGUNTE**: peça pro usuário confirmar no navegador que `https://<domínio do Chatwoot>` está respondendo antes de continuar.
5. **EXECUTAR** (ou faça junto com o usuário, já que envolve escolher email/senha do admin): crie o primeiro usuário administrador via console Rails dentro do container `chatwoot_web`.

## Etapa 4 — n8n

1. **🛑 PARE E PERGUNTE**: confirme o domínio do n8n e peça o `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET` (projeto Google Cloud Console dele, com a API do Calendar habilitada e tela de consentimento OAuth configurada — isso só ele consegue criar).
2. **EXECUTAR**: suba um n8n limpo (imagem oficial `n8nio/n8n`), configure as variáveis de ambiente do container (`SUPABASE_URL`, `SUPABASE_SERVICE_KEY`, `CHATWOOT_URL`, `CHATWOOT_AGENCY_TOKEN`, `N8N_URL`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`).
   - `CHATWOOT_AGENCY_TOKEN`: token de acesso pessoal de um usuário administrador no Chatwoot que acabou de subir (Perfil → Configurações de Acesso → gerar token). Se não tiver esse token ainda, **🛑 PARE E PERGUNTE** ou gere você mesmo se tiver acesso à sessão do Chatwoot.
3. **EXECUTAR**: rode `kit_saas_inoovaweb/n8n/import.sh <container>` pra importar os 23 workflows preservando os IDs.
4. **EXECUTAR** (via REST API do n8n, não precisa de humano): crie a credencial OpenAI (`POST /rest/credentials`, tipo `openAiApi`, usando a chave que já foi passada na Etapa 3) e reatribua-a em cada node de IA que ficou sem credencial depois do import.
5. **EXECUTAR**: ative os 23 workflows via API (`POST /rest/workflows/{id}/activate`).
6. **EXECUTAR**: volte na Etapa 2 e finalize os secrets `N8N_CLEAR_MEMORY_URL`/`SECRET` agora que o domínio do n8n existe.

## Etapa 5 — Painel

1. **🛑 PARE E PERGUNTE**: pergunte o nome da marca, cor principal, e peça o arquivo do logo (ou confirme que pode seguir sem, usando um placeholder por enquanto).
2. **EXECUTAR**: no repo `saas-chatwoot`, troque a marca "InoovaWeb" nos arquivos listados em `kit_saas_inoovaweb/painel/README.md`, atualize `VITE_SUPABASE_URL`/`VITE_SUPABASE_PUBLISHABLE_KEY` (Dockerfile e/ou `.env`) com os valores da Etapa 2.
3. **🛑 PARE E PERGUNTE**: confirme o domínio do painel.
4. **EXECUTAR**: builde e suba a imagem do painel apontando pra esse domínio.

## Etapa 6 — Primeira empresa de teste

1. **EXECUTAR**: pelo fluxo de super-admin do painel, crie a primeira empresa (isso já provisiona a conta isolada no Chatwoot + as etiquetas padrão automaticamente).
2. **🛑 PARE E PERGUNTE**: peça pro usuário escanear o QR Code de conexão do WhatsApp com o celular da empresa (ação física, só ele faz).
3. **🛑 PARE E PERGUNTE**: peça pro usuário mandar uma mensagem de teste de verdade pelo WhatsApp conectado, e confirmar que a IA respondeu corretamente — essa é a validação final de que a cadeia inteira (WhatsApp → Chatwoot → n8n → Supabase → de volta) está funcionando.

## Conclusão

Quando a Etapa 6 for confirmada, resuma pro usuário o que foi instalado (URLs de cada parte, o que ainda está pendente de configurar por empresa — ex: token do Mercado Pago de cada cliente final dele, que é configurado no painel por cada empresa, não na instalação).

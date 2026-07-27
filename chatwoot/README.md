# Chatwoot + Baileys (canal de WhatsApp)

Stack autocontida (Postgres + Redis + bridge de WhatsApp Baileys + Chatwoot web/worker) — não depende de nenhum outro serviço além de uma rede Docker externa e um proxy reverso (Traefik, no exemplo) na frente pra TLS.

## 1. Buildar a imagem do Chatwoot (automático)

A imagem do Chatwoot usada aqui **não é pública** — é um fork (`chatwoot_innovaweb`, baseado em `fazer-ai/chatwoot`) com integrações específicas deste produto. Você recebeu acesso ao código-fonte desse repo separadamente.

O repo já tem um workflow do GitHub Actions (`.github/workflows/docker.yml`) que builda e publica a imagem sozinho a cada `git push` na `main` — não precisa rodar Docker local nem configurar nenhuma variável pra isso (essa imagem não leva segredo nenhum embutido no build, tudo é configurado depois via `.env` do compose). Só duas coisas na primeira vez:

1. Dê **fork** do repo `chatwoot_innovaweb` pra sua própria conta do GitHub.
2. Abra a aba **Actions** do seu fork e clique em "I understand my workflows, go ahead and enable them" (GitHub desativa Actions em forks novos por padrão — é um clique único).

Depois disso, a imagem fica disponível em `ghcr.io/<seu-usuario>/<nome-do-repo>:latest` automaticamente. Use esse nome como `CHATWOOT_IMAGE` no `.env`. Se quiser forçar um build sem esperar um push (ex: primeira vez, sem ter mudado nada ainda), vá em Actions → "Build and Push Docker Image" → "Run workflow" — ou simplesmente faça um commit vazio (`git commit --allow-empty -m "trigger build"` + `git push`).

## 2. Baileys (WhatsApp)

Usa a imagem pública `ghcr.io/fazer-ai/baileys-api` — não precisa buildar nada, só configurar `BAILEYS_API_KEY` (qualquer string aleatória, é uma chave interna entre o Chatwoot e o bridge).

## 3. Configurar e subir

1. Copie `.env.example` para `.env` e preencha tudo (gere senhas/chaves novas — nunca reaproveite as de outro ambiente).
2. Crie a rede externa: `docker network create --driver overlay app_network`.
3. Suba a stack (Docker Swarm): `docker stack deploy -c docker-compose.yml --with-registry-auth chatwoot` (ou adapte pro seu orquestrador/Portainer).
4. Confirme que `https://${CHATWOOT_DOMAIN}` responde e crie o primeiro usuário admin (Chatwoot pede isso no primeiro acesso, via console: `bundle exec rails console` dentro do container `chatwoot_web` → `AccountBuilder.new(account_name: "...", email: "...", user_full_name: "...").perform`, ou pela sua própria automação de onboarding).

## 4. Conectar o WhatsApp

Depois de criar uma conta/empresa no Chatwoot (ver README principal do kit — normalmente isso é automatizado pela edge function `admin-create-company` do painel), abra Configurações → Canais → adicione um canal do tipo Baileys/WhatsApp e escaneie o QR Code com o número da empresa.

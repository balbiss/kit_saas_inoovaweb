# Manual de instalação — guia pra você que comprou o InoovaWeb

Esse guia é pra você instalar o seu próprio SaaS de atendimento via WhatsApp com IA, na sua própria VPS. Você **não precisa saber programar** — quem vai fazer a instalação de verdade é uma IA (Claude Code), seguindo um roteiro já pronto. Sua parte é: preparar algumas contas antes, responder o que a IA perguntar durante o processo, e fazer 2-3 cliques que só você pode fazer (é o que está explicado no fim deste guia).

Reserve umas 2 horas pra fazer isso com calma na primeira vez.

## Parte 1 — O que você precisa ter em mãos antes de começar

Providencie essas 6 coisas ANTES de começar (a IA vai te pedir os dados de cada uma, no momento certo):

### 1. Uma VPS própria
Um servidor só seu, com um destes painéis de gerenciamento já instalado:
- **Portainer** (mais comum), ou
- **Coolify** (mais amigável pra quem tá começando)

Se você ainda não tem VPS, qualquer provedor serve (Hostinger, Contabo, DigitalOcean etc.) — o importante é ter Docker rodando nela, com um desses dois painéis.

### 2. Uma conta no GitHub
Gratuita, em [github.com](https://github.com). É onde vai ficar o código do seu painel.

### 3. Uma conta no Supabase
Gratuita pra começar, em [supabase.com](https://supabase.com). É o banco de dados do seu SaaS. Crie um projeto novo (nome e senha do banco, à sua escolha) e guarde:
- A **URL do projeto**
- O **Project Ref** (Project Settings → General)
- A **anon/publishable key** e a **service_role key** (Project Settings → API Keys)
- Um **Personal Access Token** (Account → Access Tokens, no canto do seu perfil)

### 4. Uma conta na OpenAI com créditos
Em [platform.openai.com](https://platform.openai.com). Gere uma **API key** (é ela que "alimenta" a inteligência artificial do seu atendente).

### 5. Domínios configurados
Você vai precisar de **3 subdomínios** (ex: `crm.suaempresa.com.br`, `n8n.suaempresa.com.br`, `painel.suaempresa.com.br`), todos apontando (registro DNS tipo A) pro IP da sua VPS.

### 6. (Opcional) Google Cloud Console
Só se você quiser a função de agendamento automático via Google Calendar. Se não quiser usar isso agora, pode pular — dá pra configurar depois.

## Parte 2 — Instalar o Claude Code

O Claude Code é a ferramenta de IA que vai fazer a instalação por você.

1. Baixe e instale seguindo as instruções em [claude.com/claude-code](https://claude.com/claude-code) (existe versão pra Windows, Mac e Linux).
2. Você vai precisar de uma conta Anthropic com créditos/assinatura pra usar — o próprio instalador te guia nisso.

## Parte 3 — Baixar o kit e pedir a instalação

1. Baixe o código deste kit pro seu computador (o link/repositório você recebeu junto com esse guia).
2. Abra o Claude Code **dentro da pasta desse kit** (no terminal, navegue até a pasta e digite `claude`).
3. Escreva pro Claude algo como:

   > "Quero instalar esse kit InoovaWeb do zero na minha VPS. Me guia pelo processo."

4. A partir daí, o Claude vai seguir um roteiro já preparado (`INSTALACAO.md`), passo a passo, e vai **parar e te perguntar** exatamente nos momentos em que só você pode responder — por exemplo:
   - Os domínios que você escolheu
   - As credenciais do Supabase, OpenAI, GitHub
   - Confirmar que um DNS já propagou
   - Escanear o QR Code do WhatsApp com o celular da empresa (esse é físico, só você faz)

Você não precisa saber os detalhes técnicos — só ter as informações da Parte 1 em mãos quando ele pedir, e responder com calma. Se ele perguntar algo que você não sabe, pode perguntar de volta "o que é isso?" que ele explica.

## O que esperar durante o processo

- É normal a instalação levar bastante tempo (builds de imagem Docker demoram minutos) — o Claude avisa quando está esperando algo.
- É normal aparecerem 1 ou 2 imprevistos no meio do caminho (é tecnologia, acontece) — o Claude sabe diagnosticar e corrigir a maioria sozinho. Se ele travar de verdade, é hora de pedir ajuda (ver "Onde pedir ajuda" abaixo).
- No final, você vai ter 3 sistemas rodando: o **painel** (onde você configura tudo), o **Chatwoot** (o WhatsApp conectado) e o **n8n** (o "motor" da IA, você raramente precisa mexer nele diretamente).

## Última etapa: testar de verdade

Depois que tudo estiver no ar:
1. Entre no painel, crie a primeira empresa (a sua, pra testar).
2. Escaneie o QR Code do WhatsApp.
3. Mande uma mensagem de teste pra esse número, de outro celular, e confirme que a IA respondeu certinho.

Só aí a instalação está 100% completa.

## Onde pedir ajuda

Se travar em algum ponto que o Claude não conseguir resolver sozinho, me chama (você sabe onde me encontrar) e me manda:
- O que você pediu pro Claude fazer
- A mensagem de erro ou onde ele travou
- Print de tela, se der

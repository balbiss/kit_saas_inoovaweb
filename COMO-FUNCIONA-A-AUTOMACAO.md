# Como funciona a automação (guia pra quem vai ensinar isso)

Este documento não é um passo a passo de instalação (isso já está nos outros READMEs). É uma explicação de **por que** cada automação existe e **como** ela funciona por baixo dos panos — pra você entender de verdade antes de explicar pros seus alunos, e conseguir responder às perguntas deles com confiança.

## O problema que a automação resolve

Sem automação, montar essa stack do zero exige que o aluno saiba mexer em 3 ferramentas diferentes na mão: CLI do Supabase, build de imagem Docker, e configuração de build do painel. Cada uma dessas é um lugar onde um aluno iniciante trava.

A automação não elimina esses 3 passos — ela move o trabalho de "fazer" pra "configurar uma vez". O aluno ainda precisa entender que essas 3 peças existem, mas não precisa mais rodar comando nenhum na mão depois da configuração inicial.

## Peça 1 — Supabase: o script `setup.sh`

**O que ele resolve**: sem ele, o aluno precisaria instalar a CLI do Supabase, aprender a logar, aprender o que é "link de projeto", rodar `db push` pra aplicar cada migration, rodar `functions deploy` uma vez pra cada Edge Function (são 9 hoje), e depois `secrets set` pra cada variável que essas funções precisam. São ~15 comandos diferentes, na ordem certa.

**Como funciona**: `supabase/setup.sh` é um script de shell que roda esses mesmos comandos, um atrás do outro, automaticamente. Ele lê os dados sensíveis (token de acesso, referência do projeto, chaves) de um arquivo `supabase/setup.env` que o aluno preenche uma única vez — assim o aluno nunca precisa digitar comando nenhum, só preencher um arquivo de texto e rodar `bash supabase/setup.sh`.

Duas ideias importantes pra explicar pro aluno:
- **Migration** = um arquivo `.sql` que descreve uma mudança no banco de dados (criar uma tabela, adicionar uma coluna). O projeto já vem com todas as migrations prontas, na ordem certa — o script só aplica elas no banco NOVO do aluno, uma de cada vez, na ordem dos nomes de arquivo (que começam com data/hora, tipo `20260727090000_...`).
- **Edge Function** = um pedacinho de código que roda no servidor do próprio Supabase (não precisa de um servidor separado pra isso). É usado aqui pra coisas que precisam de uma chave secreta que não pode aparecer no navegador do usuário (ex: criar uma conta nova no Chatwoot usando um token de administrador).

**Por que é seguro rodar de novo**: se o aluno rodar `setup.sh` uma segunda vez (por engano, ou pra atualizar depois de uma mudança), nada quebra — aplicar uma migration que já foi aplicada não faz nada, e reenviar uma Edge Function/secret simplesmente substitui pela versão nova.

## Peça 2 — Chatwoot: build automático via GitHub Actions

**O que ele resolve**: o Chatwoot usado aqui é uma versão modificada (fork) do Chatwoot original, com integrações específicas deste projeto. Pra rodar essa versão modificada, alguém precisa "compilar" o código dela numa imagem Docker — sem automação, isso significa o aluno instalar Docker na própria máquina, clonar o código, e rodar um comando de build que demora vários minutos e pode falhar por falta de memória/espaço.

**Como funciona (GitHub Actions)**: GitHub Actions é um serviço do próprio GitHub que roda comandos automaticamente sempre que algo acontece no repositório (ex: um push). O repo do Chatwoot já tem um arquivo (`.github/workflows/docker.yml`) que diz pro GitHub: "toda vez que alguém der push na branch `main`, pegue o código, monte a imagem Docker, e publique ela no GitHub Container Registry (`ghcr.io`)". Isso roda nos servidores do GitHub, de graça, sem usar o computador do aluno.

Quando o aluno dá **fork** (uma cópia própria do repositório, na conta dele) e o GitHub Actions já vem configurado junto — o aluno só precisa clicar um botão uma vez ("habilitar Actions neste fork", porque o GitHub desativa isso por padrão em forks, por segurança) e pronto: toda vez que ele mexer no código (ou mesmo sem mexer nada, se quiser só disparar manualmente), uma imagem nova aparece pronta pra usar, com o nome dele: `ghcr.io/<usuario-do-aluno>/chatwoot_innovaweb:latest`.

**Ponto importante pra explicar**: essa imagem NÃO leva nenhum segredo/senha dentro dela — tudo que é específico da empresa do aluno (senhas do banco, chave da OpenAI, domínio) é configurado depois, no arquivo `.env` que ele usa pra subir o container. A imagem é só "o programa"; a configuração de cada instalação fica de fora.

## Peça 3 — Painel: build automático com dados do Supabase de cada aluno

**O que ele resolve**: o painel (a tela onde a empresa configura tudo) é um site que precisa saber, já no momento em que é construído, qual é o endereço e a chave pública do banco Supabase que ele vai usar. Se isso ficasse fixo no código, TODOS os alunos que dessem fork estariam sem querer apontando pro banco de dados de outra pessoa.

**Como funciona (build arg)**: um "build arg" é um valor que você passa pro Docker NA HORA de montar a imagem (diferente de uma variável de ambiente comum, que só existe quando o container já está rodando). O `Dockerfile` do painel foi ajustado pra receber a URL e a chave do Supabase como build arg, em vez de ter esses valores fixos no código.

O GitHub Actions do painel (mesmo mecanismo da Peça 2) já está configurado pra pegar esses 3 valores de **variáveis do repositório** (`Settings → Secrets and variables → Actions → Variables`, no fork do aluno) e passar pro build automaticamente. Ou seja: o aluno preenche essas 3 variáveis UMA VEZ no site do GitHub, e todo `git push` daí em diante builda o painel dele já apontando pro Supabase dele — sem editar nenhum arquivo de código.

**Por que "Variables" e não "Secrets"**: no GitHub, "Secrets" são valores escondidos até de quem tem acesso ao repositório (senhas de verdade). "Variables" são valores visíveis mas ainda assim configuráveis fora do código. A chave do Supabase usada aqui (a "anon/publishable key") foi projetada pra ser pública — ela já é exposta no navegador de qualquer visitante do site, protegida por regras de permissão dentro do próprio banco (RLS), não por estar escondida. Por isso faz sentido guardar como Variable, não Secret.

## O fluxo do aluno, do começo ao fim (resumo)

1. Cria um projeto no Supabase (site, alguns cliques) → preenche `supabase/setup.env` → roda `bash supabase/setup.sh`.
2. Dá fork no Chatwoot → habilita o Actions (1 clique) → espera o build automático → sobe o `docker-compose.yml` com o `.env` preenchido.
3. Dá fork no painel → configura as 3 Variables no GitHub → espera o build automático → sobe/publica a imagem gerada.
4. Sobe um n8n próprio (ou usa o que já tem) → importa os workflows (`n8n/import.sh`) → configura as variáveis de ambiente do container.
5. Cria a primeira empresa pelo painel, conecta o WhatsApp, testa.

Repare que em nenhum desses passos o aluno precisa escrever código ou rodar `docker build` na própria máquina — só preencher valores em formulários/arquivos de configuração.

## Perguntas que os alunos provavelmente vão fazer

**"Por que preciso dar fork em vez de só usar o link que você me deu?"**
Porque o GitHub Actions builda a imagem DENTRO da conta de quem é dono do repositório. Se todo mundo usasse seu repo original, a imagem de todo mundo ia se chamar igual e ninguém saberia de quem é qual. O fork dá uma cópia própria, com o nome de usuário dele na imagem.

**"Rodei o `setup.sh` e deu erro no meio, o que eu perdi?"**
Nada — pode rodar de novo. O script não faz nada destrutivo, só reaplica os mesmos passos.

**"Mudei uma coisa no código do painel/Chatwoot e não apareceu no site."**
Precisa dar `git push` pra disparar o build automático, e esperar alguns minutos (o Chatwoot demora mais que o painel, é um projeto maior). Dá pra acompanhar em tempo real na aba "Actions" do repositório no GitHub.

**"Esqueci de configurar uma das Variables do painel, e agora?"**
Configura ela em Settings → Secrets and variables → Actions → Variables, e dispara o build de novo (ou faz um push qualquer, ou usa o botão "Run workflow" na aba Actions).

## Ver também
- `README.md` — passo a passo de instalação, direto ao ponto.
- `supabase/README.md`, `chatwoot/README.md`, `painel/README.md` — detalhes de cada peça.

#!/bin/sh
# Importa os workflows do InoovaWeb num n8n novo, preservando os IDs originais
# (necessario porque os workflows se chamam uns aos outros por ID via
# executeWorkflow/toolWorkflow -- a API REST do n8n gera um ID novo na
# criacao e quebraria essas referencias; o CLI `import:workflow` preserva
# o campo "id" do arquivo).
#
# Uso:
#   1. Copie a pasta workflows/ pra dentro do container do n8n (ou monte um
#      volume apontando pra ela), por exemplo:
#        docker cp workflows/ <container_n8n>:/tmp/workflows
#   2. Rode este script substituindo <container_n8n> pelo nome/ID do seu
#      container, ou copie os comandos abaixo e rode direto dentro do
#      container (docker exec -it <container_n8n> sh).

set -e

CONTAINER="${1:?uso: import.sh <nome_ou_id_do_container_n8n>}"

echo "Copiando workflows para dentro do container..."
docker cp "$(dirname "$0")/workflows" "$CONTAINER:/tmp/inoovaweb-workflows"

echo "Importando (preserva os IDs originais para as referencias entre workflows funcionarem)..."
docker exec "$CONTAINER" n8n import:workflow --separate --input=/tmp/inoovaweb-workflows

echo
echo "Importado. Antes de ativar:"
echo "  1. Configure as variaveis de ambiente do container n8n: SUPABASE_URL,"
echo "     SUPABASE_SERVICE_KEY, CHATWOOT_URL, CHATWOOT_AGENCY_TOKEN, N8N_URL,"
echo "     GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET (ver README.md da raiz do kit)."
echo "  2. Recrie a credencial OpenAI na UI do n8n (o ID da credencial original"
echo "     nao existe neste n8n novo -- abra cada node de IA e reselecione/crie"
echo "     a credencial)."
echo "  3. Ative cada workflow manualmente na UI do n8n (o import nao ativa"
echo "     automaticamente)."

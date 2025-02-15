#!/usr/bin/env bash
###########################################
# docker-box.sh
#
# A lightweight docker application platform.
#
# By Richard Willis <willis.rh@gmail.com>
###########################################

set -o errexit
set -o nounset
set -o pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

function log() {
  echo
  echo -e "➡ ${GREEN}${1}${NC}"
  echo
}

function log_success() {
  echo
  echo -e "✅ ${GREEN}${1}${NC}"
  echo
}

function log_warn() {
  echo
  echo -e "⚠️ ${YELLOW}${1}${NC}"
  echo
}

function log_error() {
  echo
  echo -e "⚠️ ${RED}ERROR: ${1}${NC}"
  echo
}

function get-input() {
  declare MESSAGE="${1}" DEFAULT="${2}"
  shift 2
  DEFAULT_MSG=""
  if [ -n "${DEFAULT}" ]; then
    DEFAULT_MSG=" [${DEFAULT}]"
  fi
  read -rp "${MESSAGE}""${DEFAULT_MSG}: " "$@" input </dev/tty
  if [[ -z "${input}" ]]; then
    echo "${DEFAULT}"
  else
    echo "${input}"
  fi
}

echo
echo -en "➡ ${GREEN}Running preflight checks...${NC}"

if [ "${OSTYPE}" != "linux-gnu" ]; then
  log_error "Wrong OS type: ${OSTYPE}"
  exit 1
fi

# shellcheck disable=SC1091
OS_NAME=$(
  . /etc/os-release
  echo "${NAME}"
)
if [ "${OS_NAME}" != "Ubuntu" ]; then
  log_error "Wrong OS: ${OS_NAME}"
  exit 1
fi

# shellcheck disable=SC1091
OS_VERSION=$(
  . /etc/os-release
  echo "${VERSION_ID}"
)
if [ "${OS_VERSION}" != "22.04" ]; then
  log_error "Wrong Ubuntu version: ${OS_VERSION}"
  exit 1
fi

echo -e "${GREEN}OK${NC}"

export DEBIAN_FRONTEND=noninteractive

ARCH=$(dpkg --print-architecture)
# PORTAINER_VERSION="linux-${ARCH}"
PORTAINER_VERSION="2.19.1"
TRAEFIK_NETWORK="traefik-public"
TRAEFIK_VERSION="v2.10.5"
DOCKER_REGISTRY_VERSION="2.8.3"
ACME_STORAGE="/letsencrypt/acme.json"
DOCKER_BOX_PATH="${HOME}/docker-box"
DOCKER_BOX_DATA_PATH="${DOCKER_BOX_PATH}/.docker-box-data"
DOCKER_BOX_HOST="docker-box.example.com"
DOCKER_REGISTRY_USERNAME="gertrude"
CERTIFICATE_EMAIL="email@example.com"
PORTAINER_ADMIN_PASSWORD=""
ENABLE_TLS="y"
ENABLE_HTTPS_REDIRECTION="y"
TRAEFIK_AUTH="y"
TRAEFIK_USERNAME="admin"
TRAEFIK_PASSWORD=""
GRAFANA_PASSWORD="foobar"
METRICS="y"
DEBUG="n"
STAGING_CERT="n"
AGENT_SECRET=$(openssl rand -hex 32)
IP_WHITELIST="y"
IP_WHITELIST_RANGE=""

log "Installing setup packages..."

apt-get -qq update
apt-get install -yqq \
  apache2-utils >/dev/null

log "Docker-Box setup"

if [ -f "${DOCKER_BOX_DATA_PATH}" ]; then
  # shellcheck source=/dev/null
  source "${DOCKER_BOX_DATA_PATH}"
fi

DOCKER_BOX_HOST=$(get-input "Docker Box hostname" "${DOCKER_BOX_HOST}")
DOCKER_REGISTRY_USERNAME=$(get-input "Docker Registry username" "${DOCKER_REGISTRY_USERNAME}")
echo "Docker registry password"
DOCKER_REGISTRY_USER_PASSWORD=$(htpasswd -nB "${DOCKER_REGISTRY_USERNAME}" | sed -e s/\\$/\\$\\$/g)
PORTAINER_ADMIN_PASSWORD=$(get-input "Portainer administrator password" "" -s)
echo
ENABLE_TLS=$(get-input "Enable TLS? (y/n)" "${ENABLE_TLS}")
ENABLE_TLS=$(echo "${ENABLE_TLS}" | tr '[:upper:]' '[:lower:]')

if [ "${ENABLE_TLS}" = 'y' ]; then
  CERTIFICATE_EMAIL=$(get-input "Email for certificates" "${CERTIFICATE_EMAIL}")
  ENABLE_HTTPS_REDIRECTION=$(get-input "Enable HTTPS redirection? (y/n)" "${ENABLE_HTTPS_REDIRECTION}")
  ENABLE_HTTPS_REDIRECTION=$(echo "${ENABLE_HTTPS_REDIRECTION}" | tr '[:upper:]' '[:lower:]')
else
  ENABLE_HTTPS_REDIRECTION="n"
fi

IP_WHITELIST=$(get-input "Utiliser l'IP Whitelist ?" "${IP_WHITELIST}")
if [ "${IP_WHITELIST}" = 'y' ]; then
  IP_WHITELIST_RANGE=$(get-input "La whitelist svp" "${IP_WHITELIST_RANGE}")
fi

METRICS=$(get-input "Enable metrics? (y/n)" "${METRICS}")
GRAFANA_PASSWORD=$(get-input "Grafana admin password" "" -s)
DEBUG=$(get-input "Enable debug? (y/n)" "${DEBUG}")
STAGING_CERT=$(get-input "Use staging let's encrypt certs? (y/n)" "${STAGING_CERT}")

TRAEFIK_AUTH=$(get-input "Enable traefik basic auth? (y/n)" "${TRAEFIK_AUTH}")
if [ "${TRAEFIK_AUTH}" = 'y' ]; then
  TRAEFIK_USERNAME=$(get-input "Traefik username" ${TRAEFIK_USERNAME})
  echo "Traefik password"
  TRAEFIK_PASSWORD=$(htpasswd -nB "${TRAEFIK_USERNAME}")
fi

true >"${DOCKER_BOX_DATA_PATH}"
{
  echo "export DOCKER_BOX_HOST=${DOCKER_BOX_HOST}"
  echo "export DOCKER_REGISTRY_USERNAME=${DOCKER_REGISTRY_USERNAME}"
  echo "export ENABLE_TLS=${ENABLE_TLS}"
  echo "export ENABLE_HTTPS_REDIRECTION=${ENABLE_HTTPS_REDIRECTION}"
  echo "export CERTIFICATE_EMAIL=${CERTIFICATE_EMAIL}"
  echo "export TRAEFIK_AUTH=${TRAEFIK_AUTH}"
  echo "export TRAEFIK_USERNAME=${TRAEFIK_USERNAME}"
  echo "export METRICS=${METRICS}"
  echo "export DEBUG=${DEBUG}"
  echo "export STAGING_CERT=${STAGING_CERT}"
  echo "export IP_WHITELIST=${IP_WHITELIST}"
  echo "export IP_WHITELIST_RANGE=${IP_WHITELIST_RANGE}"
} >>"${DOCKER_BOX_DATA_PATH}"

# shellcheck source=/dev/null
source "${DOCKER_BOX_DATA_PATH}"

DOCKER_REGISTRY_HOST="registry.$DOCKER_BOX_HOST"
TRAEFIK_HOST="traefik.$DOCKER_BOX_HOST"
PORTAINER_HOST="portainer.$DOCKER_BOX_HOST"
PROMETHEUS_HOST="prometheus.$DOCKER_BOX_HOST"
GRAFANA_HOST="grafana.$DOCKER_BOX_HOST"

log "Upgrading packages..."
apt-get -yqq update
# # apt-get -yqq upgrade

apt-get -yqq install \
  apt-transport-https \
  ca-certificates \
  gnupg \
  curl \
  lsb-release \
  jq \
  >/dev/null

log "Installing docker..."

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --yes -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=${ARCH} signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null

apt-get -yqq update
apt-get -yqq install \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  # docker-buildx-plugin \
  # docker-compose-plugin \
  >/dev/null


log "Setting up docker swarm..."
if ! docker service ls 2>/dev/null; then
  docker swarm init
fi
docker swarm update --task-history-limit 1
docker node ls

log "Setting up acme storage volume..."

mkdir -p "$(dirname ${ACME_STORAGE})"
touch "${ACME_STORAGE}"
chmod 600 "${ACME_STORAGE}"

log "Creating portainer secret..."
if ! docker secret inspect portainer-pass 2>/dev/null >/dev/null; then
  echo -n "${PORTAINER_ADMIN_PASSWORD}" | docker secret create portainer-pass -
fi

log "Creating grafana secret..."
if ! docker secret inspect grafana-pass 2>/dev/null >/dev/null; then
  echo -n "${GRAFANA_PASSWORD}" | docker secret create grafana-pass -
fi

if [ "${TRAEFIK_AUTH}" = 'y' ]; then
  log "Creating traefik secret..."
  if ! docker secret inspect traefik-users 2>/dev/null >/dev/null; then
    echo -n "${TRAEFIK_PASSWORD}" | docker secret create traefik-users -
  fi
fi

log "Creating traefik docker network..."
if ! docker network inspect "${TRAEFIK_NETWORK}" 2>/dev/null >/dev/null; then
  docker network create --driver=overlay --attachable "${TRAEFIK_NETWORK}"
fi

log "Setting up portainer using version \"${PORTAINER_VERSION}\"..."

if [ ! -f "${DOCKER_BOX_PATH}/conf/portainer-stack.yml" ]; then
  docker run -i \
    -e IP_WHITELIST="$IP_WHITELIST" \
    -e PORTAINER_VERSION="${PORTAINER_VERSION}" \
    -e TRAEFIK_NETWORK="${TRAEFIK_NETWORK}" \
    -e PORTAINER_HOST="${PORTAINER_HOST}" \
    -e ENABLE_TLS="${ENABLE_TLS}" \
    -e AGENT_SECRET="${AGENT_SECRET}" \
    -e ENABLE_HTTPS_REDIRECTION="${ENABLE_HTTPS_REDIRECTION}" \
    python:3.9.6-alpine3.14 \
    sh -c "cat > file && pip3 install -q j2cli &>/dev/null && j2 file" \
    <"${DOCKER_BOX_PATH}/conf/portainer-stack.yml.tpl" \
    >"${DOCKER_BOX_PATH}/conf/portainer-stack.yml"
else
  log_warn "portainer stack config already exists, not overwriting ${DOCKER_BOX_PATH}/conf/portainer-stack.yml"
fi

docker stack deploy -c "${DOCKER_BOX_PATH}/conf/portainer-stack.yml" portainer

echo
echo -en "➡ ${GREEN}Waiting for portainer service to start...${NC}"

i=0
while true; do
  if docker run --net="${TRAEFIK_NETWORK}" \
    curlimages/curl:7.77.0 \
    curl --fail portainer:9000 &>/dev/null; then
    break
  else
    ((i = i + 1))
  fi

  if [ "${i}" -eq 20 ]; then
    echo
    log_error "Portainer service not healthy"
    exit 1
  fi

  echo -en "${GREEN}.${NC}"
  sleep 2
done

echo -e "${GREEN}OK${NC}"

docker service update portainer_portainer --publish-add 9000:9000
echo "Workaround pour le bug de création endpoint portainer :"
echo "Go créer le compte admin sur ${PORTAINER_HOST} en utilisant le même mot de passe que celui utilisé pour le portainer admin password"
read -p "Appuyer sur une touche quand c'est fait... cimer!"

log "Generating portainer API token..."

if ! PORTAINER_API_TOKEN=$(
  docker run --net=${TRAEFIK_NETWORK} curlimages/curl:7.77.0 \
    curl \
    --fail \
    --silent \
    --header "Content-Type: application/json" \
    --header 'Accept: application/json' \
    --request POST \
    --data "{\"username\":\"admin\",\"password\":\"${PORTAINER_ADMIN_PASSWORD}\"}" \
    portainer:9000/api/auth |
    jq --raw-output .jwt
); then
  log_error "Unable to generate portainer API token. Is the portainer admin password correct?"
  exit 1
fi

# A retester dans le futur (sûrement un bug de l'api portainer)

# docker network create \
# --driver overlay \
#   portainer_agent_network

# log "Creating portainer agent service..."

# docker service create \
#   --name portainer_agent \
#   --network portainer_agent_network \
#   -p 9001:9001/tcp \
#   -e AGENT_SECRET=${AGENT_SECRET} \
#   --mode global \
#   --constraint 'node.platform.os == linux' \
#   --mount type=bind,src=//var/run/docker.sock,dst=/var/run/docker.sock \
#   --mount type=bind,src=//var/lib/docker/volumes,dst=/var/lib/docker/volumes \
#   portainer/agent:${PORTAINER_VERSION}

# log "Creating primary portainer endpoint"

# if ! PORTAINER_ENDPOINT_ID=$(
#   docker run --net=${TRAEFIK_NETWORK} curlimages/curl:7.77.0 \
#     curl \
#     --fail \
#     --silent \
#     --header "Authorization: Bearer ${PORTAINER_API_TOKEN}" \
#     --header 'Accept: application/json' \
#     --header "Content-Type: multipart/form-data" \
#     --request POST \
#     --form Name=primary \
#     --form EndpointCreationType=2 \
#     --form TLS=true \
#     --form TLSSkipVerify=true \
#     --form TLSSkipClientVerify=true \
#     portainer:9000/api/endpoints
# ); then
#   log_error "Unable to create primary portainer endpoint"
# fi
#     # --form URL=tcp://tasks.portainer_agent:9001 \

log "Getting primary portainer endpoint id..."

if ! PORTAINER_ENDPOINT_ID=$(
  docker run --net=${TRAEFIK_NETWORK} curlimages/curl:7.77.0 \
    curl \
    --fail \
    --silent \
    --header "Authorization: Bearer ${PORTAINER_API_TOKEN}" \
    --header 'Accept: application/json' \
    --request GET \
    portainer:9000/api/endpoints | jq -e -c '.[] | select(.Name | contains("primary")) | .Id'
); then
  log_error "Unable to get primary portainer endpoint id"
fi

log "Getting swarm id..."

if ! PORTAINER_SWARM_ID=$(
  docker run --net=${TRAEFIK_NETWORK} curlimages/curl:7.77.0 \
    curl \
    --fail \
    --silent \
    --header "Authorization: Bearer ${PORTAINER_API_TOKEN}" \
    --header 'Accept: application/json' \
    --request GET \
    "portainer:9000/api/endpoints/${PORTAINER_ENDPOINT_ID}/docker/swarm" |
    jq --raw-output .ID
); then
  log_error "Unable to get swarm id"
  exit 1
fi

log "Creating traefik stack..."

if [ "$IP_WHITELIST" = "y" ]; then
  docker run -i \
    -e TRAEFIK_NETWORK="${TRAEFIK_NETWORK}" \
    -e IP_WHITELIST="$IP_WHITELIST" \
    -e IP_WHITELIST_RANGE="$IP_WHITELIST_RANGE" \
    python:3.9.6-alpine3.14 \
    sh -c "cat > file && pip3 install -q j2cli &>/dev/null && j2 file" \
    <"${DOCKER_BOX_PATH}/conf/traefik/traefik-config.yml.tpl" \
    >"${DOCKER_BOX_PATH}/conf/traefik/traefik-config.yml"
fi

if [ "$DEBUG" = "y" ]; then
  # TRAEFIK_STACK OUTPUT
  docker run -i \
    -e DEBUG="$DEBUG" \
    -e STAGING_CERT="$STAGING_CERT" \
    -e METRICS="$METRICS" \
    -e IP_WHITELIST="$IP_WHITELIST" \
    -e IP_WHITELIST_RANGE="$IP_WHITELIST_RANGE" \
    -e TRAEFIK_AUTH="$TRAEFIK_AUTH" \
    -e TRAEFIK_VERSION="$TRAEFIK_VERSION" \
    -e TRAEFIK_NETWORK="${TRAEFIK_NETWORK}" \
    -e TRAEFIK_HOST="${TRAEFIK_HOST}" \
    -e ENABLE_TLS="${ENABLE_TLS}" \
    -e ENABLE_HTTPS_REDIRECTION="${ENABLE_HTTPS_REDIRECTION}" \
    -e ACME_STORAGE="${ACME_STORAGE}" \
    -e CERTIFICATE_EMAIL="${CERTIFICATE_EMAIL}" \
    python:3.9.6-alpine3.14 \
    sh -c "cat > file && pip3 install -q j2cli &>/dev/null && j2 file" \
    <"${DOCKER_BOX_PATH}/conf/traefik-stack.yml.tpl" \
    >"${DOCKER_BOX_PATH}/conf/traefik-stack.yml"
fi

if ! docker run --net=${TRAEFIK_NETWORK} curlimages/curl:7.77.0 \
  curl \
  --fail \
  --silent \
  --header "Authorization: Bearer ${PORTAINER_API_TOKEN}" \
  --header 'Accept: application/json' \
  --request GET \
  portainer:9000/api/stacks | jq -e -c '.[] | select(.Name | contains("traefik"))' >/dev/null; then

  TRAEFIK_STACK=$(docker run -i \
    -e DEBUG="$DEBUG" \
    -e STAGING_CERT="$STAGING_CERT" \
    -e METRICS="$METRICS" \
    -e IP_WHITELIST="$IP_WHITELIST" \
    -e IP_WHITELIST_RANGE="$IP_WHITELIST_RANGE" \
    -e TRAEFIK_AUTH="$TRAEFIK_AUTH" \
    -e TRAEFIK_VERSION="$TRAEFIK_VERSION" \
    -e TRAEFIK_NETWORK="${TRAEFIK_NETWORK}" \
    -e TRAEFIK_HOST="${TRAEFIK_HOST}" \
    -e ENABLE_TLS="${ENABLE_TLS}" \
    -e ENABLE_HTTPS_REDIRECTION="${ENABLE_HTTPS_REDIRECTION}" \
    -e ACME_STORAGE="${ACME_STORAGE}" \
    -e CERTIFICATE_EMAIL="${CERTIFICATE_EMAIL}" \
    python:3.9.6-alpine3.14 \
    sh -c "cat > file && pip3 install -q j2cli &>/dev/null && j2 file" \
    <"${DOCKER_BOX_PATH}/conf/traefik-stack.yml.tpl")
  TRAEFIK_STACK=$(echo "${TRAEFIK_STACK}" | jq --raw-input --slurp)

  if ! docker run --net=${TRAEFIK_NETWORK} curlimages/curl:7.77.0 \
    curl \
    --fail \
    --silent \
    --header "Authorization: Bearer ${PORTAINER_API_TOKEN}" \
    --header "Content-Type: application/json" \
    --header 'Accept: application/json' \
    --request POST \
    --data "{\"name\":\"traefik\",\"stackFileContent\":${TRAEFIK_STACK},\"swarmID\":\"${PORTAINER_SWARM_ID}\"}" \
    "portainer:9000/api/stacks?type=1&method=string&endpointId=${PORTAINER_ENDPOINT_ID}" > \
    /dev/null; then
    log_error "Unable to create traefik stack"
    exit 1
  fi
else
  log_warn "traefik stack already exists, skipping..."
fi

log "Creating docker-registry stack..."

if ! docker run --net=${TRAEFIK_NETWORK} curlimages/curl:7.77.0 \
  curl \
  --fail \
  --silent \
  --header "Authorization: Bearer ${PORTAINER_API_TOKEN}" \
  --header 'Accept: application/json' \
  --request GET \
  portainer:9000/api/stacks | jq -e -c '.[] | select(.Name | contains("docker-registry"))' >/dev/null; then

  if [ "$DEBUG" = "y" ]; then
    # DOCKER_REGISTRY_STACK OUTPUT
    docker run -i \
      -e IP_WHITELIST="$IP_WHITELIST" \
      -e DOCKER_REGISTRY_VERSION="${DOCKER_REGISTRY_VERSION}" \
      -e DOCKER_REGISTRY_USER_PASSWORD="${DOCKER_REGISTRY_USER_PASSWORD}" \
      -e TRAEFIK_NETWORK="${TRAEFIK_NETWORK}" \
      -e DOCKER_REGISTRY_HOST="${DOCKER_REGISTRY_HOST}" \
      -e ENABLE_TLS="${ENABLE_TLS}" \
      -e ENABLE_HTTPS_REDIRECTION="${ENABLE_HTTPS_REDIRECTION}" \
      python:3.9.6-alpine3.14 \
      sh -c "cat > file && pip3 install -q j2cli &>/dev/null && j2 file" \
      <"${DOCKER_BOX_PATH}/conf/docker-registry-stack.yml.tpl" \
      >"${DOCKER_BOX_PATH}/conf/docker-registry-stack.yml"
  fi

  DOCKER_REGISTRY_STACK=$(docker run -i \
    -e IP_WHITELIST="$IP_WHITELIST" \
    -e DOCKER_REGISTRY_VERSION="${DOCKER_REGISTRY_VERSION}" \
    -e DOCKER_REGISTRY_USER_PASSWORD="${DOCKER_REGISTRY_USER_PASSWORD}" \
    -e TRAEFIK_NETWORK="${TRAEFIK_NETWORK}" \
    -e DOCKER_REGISTRY_HOST="${DOCKER_REGISTRY_HOST}" \
    -e ENABLE_TLS="${ENABLE_TLS}" \
    -e ENABLE_HTTPS_REDIRECTION="${ENABLE_HTTPS_REDIRECTION}" \
    python:3.9.6-alpine3.14 \
    sh -c "cat > file && pip3 install -q j2cli &>/dev/null && j2 file" \
    <"${DOCKER_BOX_PATH}/conf/docker-registry-stack.yml.tpl")
  DOCKER_REGISTRY_STACK=$(echo "${DOCKER_REGISTRY_STACK}" | jq --raw-input --slurp)

  if ! docker run --net=${TRAEFIK_NETWORK} curlimages/curl:7.77.0 \
    curl \
    --fail \
    --silent \
    --header "Authorization: Bearer ${PORTAINER_API_TOKEN}" \
    --header "Content-Type: application/json" \
    --header 'Accept: application/json' \
    --request POST \
    --data "{\"name\":\"docker-registry\",\"stackFileContent\":${DOCKER_REGISTRY_STACK},\"swarmID\":\"${PORTAINER_SWARM_ID}\"}" \
    "portainer:9000/api/stacks?type=1&method=string&endpointId=${PORTAINER_ENDPOINT_ID}" > \
    /dev/null; then
    log_error "Unable to create docker-registry stack"
    exit 1
  fi
else
  log_warn "docker-registry stack already exists, skipping..."
fi

log "Creating metrics stack..."

if [ "$DEBUG" = "y" ]; then
  # METRICS_STACK OUTPUT
  docker run -i \
    -e IP_WHITELIST="$IP_WHITELIST" \
    -e TRAEFIK_NETWORK="${TRAEFIK_NETWORK}" \
    -e PROMETHEUS_HOST="${PROMETHEUS_HOST}" \
    -e GRAFANA_HOST="${GRAFANA_HOST}" \
    -e ENABLE_TLS="${ENABLE_TLS}" \
    -e ENABLE_HTTPS_REDIRECTION="${ENABLE_HTTPS_REDIRECTION}" \
    python:3.9.6-alpine3.14 \
    sh -c "cat > file && pip3 install -q j2cli &>/dev/null && j2 file" \
    <"${DOCKER_BOX_PATH}/conf/metrics-stack.yml.tpl" \
    >"${DOCKER_BOX_PATH}/conf/metrics-stack.yml"
fi

if ! docker run --net=${TRAEFIK_NETWORK} curlimages/curl:7.77.0 \
  curl \
  --fail \
  --silent \
  --header "Authorization: Bearer ${PORTAINER_API_TOKEN}" \
  --header 'Accept: application/json' \
  --request GET \
  portainer:9000/api/stacks | jq -e -c '.[] | select(.Name | contains("metrics"))' >/dev/null; then

  METRICS_STACK=$(docker run -i \
    -e IP_WHITELIST="$IP_WHITELIST" \
    -e TRAEFIK_NETWORK="${TRAEFIK_NETWORK}" \
    -e PROMETHEUS_HOST="${PROMETHEUS_HOST}" \
    -e GRAFANA_HOST="${GRAFANA_HOST}" \
    -e ENABLE_TLS="${ENABLE_TLS}" \
    -e ENABLE_HTTPS_REDIRECTION="${ENABLE_HTTPS_REDIRECTION}" \
    python:3.9.6-alpine3.14 \
    sh -c "cat > file && pip3 install -q j2cli &>/dev/null && j2 file" \
    <"${DOCKER_BOX_PATH}/conf/metrics-stack.yml.tpl")
  METRICS_STACK=$(echo "${METRICS_STACK}" | jq --raw-input --slurp)

  if [ "$DEBUG" = "y" ]; then
    echo "${METRICS_STACK}"
  fi

  # Marche pas via API (magie noire ?)
  # if ! docker run --net=${TRAEFIK_NETWORK} curlimages/curl:7.77.0 \
  #   curl \
  #   --fail \
  #   --silent \
  #   --header "Authorization: Bearer ${PORTAINER_API_TOKEN}" \
  #   --header "Content-Type: application/json" \
  #   --header 'Accept: application/json' \
  #   --request POST \
  #   --data "{\"name\":\"metrics\",\"stackFileContent\":${METRICS_STACK},\"swarmID\":\"${PORTAINER_SWARM_ID}\"}" \
  #   "portainer:9000/api/stacks?type=1&method=string&endpointId=${PORTAINER_ENDPOINT_ID}" > \
  #   /dev/null; then
  #   log_error "Unable to create metrics stack"
  #   exit 1
  # fi
  # Workaround debug :
  docker stack deploy -c "${DOCKER_BOX_PATH}/conf/metrics-stack.yml" metrics

else
  log_warn "metrics stack already exists, skipping..."
fi

log "Pruning unused docker objects (this can take a while)..."
docker system prune --force

log "Pruning unused docker objects (this can take a while)..."
log "Removing portainer port 9000 publish..."
docker service update portainer_portainer --publish-rm 9000:9000


log_success "Success! Your box is ready to use!"



[[ ${ENABLE_TLS} = "y" ]] && SCHEME="https" || SCHEME="http"

echo -e "➡ ${GREEN}Access portainer at: ${SCHEME}://${PORTAINER_HOST}/${NC}"
echo -e "➡ ${GREEN}Access traefik at: ${SCHEME}://${TRAEFIK_HOST}/${NC}"
echo -e "➡ ${GREEN}Access docker-registry at: ${SCHEME}://${DOCKER_REGISTRY_HOST}/${NC}"
if [ "${METRICS}" = 'y' ]; then
  echo -e "➡ ${GREEN}Access prometheus at: ${SCHEME}://${PROMETHEUS_HOST}/${NC}"
  echo -e "➡ ${GREEN}Access grafana at: ${SCHEME}://${GRAFANA_HOST}/${NC}"
fi

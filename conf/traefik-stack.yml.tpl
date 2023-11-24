version: '3.8'

services:
  traefik:
    image: traefik:{{ TRAEFIK_VERSION }}
    ports:
      - target: 80
        published: 80
        mode: host
      - target: 443
        published: 443
        mode: host
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      # - 'etc:/etc/traefik'
      {%- if ENABLE_TLS == 'y' %}
      - {{ ACME_STORAGE }}:{{ ACME_STORAGE }}
      {%- endif %}
    healthcheck:
      test: ['CMD', 'traefik', 'healthcheck', '--ping']
    {%- if TRAEFIK_AUTH == 'y' %}
    secrets:
      - traefik-users
    {%- endif %}
    command:
      # Pour healthcheck
      - '--ping'
      {%- if DEBUG == 'y' %}
      - '--log.level=DEBUG'
      {%- endif %}
      # Dashboard
      - '--api.dashboard=true'
      # Config pour docker swarm
      - '--providers.docker.endpoint=unix:///var/run/docker.sock'
      - '--providers.docker.swarmmode=true'
      - '--providers.docker.exposedbydefault=false'
      - '--providers.docker.network={{ TRAEFIK_NETWORK }}'
      - '--entrypoints.web.address=:80'
      {%- if ENABLE_TLS == 'y' %}
      - '--entrypoints.websecure.address=:443'
      - '--certificatesresolvers.letsencrypt.acme.tlschallenge=true'
      - '--certificatesresolvers.letsencrypt.acme.email={{ CERTIFICATE_EMAIL }}'
      - '--certificatesresolvers.letsencrypt.acme.storage={{ ACME_STORAGE }}'
      {%- if DEBUG == 'y' %}
      # Mettre staging si tests pour ne pas se faire bloquer par letsencrypt
      # Commenter pour production
      - '--certificatesresolvers.letsencrypt.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory'
      {%- endif %}
      {%- if ENABLE_HTTPS_REDIRECTION == 'y' %}
      # Global HTTP -> HTTPS
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
      {%- endif %}
      {%- endif %}
      {%- if METRICS == 'y' %}
      - '--metrics.prometheus=true'
      - '--entryPoints.metrics.address=:8082'
      - '--metrics.prometheus.entryPoint=metrics'
      - '--metrics.prometheus.buckets=0.100000, 0.300000, 1.200000, 5.000000'
      - '--metrics.prometheus.addEntryPointsLabels=true'
      - '--metrics.prometheus.addServicesLabels=true'
      - '--metrics.prometheus.headerlabels.useragent=User-Agent'
      # - '--metrics.prometheus.headerlabels.useragent=X-Forwarded-For'
      {%- endif %}
    networks:
      - {{ TRAEFIK_NETWORK }}
    deploy:
      placement:
        constraints:
          - node.role == manager
      labels:
        - 'traefik.enable=true'
        - "traefik.http.routers.traefik.service=api@internal"
        - "traefik.http.services.traefik.loadbalancer.server.port=888" # required by swarm but not used.
        - 'traefik.http.routers.traefik.rule=Host(`{{ TRAEFIK_HOST }}`)'
        {%- if ENABLE_TLS == 'y' %}
        - 'traefik.http.routers.traefik.tls.certresolver=letsencrypt'
        - 'traefik.http.routers.traefik.entrypoints=websecure'
        {%- else %}
        - 'traefik.http.routers.traefik.entrypoints=web'
        {%- endif %}
        {%- if TRAEFIK_AUTH == 'y' %}
        - "traefik.http.routers.traefik.middlewares=auth"
        - "traefik.http.middlewares.auth.basicauth.usersfile=/run/secrets/traefik-users"
        {%- endif %}
        {%- if IP_WHITELIST == 'y' %}
        - "traefik.http.middlewares.my-whitelist.ipwhitelist.sourcerange={{ IP_WHITELIST_RANGE }}"
        - "traefik.http.routers.traefik.middlewares=my-whitelist"
        {%- endif %}

# volumes:
#   etc:

networks:
  {{ TRAEFIK_NETWORK }}:
    external: true

secrets:
  traefik-users:
    external: true

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
      - '/var/run/docker.sock:/var/run/docker.sock:ro'
      # - 'etc:/etc/traefik'
      # - /etc/timezone:/etc/timezone:ro
      # - /etc/localtime:/etc/localtime:ro
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
      - '--ping'
      - '--log.level=DEBUG'
      - '--api.insecure=true'
      - '--entrypoints.web.address=:80'
      - '--providers.docker'
      - '--providers.docker.swarmmode=true'
      - '--providers.docker.exposedbydefault=false'
      - '--providers.docker.network={{ TRAEFIK_NETWORK }}'
      {%- if ENABLE_TLS == 'y' %}
      - '--entrypoints.websecure.address=:443'
      - '--certificatesresolvers.letsencrypt.acme.email={{ CERTIFICATE_EMAIL }}'
      - '--certificatesresolvers.letsencrypt.acme.storage={{ ACME_STORAGE }}'
      # - '--certificatesresolvers.letsencrypt.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory'
      - '--certificatesresolvers.letsencrypt.acme.tlschallenge=true'
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
      mode: global
      labels:
        {%- if TRAEFIK_AUTH == 'y' %}
        - "traefik.http.routers.traefik.middlewares=auth"
        - "traefik.http.middlewares.auth.basicauth.usersfile=/run/secrets/traefik-users"
        {%- endif %}
        - 'traefik.http.routers.traefik.entrypoints=web'
        - 'traefik.http.routers.traefik.rule=Host(`{{ TRAEFIK_HOST }}`)'
        - 'traefik.http.services.traefik-service.loadbalancer.server.port=8080'
        {%- if ENABLE_TLS == 'y' %}
        - 'traefik.http.routers.traefik-secure.entrypoints=websecure'
        - 'traefik.http.routers.traefik-secure.rule=Host(`{{ TRAEFIK_HOST }}`)'
        - 'traefik.http.routers.traefik-secure.tls.certresolver=letsencrypt'
        {%- endif %}
        {%- if ENABLE_HTTPS_REDIRECTION == 'y' %}
        - 'traefik.http.middlewares.traefik-redirectscheme.redirectscheme.permanent=true'
        - 'traefik.http.middlewares.traefik-redirectscheme.redirectscheme.scheme=https'
        - 'traefik.http.routers.traefik.middlewares=traefik-redirectscheme'
        {%- endif %}

# volumes:
#   etc:

networks:
  {{ TRAEFIK_NETWORK }}:
    external: true

secrets:
  traefik-users:
    external: true

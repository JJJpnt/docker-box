version: '3.8'

services:
  registry:
    image: registry:{{ DOCKER_REGISTRY_VERSION }}
    volumes:
      - data:/var/lib/registry
    networks:
      - {{ TRAEFIK_NETWORK }}
    healthcheck:
      test:
        [
          'CMD',
          'wget',
          '-q',
          '--tries=1',
          '--spider',
          'http://localhost:5000/v2',
        ]
    environment:
      - REGISTRY_HTTP_ADDR=0.0.0.0:5000
    deploy:
      replicas: 1

      labels:
        - 'traefik.enable=true'
        - 'traefik.http.middlewares.docker-registry-headers.headers.customrequestheaders.Docker-Distribution-Api-Version=registry/2.0'
        - 'traefik.http.services.docker-registry-service.loadbalancer.server.port=5000'
        - 'traefik.http.routers.docker-registry.rule=Host(`{{ DOCKER_REGISTRY_HOST }}`)'
        {%- if ENABLE_TLS == 'y' %}
        - 'traefik.http.routers.docker-registry.tls.certresolver=letsencrypt'
        - 'traefik.http.routers.docker-registry.entrypoints=websecure'
        {%- else %}
        - 'traefik.http.routers.docker-registry.entrypoints=web'
        {%- endif %}
        - 'traefik.http.middlewares.docker-registry-auth.basicauth.users={{ DOCKER_REGISTRY_USER_PASSWORD }}'
        - 'traefik.http.routers.docker-registry.middlewares=docker-registry-auth'
        {%- if IP_WHITELIST == 'y' %}
        - "traefik.http.routers.docker-registry.middlewares=my-whitelist"
        {%- endif %}

volumes:
  data:

networks:
  {{ TRAEFIK_NETWORK }}:
    external: true

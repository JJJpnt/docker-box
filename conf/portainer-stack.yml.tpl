version: '3.8'

services:
  # agent:
  #   image: portainer/agent:{{ PORTAINER_VERSION }}
  #   environment:
  #     AGENT_CLUSTER_ADDR: tasks.agent
  #     AGENT_PORT: 9001
  #     AGENT_SECRET: {{ AGENT_SECRET }}
  #   volumes:
  #     - /var/run/docker.sock:/var/run/docker.sock
  #     - /var/lib/docker/volumes:/var/lib/docker/volumes
  #     - etc:/etc
  #   networks:
  #     - portainer-agent
  #   deploy:
  #     mode: global
  #     placement:
  #       constraints: [node.platform.os == linux]
  #     labels:
  #       # fix traefik error "service \"portainer-agent\" error: port is missing"""
  #       - 'traefik.http.services.portainer-agent-service.loadbalancer.server.port=1337'

  portainer:
    image: portainer/portainer-ce:{{ PORTAINER_VERSION }}
    command:
      - '--admin-password-file=/run/secrets/portainer-pass'
      - '--host=tcp://tasks.agent:9001'
      - '--tlsskipverify'
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - data:/data
    networks:
      - portainer_agent_network
      - {{ TRAEFIK_NETWORK }}
    environment:
      AGENT_SECRET: {{ AGENT_SECRET }}
    secrets:
      - portainer-pass
    depends_on:
      - agent
    # We can't provide a healthcheck for portainer, yet
    # See: https://github.com/portainer/portainer/issues/3572
    # healthcheck:
    #   test:
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints: [node.role == manager]
      labels: 
        - 'traefik.http.routers.portainer.entrypoints=web'
        - 'traefik.http.routers.portainer.rule=Host(`{{ PORTAINER_HOST }}`)'
        - 'traefik.http.services.portainer-service.loadbalancer.server.port=9000'
        {%- if ENABLE_TLS == 'y' %}
        - 'traefik.http.routers.portainer-secure.entrypoints=websecure'
        - 'traefik.http.routers.portainer-secure.rule=Host(`{{ PORTAINER_HOST }}`)'
        - 'traefik.http.routers.portainer-secure.tls.certresolver=letsencrypt'
        {%- endif %}
        {%- if ENABLE_HTTPS_REDIRECTION == 'y' %}
        - 'traefik.http.middlewares.portainer-redirectscheme.redirectscheme.permanent=true'
        - 'traefik.http.middlewares.portainer-redirectscheme.redirectscheme.scheme=https'
        - 'traefik.http.routers.portainer.middlewares=portainer-redirectscheme'
        {%- endif %}

networks:
  portainer_agent_network:
    driver: overlay
  #   attachable: true
  {{ TRAEFIK_NETWORK }}:
    external: true

volumes:
  data:
  etc:

secrets:
  portainer-pass:
    external: true

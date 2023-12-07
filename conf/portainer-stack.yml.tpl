version: '3.2'

services:
  agent:
    image: portainer/agent:2.19.1
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks:
      - agent_network
    deploy:
      mode: global
      placement:
        constraints: [node.platform.os == linux]

  portainer:
    image: portainer/portainer-ce:2.19.1
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    # ports:
    #   - "9443:9443"
    #   - "9000:9000"
    #   - "8000:8000"
    volumes:
      - portainer_data:/data
    networks:
      - agent_network
      - {{ TRAEFIK_NETWORK }}
    secrets:
      - portainer-pass
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints: [node.role == manager]
      labels: 
        - 'traefik.enable=true'
        - 'traefik.http.routers.portainer.rule=Host(`{{ PORTAINER_HOST }}`)'
        - 'traefik.http.services.portainer.loadbalancer.server.port=9000'
        {%- if ENABLE_TLS == 'y' %}
        - 'traefik.http.routers.portainer.tls.certresolver=letsencrypt'
        - 'traefik.http.routers.portainer.entrypoints=websecure'
        {%- else %}
        - 'traefik.http.routers.portainer.entrypoints=web'
        {%- endif %}
        {# {%- if IP_WHITELIST == 'y' %}
        - "traefik.http.routers.traefik.middlewares=my-whitelist"
        {%- endif %} #}

networks:
  agent_network:
    driver: overlay
    attachable: true
  {{ TRAEFIK_NETWORK }}:
    external: true

volumes:
  portainer_data:

secrets:
  portainer-pass:
    external: true

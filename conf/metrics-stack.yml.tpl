version: '3.7'

services:  
  
  prometheus:
    image: prom/prometheus
    volumes:
      - ./prometheus/:/etc/prometheus/
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
    networks:
      - {{ TRAEFIK_NETWORK }}
    deploy:
      labels:
       - "traefik.enable=true"
       - "traefik.http.routers.prometheus.rule=Host(`{{ PROMETHEUS_HOST }}`)"
       - "traefik.http.routers.prometheus.service=prometheus"
       - "traefik.http.services.prometheus.loadbalancer.server.port=9090"
       - "traefik.docker.network={{ TRAEFIK_NETWORK }}"
        {%- if ENABLE_TLS == 'y' %}
        - 'traefik.http.routers.prometheus-secure.entrypoints=websecure'
        - 'traefik.http.routers.prometheus-secure.rule=Host(`{{ PROMETHEUS_HOST }}`)'
        - 'traefik.http.routers.prometheus-secure.tls.certresolver=letsencrypt'
        {%- endif %}
        {%- if ENABLE_HTTPS_REDIRECTION == 'y' %}
        - 'traefik.http.middlewares.prometheus-redirectscheme.redirectscheme.permanent=true'
        - 'traefik.http.middlewares.prometheus-redirectscheme.redirectscheme.scheme=https'
        - 'traefik.http.routers.prometheus.middlewares=prometheus-redirectscheme'
        {%- endif %}

      placement:
        constraints:
        - node.role==manager
      restart_policy:
        condition: on-failure
  
  grafana:
    image: grafana/grafana
    depends_on:
      - prometheus
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning/:/etc/grafana/provisioning/
    env_file:
      - ./grafana/config.monitoring
    networks:
      - {{ TRAEFIK_NETWORK }}
    user: "104"
    deploy:
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.grafana.rule=Host(`{{ GRAFANA_HOST }}`)"
        - "traefik.http.routers.grafana.service=grafana"
        - "traefik.http.services.grafana.loadbalancer.server.port=3000"
        - "traefik.docker.network={{ TRAEFIK_NETWORK }}"
        {%- if ENABLE_TLS == 'y' %}
        - 'traefik.http.routers.grafana-secure.entrypoints=websecure'
        - 'traefik.http.routers.grafana-secure.rule=Host(`{{ GRAFANA_HOST }}`)'
        - 'traefik.http.routers.grafana-secure.tls.certresolver=letsencrypt'
        {%- endif %}
        {%- if ENABLE_HTTPS_REDIRECTION == 'y' %}
        - 'traefik.http.middlewares.grafana-redirectscheme.redirectscheme.permanent=true'
        - 'traefik.http.middlewares.grafana-redirectscheme.redirectscheme.scheme=https'
        - 'traefik.http.routers.grafana.middlewares=docker-registry-redirectscheme'
        {%- endif %}
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: on-failure

networks:
  {{ TRAEFIK_NETWORK }}:
    external: true

volumes:
    prometheus_data:
    grafana_data:



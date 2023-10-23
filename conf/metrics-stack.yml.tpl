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
       - "traefik.http.routers.prometheus.rule=Host(`{{ PROMETHEUS_HOSTNAME }}}`)"
       - "traefik.http.routers.prometheus.service=prometheus"
       - "traefik.http.services.prometheus.loadbalancer.server.port=9090"
       - "traefik.docker.network={{ TRAEFIK_NETWORK }}"
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
      - inbound
    user: "104"
    deploy:
      labels:
        - "traefik.http.routers.grafana.rule=Host(`{{ GRAFANA_HOSTNAME }}`)"
        - "traefik.http.routers.grafana.service=grafana"
        - "traefik.http.services.grafana.loadbalancer.server.port=3000"
        - "traefik.docker.network={{ TRAEFIK_NETWORK }}"
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: on-failure

volumes:
    prometheus_data:
    grafana_data:

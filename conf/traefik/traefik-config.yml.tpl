http:
  middlewares:
    ipWhitelistMiddleware:
      ipWhiteList:
        sourceRange: 
          {%- for ip in IP_WHITELIST_RANGE.split(',') %}
          - "{{ ip.strip() }}"
          {%- endfor %}

entryPoints:
  web:
    address: ":80"
    {%- if IP_WHITELIST == 'y' %}
    middlewares:
      - ipWhitelistMiddleware
    {%- endif %}

  websecure:
    address: ":443"
    {%- if IP_WHITELIST == 'y' %}
    middlewares:
      - ipWhitelistMiddleware
    {%- endif %}

providers:
  docker:
    exposedByDefault: false
    network: "{{ TRAEFIK_NETWORK }}"

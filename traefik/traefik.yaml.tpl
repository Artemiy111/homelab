global:
  checkNewVersion: false
  sendAnonymousUsage: false

log:
  level: INFO

accessLog: {}

api:
  dashboard: true
  insecure: false

ping: {}

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
  websecure:
    address: ":443"
    http:
      tls:
        certResolver: letsencrypt
        domains:
          - main: ${DOMAIN}
            sans:
              - "*.${DOMAIN}"
  # Внутренний entrypoint для Prometheus-метрик; наружу не публикуется.
  metrics:
    address: ":8082"

metrics:
  prometheus:
    entryPoint: metrics

certificatesResolvers:
  letsencrypt:
    acme:
      email: ${LETSENCRYPT_EMAIL}
      storage: /letsencrypt/acme.json
      dnsChallenge:
        provider: rfc2136
        resolvers:
          - "1.1.1.1:53"
          - "1.0.0.1:53"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: traefiknet
    watch: true

  file:
    directory: /etc/traefik/dynamic
    watch: true
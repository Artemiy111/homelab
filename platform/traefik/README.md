# Traefik

Traefik — активный обратный прокси этого репозитория. Маршрутизаторы используют
HTTPS-точку входа `websecure`, а `web` перенаправляет HTTP-запросы на HTTPS.
Порты 80 и 443 привязаны только к адресу узла и не пробрасываются на
интернет-роутере.

Чарт Traefik разворачивается через `argocd/applications/traefik.yaml`. В этом
каталоге — `values.yaml`, `tlsstore.yaml` и общие middleware
(`oauth2-proxy.middleware.yaml`). Маршруты, включая дашборд, живут в Helm-чарте
`platform/homelab`.

Адрес узла для `externalIPs` в Git не хранится — он environment-specific и
задаётся при деплое:

```sh
helm upgrade --install traefik <чарт> -f values.yaml \
  --set service.spec.externalIPs[0]=<адрес-узла>
```

## TLS

TLS терминируется на entrypoint `websecure`; маршруты не задают `tls`.
Сертификат по умолчанию отдаёт TLSStore `default` (`tlsstore.yaml`) — это
wildcard-секрет `wildcard-tls` в namespace `traefik`. Общие middleware (forward
auth `oauth2-proxy`, `secure-headers`, `ratelimit-default`) объявлены в
`oauth2-proxy.middleware.yaml` в namespace `traefik`; маршруты ссылаются на них
cross-namespace (`allowCrossNamespace: true`).

## Панель

После переключения клиентов на Technitium DNS панель доступна по адресу
`https://traefik.example.com/dashboard/`. Завершающий слеш обязателен.

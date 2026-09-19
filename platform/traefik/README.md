# Traefik

Traefik — активный обратный прокси этого репозитория. Маршрутизаторы используют
HTTPS-точку входа `websecure`, а `web` перенаправляет HTTP-запросы на HTTPS.
Порты 80 и 443 привязаны только к адресу `192.0.2.10` и не пробрасываются на
интернет-роутере.

Чарт Traefik разворачивается через `argocd/applications/traefik.yaml`. В этом
каталоге — `values.yaml`, `tlsstore.yaml`, общие middleware
(`oauth2-proxy.middleware.yaml`) и `route.yaml` дашборда; маршруты сервисов
лежат рядом с сервисами (`apps/<сервис>/route.yaml`).

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

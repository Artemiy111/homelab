# Traefik

Активный обратный прокси этого репозитория. Маршрутизаторы используют
HTTPS-точку входа `websecure`, а `web` перенаправляет HTTP-запросы на HTTPS.
Порты 80 и 443 привязаны только к адресу узла и не пробрасываются на
интернет-роутере.

Маршруты приложений живут рядом с приложениями, а не здесь. `Gateway` и
`GatewayClass` тоже описаны отдельно от values чарта: hostname слушателя и
`certificateRef` требуют домена из этих values. В values Traefik выключены
`gateway.enabled` и `gatewayClass.enabled`, иначе чарт создал бы второй Gateway
без сертификата.

## TLS

TLS терминируется на entrypoint `websecure`. Сертификат отдаёт `Gateway`
`homelab` — `certificateRef` на секрет `wildcard-casa-tls` в namespace
`traefik`. TLSStore `default` (`tlsstore.yaml`) указывает на тот же секрет: он
нужен как fallback для SNI, которого нет среди сертификатов, и раньше ссылался
на секрет старого домена — такой запрос получал чужой сертификат.

## Middleware

Общие middleware (forward auth `oauth2-proxy`, `secure-headers`,
`ratelimit-default`) объявлены в namespace `traefik`. `HTTPRoute` ссылается на них
через `ExtensionRef`, а он ищет `Middleware` **в namespace самого маршрута**:
`extensionRef` это `LocalObjectReference` без поля `namespace`. Поэтому в namespace
каждого потребителя лежит своя копия, а `allowCrossNamespace: true` на маршруты
`IngressRoute` больше не распространяется.

## Панель

После переключения клиентов на Technitium DNS панель доступна по адресу
`https://traefik.example.com/dashboard/`. Завершающий слеш обязателен.

Маршрут дашборда Argo не синхронизирует — порядок применения в `RUNBOOK.md`.

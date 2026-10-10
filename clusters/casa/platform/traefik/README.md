# Traefik

Traefik — активный обратный прокси этого репозитория. Маршрутизаторы используют
HTTPS-точку входа `websecure`, а `web` перенаправляет HTTP-запросы на HTTPS.
Порты 80 и 443 привязаны только к адресу узла и не пробрасываются на
интернет-роутере.

Чарт Traefik разворачивается через `clusters/casa/platform/traefik/app.yaml`. В этом
каталоге — `values.yaml`, `tlsstore.yaml`, общие middleware
(`oauth2-proxy.middleware.yaml`, `secure-headers.middleware.yaml`) и маршрут
дашборда (`dashboard.route.yaml`). Остальные маршруты живут рядом с
приложениями, в `clusters/casa/apps/<сервис>/k8s/route.yaml`.

Маршрут дашборда Argo не синхронизирует: у Application `traefik` в
`spec.sources` только чарт и `ref: values`, файла маршрута там нет. После
правки в git применять руками, иначе разойдётся с кластером (#858):

```sh
kubectl apply -f clusters/casa/platform/traefik/dashboard.route.yaml
```

`Gateway` и `GatewayClass` описаны в `clusters/casa/platform/traefik/manifests/`, а не
здесь: hostname слушателя и `certificateRef` требуют домена из values чарта
`clusters/casa/platform/homelab`. В values Traefik выключены `gateway.enabled`
и `gatewayClass.enabled`, иначе чарт создал бы второй Gateway без сертификата.

Адрес узла для `externalIPs` в Git не хранится — он environment-specific и
задаётся при деплое:

```sh
helm upgrade --install traefik <чарт> -f values.yaml \
  --set service.spec.externalIPs[0]=<адрес-узла>
```

## TLS

TLS терминируется на entrypoint `websecure`. Сертификат отдаёт `Gateway`
`homelab` — `certificateRef` на секрет `wildcard-tls` в namespace `traefik`
(`clusters/casa/platform/traefik/manifests/gateway-homelab.yaml`). TLSStore `default`
(`tlsstore.yaml`) остался для маршрутов, которые ещё не переведены на
Gateway API.

Общие middleware (forward auth `oauth2-proxy`, `secure-headers`,
`ratelimit-default`) объявлены в `oauth2-proxy.middleware.yaml` в namespace
`traefik`. `HTTPRoute` ссылается на них через `ExtensionRef`, а он ищет
`Middleware` **в namespace самого маршрута**: `extensionRef` это
`LocalObjectReference` без поля `namespace`. Поэтому в namespace каждого
потребителя лежит своя копия, а `allowCrossNamespace: true` на маршруты
`IngressRoute` больше не распространяется.

## Панель

После переключения клиентов на Technitium DNS панель доступна по адресу
`https://traefik.example.com/dashboard/`. Завершающий слеш обязателен.

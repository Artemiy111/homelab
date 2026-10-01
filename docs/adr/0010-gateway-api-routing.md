---
status: accepted
---

# Трафик обслуживает Traefik через Gateway API, маршруты живут рядом с приложениями

Маршрутизацию переводим с `Ingress`/`IngressRoute` на Gateway API (`HTTPRoute`).
Реализацией остаётся **тот же Traefik** — включается его dormant-провайдер
`kubernetesGateway`. Gateway и его слушатели — платформенный компонент в
`platform/homelab/templates/gateway/` (в чарте, потому что hostname слушателя
и `certificateRef` требуют домена из его `values.yaml`), а `HTTPRoute` уезжает в
`apps/<сервис>/k8s/` рядом с приложением, и
`platform/homelab/templates/routes/` исчезает.

## Considered Options

- **Envoy Gateway рядом с Traefik** — эталонная реализация, полный conformance.
  Отклонено: это второй data plane на одноузловом кластере, ему нужен второй
  LoadBalancer-адрес (иначе конфликт 80/443), и весь стек `Middleware` переписывается
  заново. Обещание смены Traefik на « Gateway API-native контроллер » откладывается
  на то время, когда Gateway API перестанет быть входом в Traefik.
- **Traefik как реализация Gateway API** — выбрано. Нет второго прокси, тот же
  `wildcard-tls`, та же логика `Middleware`. Цена признана и зафиксирована ниже.
- **Выпилить Traefik целиком** — невозможно, пока маршруты используют `Middleware`.

## Consequences

- **`Middleware` остаётся навсегда.** Traefik-овские `Middleware` в `HTTPRoute`
  работают только через `ExtensionRef`, а он завязан на CRD-провайдер:
  `pkg/config/static/static_config.go:356` регистрирует фильтр из
  `kubernetesCRD`, и без него Gateway-провайдер возвращает
  `unsupported filter extension ref` и не строит роутер. То есть «избавиться от
  IngressRoute» можно, «избавиться от Traefik CRD» — нет. Авторизация
  (oauth2-proxy), заголовки и rateLimit остаются Traefik-специфичными.
- **Gateway API CRD ставятся отдельно.** Chart 41.4.0 их не везёт (убрали в
  40.2.0: CRD не принадлежат Traefik), `skipCrds: true` на них не действует.
  Версия — v1.6.2 standard, как в доках Traefik v3.7; README чарта с указанием
  v1.5.1 устарел.
- **Приоритет роутеров несовместим.** Gateway-роутер получает приоритет ~10000 от
  длины правила, CRD-роутер — длину строки (~24) или явный `priority:`. На
  одном хосте Gateway молча перебивает CRD без warning'а. Поэтому `HTTPRoute`
  нельзя применять раньше, чем удалён `IngressRoute`: иначе старый маршрут не
  «продолжит работать», а будет незаметно вытеснен.
- **`Middleware` в `HTTPRoute` ищется в namespace маршрута, а не в `traefik`.**
  `extensionRef` — это `LocalObjectReference` без поля `namespace`, а
  `loadHTTPRouteFilterExtensionRef` передаёт в колбэк namespace самого
  `HTTPRoute`. Проверено на стенде: ссылка из `monitoring` на `secure-headers`
  даёт `middleware "monitoring-secure-headers@kubernetescrd" does not exist`.
  Поэтому `oauth2-proxy`, `secure-headers` и `ratelimit-default` размножены по
  namespace'ам потребителей, а `allowCrossNamespace: true` на `HTTPRoute`
  не действует. Обратная сторона: `kubernetesCRD` нельзя выключить, пока
  жив forward auth, даже если остальные маршруты переведены на нативные
  фильтры.
- **`nativeLB` переносится аннотацией на Service.** В `HTTPRoute` опции
  per-backend нет, и `nativeLBByDefault` включать глобально нельзя. Для
  hostNetwork-подов это не косметика: endpoint сервиса — адрес узла, и без
  nativeLB Traefik при dial-е попадает сам в себя (`node:80` отдаёт 404 от
  Traefik, `clusterIP:80` — 200 от приложения). Решение —
  `traefik.io/service.nativelb: "true"` на Service, что в
  `pkg/provider/kubernetes/gateway/kubernetes.go:1038` перекрывает
  `NativeLBByDefault`. Затрагивает home-assistant, talk-hpb и livekit.
- **Apex-домен требует отдельного слушателя.** `*.example.com` не
  пересекается с `example.com` (`findMatchingHostname` проверяет `HasSuffix`
  по `*.example.com`), поэтому для `/.well-known/matrix/*` добавлен слушатель
  `apex`.
- **Потеря шаблонизации домена.** Сейчас 49 маршрутов берут
  `{{ .Values.config.domain }}`; в `apps/` шаблонов нет. Смена домена (#672)
  становится правкой N файлов, а не одного `values.yaml`.
- **Две вещи не перенесены, потому что нечего переносить.** `elk` выведен из
  эксплуатации (#617), его `ServersTransport kibana-insecure` удалён вместе с
  маршрутом, а не потерян при миграции. `scheme: h2c` у zitadel: в
  Traefik-Gateway API схемы для `backendRef` нет вообще, но и не понадобилось —
  HTTPRoute определяет протокол по Upgrade-заголовкам, и gRPC-шлюз zitadel
  работает через обычный `HTTP`.
- **Не покрыто миграцией:** публикация адреса через `externalIPs` (deprecated в
  Kubernetes 1.36, CVE-2020-8554) — отдельная задача с возвратом MetalLB.

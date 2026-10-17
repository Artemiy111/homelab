# Argo CD

GitOps-контроллер кластера: источник правды — `main`, root-приложение
раскатывает `Application` из `clusters/casa/`. Параметры установки — в
`bootstrap/argocd-values.yaml`: это отклонения от дефолтов чарта, а не манифесты
кластера.

## Вход

Панель Argo обслуживается `HTTPRoute` на собственном self-managed логине,
дальше OIDC через authentik. Middleware `oauth2-proxy` к нему **не подключен
намеренно**: forward auth поверх сгорает — ломает сессию Argo и его CLI.
`secure-headers` подключён, `ratelimit-default` нет: UI Argo постоянно опрашивает
API, и лимит 100/50 срабатывает при обычном просмотре синка.

`secure-headers` продублирован в каждом namespace, где его использует
`ExtensionRef`: ссылка в `HTTPRoute` ищет `Middleware` рядом с маршрутом, а не
в `traefik`. Оригинал — `clusters/casa/platform/traefik/manifests/oauth2-proxy.middleware.yaml`.

## Порядок применения

Порядок задают `argocd.argoproj.io/sync-wave`. Шаг 10 — чтобы стадию можно было
вставить между соседними, не перенумеровывая все юниты.

| Волна | Что применяется |
|---|---|
| 0 | `gateway-api`, `namespaces`, `priorityclasses` |
| 10 | операторы и их CRD, хранилище: `cert-manager`, `cloudnative-pg`, `mariadb-operator`, `vault-secrets-operator`, `victoria-metrics-operator`, `vpa`, `trivy-operator`, `elastic-operator`, `falco`, `longhorn`, `snapshot-controller`, `local-path-provisioner`, `local-storage` |
| 20 | платформа и то, от чего зависят приложения: `traefik`, `vault`, `monitoring`, UI, `dns01-webhook` и `technitium` — на нём стоит выпуск wildcard-сертификата |
| 30 | кластеры баз: `cnpg`, `mariadb` |
| 40 | приложения |

Внутри `cnpg` и `mariadb` та же логика: секреты ролей → кластер (10) → база (20)
→ пользователь и его права (20).

Волна задаёт порядок **применения**, а не ожидание готовности. Argo ждёт
`Healthy` у ресурсов волны, только когда у ресурса есть health-проверка: у
`Deployment`, `PVC` и прочих встроенных она есть, у CR — только если задан
`resource.customizations.health.*` (для CNPG и MariaDB он в
`bootstrap/argocd-values.yaml`), а у `argoproj.io/Application` с Argo 1.8 её в
поставке нет. Поэтому `Application` считается применённым сразу после apply:
волны упорядочивают создание приложений, но не их готовность, а недостающие
зависимости — CR без CRD, под без секрета — добираются `retry` у приложения и
ретраями самих операторов.

Установка, бутстрап, обновление релиза, правила проектов и разборы — в
`RUNBOOK.md`.

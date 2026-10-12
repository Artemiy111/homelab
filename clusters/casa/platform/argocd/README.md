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

Установка, бутстрап, обновление релиза, правила проектов и разборы — в
`RUNBOOK.md`.

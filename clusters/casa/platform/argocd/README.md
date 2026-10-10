# Argo CD

## Вход

Панель Argo обслуживается `HTTPRoute` (`route.yaml`) на собственном
self-managed логине, дальше OIDC через authentik. Middleware `oauth2-proxy`
к нему **не подключен намеренно**: forward auth поверх сгорает — ломает
сессию Argo и его CLI. `secure-headers` подключён, `ratelimit-default` нет:
UI Argo постоянно опрашивает API, и лимит 100/50 срабатывает при обычном
просмотре синка.

## Состав каталога

| Файл | Что делает |
|---|---|
| `route.yaml` | `HTTPRoute` `argocd.<домен>` на `argocd-server:80` |
| `secure-headers.middleware.yaml` | копия общего middleware в namespace `argocd` |

`secure-headers` продублирован в каждом namespace, где его использует
`ExtensionRef`: ссылка в `HTTPRoute` ищет `Middleware` рядом с маршрутом, а не
в `traefik`. Оригинал — `clusters/casa/platform/traefik/oauth2-proxy.middleware.yaml`.

Параметры установки самого Argo CD — `bootstrap/argocd-values.yaml`, это другой
каталог: отклонения от дефолтов чарта, а не манифесты кластера.

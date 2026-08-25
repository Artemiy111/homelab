# OAuth2 Proxy

Forward auth перед приложениями без своей авторизации. Сам никого не логинит:
при отсутствии сессионной cookie отправляет браузер на форму ZITADEL, а после
входа пропускает запрос и подставляет identity-заголовки.

Ключевые флаги:
- `upstream=static://202` — oauth2-proxy НЕ проксирует трафик приложения, а
  только аутентифицирует (режим forwardAuth для Traefik);
- `reverse-proxy=true` — доверяет `X-Forwarded-*` от Traefik. Без этого
  oauth2-proxy теряет хост исходного запроса и после логина редиректит на корень
  своего хоста (`oauth.…`) вместо приложения.

## Как подключено

- Traefik middleware `oauth2-proxy@file` (см. `traefik/dynamic/middleware.yaml`)
  делает forwardAuth на `http://oauth2-proxy:4180`.
- Роутер защищаемого сервиса добавляет этот middleware; сейчас подключён к
  Structurizr (`structurizr/compose.yaml`) и к WUD/Cup
  (`image-updates/compose.yaml`).
- Публичный host `oauth.example.com` нужен для OIDC callback; cookie
  общий (`cookie-domain=.example.com`), поэтому повторный вход в другие
  сервисы не требуется.

## Настройка

1. В ZITADEL создать OIDC-приложение с redirect URI
   `https://oauth.example.com/oauth2/callback`.
2. `bash ./init.sh` создаёт `oauth2-proxy/.env` со случайным
   `OAUTH2_PROXY_COOKIE_SECRET`; осталось вписать client_id и client_secret
   из шага 1.
3. Запуск из корня репозитория — с секретами в окружении:
   `bash scripts/bootstrap-platform.sh oauth2-proxy`.

## Что получает upstream

- `X-Auth-Request-User`, `X-Auth-Request-Email` — прокидываются Traefik'ом через
  `authResponseHeaders` из `oauth2-proxy@file`;
- `X-Forwarded-User`, `X-Forwarded-Email`, `X-Forwarded-Groups` — от
  `--pass-user-headers`.

Приложение обязано доверять этим заголовкам только от прокси: прямой доступ к
upstream должен быть закрыт, а заголовки — перезаписываться. Проверку отрицательного
сценария см. в `docs/research/authentication-services.md` (этап 3).

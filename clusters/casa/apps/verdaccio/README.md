# Verdaccio

Verdaccio — npm-реестр с **uplink-прокси** на `registry.npmjs.org`, используемый
как **pull-through кэш** npm-пакетов для CI и локальной разработки. Первый
запрос пакета идёт в upstream, дальше тарболлы отдаются из локального
хранилища — недоступность или rate-limit npmjs не ломает `bun install`.

## Как это работает

- Verdaccio слушает npm-протокол: метаданные пакета (`GET /<pkg>`) и тарболлы.
- `uplinks.npmjs` — прокси на `registry.npmjs.org`; `packages` с `proxy: npmjs`
  отправляет неизвестные пакеты в uplink и кэширует ответы в `storage`.
- Режим read-only: `access: $all` (анонимное чтение), `max_users: -1` (вход и
  регистрация выключены), `publish` не задан (публикация запрещена).
- Проба готовности — `GET /-/ping`.
- В образе пользователь `verdaccio` (uid `10001`), порт `4873`; образ по
  умолчанию слушает `[::]`, поэтому `VERDACCIO_ADDRESS=0.0.0.0`.
- `maxage: 2m` задаёт TTL метаданных в uplink-кэше: тарболл иммутабелен, а
  метаданные пакета меняются при новых релизах.

`config/config.yaml` попадает в ConfigMap через `configMapGenerator`: kustomize
добавляет хэш содержимого к имени ConfigMap и переписывает ссылку в Deployment,
поэтому правка конфига сама запускает rollout (SoT — файл в git, а не ConfigMap
в кластере).

## Как подключить клиента

Внутри кластера реестр — `http://verdaccio.verdaccio.svc.cluster.local/`
(порт 80), с машины разработчика — по маршруту Traefik `https://npm.<домен>/`.
Маршрут без аутентификации (npm/bun не умеют forward auth), поэтому доступен
только в LAN/Tailscale.

`bun install --frozen-lockfile` резолвит пакеты по этой настройке; `bun.lock`
хранит `name@version` и `sha512`, а не адреса реестра, поэтому смена реестра не
требует перегенерации lockfile. Для `npm` то же самое — `.npmrc`
(`registry=`) или `NPM_CONFIG_REGISTRY`.

Эксплуатация — в `RUNBOOK.md`.

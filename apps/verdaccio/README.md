# Verdaccio

Verdaccio — npm-реестр с **uplink-прокси** на `registry.npmjs.org`, используемый
как **pull-through кэш** npm-пакетов для CI и локальной разработки. Первый
запрос пакета идёт в upstream, дальше тарболлы отдаются из локального
хранилища — недоступность или rate-limit npmjs не ломает `bun install`.

| | |
|---|---|
| Namespace | `verdaccio` |
| Развёртывание | манифестами `apps/verdaccio/k8s/` (`kubectl apply -f`) |
| Образ | `verdaccio/verdaccio:6.10.4` (пин по тегу и дайджесту, amd64) |
| Данные | PVC `verdaccio-data` на `longhorn` (кэш, потеря не страшна) |
| API | `http://verdaccio.verdaccio.svc.cluster.local:4873` — только внутри кластера |
| Потребитель | CI (`commitlint.yml`), локальный `bun install` |

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

## Развёртывание

```sh
kubectl apply -f apps/verdaccio/k8s/
kubectl -n verdaccio get pods,pvc,svc
```

## Как подключить клиента

CI и локальная разработка указывают реестр перед установкой:

```
npm_config_registry=http://verdaccio.verdaccio.svc.cluster.local:4873/
```

`bun install --frozen-lockfile` резолвит пакеты по этой настройке; `bun.lock`
хранит `name@version` и `sha512`, а не адреса реестра, поэтому смена реестра не
требует перегенерации lockfile. Для `npm` то же самое — `.npmrc`
(`registry=`) или `NPM_CONFIG_REGISTRY`.

Хостам вне кластера нужен маршрут (например `npm.<домен>` через Traefik) —
пока не сделано.

## Размер кэша и очистка

Том — `longhorn`, 1Gi, без `Retain`: кэш восстановим. Если том переполнится,
проще увеличить PVC или удалить `verdaccio-data` (Verdaccio скачает нужное
заново). Встроенной эвикции по размеру у Verdaccio нет.

## Проверка на живом стенде

1. `kubectl -n verdaccio get pods,pvc,svc` — под `Running`.
2. Изнутри кластера в окружении с пустым кэшем:

   ```sh
   npm_config_registry=http://verdaccio.verdaccio.svc.cluster.local:4873/ \
     npm view @commitlint/cli version
   ```

   В логах Verdaccio виден запрос в uplink.
3. Повторить — пакет отдаётся из хранилища, в логах нет обращения к
   `registry.npmjs.org`.
4. Симуляция падения upstream: сломать `uplinks.npmjs.url` в конфиге (или
   закрыть egress) — уже закэшированный пакет всё равно отдаётся.

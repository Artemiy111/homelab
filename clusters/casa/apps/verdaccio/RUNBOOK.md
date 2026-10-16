# Verdaccio: эксплуатация

## Подключение клиента

CI и локальная разработка указывают реестр перед установкой:

```
npm_config_registry=http://verdaccio.verdaccio.svc.cluster.local/
```

С машины разработчика тот же реестр доступен по маршруту Traefik:

```
npm_config_registry=https://npm.<домен>/ bun install
```

## Размер кэша и очистка

Том — `longhorn`, 1Gi, без `Retain`: кэш восстановим. Если том переполнится,
проще увеличить PVC или удалить `verdaccio-data` (Verdaccio скачает нужное
заново). Встроенной эвикции по размеру у Verdaccio нет.

## Проверка на живом стенде

1. `kubectl -n verdaccio get pods,pvc,svc` — под `Running`.
2. Изнутри кластера в окружении с пустым кэшем:

   ```sh
   npm_config_registry=http://verdaccio.verdaccio.svc.cluster.local/ \
     npm view @commitlint/cli version
   ```

   В логах Verdaccio виден запрос в uplink.
3. Повторить — пакет отдаётся из хранилища, в логах нет обращения к
   `registry.npmjs.org`.
4. Симуляция падения upstream: сломать `uplinks.npmjs.url` в конфиге (или
   закрыть egress) — уже закэшированный пакет всё равно отдаётся.

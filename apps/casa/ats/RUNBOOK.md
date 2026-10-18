# ATS: эксплуатация

## Как добавить origin

Добавить строку в `config/remap.config` (префикс → HTTPS-база) и, если origin
отдаёт файлы без `Cache-Control`, — `dest_domain=<хост> ttl-in-cache=<срок>` в
`config/cache.config`. Если origin редиректит на другой хост (как
`github.com` → CDN), хост-цель тоже должен быть в `cache.config`. Достаточно
закоммитить — rollout произойдёт сам.

## Как подключить клиента

Подставить базовый адрес кэша вместо публичного хоста, сохранив путь:

```
# вместо https://github.com/cli/cli/releases/download/...
curl http://ats.ats.svc.cluster.local/github/cli/cli/releases/download/...
```

Там, где инструмент умеет менять источник целиком, удобнее задать его целиком:

```
GO_DOWNLOAD_BASE_URL=http://ats.ats.svc.cluster.local/godev          # go.dev/dl
RUSTUP_DIST_SERVER=http://ats.ats.svc.cluster.local/rust             # static.rust-lang.org
```

Кэш доступен только внутри кластера (ClusterIP). Внешний маршрут Traefik
намеренно не заведён: профиль нагрузки — CI и провижининг, а открытый кэш
наружу расширяет поверхность атаки без пользы.

## Размер кэша и очистка

Том — `longhorn`, 5Gi, без `Retain`. Удалить объект из кэша (токен взять из
секрета сервиса):

```sh
curl -X PURGE -H "X-ATS-Purge: $ATS_PURGE_TOKEN" \
  http://ats.ats.svc.cluster.local/github/<path>
```

Плагин привязывает PURGE ко всему правилу remap: запрос с секретом удаляет
содержимое этого origin'а.

Удалить весь кэш: удалить PVC `ats-cache` (ATS заполнит заново).

## Проверка на живом стенде

1. `kubectl -n ats get pods,pvc,svc` — под `Running`, PVC `Bound`.
2. Холодный запрос через кэш:

   ```sh
   curl -fsS -o /tmp/bun.zip -w '%{http_code} %{size_download}\n' \
     http://ats.ats.svc.cluster.local/github/oven-sh/bun/releases/download/bun-v1.4.0/bun-linux-x64.zip
   sha256sum /tmp/bun.zip
   ```

   Ожидаемый sha256 совпадает с `apps/casa/rustfs/manifests/artifacts.tsv`
   (`2d03fb5f...2fe452`). Важно, что вернулся **файл**, а не `302`.
3. Повторный запрос — быстрее, из кэша: `GET2 t≈0.15s` против `GET1 t≈1.0s`,
   счётчик `traffic_ctl metric get proxy.process.http.cache_hit_fresh` растёт.
4. `curl -X PURGE -H "X-ATS-Purge: <секрет>" <url>` возвращает `200` с телом
   `PURGED <origin>`, и следующий запрос снова идёт в upstream. Проверить
   персистентность: `/var/cache/trafficserver/purge-<origin>` на PVC содержит
   выросший generation id, и после рестарта пода он читается (ошибок
   `remap_purge` в `diags.log` для этого origin'а нет).

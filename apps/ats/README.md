# ATS

Apache Traffic Server (ATS) — обратный прокси с **дисковым HTTP-кэшем**,
используемый как generic-кэш для бинарных артефактов, которые тянутся по
обычным URL: релизы GitHub, `go.dev`, `static.rust-lang.org`, `get.helm.sh`,
`archive.apache.org`, `download.docker.com`, `pkgs.tailscale.com`.

Это «слой 2» поверх протокольных зеркал: Zot (OCI), Verdaccio (npm), Athens
(Go) понимают свои протоколы, а произвольные HTTPS-файлы — нет. RustFS-зеркало
закрывает их перечислением каждого артефакта; ATS вместо этого кэширует по URL
из **allowlist**. Обоснование выбора ATS — в
`docs/research/generic-http-cache-mirrors.md`.

| | |
|---|---|
| Namespace | `ats` |
| Развёртывание | `kubectl apply --server-side --field-manager=homelab -k apps/ats` (kustomize) |
| Образ | `trafficserver/trafficserver:10.2.0` (пин по тегу и дайджесту, amd64) |
| Данные | PVC `ats-cache` на `longhorn` 5Gi (кэш, потеря не страшна) |
| API | `http://ats.ats.svc.cluster.local` — внутри кластера |
| Потребитель | CI, Ansible-провижининг хоста |

## Как это работает

- ATS отдаётся через Service на `:80`. Клиент адресует **наш** хост с префиксом
  origin'а: `http://ats.ats.svc.cluster.local/github/<path>`.
- `remap.config` — это allowlist: каждое `map`-правило переводит клиентский
  префикс в origin-базу. Запросов вне правил ATS не обсуживает
  (`url_remap.remap_required: 1`), открытым прокси он не становится.
- К origin ATS идёт по **HTTPS** с SNI (`ssl.client.sni_policy: host`) и
  проверкой сертификата (`verify.server.policy: ENFORCED`).
- **Follow редиректов.** GitHub Releases отдаёт не файл, а `302` на подписанный
  CDN (`release-assets.githubusercontent.com`). Дефолт ATS —
  `http.number_of_redirections: 0`, то есть редирект не разворачивается. Мы
  ставим `3`, чтобы ATS сам прошёл на CDN и закэшировал **файл**, а не ответ
  `302` — это ключевая причина, по которой выбран именно ATS (nginx так не
  умеет, Envoy cache filter не кэширует `302`).
- **Политика кэша.** Дефолт `http.cache.required_headers: 2` кэширует только
  объекты с явным `Cache-Control`/`Expires`, которых у релизных ассетов нет.
  Поэтому в `records.yaml` требование снято, а TTL задан явно в `cache.config`
  по `dest_domain`. В `cache.config` указаны и хосты CDN после редиректа.
- Хранилище — `storage.config`: файл кэша фиксированного размера на PVC. ATS
  создаёт файл при старте, поэтому размер должен быть **меньше** объёма PVC с
  запасом: Longhorn отдаёт файловой системе чуть меньше заявленного (том 5Gi →
  ~4.9G), и кэш впритык не создастся (ATS пишет `cache unable to open ... :
  Permission denied` и стартует с отключённым кэшем). Поэтому PVC 5Gi, кэш 4G.

## Конфигурация

Файлы в `config/` собираются в ConfigMap через `configMapGenerator` в
`kustomization.yaml`: kustomize добавляет хэш содержимого к имени и переписывает
ссылку в Deployment, поэтому правка конфига сама запускает rollout (SoT — файл
в git, а не ConfigMap в кластере).

| Файл | Назначение |
|---|---|
| `records.yaml` | follow редиректов, политика кэша, TLS к origin |
| `remap.config` | allowlist origin'ов (префикс → HTTPS-база) |
| `cache.config` | TTL по `dest_domain` |
| `storage.config` | путь и размер дискового кэша |
| `plugin.config` | `stats_over_http.so` (метрики) |
| `ip_allow.yaml` | ACL методов (PURGE из приватных сетей) |
| `run.sh` | entrypoint: копирует конфиги и подставляет секрет PURGE |

ATS читает конфиги из **`/opt/etc/trafficserver`** (там они лежат в образе, не
в `/etc/trafficserver`). Опцией `--conf_dir` этот каталог подменить нельзя: по
usage она помечена как «config dir to verify» и действует только для команд
`-C` (`verify_config` и т. п.), а не для запуска.

Поэтому ConfigMap монтируется целиком в staging-каталог `/run/ats-src`, а
`run.sh` на старте копирует оттуда шесть своих файлов в
`/opt/etc/trafficserver` и запускает `traffic_server`. Так подстановка секрета
PURGE реально попадает в загружаемый `remap.config`, а дефолты образа
(`body_factory/`, `strategies.yaml`, `ssl_multicert.config` и пр.) не
затрагиваются.

### Права и `fsGroup`

`traffic_server` всегда сбрасывает привилегии на `proxy.config.admin.user_id`
(в образе — `nobody`, uid/gid 65534; настройка read-only) и уже от него пишет
`cache.db`. Тому Longhorn принадлежит root, поэтому в `securityContext` пода
задан `fsGroup: 65534` — групповая запись в том для `nobody`.

### PURGE и секрет

Плагин инвалидации (`remap_purge.so`) подключается **в `remap.config`** через
`@plugin=` (он remap-плагин, не глобальный — в `plugin.config` его быть не
должно). Ему обязательны `--secret` и `--state-file`; без них он не
инициализируется. Секрета в git быть не должно, поэтому `run.sh` на старте
подставляет `$(ATS_PURGE_TOKEN)` из Secret в `remap.config` (см. «Конфигурация»
выше).

Secret `ats` приходит из `k8s/sealedsecret.yaml` (значение также в
`secrets.enc.env`); имя ключа — `ATS_PURGE_TOKEN`.

`PURGE` защищён секретом, но по умолчанию `ip_allow.yaml` образа разрешает
этот метод только с localhost (иначе — `403`). Свой `config/ip_allow.yaml`
разрешает приватным сетям кластера все методы; вне них разрушительные методы
(`PURGE`/`PUSH`/`DELETE`/`TRACE`) закрыты. Правило с ограниченным списком
методов разрешает только их, а остальные для этого диапазона запрещает, поэтому
для приватных сетей указан `methods: ALL`, а защиту `PURGE` даёт секрет.

`PURGE` инвалидирует **всё правило remap** (весь origin), а не один объект:
плагин увеличивает generation id, и объекты прежнего поколения в кэше
становятся невалидными. `PURGE` на URL, которого нет в кэше, возвращает `404`,
на существующий — `200` (успешный ответ — `200` с телом `PURGED <origin>`).

Generation id хранится в `--state-file` на PVC (`/var/cache/trafficserver/
purge-<origin>`), поэтому переживает рестарт пода. При старте плагин пишет
`ERROR Can not open file`, если файла нет; `run.sh` предсоздаёт пустые файлы от
имени `nobody`, чтобы этот штатный случай не засорял лог.

## Развёртывание

```sh
kubectl apply --server-side --field-manager=homelab -k apps/ats
kubectl -n ats get pods,pvc,svc
```

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

## Ограничения

- **Только allowlist.** URL, которых нет в `remap.config`, не обслуживаются.
- **URL внутри экшенов не перенаправить.** `uses: actions/setup-java` и
  подобные сами строят адреса (`api.github.com`, `raw.githubusercontent.com`),
  и без MITM подменить их нельзя — эта часть закрывается RustFS-зеркалом и
  предзаполнением tool-cache раннера (см. `apps/forgejo/README.md`, issue #211).
- **Нет `/metrics`.** Метрики отдаёт плагин `stats_over_http` в своём формате;
  для Prometheus нужен внешний exporter.
- **Кэш не резервируется под объект целиком без TTL.** Объект, попавший в кэш
  по политике, живёт до истечения TTL; принудительно — `PURGE`.
- Эвикции «по размеру» как таковой нет: ATS вытесняет объекты по своей
  стратегии, но при заполнении тома крупными объектами возможен рост до отказа
  записей. При переполнении проще увеличить PVC и размер в `storage.config`
  либо удалить `ats-cache` (кэш восстановим).

## Размер кэша и очистка

Том — `longhorn`, 5Gi, без `Retain`. Удалить объект из кэша (секрет — из
`secrets.enc.env` на сервере, `sops -d`):

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

   Ожидаемый sha256 совпадает с `apps/rustfs/artifacts.tsv`
   (`2d03fb5f...2fe452`). Важно, что вернулся **файл**, а не `302`.
3. Повторный запрос — быстрее, из кэша: `GET2 t≈0.15s` против `GET1 t≈1.0s`,
   счётчик `traffic_ctl metric get proxy.process.http.cache_hit_fresh` растёт.
4. `curl -X PURGE -H "X-ATS-Purge: <секрет>" <url>` возвращает `200` с телом
   `PURGED <origin>`, и следующий запрос снова идёт в upstream. Проверить
   персистентность: `/var/cache/trafficserver/purge-<origin>` на PVC содержит
   выросший generation id, и после рестарта пода он читается (ошибок
   `remap_purge` в `diags.log` для этого origin'а нет).

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
| Развёртывание | `kubectl apply -k apps/ats` (kustomize) |
| Образ | `trafficserver/trafficserver:10.2.0` (пин по тегу и дайджесту, amd64) |
| Данные | PVC `ats-cache` на `longhorn` 5Gi (кэш, потеря не страшна) |
| API | `http://ats.ats.svc.cluster.local:8080` — внутри кластера |
| Потребитель | CI, Ansible-провижининг хоста |

## Как это работает

- ATS слушает `:8080`. Клиент адресует **наш** хост с префиксом origin'а:
  `http://ats.ats.svc.cluster.local:8080/github/<path>`.
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
  резервирует его целиком, поэтому размер в `storage.config` (5G) должен
  совпадать с `requests.storage` PVC.

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
| `run.sh` | entrypoint: подстановка секрета PURGE в `remap.config` |

Конфиги монтируются по `subPath` в **`/opt/etc/trafficserver`**: именно там
лежат конфиги в образе (не `/etc/trafficserver`). Монтировать каталог целиком
нельзя — перекроются дефолты образа (`body_factory`, `strategies.yaml`,
`sni.yaml` и т. д.).

### PURGE и секрет

Плагин инвалидации (`remap_purge.so`) подключается **в `remap.config`** через
`@plugin=` (он remap-плагин, не глобальный — в `plugin.config` его быть не
должно). Ему обязательны `--secret` и `--state-file`; без них он не
инициализируется. Секрета в git быть не должно, поэтому `run.sh` на старте
копирует конфиги в `/run/ats` (tmpfs) и подставляет `$(ATS_PURGE_TOKEN)` из
Secret, после чего запускает `traffic_server --conf_dir /run/ats`.

Secret `ats` приходит из `k8s/sealedsecret.yaml` (значение также в
`secrets.enc.env`); имя ключа — `ATS_PURGE_TOKEN`.

## Развёртывание

```sh
kubectl apply -k apps/ats
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
curl http://ats.ats.svc.cluster.local:8080/github/cli/cli/releases/download/...
```

Там, где инструмент умеет менять источник целиком, удобнее задать его целиком:

```
GO_DOWNLOAD_BASE_URL=http://ats.ats.svc.cluster.local:8080/godev          # go.dev/dl
RUSTUP_DIST_SERVER=http://ats.ats.svc.cluster.local:8080/rust             # static.rust-lang.org
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
  http://ats.ats.svc.cluster.local:8080/github/<path>
```

Плагин привязывает PURGE ко всему правилу remap: запрос с секретом удаляет
содержимое этого origin'а.

Удалить весь кэш: удалить PVC `ats-cache` (ATS заполнит заново).

## Проверка на живом стенде

1. `kubectl -n ats get pods,pvc,svc` — под `Running`, PVC `Bound`.
2. Холодный запрос через кэш:

   ```sh
   curl -fsS -o /tmp/bun.zip -w '%{http_code} %{size_download}\n' \
     http://ats.ats.svc.cluster.local:8080/github/oven-sh/bun/releases/download/bun-v1.4.0/bun-linux-x64.zip
   sha256sum /tmp/bun.zip
   ```

   Ожидаемый sha256 совпадает с `apps/rustfs/artifacts.tsv`
   (`2d03fb5f...2fe452`). Важно, что вернулся **файл**, а не `302`.
3. Повторный запрос — быстрее, без обращения к upstream. Проверить можно
   метрикой кэша (`traffic_ctl metric get proxy.process.http.cache_hit_fresh`)
   или временно убрав origin из `cache.config`/закрыв egress.
4. `curl -X PURGE -H "X-ATS-Purge: <секрет>" <url>` — содержимое origin'а
   удаляется из кэша.

# Generic HTTP/URL-кэш для бинарных артефактов: ATS, nginx, Varnish, Squid и «восходящие звёзды»

Дата проверки: 2026-09-23.

Дополнение к `docs/research/registry-lightweight-comparison.md` (тот документ про
**protocol mirrors**: OCI, npm, Go, apt). Здесь — только **произвольный HTTP**:
бинарники и релизные ассеты, которые CI и провижининг хоста тянут по
обычному HTTPS с `github.com`, `go.dev`, `static.rust-lang.org`, `get.helm.sh`,
`download.docker.com`, `pkgs.tailscale.com` и т. п. В прошлой редакции ATS был
помечен как «доки не проверились» — здесь он проверен и разобран, плюс добавлен
обзор новых проектов.

## 1. Область исследования

Задача — выбрать **generic reverse-proxy cache**: клиент адресует наш хост, хост
идёт в upstream, кэширует ответ по URL и отдаёт повторно. Нужны:

- кэш по URL без знания протокола пакетного менеджера (в отличие от Zot,
  Verdaccio, Athens);
- работа с **HTTPS-upstream как TLS-клиент** (SNI!), без MITM со стороны клиента;
- follow за 302 (см. §2) — это отдельное требование, а не деталь;
- allowlist upstream'ов, TTL/эвикция, purge, метрики, вменяемый образ для k8s.

Отдельно фиксируется **фундаментальный предел**: то, что action внутри job'а
тянет сам через `api.github.com`/`raw.githubusercontent.com`, generic-кэш
перехватить не может без MITM — потому что URL строит сам action, а не наш
ingress.

## 2. Почему это отдельный класс

### 2.1 GitHub Releases отдаёт 302 на подписанный CDN

Ссылка вида `https://github.com/<owner>/<repo>/releases/download/<tag>/<asset>`
не отдаёт файл напрямую. Проверено `curl -I` 2026-09-23 (хосты `helm/helm`,
`gitleaks/gitleaks`):

```
HTTP/2 302
location: https://release-assets.githubusercontent.com/...<signed query>
```

(полный подписанный `Location` не приводится: там короткоживущий токен, в
документ он не выносится — см. `docs/agents/information-handling.md`).

`@actions/tool-cache` скачивает через `@actions/http-client`, и у него серия
багов ровно на этом: относительные редиректы (`Invalid URL`) — [actions/toolkit#2226](https://github.com/actions/toolkit/issues/2226),
[#2227](https://github.com/actions/toolkit/pull/2227) (PR-фикс), «Invalid URL» в
целом — [#1692](https://github.com/actions/toolkit/issues/1692), зависания по
ETIMEDOUT на `185.199.109.133:443` (github.com) — [#1236](https://github.com/actions/toolkit/issues/1236),
скачивание «иногда 2 часа» — [#850](https://github.com/actions/toolkit/issues/850).
Симптомы подтверждаются у setup-bun: [#82](https://github.com/oven-sh/setup-bun/issues/82),
[#100](https://github.com/oven-sh/setup-bun/issues/100), [#55](https://github.com/oven-sh/setup-bun/issues/55).

Вывод: кэш, который **сам** ходит в upstream, должен уметь следовать 302 на
`release-assets.githubusercontent.com` и кэшировать **финальный** объект. Это
не «HTTP-деталь», а ядро задачи (см. §3, колонка «follow 3xx»).

### 2.2 Предел: action сам строит URL к GitHub API

Даже когда у action есть вход `mirror`, он **сначала** идёт на GitHub за
манифестом версий, и только потом качает бинарник с зеркала:

- [actions/setup-node#1285](https://github.com/actions/setup-node/issues/1285):
  при недоступном GitHub с self-hosted runner'а `getInfoFromManifest` «timeout
  waiting for GitHub» и до ветки скачивания с `mirror` дело не доходит;
- [actions/setup-python#1302](https://github.com/actions/setup-python/issues/1302)
  (добавление `mirror`/`mirror-token`): если `mirror` — это
  `raw.githubusercontent.com/{owner}/{repo}/{branch}`, манифест тянется через
  **GitHub REST API** (`api.github.com`), т. е. другой origin, чем self-mirror.

Значит, никакой reverse-proxy cache не перенаправит эти запросы: их URL заданы
внутри action'а. Обойти это можно только:

1. **MITM/transparent interception** (Squid SslBump) — не то, что нужно (см. §3);
2. предварительно наполнять tool-cache runner'а (`RUNNER_TOOL_CACHE` /
   `AGENT_TOOLSDIRECTORY`) — действия вообще не пойдут в сеть;
3. `mirror`/base-url входы — но они спасают только от **скачивания**, не от
   первичного обращения к GitHub (§4).

## 3. Сравнительная таблица кандидатов

Версии/даты — GitHub Releases API, теги, официальные сайты; звёзды — GitHub API;
размеры образов — метаданные реестров (Docker Hub tag API `images[].size`,
GHCR — сумма `layers[].size`), сжатые `linux/amd64`, проверено 2026-09-23.

### 3.1 Идентичность и ресурсы

| Кандидат | Версия (дата) | Лицензия | Язык | ★ GitHub | Образ (сжатый, amd64) | Активность |
| --- | --- | --- | --- | --- | --- | --- |
| **Apache Traffic Server** | `10.2.0` (тег 2026-08-12) | Apache-2.0 | C++ | 1987 | `trafficserver/trafficserver:10.2.0` — **100.9 MB** | pushed 2026-09-22 |
| **nginx** `proxy_cache` | `release-1.31.6` (2026-09-15) | BSD-2-Clause | C | 31710 | `nginx:stable` — **63.2 MB** | pushed 2026-09-16 |
| **Vinyl Cache** (ex-Varnish) | `9.1.0` (2026-09-16) | BSD-2-Clause | C | 4045 (старый репо, архив) | `varnish:9.0.4` — **132.5 MB** | см. §5.3 (переезд) |
| **Squid** | `SQUID_7_7` (2026-08-24) | GPL-2.0 | C++ | 3104 | `ubuntu/squid:latest` — **70.2 MB** | pushed 2026-09-22 |
| **Nexus CE raw proxy** | `3.96.3-01` (2026-09-22) | EPL-1.0 | Java | 2652 | `sonatype/nexus3:latest` — **484.2 MB** | pushed 2026-09-22 |
| **Envoy + cache filter** | `v1.39.1` (2026-08-27) | Apache-2.0 | C++ | 28974 | `envoyproxy/envoy:v1.39.1` — **73.7 MB** | pushed 2026-09-22 |
| **Souin** | `v1.7.9` (2026-09-16) | MIT | Go | 1006 | `darkweak/souin:v1.7.9` — **25.6 MB** | pushed 2026-09-18 |
| **Traefik** (плагин) | `v3.7.13` (2026-09-04) | MIT | Go | 64930 | `traefik:v3.7.13` — **55.2 MB** | pushed 2026-09-22 |
| **Caddy + cache-handler** | `cache-handler v0.17.0` (2026-09-17) | Apache-2.0 | Go | 393 | готового образа нет (xcaddy) | pushed 2026-09-17 |
| **Pingora** (фреймворк) | `0.9.0` (2026-09-09) | Apache-2.0 | Rust | 27511 | готового образа нет | pushed 2026-09-11 |
| **HAProxy** | `v3.4.0` (2026-06-03) | GPL-2.0 | C | 6871 | `haproxy:3.4.0` — **47.1 MB** | pushed 2026-09-21 |

### 3.2 Способности (главное)

| Кандидат | Тип | TLS к upstream (SNI) | HTTP/2 | Follow 302 | Дисковый кэш | Purge API | Prometheus | MITM нужен? |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **ATS** | pure reverse | **Да** (`remap` c `https://`, `proxy.config.ssl.client.*`) | Да (in/out) | **Да** (`proxy.config.http.number_of_redirections`, по умолч. **0**) | **Да** (`storage.yaml`) | Да (`remap_purge` + `PURGE`) | Не 1st-party (`stats_over_http` + exporter) | **Нет** |
| **nginx** `proxy_cache` | pure reverse | Да (`proxy_ssl_server_name`, по умолч. **off**) | Да (нюансы, §8) | **Нет** | Да (`proxy_cache_path`) | Нет в OSS (`proxy_cache_purge` — Plus) | Не 1st-party (exporter/VTS) | **Нет** |
| **Vinyl Cache** | pure reverse | **Сам нет**; TLS через haproxy off/onload | Да (через haproxy/`feature=+http2`) | Не документировано | Да (stevedore, `-s`) | Через VCL/VMOD | Через VMOD/exporter | **Нет**, но +haproxy |
| **Squid** | forward/reverse | Да (reverse `cache_peer` + `ssl`) | Ограниченно | Не документировано | Да | Через `squidclient PURGE` | Через exporter (`squid_exporter`) | **Да, только для прозрачного HTTPS** (`SslBump`) |
| **Nexus raw proxy** | pure reverse | Да | Да (JVM) | Да (HTTP-клиент сам разрешает) | Да | Да (REST) | Да (`/service/metrics/prometheus`) | **Нет** |
| **Envoy cache filter** | pure reverse | Да | Да | Нет (кэширует 200/301/308, не 302) | FS-backend помечен WIP | Нет REST | **Да, 1st-party** | **Нет** |
| **Souin** | pure reverse / плагин | Да | Да (зависит от хоста) | Не документировано | Да (Badger/Simplefs/…) | Да (REST) | **Да, 1st-party** | **Нет** |
| **Traefik** | ingress + плагин | Да | Да | — | Через Souin-плагин | Через Souin | Да (Traefik metrics) | **Нет** |
| **Caddy + cache-handler** | pure reverse | Да | Да | Не документировано | Да | Да (REST) | Да (API `prometheus`) | **Нет** |
| **Pingora** | фреймворк | (пишешь сам) | Да | — | Только `pingora-memory-cache` (RAM) | — | Библиотека | **Нет** |
| **HAProxy** | pure reverse | Да (`ssl`) | Да | Нет | **Нет — только RAM** | Нет | **Да, 1st-party** (`prometheus-exporter`) | **Нет** |

## 4. Официальные входы подмены источника

Проверено по `action.yml` на ветке `main` (номера строк — на 2026-09-23).

| Инструмент | Вход/переменная | Значение по умолчанию | Первичный источник |
| --- | --- | --- | --- |
| `actions/setup-node` | `mirror` (стр. 28), `mirror-token` (стр. 30) | node-versions на GitHub | [action.yml](https://github.com/actions/setup-node/blob/main/action.yml) |
| `actions/setup-python` | `mirror` (стр. 21), `mirror-token` (стр. 24) | `https://raw.githubusercontent.com/actions/python-versions/main` | [action.yml](https://github.com/actions/setup-python/blob/main/action.yml) |
| `actions/setup-go` | `go-download-base-url` (стр. 22) / env `GO_DOWNLOAD_BASE_URL` | `https://go.dev/dl` | [action.yml](https://github.com/actions/setup-go/blob/main/action.yml) |
| `actions/setup-java` | **нет** mirror/base-url; есть `jdkFile` (стр. 25, deprec.) и `mvn-*`-репозитории | дистрибутивы (Temurin и др.) качаются напрямую | [action.yml](https://github.com/actions/setup-java/blob/main/action.yml) |
| `rustup` | `RUSTUP_DIST_SERVER` (default `https://static.rust-lang.org`), `RUSTUP_UPDATE_ROOT` (default `…/rustup`) | static.rust-lang.org | [rustup env vars](https://rust-lang.github.io/rustup/environment-variables.html) |
| Helm | официальной mirror-переменной нет; базовый URL `get.helm.sh` | get.helm.sh | [helm install script](https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3) |
| sops / kubeseal / argocd / kubectl-cnpg / gitleaks | официального mirror-входа нет — только GitHub Releases assets | github.com | см. §2.1 |

Ключевой нюанс: **наличие `mirror` не отменяет обращение к GitHub** (§2.2,
setup-node#1285, setup-python#1302). Для setup-java официального способа
подменить источник нет вообще — только `jdkFile` (вручную положить файл) или
перехват (`api.adoptium.net`, `download.oracle.com`, …) через generic-кэш с
последующим переопределением через переменные/прокси окружения (если дистрибутив
их уважает).

## 5. Разбор по кандидатам

### 5.1 Apache Traffic Server `10.2.0`

- **Ресурсы.** Релиз: тег `10.2.0`, коммит 2026-08-12, [tags API](https://github.com/apache/trafficserver/tags).
  Образ `trafficserver/trafficserver:10.2.0` (Docker Hub) — **100.9 MB** сжатый
  amd64, обновлён 2026-08-19; Dockerfile'ы проекта — [contrib/docker](https://github.com/apache/trafficserver/tree/master/contrib/docker).
- **Pure reverse proxy.** `remap.config`: `map <from> <to>`, где `to` — `http`,
  **`https`**, `ws`, `wss`; есть `reverse_map` для перезаписи `Location` у
  origin-ответов, ACL-фильтры (`@action`, `@src_ip`), `.include` и `@volume`
  для выбора дискового тома: [remap.config](https://docs.trafficserver.apache.org/en/latest/admin-guide/files/remap.config.en.html).
- **TLS к upstream (SNI).** `https://`-replacement + записи
  `proxy.config.ssl.client.sni_policy`, `proxy.config.ssl.client.verify.server.policy`,
  `proxy.config.ssl.client.CA.cert.*`: [records.yaml](https://docs.trafficserver.apache.org/en/latest/admin-guide/files/records.yaml.en.html).
- **HTTP/2.** Вход (через `Listen … proto=http2;http`), выход — ALPN `h2`
  (`proxy.config.ssl.client.alpn_protocols`); лимиты
  `proxy.config.http2.max_concurrent_streams_in/out`: тот же records.yaml.
- **Follow 302 — критично.** `proxy.config.http.number_of_redirections` (по
  умолчанию **0**) — «maximum number of times Traffic Server does a redirect
  follow location on receiving a 3XX Redirect response»; есть
  `proxy.config.http.redirect.actions` (`routable:follow`). То есть ATS **сам**
  сходит по 302 GitHub на CDN и отдаст клиенту финальный объект: records.yaml.
- **Кэш.** Диск/тома — `storage.yaml` (раздел [Cache Storage](https://docs.trafficserver.apache.org/en/latest/admin-guide/storage/index.en.html));
  политики — `cache.config` (`ttl-in-cache`, `revalidate`, `pin-in-cache`,
  `never-cache`, `ignore-server-no-cache`), причём доки сами называют ручное
  задание политик антипаттерном: [cache.config](https://docs.trafficserver.apache.org/en/latest/admin-guide/files/cache.config.en.html).
- **Purge.** In-tree плагин `remap_purge` (метод `PURGE`): [plugins](https://docs.trafficserver.apache.org/en/latest/admin-guide/plugins/index.en.html).
- **Метрики.** Плагин `stats_over_http` (статистика по HTTP) — [Monitoring](https://docs.trafficserver.apache.org/en/latest/admin-guide/monitoring/index.en.html);
  **first-party Prometheus-эндпоинта нет** (в `plugins/` и `plugins/experimental/`
  только `stats_over_http`, `http_stats`, `system_stats`), нужен внешний
  exporter.
- **K8s.** Готового Helm-чарта/оператора нет; разворачивается обычным Deployment
  (образ с Docker Hub, конфиги монтируются). В multi-upstream — allowlist из
  `remap`-правил.

### 5.2 nginx `proxy_cache` (baseline)

- `proxy_cache_path` (диск), `proxy_cache`, `proxy_ssl_server_name on`
  (**по умолчанию off** — без него SNI upstream'у не уйдёт), `resolver` при
  `proxy_pass` с переменными: [ngx_http_proxy_module](https://nginx.org/en/docs/http/ngx_http_proxy_module.html).
- **Не следует за 302**: OSS nginx не имеет директивы follow-redirect; `Location`
  уходит клиенту, а `proxy_redirect` лишь переписывает заголовок. Значит, для
  GitHub Releases чистый nginx не кэширует финальный ассет (клиент уйдёт на CDN
  мимо кэша) — нужен либо upstream, отдающий 200, либо OpenResty/Lua.
  (Прямого «nginx не следует редиректам» в доках нет — это вывод из отсутствия
  директивы, см. §8.)
- **Purge**: `proxy_cache_purge` — **только NGINX Plus**, в OSS нет (сторонние
  модули не в счёт). **Prometheus**: first-party нет, нужен
  `nginx-prometheus-exporter` или `nginx-module-vts`.
- Вывод: остаётся **эталоном простоты**, но именно follow-302 и purge делают ATS
  предпочтительнее для GitHub Releases.

### 5.3 Vinyl Cache `9.1.0` (бывший Varnish Cache)

- **Важно, что изменилось.** Проект **переименован в Vinyl Cache** и **ушёл с
  GitHub**; репозиторий `varnishcache/varnish-cache` **архивирован**
  (`archived=true`), README: «IMPORTANT — THIS REPOSITORY HAS MOVED», новая
  площадка — Forgejo `code.vinyl-cache.org/vinyl-cache/vinyl-cache`:
  [Vinyl Cache has left github](https://vinyl-cache.org/organization/moving.html).
  Последний релиз — [Vinyl Cache 9.1.0 (2026-09-16)](https://vinyl-cache.org/releases/rel9.1.0.html).
  Лицензия — BSD-2-Clause (`SPDX-License-Identifier` в README старого репо).
- **TLS — сам не умеет.** «Vinyl Cache famously does not directly support TLS
  (SSL)»; документированный «TLSandwich» — haproxy как TLS-offload и TLS-onload,
  связь с `vinyld` по UDS + PROXY protocol. Для HTTP/2: `vinyld -p feature=+http2`
  и `alpn h2,http/1.1` в haproxy. Отдельно сказано, что TLS поддержка
  (TLSentinel) — в работе: [Configuring TLS with haproxy](https://vinyl-cache.org/tutorials/tls_haproxy.html).
  То есть для homelab это **+ ещё один компонент** (haproxy) или отказ от TLS.
- Кэширование — суть продукта (VCL, `ttl`, `beresp`), дисковый stevedore (`-s`),
  purge через VCL. Follow backend 302 в доках не описан (tip-страница
  [301/302 Redirects](https://vinyl-cache.org/tips/vcl/redirect.html) — про
  синтетические редиректы, не про follow).
- Docker-образ `varnish:9.0.4` (Docker Hub, обновлён 2026-09-19) — **132.5 MB**;
  тег `stable` — 122.0 MB.
- **Практический вывод:** мощный и «правильный» кэш, но из-за отсутствия своего
  TLS и переезда инфраструктуры для односервисного homelab это лишний компонент.

### 5.4 Squid (включая MITM-оговорку)

- **Прозрачный HTTPS требует MITM.** Документация прямо описывает `SslBump` как
  «man-in-the-middle attack from the overall network security point of view»,
  с предупреждениями про легальность/этику. Без bump зашифрованный трафик либо
  туннелируется (CONNECT), либо не проходит через Squid:
  [Squid HTTPS](https://wiki.squid-cache.org/Features/HTTPS). Следствия MITM:
  свой CA в trust store всех клиентов, поломка certificate pinning (Go-тулчейн,
  `rustup` с pinning, часть action'ов), расширение поверхности атаки.
- **Reverse proxy без MITM.** Squid умеет terminate TLS на `https_port` и
  работать как accel/reverse-proxy; для TLS-к-origin используется `cache_peer`
  с флагом `ssl` (см. §8 — здесь не проверено отдельной страницей).
- Прочее: `SQUID_7_7` (2026-08-24), GPL-2.0, образ `ubuntu/squid` — 70.2 MB;
  purge — `squidclient -m PURGE`; Prometheus — сторонний `squid_exporter`.
- **Вывод:** для CI подходит reverse-proxy режим без MITM, но это не основной
  кейс Squid, а follow-302/allowlist настраиваются заметно менее прозрачно, чем
  в ATS.

### 5.5 Nexus CE raw proxy

- Уже разобран в `registry-lightweight-comparison.md`: raw proxy умеет
  проксировать статические деревья (пример из доков — `https://nodejs.org/dist/`),
  один upstream на репозиторий: [Raw Repositories](https://help.sonatype.com/en/raw-repositories.html);
  требования Small — **2 CPU / 8 GB RAM / 20 GB**, контейнерный деплой с H2 в k8s
  не поддержан → PostgreSQL: [System requirements](https://help.sonatype.com/en/sonatype-nexus-repository-system-requirements.html).
- Релиз `3.96.3-01` (2026-09-22), образ 484.2 MB, EPL-1.0.
- **Вывод:** оправдан, только если Nexus уже поднимается ради apt/npm; ради
  only-HTTP кэша — дорого.

### 5.6 Envoy + `envoy.filters.http.cache`

- Фильтр `envoy.filters.http.cache` + storage-бэкенды (`envoy.http.cache`):
  in-memory `SimpleHttpCache` и **persistent `FileSystemHttpCacheConfig` (LRU)**:
  [Cache filter](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/cache_filter).
  Есть и «CacheV2 filter».
- **Maturity-оговорка:** `CacheConfig`/`SimpleHttpCache` помечены
  `package_version_status = ACTIVE`, но `file_system_http_cache.proto` имеет
  `work_in_progress = true` (xDS-аннотация) — это видно в исходнике
  [file_system_http_cache.proto](https://raw.githubusercontent.com/envoyproxy/envoy/v1.39.1/api/envoy/extensions/http/cache/file_system_http_cache/v3/file_system_http_cache.proto).
  Кэширует 200/203/204/206/300/301/308/404/405/410/414/451/501 — **302 не
  кэширует** и, судя по докам, не следует за ним.
- Сильные стороны: native Prometheus, TLS к upstream, HTTP/2, зрелая
  observability; в k8s — Envoy Gateway/Deployment. Образ 73.7 MB, Apache-2.0.
- **Вывод:** отличный прокси, но кэш-фильтр — не «включил и забыл»: FS-бэкенд
  WIP, 302 не покрыт.

### 5.7 Traefik (плагин)

- **First-party HTTP-cache middleware у Traefik нет.** Список HTTP-middleware
  (`AddPrefix`, `Buffering`, `Compress`, `Retry`, …) кэша не содержит; сторонние
  — в каталоге плагинов: [HTTP Middleware Overview](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/overview/).
- Кэш — community-плагин **Souin** (`moduleName: github.com/darkweak/souin`,
  манифест `traefik.yml`): [plugins/traefik](https://github.com/darkweak/souin/tree/master/plugins/traefik).
  Каталог: [plugins.traefik.io](https://plugins.traefik.io/plugins).
- **Вывод:** Traefik уже стоит как ingress, поэтому плагин Souin — удобный путь
  «всё в одном», но это не first-party, а зависимость от одного мейнтейнера
  (см. §8).

## 6. Восходящие звёзды

Поиск по GitHub («http cache proxy kubernetes», «artifact caching proxy»,
«pull-through cache», «generic artifact mirror kubernetes», 2026-09-23) даёт
почти исключительно **OCI**-проекты (`gardener-extension-registry-cache`,
`aceeric/ociregistry`, `flemzord/mutating-registry-webhook`, `ix64/cr-mirrors`) —
generic HTTP-артефактов среди них нет. Для не-OCI пространства реально
существуют:

- **Souin** `v1.7.9` — самый интересный. RFC-7234-совместимый HTTP-кэш (Vary,
  request coalescing, stale, Cache-Status RFC 9211, ESI), самостоятельный
  reverse-proxy режим (`reverse_proxy_url`) и плагины/модули: Caddy, Traefik,
  Tyk, RoadRunner и Go-middleware'ы: [README](https://github.com/darkweak/souin).
  First-party **Prometheus API** и REST purge API. Хранилища вынесены в
  [darkweak/storages](https://github.com/darkweak/storages): Badger, Etcd,
  Go-redis, Nats, Nuts, Olric, Otter, Redis (rueidis), Simplefs — но с v1.7.0
  встроено только одно in-memory-хранилище, остальные добавляются на этапе
  сборки (`xcaddy --with …`). Образ 25.6 MB, MIT, активен.
- **Caddy `cache-handler`** `v0.17.0` — модуль `http.handlers.cache` (**на базе
  Souin**), distributed, REST purge, Prometheus, ESI. Это **community-модуль
  под организацией caddyserver**, не ядро Caddy; ставится `xcaddy build --with
  github.com/caddyserver/cache-handler` (готового образа нет):
  [README](https://github.com/caddyserver/cache-handler). 393★ — адопция низкая.
- **Envoy cache filter / CacheV2** — см. §5.6; «звезда» скорее в экосистеме
  Envoy, чем в самом кэше.
- **Cloudflare Pingora** `0.9.0` — **фреймворк**, не готовый кэш-прокси: кэш —
  только `pingora-memory-cache` (RAM, защита от cache stampede):
  [README](https://github.com/cloudflare/pingora). OSS-прокси на Pingora —
  `memorysafety/river` (**2353★, последний push 2024-09-06, релиз `v0.5.0`
  2024-08-30**) — это специализированный прокси для crates.io, а не generic
  artifact cache, и он неактивен.
- **HAProxy cache** — не «звезда», но важно знать: секция `cache` + `cache-store`/
  `cache-use`. Ограничения жёсткие: **RAM-only** (`total-max-size`, максимум
  **4095 MB**), кэшируются только **200**, только **GET**, HTTP **≥1.1**, запросы
  с `Authorization` не кэшируются, `max-object-size` ≤ половины `total-max-size`,
  `max-age` по умолчанию **60 c**: [HAProxy 3.4 config](https://docs.haproxy.org/3.4/configuration.html).
  То есть это «small object cache», а **не** general-purpose кэш бинарников
  (ассеты на десятки-сотни МБ не поместятся). Prometheus — first-party
  (`http-request use-service prometheus-exporter`).
- Прочие находки, не тянущие на «звезду»: `JetBrains/artifacts-caching-proxy`
  (6★) и `BenjaminSchubert/locaccel` (2★) — уже упоминались как
  низкоадоптированные; `ppy/s3-nginx-proxy` (31★, nginx-обёртка) и
  `safl/withcache` (0★, curl/wget-шимы) — слишком сырые.

## 7. Вывод для homelab

1. **Это отдельный сервис, не покрываемый protocol mirrors.** Zot/Verdaccio/
   Athens не умеют произвольный HTTP; нужен generic reverse-proxy cache с
   allowlist upstream'ов.
2. **Рекомендация: Apache Traffic Server `10.2.0`** — единственный из
   проверенных, кто закрывает **все** требования сразу:
   - pure reverse proxy без MITM (`remap.config`, `https://`-replacement);
   - **TLS-к-origin со SNI** (`proxy.config.ssl.client.*`);
   - HTTP/2 вход/выход;
   - **follow 302** на GitHub CDN (`proxy.config.http.number_of_redirections > 0`) —
     ключевое отличие от nginx/Envoy;
   - дисковый кэш (`storage.yaml`), TTL/revalidate/pin (`cache.config`),
     allowlist через `remap`, purge (`remap_purge`);
   - Apache-2.0, образ ~101 MB, активные релизы.
   Компромисс: нет first-party Prometheus (нужен exporter от `stats_over_http`)
   и конфиг на файлах, а не на CRD.
3. **Альтернативы:**
   - **Souin `v1.7.9`** — если важнее k8s-дружелюбность, Prometheus из коробки и
     единый стек с уже стоящим Traefik (плагин). Минусы: внешние хранилища
     собираются вручную, один мейнтейнер, follow-302 не документирован.
   - **nginx `proxy_cache`** — минимальный вес и уже знакомая эксплуатация, но
     **без follow-302** GitHub Releases не закроет; purge только в Plus.
   - **Envoy cache filter** — для тех, у кого Envoy уже есть; FS-бэкенд WIP, 302
     не покрыт.
   - **Nexus raw proxy** — только если Nexus и так поднимается; 8 GiB RAM и
     PostgreSQL.
4. **Что кэш принципиально не закрывает.**
   - URL, которые action строит сам (`api.github.com`,
     `raw.githubusercontent.com`, `actions/*-versions`): их не перенаправить без
     MITM. setup-node#1285 и setup-python#1302 показывают, что `mirror` не
     спасает от первичного обращения к GitHub.
   - `actions/setup-java` — официального mirror-входа нет (§4).
   - Инструменты без official base-url (helm, sops, kubeseal, argocd,
     kubectl-cnpg, gitleaks) требуют **переписывания URL** в CI на адрес кэша
     (по аналогии с `RUSTUP_DIST_SERVER` и `GO_DOWNLOAD_BASE_URL`).
   - Поэтому параллельно с кэшем остаётся практика из
     `registry-lightweight-comparison.md`: **предзакачивать критичные версии в
     RustFS** (`mirror-sync`) и/или наполнять tool-cache runner'а
     (`RUNNER_TOOL_CACHE`), чтобы action'ы могли не ходить в сеть вообще.
5. **Практичная композиция:** `ATS` (generic HTTP, allowlist + follow-302) для
   GitHub Releases/`get.helm.sh`/`static.rust-lang.org` + env-переопределения
   (`RUSTUP_DIST_SERVER`, `GO_DOWNLOAD_BASE_URL`, `mirror*` в setup-*) + RustFS
   как «холодное» зеркало для того, что кэш не покрывает.

## 8. Не подтверждённые утверждения

- **nginx «не следует за 302»** — прямого утверждения в документации нет;
  вывод из отсутствия соответствующей директивы в
  `ngx_http_proxy_module`. Для GitHub Releases это надо проверять на стенде.
- **`proxy_cache_purge` только в NGINX Plus** — из распространённого знания;
  страница OSS-модуля purge отдельно не открывалась.
- **nginx без first-party Prometheus** — вывод из отсутствия эндпоинта в
  `ngx_http_stub_status_module`/доках; нужен внешний exporter/VTS.
- **Squid reverse-proxy с TLS-к-origin** (`cache_peer … ssl`) — не проверено
  отдельной страницей документации Squid; на wiki подтверждён только приём
  TLS от клиента (`https_port`) и MITM-семантика `SslBump`.
- **Follow-302 у Squid / Varnish / Souin / Caddy / Envoy** — в документации не
  найдено; помечено «не документировано». У Envoy кэшируются коды без 302
  (прямое утверждение доков), у остальных — открытый вопрос.
- **HAProxy: «GPL-2.0»** — взято из общего знания; GitHub API отдаёт
  `NOASSERTION`, файл лицензии отдельно не проверялся.
- **Vinyl Cache: отсутствие follow-302 и purge/VCL-детали** — по докам не
  проверялось; tip-страница описывает только синтетические редиректы.
- **Traefik: динамическая загрузка плагина без пересборки** — из документации
  каталога плагинов напрямую не подтверждено; подтверждён только факт
  community-плагина Souin и отсутствие first-party кэша.
- **Caddy `cache-handler`: «community-модуль под caddyserver org»** — по README
  это модуль на базе Souin; официального статуса «core» нет, но и точной
  формулировки «community» в README не найдено.
- **Размеры образов** — из метаданных реестров (Docker Hub tag API
  `images[].size`, GHCR — сумма слоёв), сжатые `linux/amd64`; цифры зависят от
  тега/архитектуры и могут расходиться (например, Zot здесь 75.2 MB против
  71.7 MB в предыдущем документе).
- **RAM-потребление** кандидатов — не измерялось; официальных цифр для
  лёгких кандидатов нет, поэтому в таблицах RAM не приводится.
- **`actions/setup-go`**: что входа `go-download-base-url` достаточно для полной
  air-gapped работы (без обращения к `actions/go-versions`) — не проверялось;
  подтверждён только сам вход.
- **nginx: HTTP/2 к upstream** — серверный HTTP/2 у nginx есть, но поддержка
  HTTP/2 именно к upstream в конкретной версии в этой сессии не проверялась;
  в таблице стоит «нюансы».

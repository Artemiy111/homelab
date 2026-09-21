# Слой кэширования внешних пакетов для homelab: OCI, npm, бинарники, apt

Дата проверки: 2026-09-21.

> **Что изменилось с редакции 2026-08-16.** Исследование переписано под текущую
> реальность: в homelab развёрнут **Forgejo 16.x** (Kubernetes k0s + Argo CD,
> не Docker Compose), а задача сместилась с «хостинга своих пакетов» на
> **кэширование внешних**. Приоритет — контейнерные образы; npm, бинарники и apt
> рассмотрены как сопутствующие. Старые таблицы «npm + Docker» и выводы про
> Gitea больше не отражают действительность; посвящённые им документы удалены,
> всё существенное сведено в этот файл.

## Область исследования

Задача — выбрать минимальный по весу набор сервисов, который **кэширует
внешние источники пакетов**, чтобы падения и rate-limit'ы upstream'ов не
ломали CI и деплой. Кэш должен обслуживать **и кластер, и CI**:

- **кластер k0s** — containerd на узле тянет образы сервисов из `docker.io`,
  `ghcr.io`, `quay.io`, `registry.k8s.io`, вендорских реестров;
- **Forgejo Actions runner** — dockerd сайдкара `dind` тянет job-образы
  (`runs-on`) и образы, которые workflow'ы собирают/пуллят внутри job'ов;
- **npm** — `bun install`/`npm install` внутри CI;
- **бинарники/тулчейны** — GitHub Releases, `go.dev`, `static.rust-lang.org`,
  `archive.apache.org`; сегодня такие артефакты вручную перепубликуются в
  Forgejo generic packages (`scripts/publish-kubeconform-assets.sh`,
  `.forgejo/workflows/secrets.yml`);
- **apt** — пакеты ОС в образах сборки (опционально).

«Лёгкость» оценивается по трём осям: потребление RAM, размер Docker-образа,
число компонентов и своих зависимостей (БД и т. п.). Версии, теги, размеры и
даты проверены по первичным источникам: GitHub/GitLab/Codeberg Releases API,
метаданные реестров, официальные документации — 2026-09-21.

## Текущая реальность homelab

| Что | Состояние |
| --- | --- |
| Git-платформа | **Forgejo 16.x** (`data.forgejo.org/forgejo:16-rootless`), в k8s |
| Реестры Forgejo | container + 20+ форматов пакетов (npm, generic, …) — **только хостинг** |
| OIDC-провайдер | **Zitadel** (`id.example.com`); Authentik — тестовый стенд |
| Runtime кластера | k0s v1.36.3, containerd 2.x; конфиг `/etc/k0s/containerd.toml`, drop-in'ы `/etc/k0s/containerd.d/*.toml` |
| CI | Forgejo Runner + `docker:dind` сайдкар; доступ к Forgejo есть, к части внешних хостов (github.com) — нет |
| OCI-кэш | **отсутствует** |
| npm-кэш | **отсутствует** |
| Бинарь-кэш | вручную: Forgejo generic packages |

Ключевой факт: **Forgejo не умеет проксировать/кэшировать** — подтверждено
официальной документацией и кодом. В `[packages]` нет ключей proxy/mirror/cache,
а в `routers/api/packages/container/container.go` нет обработки
`proxy`/`upstream`/`mirror`:
[Forgejo container registry](https://forgejo.org/docs/latest/user/packages/container/),
[config cheat sheet](https://forgejo.org/docs/latest/admin/config-cheat-sheet/),
[`container.go`](https://codeberg.org/forgejo/forgejo/raw/branch/forgejo/routers/api/packages/container/container.go).
Поэтому кэш — отдельный сервис, а Forgejo остаётся хостом своих пакетов и
хранилищем generic-артефактов.

## Ключевые ограничения клиентов

Это определяет, что вообще можно кэшировать прозрачно, и поэтому вынесено
отдельно от сравнения серверов.

- **Зеркало в containerd/dockerd само не кэширует.** И containerd
  (`hosts.toml`), и Docker (`registry-mirrors`) лишь перенаправляют клиента;
  кэшем обязан быть сервер, реализующий pull-through. Без такого сервера
  «зеркало» бесполезно:
  [containerd hosts.toml](https://github.com/containerd/containerd/blob/main/docs/hosts.md),
  [Distribution mirror recipe](https://distribution.github.io/distribution/recipes/mirror/).
- **containerd настраивается per-registry.** `config_path` + каталог на каждый
  host (`docker.io/hosts.toml`, `ghcr.io/hosts.toml`, …) или `_default`.
  `_default` — catch-all, но тогда кэш должен сам разобрать, к какому upstream
  относится образ. containerd при несовпадении namespace подставляет query
  `?ns=<registry>`; **ни Distribution, ни Zot это поведение не документируют**
  (см. «Не подтверждённые утверждения»). Надёжный шаблон — отдельный
  `hosts.toml` на каждый реестр, указывающий на свой путь/инстанс кэша.
- **Docker daemon умеет mirror только для Docker Hub.** «It is not possible to
  run the Docker daemon against a pull through cache with another upstream
  registry» — `registry-mirrors` не перенаправит `ghcr.io/...` или
  `quay.io/...`:
  [Distribution mirror recipe](https://distribution.github.io/distribution/recipes/mirror/),
  [Docker Hub mirror](https://docs.docker.com/docker-hub/image-library/mirror/).
- **`dind` принимает конфиг dockerd** либо аргументами (`docker:dind
  --registry-mirror=...`), либо смонтированным `/etc/docker/daemon.json`;
  переменной `DOCKERD_CONFIG` не существует:
  [docker:dind docs](https://github.com/docker-library/docs/blob/master/docker/README.md),
  [dockerd reference](https://docs.docker.com/reference/cli/dockerd/).
- **У runner'а нет своего registry-mirror.** Job-образы тянет тот самый dockerd
  сайдкара (`container.docker_host`). Значит, для не-Hub образов прозрачного
  кэша нет — остаётся ссылаться на кэш явно в label'ах/workflow'ах:
  [Forgejo runner config](https://forgejo.org/docs/latest/admin/actions/configuration/),
  [docker access](https://forgejo.org/docs/latest/admin/actions/docker-access/).
- **k0s: drop-in'ы containerd.** `/etc/k0s/containerd.d/*.toml` применяются,
  только пока в `/etc/k0s/containerd.toml` сохранена строка `# k0s_managed=true`;
  для containerd 2.x drop-in должен быть `version = 3` и использовать плагин
  `io.containerd.cri.v1.images`. Образы самого k0s можно перевести
  на свой реестр через `spec.images.repository`:
  [k0s runtime](https://docs.k0sproject.io/head/runtime/),
  [k0s configuration](https://docs.k0sproject.io/head/configuration/).

## Сравнительная таблица: OCI pull-through кэш

| Кандидат | Лицензия | Хостинг / кэш | Несколько upstream'ов на инстанс | RAM | Образ (сжатый, amd64) | Своя БД / сервисы | Web-UI | Аутентификация | OIDC | Управление размером кэша | Версия, поддержка | Практический вывод |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Zot** `v2.1.21` | Apache-2.0 | Да / **Да** (on-demand sync) | **Да** (`sync.registries[]`, path-prefix) | ~83 MiB idle после прогрева (изм. 2026-08-16, в. 2.1.20) | 71.7 MB | — (ФС/S3/GCS) | Да (ui extension) | mTLS, htpasswd, LDAP, Bearer/OAuth2, `accessControl` | Да | On-demand; встроенного лимита не документировано | Активна (релиз 2026-09-06) | **Основной кандидат**: один инстанс на все реестры |
| **CNCF Distribution** `v3.1.1` | Apache-2.0 | Да / **Да** (pull-through рецепт) | **Нет** — один upstream на инстанс | ~12 MiB idle (изм. 2026-08-16) | 19.2 MB | — | Нет | htpasswd (bcrypt) / token | — | `proxy.ttl` (по умолч. 168h) + GC/cleanup | Активна (релиз 2026-05-01) | Минимальный вес, но по инстансу на реестр |
| **Harbor** `v2.15.2` | Apache-2.0 | Да / **Да** (proxy-cache project) | **Да** (несколько proxy-project'ов) | Min **2 CPU / 4 GiB / 40 GB**; реком. 4/8/160 | 696.4 MB (офлайн-инсталлятор) | PostgreSQL + набор сервисов | Да | БД Harbor, ROBOT, LDAP, OIDC | Да | 7-дневный tag-retention на proxy-project | Активна (релиз 2026-07-02) | Мощно, но заметно тяжелее |
| **Nexus CE** `3.96.2-01` | EPL-1.0 | Да / **Да** (docker proxy) | **Да** (репозиторий на upstream) | Small: **2 CPU / 8 GiB / 20 GB**; контейнерный деплой с H2 **не поддерживается** — нужен PostgreSQL | 475.7 MB | PostgreSQL (для k8s) | Да | Локальные, LDAP, OIDC, SAML (Pro), Crowd | Спорно (см. ниже) | TTL/cleanup-политики | Активна (релиз 2026-09-18) | Универсальный комбайн, но JVM и 8 GiB |
| **Forgejo** `v16.0.5` | GPL-3.0-or-later | Да / **Нет** | — | часть реестра отдельно не выделена | ~80 MB (16.0.x) | уже есть (CNPG PostgreSQL) | Да | PAT | вход OIDC | — | Активна (релиз 2026-09-17) | **Кэшем быть не может** — только хостинг |
| Spegel `v0.7.4` | MIT | не реестр: P2P-повтор между нодами | — | — | — | — | Нет | — | — | — | Активна (2026-07-15) | Best-effort, не диск-кэш; лишь надстройка |
| Dragonfly `v2.5.2` | Apache-2.0 | P2P + proxy/mirror | — | — | — | supernode/scheduler/manager + Redis/MySQL | — | — | — | — | Активна (2026-09-14) | Оверкилл для одного узла |
| Trow `v0.7.2` | Apache-2.0 | Да / **Да** («proxy any registry») | Да | — | — | — | — | заявлены в roadmap | — | — | **Релизов нет с 2025-02-21**, beta | Не для прод-стенда |

## Сравнительная таблица: npm / generic / apt

| Источник | Кандидат | Лицензия | Кэш/прокси | RAM / вес | Примечание |
| --- | --- | --- | --- | --- | --- |
| **npm** | Verdaccio `v6.10.4` | MIT | **Да**: uplink-прокси `registry.npmjs.org` | Node.js, лёгкий | Только npm-протокол; встроенной эвикции/лимита нет; OIDC-плагин сторонний и заброшен |
| **npm/apt/raw** | Nexus CE `3.96.2-01` | EPL-1.0 | **Да**: npm, apt, raw, docker, Go, PyPI и др. | 2 CPU / 8 GiB | Единственный «один на всё», но тяжёлый и требует PostgreSQL в k8s |
| **generic HTTP** | nginx `proxy_cache` | BSD-2 | **Да**: кэш произвольного HTTPS-upstream (nginx сам TLS-клиент) | минимальный | Нет MITM: клиент ходит на nginx; `proxy_ssl_server_name on` обязателен; ссылки в HTML не переписываются |
| **generic HTTP** | Squid / ATS / Varnish | GPL / Apache / BSD | Частично | средний | Squid для видимого HTTPS — `SslBump` (MITM); Varnish без TLS (нужен Hitch); ATS-доки не проверились |
| **Go** | Athens `v0.18.1` | Apache-2.0 | **Да**: GOPROXY | средний | Официальный протокол `GOPROXY`; Nexus/Artifactory тоже умеют |
| **Rust** | `RUSTUP_DIST_SERVER` + reverse proxy | — | Через env | — | Официального self-host зеркала нет; `panamax` `v1.0.14` (2024-06) не обновляется |
| **Python** | devpi-server `6.20.3` | MIT | **Да**: PyPI mirror | средний | Плюс Nexus PyPI proxy |
| **apt** | apt-cacher-ng `3.7.5` | — | **Да** | минимальный | Специализированный кэш; альтернатива — Nexus APT proxy |
| **GitHub Releases** | Forgejo generic + `gh release download` | — | **Нет готового**: стандартного инструмента нет | — | Только ручная/скриптовая перепубликация (текущий подход) |

## Тяжёлые решения (точки отсчёта)

| Кандидат | RAM (официально) | Образ (сжатый) | БД / компоненты | Практический вывод |
| --- | --- | --- | --- | --- |
| Nexus Repository 3 `3.96.2-01` | Small profile: **2 CPU / 8 GB RAM**, H2; в k8s H2 не поддержан → PostgreSQL | 475.7 MB | Своя H2 или PostgreSQL | Разумен только при росте до многих форматов в одном месте |
| Harbor `2.15.2` | Min **2 CPU / 4 GB RAM**, реком. 4 CPU / 8 GB / 160 GB | 696.4 MB (офлайн-инсталлятор) | PostgreSQL + набор контейнеров | Web-UI и сканирование «из коробки», но тяжелее |
| GitLab CE `19.4.x` | Single node min **8 vCPU / 16 GB RAM** | 1312.5 MB | PostgreSQL + Redis + свои | Оправдан только при готовности поднять GitLab целиком |
| Dragonfly `2.5.2` | — | — | supernode, scheduler, manager, Redis, MySQL | P2P оправдан в крупных кластерах |

## Ресурсы

Размеры образов — сжатые, `linux/amd64`, по метаданным реестров (2026-09-21).
Замеры RAM — локальные измерения `docker stats` от 2026-08-16 (см. «Не
подтверждённые утверждения»), версии тогда были чуть старше.

### Zot `v2.1.21`

- Релиз 2026-09-06: [Releases `project-zot/zot`](https://github.com/project-zot/zot/releases).
  Образ `ghcr.io/project-zot/zot:v2.1.21` — **71.7 MB** (сумма config+layers
  манифеста GHCR), digest `sha256:82584438…`.
- **Один инстанс — много upstream'ов.** `extensions.sync.registries[]`, у каждого
  `urls[]`, `onDemand: true` (pull-through) и `content[]` с `prefix`/
  `destination`/`stripPrefix`. Репозиторий поставляет
  `examples/config-popular-registries.json` разом для `docker.io`, `gitlab`,
  `ghcr.io`, `quay.io`, `gcr.io`, `registry.k8s.io`:
  [Mirroring](https://zotregistry.dev/v2.1.21/articles/mirroring/).
  Документированный шаблон multi-upstream — **path-prefix**
  (`zot/ghcr.io/...`), а не прозрачный hostname-mirror.
- Публикуемый образ собирается со **всеми расширениями**
  (`debug,imagetrust,lint,metrics,mgmt,profile,scrub,search,sync,ui,userprefs,events`;
  CVE-сканирование — часть `search`, тянет Trivy DB из
  `ghcr.io/aquasecurity/trivy-db`): [Makefile v2.1.21](https://raw.githubusercontent.com/project-zot/zot/v2.1.21/Makefile).
  Есть минимальный образ без расширений.
- Docker Hub из-за rate-limit рекомендуется подключать **только `onDemand`**;
  для сохранения digest/подписей — `http.compat: ["docker2s2"]` +
  `sync.preserveDigest: true`:
  [Mirroring](https://zotregistry.dev/v2.1.21/articles/mirroring/).
- Auth: mTLS, htpasswd, LDAP, Bearer/OAuth2 + `accessControl`:
  [Authn/Authz](https://zotregistry.dev/v2.1.21/articles/authn-authz/).
  Хранилище: ФС (hardlink-dedupe, inline GC), S3/S3-совместимое, GCS:
  [Admin config](https://zotregistry.dev/v2.1.21/admin-guide/admin-configuration/).

### CNCF Distribution `v3.1.1`

- Релиз 2026-05-01: [Releases `distribution/distribution`](https://github.com/distribution/distribution/releases).
  Образ `registry:3.1.1` — **19.2 MB** (Docker Hub tag metadata).
- Pull-through — официальный рецепт: `proxy.remoteurl`, `proxy.username` /
  `proxy.password`, `proxy.ttl` (по умолчанию `168h`, `0` — без истечения),
  `proxy.exec` для credential helper. Для очистки нужен
  `storage.delete.enabled: true`:
  [Registry as a pull through cache](https://distribution.github.io/distribution/recipes/mirror/).
- **Ограничение: один upstream на инстанс** — «It's currently possible to mirror
  only one upstream registry at a time»; URL mirror'а — только корень домена.
  Поэтому pattern — по инстансу на реестр (или общий reverse-proxy спереди).
- Auth: htpasswd (только bcrypt) или token; хранилище `filesystem` (рекомендуется
  для proxy), `s3`, `gcs`, `azure`:
  [Configuration](https://distribution.github.io/distribution/about/configuration/).

### Forgejo `v16.0.5` (текущий хостинг)

- Релиз 2026-09-17: [Codeberg releases API](https://codeberg.org/api/v1/repos/forgejo/forgejo/releases).
  Образ `forgejo/forgejo:16-rootless` ~80 MB (16.0.x), локально измеренный idle
  RAM ~104–125 MiB (SQLite, 2026-08-16). В homelab база — CNPG PostgreSQL.
- Контейнерный реестр и 20+ форматов пакетов, **только хостинг**:
  [Container](https://forgejo.org/docs/latest/user/packages/container/),
  [Generic](https://forgejo.org/docs/latest/user/packages/generic/),
  [Config cheat sheet](https://forgejo.org/docs/latest/admin/config-cheat-sheet/).
- В коде контейнерного API нет обработки proxy/upstream/mirror (см. «Текущая
  реальность»).

### Verdaccio `v6.10.4`

- Релиз 2026-09-20: [Releases `verdaccio/verdaccio`](https://github.com/verdaccio/verdaccio/releases),
  npm `latest` = 6.10.4.
- Uplink-кэш: `cache: true` (по умолчанию), `maxage` (2m), `fail_timeout` (5m),
  `max_fails` (2), `timeout`. **Uplinks обязаны быть npm-совместимыми** — apt,
  docker и generic HTTP Verdaccio не проксирует:
  [Uplinks](https://verdaccio.org/docs/uplinks).
- Хранилище — ФС (`storage:`, `VERDACCIO_STORAGE_PATH`), `store:`-плагины для S3
  и т. п.; встроенного лимита/эвикции кэша в документации нет:
  [Configuration](https://verdaccio.org/docs/configuration).
- OIDC: официального плагина нет; сторонний `verdaccio-openid-connect` 3.0.0
  (версия 2024, репозиторий не обновлялся ~2 года) — узкое место:
  [GitHub](https://github.com/deeplay-io/verdaccio-openid-connect),
  [npm](https://registry.npmjs.org/verdaccio-openid-connect/latest).

### Nexus CE `3.96.2-01`

- Релиз 2026-09-18: [Releases `sonatype/nexus-public`](https://github.com/sonatype/nexus-public/releases),
  [release notes 3.96.0](https://help.sonatype.com/en/sonatype-nexus-repository-3-96-0-release-notes.html).
- В CE (feature matrix) — Alpine, APT, Docker, Go, npm, PyPI, Rust Cargo, raw и
  др.; PRO — Azure/GCS blob stores, HA, SAML, content replication:
  [Feature matrix](https://help.sonatype.com/en/nexus-repository-feature-matrix.html).
- Docker proxy — **один upstream на репозиторий**:
  [Proxy repository for Docker](https://help.sonatype.com/en/proxy-repository-for-docker.html).
- Raw proxy умеет проксировать статические деревья (пример из доков —
  `https://nodejs.org/dist/`):
  [Raw repositories](https://help.sonatype.com/en/raw-repositories.html).
- Требования: Small — **2 CPU / 8 GB RAM / 20 GB**, Java 21; контейнерный деплой
  с H2 **не поддержан** → для k8s нужен внешний PostgreSQL:
  [System requirements](https://help.sonatype.com/en/sonatype-nexus-repository-system-requirements.html).

### Generic HTTP-кэш (nginx)

- `ngx_http_proxy_module`: `proxy_cache_path`, `proxy_cache`,
  `proxy_ssl_server_name on` (по умолчанию **off** — без него SNI upstream'у не
  уйдёт), `resolver` при `proxy_pass` с переменными:
  [nginx docs](https://nginx.org/en/docs/http/ngx_http_proxy_module.html).
- MITM-варианты: Squid `SslBump` (документация сама называет это
  man-in-the-middle), Varnish без TLS (нужен Hitch), ATS — доки в текущей сессии
  не проверились:
  [Squid HTTPS](https://wiki.squid-cache.org/Features/HTTPS),
  [hitch](https://github.com/varnish/hitch).

### apt-cacher-ng `3.7.5`

- Специализированный кэш-прокси для пакетов дистрибутива, без интерпретатора и
  больших зависимостей:
  [Debian sources](https://sources.debian.org/api/src/apt-cacher-ng/),
  [ACNG](https://www.unix-ag.uni-kl.de/~bloch/acng/).

## Вывод для homelab

1. **Хостинг первого своего уже решён, кэш — нет.** Forgejo 16.x хостит
   контейнерные образы и 20+ форматов, но **не проксирует**; значит, слой
   кэширования — отдельный сервис. Ручная перепубликация бинарников в Forgejo
   generic packages остаётся рабочим приёмом, но это не кэш, а копия.
2. **OCI — основной сценарий. Рекомендация: Zot `v2.1.21`.**
   Один инстанс, один конфиг на все upstream'ы (`docker.io`, `ghcr.io`,
   `quay.io`, `registry.k8s.io`, …), on-demand-кэш, OIDC (совпадает с Zitadel),
   S3-хранилище (в homelab есть RustFS), UI; образ ~72 MB — на уровне Forgejo.
   Потребители:
   - **кластер**: `hosts.toml` на каждый реестр в
     `/etc/k0s/containerd.d/certs.d/<host>/` (drop-in, `version = 3`), либо
     `spec.images.repository` для образов самого k0s;
   - **CI**: `registry-mirrors` в `/etc/docker/daemon.json` сайдкара `dind`
     закрывает **только Docker Hub**; для `ghcr.io`/`quay.io` job-образов
     прозрачного пути нет — ссылаться на путь кэша явно в label'ах/workflow'ах.
   - Docker Hub подключать `onDemand`; для пинов по digest —
     `docker2s2` + `preserveDigest`.
3. **Альтернатива OCI: CNCF Distribution `v3.1.1`.** Абсолютный минимум
   (19 MB, ~12 MiB RAM), но **по инстансу на upstream**. Выигрывает, если нужен
   предельно простой кэш для одного-двух реестров и не нужны UI/OIDC/
   multi-upstream. Для пары десятков реестров это уже много инстансов.
4. **npm:** Verdaccio `v6.10.4` — единственный лёгкий вариант; закрывает
   host + uplink-кэш `registry.npmjs.org`. OIDC только сторонним устаревшим
   плагином — если OIDC обязателен, это его слабое место; в CI чаще достаточно
   токена/анонимного чтения.
5. **Бинарники/тулчейны (GitHub Releases, rustup, go.dev, Maven):** стандартного
   кэша нет. Практичные варианты, по возрастанию веса:
   - **nginx `proxy_cache`** на фиксированный allowlist upstream'ов + смена URL
     в workflow'ах / tool-specific env (`RUSTUP_DIST_SERVER`, `GOPROXY`);
   - оставить текущий приём: разовая публикация в Forgejo generic packages
     (`gh release download` + `PUT /api/packages/.../generic/...`);
   - **Nexus CE raw proxy** — если уже поднимается Nexus ради apt/npm.
6. **apt (опционально):** apt-cacher-ng, если сборка образов часто тянет пакеты.
7. **Один комбайн вместо набора — Nexus CE `3.96.2-01`** (npm+apt+raw+docker+Go
   в одном), но цена — **8 GiB RAM**, Java 21 и PostgreSQL в k8s. Для
   одноузлового homelab это не «лёгкий» выбор; Harbor (4–8 GB) и GitLab (16 GB)
   тяжелее ещё на порядок. Artifactory OSS — **Java-only**, npm/docker/generic
   в нём не проксируются: [JFrog Open Source](https://jfrog.com/open-source/).
8. **Практичная композиция:** **Zot (OCI) + Verdaccio (npm) + nginx
   `proxy_cache` (бинарники)** дают покрытие всех четырёх категорий при
   сопоставимом с одним Forgejo бюджете; Nexus/Harbor — только при сознательном
   согласии на 4–8 GiB ради «одного окна».

## Не подтверждённые утверждения

- **Замеры RAM** (Zot ~83 MiB, Distribution ~12 MiB, Forgejo ~104–125 MiB) —
  локальные `docker stats` от 2026-08-16 (Docker Desktop, macOS), версии чуть
  старше текущих; официальных цифр для «самых лёгких» кандидатов нет.
- **Размеры образов** — из метаданных реестров (`docker manifest inspect` /
  registry API) на 2026-09-21, а не из документации; зависят от тега и
  архитектуры.
- **«containerd `?ns=` понимают Distribution/Zot»** — прямых подтверждений в
  документации/коде не найдено. Официальный multi-upstream у Zot — path-prefix,
  поэтому в homelab рассчитывать на прозрачный `_default`-mirror нельзя без
  проверки на стенде.
- **«Docker daemon mirror только для Docker Hub»** — из документации
  Distribution и Docker; поведение по версиям Docker Engine отдельно не
  проверялось.
- **Zot: расширения в публикуемом образе** — подтверждено Makefile v2.1.21
  (собирается со всеми расширениями); в документации расширения описаны как
  опция. Размер каталога Trivy DB измерить не удалось.
- **Zot: встроенного управления размером кэша нет** — вывод из отсутствия
  соответствующего раздела в документации, а не прямое утверждение.
- **Nexus: OIDC-редакция** — OIDC-реалм описан в документации, но feature
  matrix отдельно не помечает его; принадлежность CE не подтверждена.
- **Nexus: «контейнерный деплой с H2 не поддержан»** — формулировка официальной
  страницы системных требований; подразумевает обязательный внешний PostgreSQL
  в k8s.
- **Verdaccio: лимит/эвикция кэша, размер образа** — первичного документа с
  явным утверждением нет; «управления размером кэша нет» — вывод из описания
  uplink (`cache`, `maxage`) и назначения `@verdaccio/package-filter`
  (фильтр по имени, не очистка).
- **nginx как «стандартный» кэш для CI** — приём распространённый, но
  первичного источника, что это отраслевой стандарт, нет; JetBrains
  `artifacts-caching-proxy` и `locaccel` — низкоадоптированные эксперименты.
- **GitHub Releases mirroring** — стандартного инструмента нет; первичные
  примитивы — `gh release download` и Forgejo generic packages.
- **Forgejo runner `config.example.yaml`** — файл прочитать не удалось
  (code.forgejo.org отдаёт anti-bot challenge), поэтому отсутствие
  runner-level registry-mirror выведено из публичной документации.
- **Dragonfly containerd proxy/mirror** — страница документации рендерится
  клиентским JS, подтверждён только README + sitemap.
- **GitLab CE `19.4.x`, Harbor `2.15.2`, Nexus `3.96.2-01`,
  Dragonfly `2.5.2`** — тяжёлые точки отсчёта: RAM/размеры взяты из официальных
  требований и прошлых редакций документа; актуальность на 2026-09-21 по каждой
  цифре отдельно не перепроверялась.

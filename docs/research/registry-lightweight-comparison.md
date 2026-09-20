# Лёгкие саморазмещаемые реестры npm + Docker (OCI) для homelab

Дата проверки: 2026-08-16.

## Область исследования

Задача — выбрать **минимальный по весу** набор сервисов, закрывающий обе
потребности homelab:

- **npm**: приватный реестр (хостинг собственных пакетов) и/или прокси с кэшем
  `registry.npmjs.org` (ускорение установок в локальной сети);
- **Docker/OCI**: приватный реестр (хостинг собственных образов) и/или кэш
  Docker Hub (защита от rate-limit и ускорение pull).

Учитывается уже развёрнутый в homelab **Gitea 1.27.x** (Docker Compose + Traefik),
который умеет хостить и npm-пакеты, и образы. Пользователи заходят через
развёрнутый OIDC-провайдер (Pocket ID), поэтому отдельно сравнивается поддержка
входа по OIDC (роль клиента/RP). «Лёгкость» оценивается по трём осям:
потребление RAM, размер Docker-образа, количество компонентов/своих зависимостей
(БД и т. п.).

Лёгкие кандидаты: Verdaccio, cnpmcore, CNCF Distribution, Zot, Gitea Packages.
Альтернатива Gitea для пакетного реестра — Forgejo (рассмотрен отдельно).
Тяжёлые решения (Nexus Repository 3, Harbor, GitLab CE) включены только как
**точки отсчёта ресурсов**, чтобы подтвердить, что переход на них неоправдан.

Версии, теги, размеры образов и даты проверены по первичным источникам: GitHub
Releases API, метаданные Docker Hub / ghcr.io (`docker manifest inspect`),
официальные документации. Замеры потребления RAM — локальные измерения на
Docker Desktop (macOS), отмечены явно (см. раздел «Не подтверждённые
утверждения»).

## Сравнительная таблица

| Кандидат | Лицензия | npm: хостинг / кэш | Docker/OCI: хостинг / кэш | RAM* | Образ (сжатый, amd64) | Своя БД / сервисы | Web-UI | Аутентификация | OIDC (вход/RP) | Управление размером кэша | Версия, поддержка | Практический вывод |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Verdaccio `6.9.2` | MIT | **Да / Да** (uplink-кэш npmjs) | — | ~119 MiB idle (изм.) | 66.6 MB | — (файловая ФС) | Да (встроенный) | htpasswd встроен, JWT/legacy | Плагин (сторонний, устарел 2024) | Нет лимита/эвакуации; uplink `cache:false` или фильтр по имени | Активна (релиз 2026-08-02), 225,5M pulls | Главный кандидат для npm |
| cnpmcore `4.34.3` | MIT | **Да / Да** (sync-зеркало) | — | Заявлено нет; **нужны MySQL + Redis** | 514.2 MB (тег устарел с 2025-03-09) | MySQL + Redis | Да | — | — | — | Активна, но официальный Docker-образ не обновляется | Для homelab избыточен |
| CNCF Distribution `3.1.1` | Apache-2.0 | — | **Да / Да** (pull-through cache, рецепт) | ~12 MiB idle (изм.) | 19.2 MB | — | Нет | htpasswd / token (спецификация) | — (htpasswd/token) | Pull-through без лимита, но `proxy.ttl` (default 168h) | Активна (push 2026-08-10), 1,76 млрд pulls | Минимальный вес для Docker-кэша |
| Zot `v2.1.20` | Apache-2.0 | — (не npm-протокол) | **Да / Да** (on-demand pull-through cache) | ~83 MiB idle после прогрева (изм.) | 70.9 MB | — (ФС/S3/GCS/Azure; по умолчанию boltdb-метаданные) | Да (ui extension) | htpasswd, LDAP, OIDC, mTLS | Да (OpenID/OAuth2: GitHub/Google/GitLab/dex) | On-demand; встроенного лимита не документировано | Активна (push 2026-08-16) | Лёгкий современный реестр; первый старт качает trivy-db |
| Gitea Packages `1.27.x` | MIT | **Да / Нет** | **Да / Нет** | Реестровая часть не выделена (оценка) | 68.7 MB (образ Gitea 1.27.1) | Уже есть (SQLite/PostgreSQL/MySQL) | Да (Gitea) | Gitea personal access token | Да (вход OAuth2/OIDC) | — (без прокси) | Активна (1.27.2, 2026-08-13) | Уже в homelab: хостинг обоих типов без новых компонентов, но без кэша |
| Forgejo `16.0.2` | GPL-3.0-or-later (с v9.0) | **Да / Нет** | **Да / Нет** | ~104–125 MiB idle (изм.) | 80.3 MB | Уже есть (SQLite/PostgreSQL/MySQL) | Да (Forgejo) | Как Gitea + OIDC-клиент | Да (вход OAuth2/OIDC, `[oauth2_client]`) | — (без прокси) | Стабильная 16.0.2 (до 2026-10-29), LTS 15.0.6 (до 2027-07-15) | Альтернатива Gitea: реестры и OIDC как у Gitea, но переход с Gitea 1.23+ не прозрачен и лицензия GPLv3+ |

\* RAM — локальные измерения idle-состояния (Verdaccio, Distribution, Zot,
Forgejo), см. разделы «Ресурсы» и «Не подтверждённые утверждения».

### Тяжёлые решения (точки отсчёта)

| Кандидат | RAM (официально) | Образ (сжатый) | БД / компоненты | Практический вывод |
| --- | --- | --- | --- | --- |
| Nexus Repository 3 `3.95.1` | Small profile: **2 CPU / 8 GB RAM**, min heap 2703M, host min 8 GB | 475.7 MB | Своя (blob stores) | Разумен только при росте потребностей до нескольких форматов |
| Harbor `2.15.2` | Min **2 CPU / 4 GB RAM**, рекомендовано 4 CPU / 8 GB RAM / 160 GB диск | 696.4 MB (офлайн-инсталлятор) | PostgreSQL + набор контейнеров | Web-UI и сканирование «из коробки», но заметно тяжелее |
| GitLab CE `19.2.x` | Single node min **8 vCPU / 16 GB RAM** | 1312.5 MB | PostgreSQL + Redis + свои | Оправдан только при готовности поднять GitLab целиком |

## Ресурсы

Размеры образов (сжатые, `linux/amd64`, `docker manifest inspect`,
2026-08-16), потребление RAM (docker stats, 2026-08-16).

### Verdaccio `6.9.2`

Образ `verdaccio/verdaccio:latest` — 66.6 MB, обновлён 2026-08-02, 225 517 068
pulls: [Docker Hub `verdaccio/verdaccio`](https://hub.docker.com/r/verdaccio/verdaccio).
Релиз 6.9.2 — 2026-08-02:
[GitHub Releases `verdaccio/verdaccio`](https://github.com/verdaccio/verdaccio/releases).

- Измерено: idle RAM ~118.6 MiB, CPU ~0.01% (Docker Desktop, macOS).
- npm: хостинг + uplink-прокси с кэшем `registry.npmjs.org`; хранилище —
  файловая ФС по умолчанию; htpasswd + JWT/legacy токены:
  [What is Verdaccio](https://verdaccio.org/docs/what-is-verdaccio/),
  [Uplinks](https://verdaccio.org/docs/uplinks),
  [Authentication](https://verdaccio.org/docs/authentication).
- Полное описание и источники — в соседнем документе
  [npm-registry-selfhosted.md](npm-registry-selfhosted.md).

### cnpmcore `4.34.3`

Образ `fengmk2/cnpmcore:latest` — 514.2 MB, обновление на Docker Hub —
2025-03-09 (**устарел** относительно релизов репозитория 2026-08-16):
[Docker Hub `fengmk2/cnpmcore`](https://hub.docker.com/r/fengmk2/cnpmcore),
[GitHub `cnpm/cnpmcore`](https://github.com/cnpm/cnpmcore).

- Описание проекта — «Private NPM Registry for Enterprise»:
  [GitHub `cnpm/cnpmcore` — README](https://github.com/cnpm/cnpmcore).
- Self-host требует внешние БД: в официальном `docker-compose.yml` поднимаются
  `mysql:9` + `redis:6-alpine` (и phpmyadmin для разработки):
  [docker-compose.yml `cnpm/cnpmcore`](https://raw.githubusercontent.com/cnpm/cnpmcore/master/docker-compose.yml).
- Официальных системных требований к RAM/диску найти не удалось (см. раздел
  «Не подтверждённые утверждения»).

### CNCF Distribution (Docker Distribution, `registry`) `3.1.1`

Образ `registry:latest` — 19.2 MB, обновлён 2026-06-23, 1 764 409 466 pulls:
[Docker Hub `library/registry`](https://hub.docker.com/r/library/registry).
Релиз v3.1.1 — 2026-05-01:
[GitHub Releases `distribution/distribution`](https://github.com/distribution/distribution/releases).

- Измерено: idle RAM ~11.5 MiB (стартовый всплеск ~50 MiB).
- Pull-through cache Docker Hub — официальный рецепт:
  [Registry as a pull through cache](https://distribution.github.io/distribution/recipes/mirror/);
  авторизация htpasswd/token:
  [Configuration — auth](https://distribution.github.io/distribution/about/configuration/).
- Сборка мусора описана в официальной документации:
  [Garbage collection](https://distribution.github.io/distribution/about/garbage-collection/).
- Web-UI нет. Полное описание — в соседнем документе
  [docker-registry-selfhosted.md](docker-registry-selfhosted.md).

### Zot `v2.1.20`

Образ `ghcr.io/project-zot/zot:latest` — 70.9 MB (amd64; digest
`sha256:542e25be…`), соответствует релизу v2.1.20 (2026-08-04):
[GitHub Releases `project-zot/zot`](https://github.com/project-zot/zot/releases).

- Релизные бинарные артефакты (GitHub Releases API): `zot-linux-amd64`
  **214.6 MB** (полная сборка), `zot-linux-amd64-minimal` **78.1 MB**.
- Измерено: idle RAM ~83.4 MiB после прогрева; при первом старте CPU ~100% —
  качается база уязвимостей trivy (см. ниже).
- Опубликованный образ по умолчанию запускает **полную** сборку с включёнными
  расширениями `search` (CVE/trivy, updateInterval 2h) + `ui` + `mgmt` — это
  подтверждено извлечением `/etc/zot/config.json` из образа (замечено также в
  логах первого запуска: download trivy db). Минимальная конфигурация — образ,
  собранный по `build/Dockerfile-minimal`, и конфиг из
  [examples/config-minimal.json](https://raw.githubusercontent.com/project-zot/zot/main/examples/config-minimal.json):
  [build/Dockerfile](https://raw.githubusercontent.com/project-zot/zot/main/build/Dockerfile),
  [build/Dockerfile-minimal](https://raw.githubusercontent.com/project-zot/zot/main/build/Dockerfile-minimal).
- Спецификации — OCI Distribution и OCI Image; **npm-протокол не поддерживается**
  (npm-клиенты к Zot не подключаются):
  [Zot — features](https://zotregistry.dev/v2.1.20/general/features/).
- Pull-through cache, хранилища (ФС/S3/GCS/Azure), auth (htpasswd/LDAP/OIDC/mTLS) —
  [Zot docs](https://zotregistry.dev/v2.1.20/).

### Gitea Packages `1.27.x`

Образ `docker.gitea.com/gitea:1.27.1` — 68.7 MB.
Официально «A Raspberry Pi 3 is powerful enough to run Gitea for small workloads»
и «2 CPU cores and 1GB RAM is typically sufficient for small teams/projects»:
[What is Gitea?](https://docs.gitea.com/).
Вклад именно пакетного реестра в RAM отдельно не документирован (оценка).

- npm: [NPM Package Registry](https://docs.gitea.com/usage/packages/npm);
- container: [Container Registry](https://docs.gitea.com/usage/packages/container);
- оба — только хостинг своих пакетов/образов, без прокси-кэша.

### Forgejo (альтернатива Gitea)

Образ `codeberg.org/forgejo/forgejo:16.0.2` — 80.3 MB сжатый (amd64,
`docker manifest inspect` из реестра, 2026-08-16); локальный распакованный —
~73.0 MiB. Официальное зеркало образов — `data.forgejo.org`, есть rootless-тег
`:16-rootless`. Стабильный релиз 16.0.2 (2026-07-30, поддержка до 2026-10-29),
LTS 15.0.6 (поддержка до 2027-07-15):
[Forgejo — Releases](https://forgejo.org/releases/),
[Installation with Docker](https://forgejo.org/docs/v16.0/admin/installation/docker/).

- Измерено: idle RAM ~104–125 MiB, CPU ~0.1% (SQLite, отключены Actions и
  индексаторы, Docker Desktop (macOS), 2026-08-16).
- npm и Container реестры — как в Gitea (хостинг своих пакетов/образов, без
  прокси-кэша): [npm Package Registry](https://forgejo.org/docs/v16.0/user/packages/npm/),
  [Container Registry](https://forgejo.org/docs/v16.0/user/packages/container/).
- Вход пользователей через внешний OIDC-провайдер (клиент/RP) поддерживается:
  секция `[oauth2_client]` (`OPENID_CONNECT_SCOPES`, `ENABLE_AUTO_REGISTRATION`,
  `USERNAME = preferred_username`, `ACCOUNT_LINKING`):
  [Configuration Cheat Sheet](https://forgejo.org/docs/v16.0/admin/config-cheat-sheet/);
  подтверждено и в дефолтном `app.example.ini` (строки ~1652–1686).
- Лицензия: **с v9.0 (коммит «Forgejo v9.0 is GPLv3+», 2024-07-25) Forgejo
  перешёл на GPL-3.0-or-later** (Gitea — MIT): файл `LICENSE` в репозитории
  [forgejo/forgejo](https://codeberg.org/forgejo/forgejo).
- Миграция: прозрачный апгрейд Gitea→Forgejo возможен только до **Gitea v1.22 →
  Forgejo v10.0.x**; для Gitea 1.23+ нужна ручная правка БД или миграция
  репозиториев в приложении: [Gitea compatibility](https://forgejo.org/2024-12-gitea-compatibility/).
  Для текущего homelab (Gitea 1.27.x) переход не прозрачен.
- Официальных системных требований (RAM/диск) Forgejo не публикует; README
  позиционирует проект как лёгкий — «Forgejo can easily be hosted on nearly
  every machine».

## Вывод для homelab

1. **Хостинг собственных пакетов и образов уже решён** без новых компонентов:
   Gitea Packages на текущем Gitea 1.27.x умеет и npm-пакеты, и контейнерные
   образы, а вход пользователей работает через OIDC (Pocket ID). Осталась
   только задача **кэширования** публичных реестров.
2. **Рекомендуемый вариант: Gitea + Verdaccio + Distribution.**
   - Verdaccio `6.9.2` закрывает npm целиком: приватный хостинг (если нужен
     отдельно от Gitea) + кэширующий uplink `registry.npmjs.org`. OIDC-вход
     возможен только через сторонний устаревший плагин `verdaccio-openid-connect`
     (3.0.0, 2024) — если OIDC для npm обязателен, это узкое место. Встроенного
     ограничения размера кэша у Verdaccio нет (диск растёт с кэшем); при
     желании ограничить кэшируемое — `cache: false` на uplink + фильтр по имени
     (`@verdaccio/package-filter`).
   - CNCF Distribution `3.1.1` — минимальный pull-through кэш Docker Hub
     (19.2 MB, ~12 MiB RAM); лимита размера нет, но есть `proxy.ttl`
     (по умолчанию 168h) для истечения кэшированных слоёв.
   - Дополнительный бюджет: ~150 MiB RAM (Verdaccio ~119 MiB + Distribution
     ~12 MiB + накладные расходы Docker), ~86 MB образов, два compose-сервиса
     за Traefik.
3. **Forgejo вместо Gitea — нецелесообразно.** Возможности пакетного реестра и
   OIDC-входа у Forgejo такие же, вес сопоставим (~104–125 MiB, образ 80.3 MB),
   но переход с Gitea 1.23+ не прозрачен (нужна ручная миграция БД), а лицензия
   с v9.0 — GPL-3.0-or-later. Менять Gitea на Forgejo ради реестров смысла нет.
4. **Альтернатива: Zot вместо Distribution.** Zot `v2.1.20` даёт встроенный
   web-UI, LDAP/OIDC, S3/GCS/Azure-хранилище и кэш on-demand при сопоставимом
   весе (~83 MiB), но официальный образ по умолчанию включает поиск + CVE
   (первый запуск качает базу trivy); для «голого» минимального кэша — собранный
   по `Dockerfile-minimal` бинарь. npm при этом всё равно закрывается Verdaccio.
5. **Избыточно для homelab:** cnpmcore (MySQL + Redis, образ 514 MB, тег на
   Docker Hub устарел); Nexus (8 GB RAM — при этом OIDC есть уже в Community
   Edition); Harbor (4–8 GB RAM); GitLab (16 GB RAM). Эти решения остаются
   актуальными только при перерастании потребностей домашней сети.

## Не подтверждённые утверждения

- **Замеры RAM** (Verdaccio ~119 MiB, Distribution ~12 MiB, Zot ~83 MiB,
  Forgejo ~104–125 MiB) — это локальные измерения `docker stats` от 2026-08-16
  на Docker Desktop (macOS), а не цифры из официальных документов. Для «самых
  лёгких» кандидатов первичных цифр не существует.
- **Замер размера образа Forgejo (80.3 MB сжатый, amd64)** — получен из
  манифеста реестра (`docker manifest inspect`/registry API, 2026-08-16), а не
  из официальной документации; официальных системных требований Forgejo не
  публикует.
- **Forgejo: даты поддержки релизов** — «16.0.2 до 2026-10-29», «15.0.6 LTS до
  2027-07-15» — по [forgejo.org/releases](https://forgejo.org/releases/) на
  2026-08-16 и могут сдвигаться.
- **«Zot npm-клиентами не поддерживается»** — выведено из того, что Zot
  реализует OCI Distribution и OCI Image спецификации и в официальных материалах
  не описывается npm-интерфейс; прямого документа «npm не поддерживается» нет.
- **«Официальный образ Zot включает расширения по умолчанию»** — подтверждено
  извлечением `/etc/zot/config.json` из опубликованного образа (search/CVE + ui
  + mgmt), а не документацией; в документации описаны расширения как опция.
- **Gitea: вклад пакетного реестра в RAM** — официально не выделен; цифра «1 GB
  RAM достаточно» относится к Gitea в целом.
- **cnpmcore: системные требования** (RAM, диск) — официального документа не
  найдено; вывод о тяжести основан на составе образа (514.2 MB) и обязательных
  внешних MySQL + Redis.
- **Zot: размер каталога базы trivy** — измерить не удалось (в образе нет
  командной оболочки).
- **Verdaccio: плагин OIDC `verdaccio-openid-connect`** — данные npm и GitHub на
  2026-08-16 (npm 3.0.0 от 2024-10-18, репозиторий deeplay-io, 16 звёзд, без
  файла лицензии, не архивирован); совместимость заявлена для Verdaccio 4/5/6 и
  с текущей 6.9.x на практике не проверялась.
- **«У Verdaccio нет управления размером кэша»** — вывод из документации uplink
  (`cache`, `maxage`) и назначения плагина `@verdaccio/package-filter` (фильтр
  по имени, а не очистка); отдельного раздела «управление размером кэша» нет.
- **Distribution `proxy.ttl`** — описание «expire proxy cache … 168h default,
  set to 0 to disable» из официальной документации конфигурации; на практике не
  проверялось.
- **Nexus: OIDC в Community Edition** — выведено из того, что в списке
  Pro-функций OIDC отсутствует (Pro-реальм — SAML и Crowd), а в документации
  аутентификации OIDC описан среди реальмов; прямой формулировки «OIDC доступен
  в CE» документация не содержит.
- **Путь колбэка OIDC-клиента Forgejo/Gitea** (`{ROOT_URL}/user/oauth2/{name}/callback`)
  — из официальной документации не подтверждён (секция `[oauth2_client]` путь не
  описывает); проверить по исходному коду не удалось — codeberg.org был
  недоступен 2026-08-16. Важно для регистрации redirect URI в Pocket ID.
- **Pull-счётчики Docker Hub** (Verdaccio 225 517 068, registry 1 764 409 466,
  nexus3 200 822 619, harbor-portal 22 789 993) — актуальны на 2026-08-16.

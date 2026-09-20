# Самостоятельно размещаемый реестр и кэш-прокси npm

Дата проверки: 2026-08-16.

## Область исследования

Рассматривается установка в homelab сервиса для npm: приватный реестр
(хостинг собственных пакетов) и/или прокси с кэшем `registry.npmjs.org`
(ускорение установок в локальной сети и защита от недоступности публичного
реестра). Ориентир — контейнер под Docker Compose + Traefik, как у остальных
сервисов репозитория.

В сравнение включены: Verdaccio, Sonatype Nexus Repository 3, JFrog Artifactory
(OSS), GitLab Package Registry, Gitea Packages (npm) — уже развёрнутый в homelab
Gitea 1.27.1, cnpmjs.org и его преемник cnpmcore (npmmirror), npm-proxy-cache и
sinopia (исторический предшественник). Критерии: лицензия, хостинг vs
прокси-кэш, хранилище, активность поддержки, Docker-образ, модель
аутентификации.

Версии, теги и даты проверены по первичным источникам: GitHub Releases API,
метаданным Docker Hub/releases.jfrog.io, официальным документациям. Там, где
утверждение не удалось подтвердить единственным первичным документом, это
отмечено явно.

## Итог

| Кандидат | Лицензия | Реестр vs прокси/кэш | Хранилище | Поддержка | Docker | Аутентификация | Практический вывод |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Verdaccio `6.9.2` | MIT | **И то и другое**: private registry + uplink-прокси с кэшем npmjs | Файловая система (по умолчанию) + storage-плагины | Активная (релиз 2026-08-02) | `verdaccio/verdaccio` (225M+ pulls) | htpasswd встроен, auth-плагины (LDAP и др.), npm-токены JWT/legacy | Главный кандидат для homelab |
| Nexus Repository 3 `3.95.1` (Community Edition) | EPL-1.0 | **И то и другое**: hosted + proxy (кэш) + group для npm | Blob stores: File, S3, Azure, Google Cloud | Активная (релиз 2026-08-13) | `sonatype/nexus3` (200M+ pulls) | Локальные users, LDAP, OIDC, SAML, Crowd | Мощный универсальный вариант, но тяжёлый (JVM) |
| JFrog Artifactory OSS `7.161.16` | Free OSS-распространение от JFrog | **OSS — только Java**; npm — только в платной платформе | Локальное/плагины | Активная | `releases-docker.jfrog.io/jfrog/artifactory-oss` | Локальные users, LDAP и др. (Pro) | Для npm не подходит — OSS Java-only |
| GitLab Package Registry (Free tier) | GitLab CE (self-managed), MIT | Только хостинг своих пакетов + redirect-fallback на npmjs (без кэша) | Объектное хранилище GitLab | Активная | Официальный GitLab image | PAT / deploy / CI-токены | Имеет смысл только если поднять GitLab |
| Gitea Packages (npm) `1.27.x` | MIT | Только хостинг своих пакетов; прокси/кэш npmjs нет | Файловое хранилище Gitea (dedup blobs + cleanup rules) | Активная | `docker.gitea.com/gitea` | Gitea personal access token | Уже есть в homelab: хостинг своих npm-пакетов бесплатно, но не кэш |
| cnpmcore (npmmirror) `4.34.3` | MIT | Self-host private npm registry; на нём работает публичный зеркальный сервис | Своё хранилище | Активная (2026-08-16) | Есть | — | Альтернатива, ориентированная на CNPM-экосистему |
| cnpmjs.org | — | — | — | Мёртв (deprecated, архивирован) | — | — | Не использовать |
| npm-proxy-cache (runk) | MIT | Только HTTP/HTTPS кэш-прокси (без реестра) | Локальный кэш | Условно активен (push 2026-07-29) | — | — | Простейший кэш без web-UI и авторизации |
| sinopia `1.4.0` | Метаданных нет | Хостинг | Локальное | Мёртв (последний тег v1.4.0, npm 2016) | — | htpasswd | Исторический, не использовать |

## Verdaccio

**Версия:** `6.9.2` (релиз 2026-08-02), MIT, репозиторий активен (последний push
2026-08-15, архивирован: нет):
[GitHub Releases `verdaccio/verdaccio`](https://github.com/verdaccio/verdaccio/releases).

Официальное описание — «lightweight private npm proxy registry» на Node.js:
[What is Verdaccio](https://verdaccio.org/docs/what-is-verdaccio/). Это ровно
нужная комбинация: приватный реестр для собственных пакетов и локальный прокси,
который кэширует зависимости по запросу («Verdaccio cache all dependencies on
demand and speed up installations in local or private networks»):
[What is Verdaccio — Proxy](https://verdaccio.org/docs/what-is-verdaccio/).

Ключевые механизмы из официальной документации:

- **Uplinks** — внешние реестры, из которых подтягиваются пакеты при отсутствии
  локально; по умолчанию `npmjs` → `https://registry.npmjs.org/`:
  [Uplinks](https://verdaccio.org/docs/uplinks),
  [Configuration File](https://verdaccio.org/docs/configuration).
- **Хранилище** — по умолчанию файловая система (`storage: ./storage`,
  переменная `VERDACCIO_STORAGE_PATH`), приватные пакеты и secret для подписи
  токенов хранятся в `.verdaccio-db`; вместо дефолтного хранилища подключаются
  storage-плагины:
  [Configuration File — Storage](https://verdaccio.org/docs/configuration).
- **Аутентификация** — встроенный `htpasswd` + `npm adduser`; через auth-плагины
  подключаются внешние провайдеры (включая LDAP); токены подписываются legacy
  (AES-256-CTR) или JWT:
  [Authentication](https://verdaccio.org/docs/authentication),
  [Configuration File — Auth и Token signature](https://verdaccio.org/docs/configuration).
- **Плагины** — пять типов: authentication, middleware, storage, theme (UI),
  filters:
  [Plugins](https://verdaccio.org/docs/plugins).
- **npm audit** — встроенный middleware обрабатывает `npm audit` на клиенте:
  [Configuration File — Audit](https://verdaccio.org/docs/configuration).
- **Фильтрация версий** — плагин `@verdaccio/package-filter` (с v6.4.0) умеет
  скрывать версии (карантин, блокировка по имени/scope):
  [Configuration File — Package Filter](https://verdaccio.org/docs/configuration).

Docker: официальный образ `verdaccio/verdaccio` (225M+ pulls):
[Docker](https://verdaccio.org/docs/docker),
[Docker Hub `verdaccio/verdaccio`](https://hub.docker.com/r/verdaccio/verdaccio).

## Sonatype Nexus Repository 3

**Версия:** `release-3.95.1-01` (2026-08-13), лицензия EPL-1.0 (публичное зеркало
исходников), репозиторий активен:
[GitHub Releases `sonatype/nexus-public`](https://github.com/sonatype/nexus-public/releases).

npm поддерживается тремя типами репозиториев:

- **hosted** — приватный хостинг собственных пакетов;
- **proxy** — кэширующий прокси внешнего реестра (`registry.npmjs.org`);
- **group** — объединение нескольких hosted/proxy за одним URL.

Описание и настройка npm-клиентов:
[npm Registry](https://help.sonatype.com/en/npm-registry.html).

Модель лицензирования: Community Edition (бесплатна) покрывает базовые
возможности, включая npm proxy/hosted/group; Pro-функции вынесены отдельно
(Content Replication, Repository Health Check и др.):
[Sonatype Nexus Repository](https://help.sonatype.com/en/sonatype-nexus-repository.html),
[Nexus Repository Professional Features](https://help.sonatype.com/en/nexus-repository-pro-features.html).

Хранилище — blob stores: файловое (по умолчанию), AWS S3, Azure Blob Store,
Google Cloud:
[Blob Stores](https://help.sonatype.com/en/blob-stores.html).

Аутентификация — локальные users, LDAP, OpenID Connect, SAML, Atlassian Crowd:
[Authentication](https://help.sonatype.com/en/authentication.html).

Docker: официальный образ `sonatype/nexus3` (200M+ pulls, обновлён 2026-08-13):
[Docker Hub `sonatype/nexus3`](https://hub.docker.com/r/sonatype/nexus3). Сервис
на JVM — заметно тяжелее Verdaccio и требует больше памяти.

## JFrog Artifactory

**Полная платформа Artifactory** полностью поддерживает npm: local (хостинг),
remote (прокси с кэшем `registry.npmjs.org`) и virtual (агрегация) репозитории,
SHA512, интеграция с npm/yarn/pnpm:
[npm Repositories](https://docs.jfrog.com/artifactory/docs/npm-repositories.md),
[Supported Package Types](https://docs.jfrog.com/artifactory/docs/supported-package-types.md).

**Критичное ограничение:** бесплатная редакция **Artifactory OSS** официально
позиционируется как «for Java Package Management» — «Get JFrog Artifactory's
free, open source version and manage Java binary artifacts centrally»:
[JFrog Open Source](https://jfrog.com/open-source/). npm в OSS не входит;
поддержка npm описывается для полной (платной) платформы. Отдельного документа,
где дословно сказано «npm не поддерживается в OSS», найти не удалось — вывод
сделан из официального описания OSS как Java-редакции
(см. раздел «Не подтверждённые утверждения»).

Текущая версия OSS — `7.161.16` (по метаданным RPM-репозитория
`releases.jfrog.io`). Установка — tar.gz, Docker Compose, RPM, DEB, Helm; образ
`releases-docker.jfrog.io/jfrog/artifactory-oss:latest`:
[Download Artifactory OSS](https://jfrog.com/community/download-artifactory-oss/).

Итог: для npm в homelab Artifactory OSS не подходит; использование Pro не
оправдано для домашней сети.

## GitLab Package Registry

npm-реестр доступен во всех тирах (включая **Free**) и в self-managed
инсталляциях: [npm packages in the package registry](https://docs.gitlab.com/user/packages/npm_registry/).
Поддерживает publish/install (project/group/instance endpoints), dist-tags,
deprecate, delete, `npm audit`:
[npm packages — publish/install/audit](https://docs.gitlab.com/user/packages/npm_registry/).

Аутентификация — Personal/Group/Project access token (scope `api`), deploy token
или CI job token:
[npm packages — Authenticate](https://docs.gitlab.com/user/packages/npm_registry/).

Важно: GitLab — это **хостинг своих пакетов**, а не кэш-прокси. Для не
найденных пакетов он делает redirect-fallback на `npmjs.com` (клиент уходит в
публичный реестр, кэша локально не остаётся):
[npm packages — Package forwarding to npmjs.com](https://docs.gitlab.com/user/packages/npm_registry/).
Отдельный Dependency Proxy для пакетов существует, но в домашней сети поднятие
GitLab ради npm — непропорционально большой шаг по сравнению с Verdaccio.

## Gitea Packages (npm)

Gitea имеет встроенный npm registry; документация версии 1.27 (соответствует
развёрнутому в homelab Gitea 1.27.1):
[NPM Package Registry](https://docs.gitea.com/usage/packages/npm). URL реестра —
`https://<host>/api/packages/{owner}/npm/`; поддерживаются scoped и unscoped
пакеты и команды `npm install`, `npm ci`, `npm publish`, `npm unpublish`,
`npm dist-tag`, `npm view`, `npm search`:
[NPM Package Registry — Supported commands](https://docs.gitea.com/usage/packages/npm).
Аутентификация — personal access token с правами на пакеты:
[NPM Package Registry — Configuring](https://docs.gitea.com/usage/packages/npm).

Ограничение: это **только хостинг** — прокси/кэша `registry.npmjs.org` в
документации нет. Хранилище — файловое хранилище Gitea с дедупликацией blob и
cleanup rules:
[Packages Storage](https://docs.gitea.com/usage/packages/storage).

Практический вывод: хостинг собственных npm-пакетов уже возможен на текущем
Gitea без новых компонентов, но он не решает задачу кэширования публичных
зависимостей.

## cnpmjs.org и cnpmcore (npmmirror)

**cnpmjs.org** — deprecated и архивирован; описание репозитория прямо
перенаправляет на `cnpm/cnpmcore`:
[GitHub `cnpm/cnpmjs.org`](https://github.com/cnpm/cnpmjs.org).

**cnpmcore** — «Private NPM Registry for self-host», MIT, активен (последний
push 2026-08-16, релиз `4.34.3` 2026-08-16). Именно на нём работает публичный
зеркальный сервис `registry.npmmirror.com`:
[GitHub `cnpm/cnpmcore`](https://github.com/cnpm/cnpmcore),
[GitHub Releases](https://github.com/cnpm/cnpmcore/releases).

Работоспособный self-host вариант, но проект ориентирован на китайскую
экосистему npmmirror; для homelab преимуществ над Verdaccio не даёт.

## npm-proxy-cache

`runk/npm-proxy-cache` — «HTTP/HTTPS caching proxy for npm», MIT, активен
(последний push 2026-07-29), но маленький проект (164 stars):
[GitHub `runk/npm-proxy-cache`](https://github.com/runk/npm-proxy-cache).

Это чистый кэш-прокси: реестра (хостинга собственных пакетов), web-UI и
авторизации пользователей нет. Годится только как очень простой слой кэша для
публичных пакетов, если нужен минимальный вес.

## sinopia

`rlidwka/sinopia` — «Private npm repository server», последний тег `v1.4.0`
(последняя публикация на npm — 2024-10-22, фактически не поддерживается; в
метаданных GitHub лицензия не указана):
[GitHub `rlidwka/sinopia`](https://github.com/rlidwka/sinopia),
[npm `sinopia`](https://www.npmjs.com/package/sinopia).

Исторический предшественник семейства реестров, на смену которому пришёл
Verdaccio (репозиторий Verdaccio создан в 2016 году, после остановки развития
sinopia). Связь «Verdaccio = форк sinopia» в текущей сессии не удалось
подтвердить первичным документом (см. ниже). Использовать sinopia в новых
установках смысла нет.

## Вывод для homelab

1. **Verdaccio** — основной кандидат. Node.js (не JVM), одна задача — npm,
   лицензия MIT, активная разработка, официальный Docker-образ и заявленная
   совместимость с npm/yarn/pnpm. Закрывает обе потребности сразу: приватный
   реестр собственных пакетов и кэширующий uplink на `registry.npmjs.org`
   (включая встроенную обработку `npm audit`). Разворачивается одной compose
   службой за Traefik; auth по htpasswd с возможностью расширения плагинами.
2. **Nexus Repository 3 (Community Edition)** — рациональная альтернатива, если
   со временем понадобится единый реестр для нескольких форматов (npm + Maven +
   Docker и др.): hosted/proxy/group для npm, blob stores на S3-совместимое
   хранилище, OIDC/SAML из коробки. Минус — вес и потребление памяти (JVM).
3. **Gitea Packages (npm)** — можно использовать уже сейчас, без новых
   компонентов, для хостинга приватных npm-пакетов (например, собственных
   библиотек), даже если не разворачивать Verdaccio. Кэша публичных зависимостей
   он не даёт.

Artifactory OSS для npm не подходит; GitLab — только при появлении GitLab в
homelab; cnpmjs.org и sinopia мертвы; npm-proxy-cache слишком ограничен
(нет реестра и auth).

## Не подтверждённые утверждения

- **«npm не поддерживается в Artifactory OSS»** — прямого документа с такой
  формулировкой найти не удалось. Утверждение основано на официальном описании
  OSS как «for Java Package Management»
  ([jfrog.com/open-source](https://jfrog.com/open-source/)) и том, что вся
  документация по npm относится к полной платформе
  ([npm-repositories.md](https://docs.jfrog.com/artifactory/docs/npm-repositories.md)).
- **«Verdaccio — форк sinopia»** — факт широко известен, но в первичных
  документах обеих проектов (README, официальные доки, метаданные GitHub/npm)
  явной формулировки в текущей сессии не обнаружено. Подтверждены только
  времена создания (sinopia 2013, Verdaccio 2016) и что sinopia не развивается.
- **cnpmcore: модель аутентификации и типы хранилища** — в деталях не
  проверялись (за решением «не использовать» этот пробел не влияет).

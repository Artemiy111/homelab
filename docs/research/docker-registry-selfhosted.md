# Самостоятельно размещаемый реестр контейнеров (OCI/Docker) и комбинированные решения npm + Docker

Дата проверки: 2026-08-16.

## Область исследования

Рассматривается установка в homelab сервиса для контейнерных образов: приватный
реестр (хостинг собственных образов) и/или прокси с кэшем Docker Hub
(ускорение pull в локальной сети и защита от недоступности/rate-limit публичного
реестра). Ориентир — контейнер под Docker Compose + Traefik, как у остальных
сервисов репозитория.

В сравнение включены реестры: CNCF Distribution (Docker Distribution, `registry`),
Harbor, Gitea Container Registry (уже развёрнутый в homelab Gitea 1.27.1),
GitLab Container Registry, Zot, Quay, а также нереестровые ускорители Dragonfly и
Spegel. Отдельно рассмотрены комбинированные решения «npm + Docker» кроме Nexus
(он покрыт в отдельном документе): Gitea Packages, GitLab Package Registry,
JFrog Artifactory и связка «два отдельных инструмента». Критерии: лицензия,
хостинг vs прокси-кэш, хранилище, активность поддержки, Docker-образ, модель
аутентификации.

Версии, теги и даты проверены по первичным источникам: GitHub Releases API,
метаданным Docker Hub, официальным документациям. Там, где утверждение не
удалось подтвердить единственным первичным документом, это отмечено явно.

## Итог

### Docker-реестры

| Кандидат | Лицензия | Хостинг vs прокси/кэш | Хранилище | Поддержка | Docker | Аутентификация | Практический вывод |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CNCF Distribution `3.1.1` | Apache-2.0 | **И то и другое**: хостинг + официальный рецепт pull-through cache | Локальная ФС (по умолчанию) + драйверы azure/gcs/s3/inmemory | Активная (push 2026-08-10) | `registry` / `distribution/registry` (1,76 млрд pulls) | htpasswd (basic auth) или token auth (спецификация) | База всей экосистемы: минимум зависимостей, подходит как простой хостинг и кэш |
| Harbor `2.15.2` | Apache-2.0 | **И то и другое**: хостинг + proxy cache (Docker Hub и другие) | filesystem (по умолчанию) + azure/gcs/s3/swift/oss | Активная (push 2026-08-16) | `goharbor/harbor-portal` (22,8M pulls) | DB, LDAP, OIDC | Полнофункциональный self-host реестр с web-UI и сканированием, но заметно тяжелее Distribution |
| Gitea Container Registry `1.27.x` | MIT | **Только хостинг** своих образов; прокси/кэша Docker Hub нет | Локальная ФС (по умолчанию) + minio (S3-совместимое) + azureblob | Активная (1.27.2, 2026-08-13) | `docker.gitea.com/gitea` | Gitea personal access token | Уже есть в homelab: хостинг своих образов бесплатно, но не кэш |
| GitLab Container Registry `19.2.x` | GitLab CE (self-managed), MIT | **Только хостинг** своих образов; proxy-кэша в документации нет | filesystem (по умолчанию) + azure/gcs/s3 | Активная (релиз 2026-08-11) | Официальный GitLab image | GitLab PAT / deploy / CI-токены | Имеет смысл только если поднять GitLab |
| Zot `2.1.20` | Apache-2.0 | **И то и другое**: хостинг + pull-through cache (on-demand) | Локальная ФС + S3/GCS/Azure Blob | Активная (push 2026-08-16) | `ghcr.io/project-zot/zot` | htpasswd, LDAP, OAuth2/OIDC, mTLS | Лёгкий современный реестр с кэшем; перспективный кандидат для homelab |
| Quay `3.17.4` | Apache-2.0 | **И то и другое**: хостинг + proxy cache (per-org, без rate-limit) | local/S3/GCS/Swift/Ceph/ODF | Активная (push 2026-08-16) | `quay.io/projectquay/quay` | LDAP/Keystone/OIDC/Google/GitHub | Мощный, но требует PostgreSQL и Redis; тяжёлый для homelab |
| Dragonfly `2.5.1` | Apache-2.0 | Не реестр: P2P-ускорение доставки образов | Локальные кэши нод | Активная (CNCF Graduated, push 2026-08-14) | `dragonflyoss/dragonfly` | — | Оверкилл для homelab; оправдан только в крупных кластерах |
| Spegel `0.7.4` | MIT | Не реестр: кэш-зеркало между нодами кластера | containerd store нод | Активная (push 2026-07-15) | `ghcr.io/spegel-org/spegel` | — | Только Kubernetes + containerd; для Docker Compose неприменим |

### Комбинированные решения «npm + Docker» (кроме Nexus)

| Кандидат | Лицензия | npm + Docker | Прокси/кэш | Хранилище | Поддержка | Docker | Аутентификация | Практический вывод |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Gitea Packages `1.27.x` | MIT | **Да, оба**: npm registry + container registry | Нет — только хостинг и для npm, и для образов | Файловое хранилище Gitea (dedup blobs) + minio/azureblob | Активная | `docker.gitea.com/gitea` | Gitea personal access token | Уже в homelab: хостинг npm-пакетов и образов бесплатно, но без кэша |
| GitLab Package Registry `19.2.x` | GitLab CE, MIT | **Да, оба**: npm + container registry (оба в Free tier) | Нет — хостинг; для npm redirect-fallback на npmjs без кэша | Объектное хранилище GitLab | Активная | Официальный GitLab image | PAT / deploy / CI-токены | Полный «комбайн», но непропорционально большой шаг для домашней сети |
| JFrog Artifactory | OSS: «for Java Package Management» | Нет в OSS: и npm, и Docker только в платной платформе | — | — | Активная | — | — | Для homelab не подходит (платно или не поддерживает форматы) |
| Два отдельных инструмента (Verdaccio + Distribution/Harbor/Zot) | MIT / Apache-2.0 | **Да, оба**, каждый в своей роли | Да: Verdaccio — кэш npmjs, реестр — pull-through cache Docker Hub | По инструментам | Активная | По инструментам | По инструментам | Прагматичное решение: закрывает хостинг и кэш обоих типов |

## CNCF Distribution (Docker Distribution, `registry`)

**Версия:** `v3.1.1` (релиз 2026-05-01), лицензия Apache-2.0, репозиторий активен
(последний push 2026-08-10, 10 566 stars):
[GitHub Releases `distribution/distribution`](https://github.com/distribution/distribution/releases).

Официальное описание — «storage and content delivery system, holding named
container images»: [About Registry](https://distribution.github.io/distribution/about/).
Хранилище делегируется драйверам; по умолчанию — локальная POSIX-файловая
система «suitable for development or small deployments», доступны драйверы
Filesystem, Google Cloud Storage, Microsoft Azure, S3 (inmemory — только для
тестов):
[Registry storage driver](https://distribution.github.io/distribution/storage-drivers/).

Pull-through cache Docker Hub — официальный рецепт (proxy-реестр, который
фетчит образы из upstream по запросу и кэширует локально):
[Registry as a pull through cache](https://distribution.github.io/distribution/recipes/mirror/).

Аутентификация — встроенная htpasswd (basic auth) или token auth с
поддерживаемой спецификацией токенов и OAuth2:
[Configuration — auth](https://distribution.github.io/distribution/about/configuration/),
[Token Authentication Specification](https://distribution.github.io/distribution/spec/auth/).

Docker: официальные образы `registry` (Docker Hub, тег `latest` = `3.1.1`,
обновлён 2026-06-23, 1 764 408 219 pulls) и `distribution/registry`:
[Docker Hub `library/registry`](https://hub.docker.com/r/library/registry),
[About Registry](https://distribution.github.io/distribution/about/).

## Harbor

**Версия:** `v2.15.2` (релиз 2026-07-02), лицензия Apache-2.0, репозиторий активен
(последний push 2026-08-16, 29 159 stars):
[GitHub Releases `goharbor/harbor`](https://github.com/goharbor/harbor/releases).

Proxy cache — кэширующий pull-through прокси для Docker Hub и других upstream
реестров с политиками конфиденциальности и сроком хранения:
[Configure Proxy Cache](https://goharbor.io/docs/2.15.0/administration/configure-proxy-cache/).

Аутентификация — пользователи в базе Harbor, LDAP/AD, OIDC:
[Configure Authentication](https://goharbor.io/docs/2.15.0/administration/configure-authentication/).

Хранилище — `filesystem` (по умолчанию), а также `azure`, `gcs`, `s3`, `swift`,
`oss`; внешняя БД — только PostgreSQL:
[Configuration YAML File — Storage Backend](https://goharbor.io/docs/2.15.0/install-config/configure-yml-file/).

Docker: образ `goharbor/harbor-portal` (22 789 923 pulls, обновлён 2026-08-15):
[Docker Hub `goharbor/harbor-portal`](https://hub.docker.com/r/goharbor/harbor-portal).
Развёртывание — через installer (на базе Docker Compose) или Helm.

## Gitea Container Registry

Gitea имеет встроенный container registry; документация версии 1.27 (соответствует
развёрнутому в homelab Gitea 1.27.1):
[Container Registry](https://docs.gitea.com/usage/packages/container). URL —
`https://<host>/{owner}/{image}:{tag}`, работа с клиентом `docker`:
`docker login`, `docker build/tag/push`, `docker pull`:
[Container Registry — Push and Pull](https://docs.gitea.com/usage/packages/container).
Аутентификация — пароль или personal access token (обязателен при 2FA/OAuth):
[Container Registry — Login](https://docs.gitea.com/usage/packages/container).

Ограничение: это **только хостинг** — прокси/кэша Docker Hub в документации нет
(см. раздел «Не подтверждённые утверждения»). Хранилище пакетов — файловая
система Gitea (по умолчанию), minio (S3-совместимое) или azureblob:
[Packages Storage](https://docs.gitea.com/usage/packages/storage),
[Configuration Cheat Sheet — Storage](https://docs.gitea.com/administration/config-cheat-sheet).

Практический вывод: хостинг собственных образов уже возможен на текущем Gitea
без новых компонентов, но он не решает задачу кэширования Docker Hub.

## GitLab Container Registry

Container registry доступен во всех тирах (включая **Free**) и во всех
предложениях (GitLab.com, Self-Managed, Dedicated):
[GitLab Container Registry — Tier](https://docs.gitlab.com/user/packages/container_registry/).

Реестр работает по HTTPS по умолчанию и построен на базе Docker Distribution.
Хранилище — локальная файловая система (по умолчанию,
`/var/opt/gitlab/gitlab-rails/shared/registry`) с возможностью объектного
хранилища; поддерживаемые драйверы: `filesystem`, `azure` (Azure Blob Storage),
`gcs` (Google Cloud Storage), `s3` (Amazon S3 и совместимые):
[Configure storage for the container registry](https://docs.gitlab.com/administration/packages/container_registry/).

Аутентификация — учётные записи GitLab (PAT, deploy/CI-токены).

Версия: последний стабильный релиз GitLab — `v19.2.2` (2026-08-11; master —
`19.3.0-pre`):
[GitLab tags](https://gitlab.com/gitlab-org/gitlab/-/tags).

Практический вывод: полноценный integrated-реестр, но поднятие GitLab ради него
непропорционально большой шаг для домашней сети.

## Zot

**Версия:** `v2.1.20` (релиз 2026-08-04), лицензия Apache-2.0, репозиторий активен
(последний push 2026-08-16, 2 622 stars):
[GitHub Releases `project-zot/zot`](https://github.com/project-zot/zot/releases).

Pull-through cache — on-demand прокси Docker Hub (включая совместимость с
Docker client через `docker2s2` и `preserveDigest` для подписи содержимого):
[Using zot as a Docker pull-through cache](https://zotregistry.dev/v2.1.20/articles/docker/#using-zot-as-a-docker-pull-through-cache).

Хранилище — локальная файловая система и объектные хранилища S3, Google Cloud,
Azure Blob:
[Storage](https://zotregistry.dev/v2.1.20/articles/storage/).

Аутентификация — TLS/mTLS, htpasswd, LDAP, OAuth2/OIDC, с поддержкой API-ключей:
[Authentication & Authorization](https://zotregistry.dev/v2.1.20/articles/authn-authz/).

Docker: образ `ghcr.io/project-zot/zot` (deploy по документации проекта):
[Deploy](https://zotregistry.dev/v2.1.20/articles/).

## Quay

**Версия:** `v3.17.4` (релиз 2026-08-12), лицензия Apache-2.0, репозиторий активен
(последний push 2026-08-16, 2 819 stars):
[GitHub Releases `quay/quay`](https://github.com/quay/quay/releases).

Официальные возможности из README: Docker Registry v2, OCI v1.1, аутентификация
LDAP/Keystone/OIDC/Google/GitHub, хранилища локальное/S3/GCS/Swift/Ceph/ODF,
сканирование уязвимостей Clair:
[GitHub `quay/quay` — README](https://github.com/quay/quay).

Proxy cache — кэширующий pull-through прокси для upstream реестров (Docker Hub и
др.) с обходом rate-limit, политикой срока хранения, настройкой per-org и
возможностью сканирования кэшированных образов:
[Quay docs — proxy cache](https://github.com/quay/quay-docs).

Docker: образ `quay.io/projectquay/quay`. Развёртывание требует PostgreSQL и
Redis, полноценная эксплуатация — через Quay Operator (Kubernetes), что для
homelab на Docker Compose избыточно.

## Dragonfly

**Версия:** `v2.5.1` (релиз 2026-07-27), лицензия Apache-2.0, репозиторий активен
(последний push 2026-08-14, 3 298 stars), CNCF **Graduated**:
[GitHub Releases `dragonflyoss/dragonfly`](https://github.com/dragonflyoss/dragonfly/releases).

Это не hosted-реестр, а P2P-система ускорения доставки образов: контейнерные
ноды распределяют слои образов друг другу, сокращая трафик до registry:
[GitHub `dragonflyoss/dragonfly` — README](https://github.com/dragonflyoss/dragonfly).

Для homelab на одном-двух хостах оверкилл; применение оправдано в больших
кластерах с массовыми pull одних и тех же образов.

## Spegel

**Версия:** `v0.7.4` (релиз 2026-07-15), лицензия MIT, репозиторий активен
(последний push 2026-07-15, 3 740 stars):
[GitHub Releases `spegel-org/spegel`](https://github.com/spegel-org/spegel/releases).

«Stateless cluster-local OCI registry mirror» — кэширует и отдаёт образы между
нодами Kubernetes-кластера, распространяя их по containerd store нод:
[Getting started](https://spegel.dev/docs/getting-started/).

Требует Kubernetes + containerd. Для стека Docker Compose, используемого в
homelab, неприменим.

## Комбинированные решения «npm + Docker» (кроме Nexus)

### Gitea Packages

На одном экземпляре Gitea доступны и npm registry, и container registry (обе
функции — хостинг своих пакетов/образов, без прокси-кэша):
[NPM Package Registry](https://docs.gitea.com/usage/packages/npm),
[Container Registry](https://docs.gitea.com/usage/packages/container).
Хранилище общее для всех типов пакетов — файловое хранилище Gitea с
дедупликацией blob и cleanup rules:
[Packages Storage](https://docs.gitea.com/usage/packages/storage).

Практический вывод: минимально достаточное решение для хостинга собственных
npm-пакетов и образов на уже развёрнутом Gitea.

### GitLab Package Registry

И npm (все тиры, включая Free), и container registry (Free) доступны в
self-managed GitLab:
[npm packages in the package registry](https://docs.gitlab.com/user/packages/npm_registry/),
[GitLab Container Registry — Tier](https://docs.gitlab.com/user/packages/container_registry/).

Обе функции — хостинг своих пакетов; для npm есть redirect-fallback на npmjs без
локального кэша:
[npm packages — Package forwarding to npmjs.com](https://docs.gitlab.com/user/packages/npm_registry/).
Один экземпляр покрывает и npm, и образы, но требует поднятия GitLab целиком.

### JFrog Artifactory

Бесплатная редакция **Artifactory OSS** официально позиционируется как «for Java
Package Management» — «manage Java binary artifacts centrally»:
[JFrog Open Source](https://jfrog.com/open-source/). Поддержка и npm, и Docker
описывается только для полной (платной) платформы:
[npm Repositories](https://docs.jfrog.com/artifactory/docs/npm-repositories.md),
[Supported Package Types](https://docs.jfrog.com/artifactory/docs/supported-package-types.md).
Для homelab не подходит (платно или не поддерживает нужные форматы).

### Связка «два отдельных инструмента»

Скомбинировать покрытие npm (Verdaccio или Nexus) и контейнеров
(Distribution/Harbor/Zot) двумя лёгкими сервисами. Оба компонента независимы,
каждый уже проверен по первичным источникам в этом и соседнем документах.
Минус — два сервиса и две точки настройки вместо одного, плюс — каждый решает
свою задачу полноценно (хостинг + кэш).

## Вывод для homelab

1. **Хостинг собственных образов уже решён:** Gitea Container Registry на текущем
   Gitea 1.27.1 позволяет push/pull приватных образов без новых компонентов.
   Этого достаточно, если нужен только хостинг.
2. **Кэш/прокси Docker Hub (ускорение pull и защита от rate-limit) — главный
   недостающий кусок.** Здесь три разумных варианта:
   - **CNCF Distribution `3.1.1`** — минимальный вес и одна роль: реестр +
     официальный рецепт pull-through cache. Хорошо ложится на Docker Compose +
     Traefik, auth по htpasswd или token.
   - **Zot `2.1.20`** — лёгкий современный реестр со встроенным pull-through
     cache (on-demand), S3/GCS/Azure-хранилищем и OIDC из коробки; чуть больше
     возможностей, чем голый Distribution, при сопоставимом весе.
   - **Harbor `2.15.2`** — если нужен полнофункциональный реестр с web-UI,
     сканированием и proxy cache «из коробки»; заметно тяжелее (отдельный
     PostgreSQL, набор контейнеров).
3. **Комбинированное «npm + Docker» (кроме Nexus):** Nexus остаётся самым
   целостным универсальным вариантом (см. документ по npm). Среди «лёгких»
   комбинаций лучший путь — использовать уже развёрнутый **Gitea Packages** для
   хостинга и npm-пакетов, и образов, а кэширование публичных зависимостей и
   Docker Hub закрыть парой лёгких прокси (Verdaccio + Distribution или Zot).
   GitLab подходит только при готовности поднять GitLab целиком; Artifactory OSS
   — нет.

## Не подтверждённые утверждения

- **«Gitea Container Registry не имеет прокси/кэша Docker Hub»** — прямого
  документа с такой формулировкой нет. Утверждение основано на том, что
  официальная документация описывает только push/pull собственных образов
  ([Container Registry](https://docs.gitea.com/usage/packages/container));
  наличие скрытой возможности не исключено (аналогично тому, как в документе по
  npm выводилось отсутствие прокси для Gitea npm).
- **«GitLab Container Registry не имеет proxy-кэша»** — в документации
  самоуправляемого GitLab (admin и user guide) описан только хостинг образов;
  наличие pull-through функции не проверялось отдельно.
- **«npm и Docker не поддерживаются в Artifactory OSS»** — основано на
  официальном описании OSS как «for Java Package Management»
  ([jfrog.com/open-source](https://jfrog.com/open-source/)); прямого документа с
  перечнем неподдерживаемых в OSS форматов найти не удалось.
- **Zot: точная конфигурация pull-through cache** — детальные параметры
  (расписания синхронизации, политики сохранности) в текущей сессии в деталях
  не проверялись; подтверждён сам механизм on-demand кэша
  ([Zot — pull-through cache](https://zotregistry.dev/v2.1.20/articles/docker/#using-zot-as-a-docker-pull-through-cache)).

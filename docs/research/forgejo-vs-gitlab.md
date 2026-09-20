# Forgejo vs GitLab CE: сравнение self-hosted Git-платформ для homelab

Дата проверки: 2026-08-17.

## Область исследования

Задача — сравнить **Forgejo** и **GitLab Community Edition (CE)** как
саморазмещаемые платформы для хостинга Git-репозиториев в условиях homelab.
Forgejo — лёгкий форк Gitea под лицензией GPL-3.0-or-later, развивается
некоммерческой организацией Codeberg e.V. GitLab CE — open-core платформа
компании GitLab Inc., ядро распространяется под MIT-лицензией, но
представляет собой полноценную DevOps-платформу с значительно бо́льшим
весом.

Сравнение проводится по восьми осям: лицензия, потребление ресурсов,
функциональность, частота релизов, путь миграции, экосистема сообщества,
управление проектом и сложность эксплуатации. Источники — официальные
документации, репозитории, LICENSE-файлы, страницы релизов, Docker Hub.

## Лицензия

### Forgejo

**GPL-3.0-or-later** — с версии 9.0 (коммит «Forgejo v9.0 is GPLv3+»,
2024-07-25). До v9.0 использовалась MIT-лицензия.

- Файл лицензии: [codeberg.org/forgejo/forgejo/LICENSE](https://codeberg.org/forgejo/forgejo/raw/branch/forgejo/LICENSE)
- Проект **гарантирует** распространение исключительно под свободными
  лицензиями: «Forgejo will always be Free and Open Source Software»
  ([forgejo.org](https://forgejo.org)).
- DCO (Developer Certificate of Origin) вместо передачи авторских прав.

### GitLab CE

**MIT License** — для Community Edition
([LICENSE](https://gitlab.com/gitlab-org/gitlab-foss/-/blob/master/LICENSE)).
Enterprise Edition распространяется под собственной лицензией
[GitLab Enterprise Edition license](https://gitlab.com/gitlab-org/gitlab/-/blob/master/ee/LICENSE).

- **Open Core**: многие функции доступны только в EE (Premium/Ultimate):
  Dependency Proxy для container registry, Advanced LDAP/SAML
  (синхронизация групп), Audit Events, Compliance Frameworks, SAST/DAST
  и другие
  ([Feature comparison](https://about.gitlab.com/pricing/feature-comparison/)).
- CE не содержит код EE; при истечении лицензии EE можно перейти обратно
  на CE, но функции EE станут недоступны
  ([FAQ](https://about.gitlab.com/pricing/#what-happens-if-i-decide-not-to-renew-my-subscription)).

### Практические последствия для homelab

| Аспект | Forgejo (GPL-3.0+) | GitLab CE (MIT) |
| --- | --- | --- |
| Использование в homelab | Без ограничений | Без ограничений |
| Модификация и пересборка | Обязанность предоставить исходный код при распространении | Без ограничений |
| Open Core / платные функции | Нет — гарантия FOSS | Да — многие функции только в EE |
| Интеграция с проприетарным ПО | Ограничено (copyleft) | Без ограничений |

Для homelab-сценария разница в лицензиях **практически незначима**: обе
лицензии позволяют свободно использовать для собственных нужд. Ключевое
отличие — GitLab использует модель Open Core: бесплатная CE версия намеренно
ограничена по функциональности по сравнению с платными тирами.

## Потребление ресурсов

### Docker-образы (сжатые, linux/amd64)

| Проект | Тег | Размер образа | Источник |
| --- | --- | --- | --- |
| Forgejo | `codeberg.org/forgejo/forgejo:16.0.2` | 80.3 MB | `docker manifest inspect`, 2026-08-16 |
| GitLab CE | `gitlab/gitlab-ce:latest` (19.1.0) | 1 330 MB | [Docker Hub](https://hub.docker.com/r/gitlab/gitlab-ce) |

GitLab CE образ **в ~16.6 раз тяжелее** Forgejo. Это объясняется тем, что
образ GitLab CE (Omnibus) содержит Rails-приложение, Sidekiq, Puma, Gitaly,
PostgreSQL, Redis, Prometheus, Grafana и десятки других компонентов
([Install GitLab in Docker](https://docs.gitlab.com/install/docker/installation/)).

### Системные требования

| Параметр | Forgejo | GitLab CE |
| --- | --- | --- |
| Минимум CPU | Не документировано (2 ядра рекомендация Gitea) | **8 vCPU** (single-node baseline) |
| Минимум RAM | Не документировано (~104–125 MiB idle изм.) | **16 GB** (baseline), 8 GB (ограниченная среда) |
| Минимум диск | Не документировано | 40 GB (приложение) + репозитории + PostgreSQL |
| База данных | SQLite, PostgreSQL, MySQL | Только PostgreSQL |
| Redis/Valkey | Нет (не требуется) | **Обязательно** (Redis ≥ 7.0 или Valkey ≥ 7.2) |
| Raspberry Pi | «Easily hosted on nearly every machine» | Не рекомендуется |

Источники:
- Forgejo: [README](https://codeberg.org/forgejo/forgejo) — «Forgejo can
  easily be hosted on nearly every machine»
- GitLab: [Installation requirements](https://docs.gitlab.com/install/requirements/)

### Потребление RAM (локальные измерения, Reference doc)

Из документа [registry-lightweight-comparison.md](registry-lightweight-comparison.md):
- Forgejo: idle RAM ~104–125 MiB (SQLite, Actions и индексаторы отключены,
  Docker Desktop macOS)
- GitLab CE: официальные требования — **16 GB RAM** minimum (baseline),
  8 GB в memory-constrained среде
  ([running GitLab in a memory-constrained environment](https://docs.gitlab.com/omnibus/settings/memory_constrained_envs/))

### Сравнение ресурсов

| Параметр | Forgejo 16.x | GitLab CE 19.x | Соотношение |
| --- | --- | --- | --- |
| Docker образ (amd64) | 80.3 MB | 1 330 MB | **16.6x** |
| RAM idle (изм.) | ~104–125 MiB | ≥ 8 000 MiB (мин.) | **64–77x** |
| RAM baseline (документ.) | Не документировано | 16 384 MiB | **131–157x** |
| Своя БД | SQLite включён | PostgreSQL (отдельно) | — |
| Redis | Не нужен | Обязательно | — |
| Компонентов в образе | 1 (бинарник) | 10+ (Omnibus) | — |

## Функциональное сравнение

### Таблица сравнения возможностей

| Возможность | Forgejo 16.x | GitLab CE 19.x | Примечания |
| --- | --- | --- | --- |
| **Хостинг репозиториев** | Да | Да | Базовая функциональность |
| **CI/CD** | Forgejo Actions (GitHub Actions compatible) | GitLab CI/CD (встроенный, `.gitlab-ci.yml`) | См. детали ниже |
| **Container Registry** | Да | Да | В CE без Dependency Proxy (EE) |
| **Package Registry** | 20+ форматов (npm, PyPI, Cargo, Helm и др.) | npm, PyPI, Maven, Helm, NuGet, Generic, Terraform Module | GitLab CE: fewer форматов, но proxy только в Premium |
| **LDAP** | Да | Да | CE: базовый; Premium: синхронизация групп |
| **OIDC (вход/RP)** | Да (`[oauth2_client]`) | Да (OIDC/OAuth2/OmniAuth) | Оба поддерживают |
| **SAML 2.0** | Нет | Да (в CE для Self-Managed) | [SAML SSO for GitLab Self-Managed](https://docs.gitlab.com/ee/integration/saml/) |
| **OAuth2 Provider** | Да | Да (в CE) | GitLab как OIDC/OAuth2 провайдер |
| **WebAuthn / 2FA** | Да | Да | Многофакторная аутентификация |
| **API (REST)** | Да | Да (REST + GraphQL) | GitLab также предоставляет GraphQL API |
| **Webhooks** | Да | Да | Интеграция с внешними сервисами |
| **Wiki** | Да | Да | Версионная документация |
| **Snippets** | Да | Да | Фрагменты кода |
| **Code Review** | Да (Pull Requests) | Да (Merge Requests + approvals) | GitLab: multi-approver, approval rules |
| **Protected Branches** | Да | Да | Оба поддерживают |
| **Pages (статический хостинг)** | Нет | Да (GitLab Pages) | Требует wildcard DNS |
| **Issue Tracking** | Да | Да | GitLab: Labels, Milestones, Iterations, Epics |
| **Project Management** | Базовый (Issues, Labels, Projects) | Полный (Issues, Epics, Iterations, Roadmap, Time Tracking) | GitLab значительно богаче |
| **Package Forwarding / Proxy** | Нет | Premium/Ultimate (npm, Maven, PyPI) | Dependency Proxy для контейнеров — EE only |
| **SAST / DAST / Secret Detection** | Нет | CE: базовый; Premium/Ultimate: полный | Open Core модель |
| **Geo (мультисайт)** | Нет | EE only | Репликация для геораспределённых команд |
| **Container Image Signatures** | Нет | Да (Cosign,OCI 1.1) | GitLab 17.1+ |
| **Federation** | В разработке | Нет | Forgejo активно работает |

### CI/CD: Forgejo Actions vs GitLab CI/CD

**Forgejo Actions** — совместимая с GitHub Actions система CI/CD. Требует
отдельный компонент **runner** для выполнения задач:
- Forgejo Runner: [Forgejo Runner](https://forgejo.org/docs/latest/admin/actions/)
- Синтаксис: `.github/workflows/` YAML-файлы (те же, что и GitHub Actions)
- Преимущества: огромная экосистема готовых Actions из GitHub Marketplace

**GitLab CI/CD** — встроенная система CI/CD, не требующая внешних компонентов
(кроме runner'а). Конфигурация в `.gitlab-ci.yml`:
- GitLab Runner: отдельный компонент ([GitLab Runner](https://docs.gitlab.com/runner/))
- Преимущества: глубокая интеграция с платформой (environments, deployments,
  review apps, Auto DevOps, security scanning)
- CE включает базовый CI/CD; продвинутые функции (CI/CD Catalog,
  required pipelines) — в Premium/Ultimate

| Аспект CI/CD | Forgejo Actions | GitLab CI/CD |
| --- | --- | --- |
| Файл конфигурации | `.github/workflows/*.yml` | `.gitlab-ci.yml` |
| Совместимость | GitHub Actions | Собственный формат |
| Runner | Forgejo Runner (отдельный) | GitLab Runner (отдельный) |
| Встроенные templates | Нет | Да (Auto DevOps) |
| Security scanning | Через внешние Actions | Встроен (CE: базовый, EE: полный) |
| Environments / Deployments | Через внешние Actions | Встроенные |

### Container Registry

Forgejo и GitLab CE оба предоставляют встроенный container registry для
хостинга OCI/Docker образов.

- **Forgejo**: хостинг собственных образов, без pull-through cache
  ([Container Registry](https://forgejo.org/docs/v16.0/user/packages/container/))
- **GitLab CE**: хостинг образов, multi-architecture поддержка,
  container image signatures (Cosign), но **Dependency Proxy** (pull-through
  cache для Docker Hub) — только в Premium/EE
  ([Container Registry](https://docs.gitlab.com/ee/user/packages/container_registry/),
  [Dependency Proxy](https://docs.gitlab.com/ee/user/packages/dependency_proxy/))

### Package Registry

| Формат | Forgejo | GitLab CE | GitLab Premium+ |
| --- | --- | --- | --- |
| npm | Да | Да | Да + forwarding |
| PyPI | Да | Да | Да + forwarding |
| Maven | Да | Да | Да + forwarding |
| Helm | Да | Да | Да |
| Cargo | Да | Нет | Нет |
| Conan | Да | Нет | Нет |
| NuGet | Да | Да | Да |
| Generic | Да | Да | Да |

Forgejo поддерживает **20+ форматов** пакетов
([Package Registry](https://forgejo.org/docs/v16.0/user/packages/)),
в то время как GitLab — меньше, но с возможностью проксирования
(pull-through) для ключевых реестров в платных тирах.

### Аутентификация

| Метод | Forgejo | GitLab CE | GitLab Premium+ |
| --- | --- | --- | --- |
| Встроенная аутентификация | Да | Да | Да |
| LDAP | Да | Да | Да + синхронизация групп |
| OIDC (вход/RP) | Да | Да | Да |
| SAML 2.0 | Нет | **Да** (Self-Managed) | Да + Group Sync |
| OAuth2 Provider | Да | Да | Да |
| WebAuthn / 2FA | Да | Да | Да |
| SCIM | Нет | Нет | Premium (Self-Managed) |

GitLab CE поддерживает **SAML 2.0** для self-managed установок — это
отличие от Forgejo, где SAML отсутствует
([SAML SSO for GitLab Self-Managed](https://docs.gitlab.com/ee/integration/saml/)).

## Частота релизов и поддержка

### Forgejo

- **Частота**: четвертные релизы (каждые 3 месяца) по фиксированному
  расписанию.
- **Последние релизы**:
  - 16.0.2 (2026-07-30) — стабильный, поддержка до 2026-10-29
  - 15.0.6 (2026-07-30) — LTS, поддержка до 2027-07-15
- **LTS-политика**: документирована. LTS-версия выходит в первом квартале
  каждого года и поддерживается **15 месяцев** (3 месяца стабильной + 12
  месяцев LTS)
  ([Release schedule](https://forgejo.org/docs/latest/admin/release-schedule/)).
- **Security-уведомления**: публичные, доступны всем через
  [security-announcements](https://codeberg.org/forgejo/security-announcements/issues).
- **Semantic Versioning**: соблюдается с версии 7.0.0.

### GitLab CE

- **Частота**: ежемесячные релизы (3-й четверг каждого месяца) +
  патч-релизы **дважды в месяц** (среда до и после ежемесячного релиза)
  ([Monthly releases](https://handbook.gitlab.com/handbook/engineering/releases/monthly-releases/)).
- **Последние релизы**:
  - 19.2.2 (2026-08-12) — патч-релиз (security/bug fixes)
  - 19.2.0 (2026-07-16) — ежемесячный релиз
  - 19.1.0 (2026-06-18)
  - 19.0.0 (2026-05-21) — major-релиз
- **Maintenance policy**: исправления ошибок — для текущей стабильной
  версии; исправления безопасности — для текущей + двух предыдущих минорных
  версий
  ([Maintenance policy](https://docs.gitlab.com/policy/maintenance/)).
- **Major-релизы**: ежегодно (май). GitLab 19.0 — 2026-05-21.
- **Security-уведомления**: публичные, патчи публикуются в security blog
  через 90 дней после исправления
  ([Security Patch Release Process](https://gitlab-org.gitlab.io/release/docs/general/security/security-engineer/)).
- **LTS**: формально отсутствует. Нет долгосрочно поддерживаемых версий.

### Сравнение политики релизов

| Параметр | Forgejo | GitLab CE |
| --- | --- | --- |
| Частота релизов | 3 мес (фиксировано) | 1 мес (фиксировано) |
| Патч-релизы | По мере необходимости | 2 раза в месяц |
| LTS | Да, 15 месяцев | Нет |
| Semantic Versioning | Да, с v7.0 | Да (major.minor.patch) |
| Security-уведомления | Публичные | Публичные (через 90 дней) |
| Major-релизы | Нет (непрерывное развитие) | Ежегодно (май) |

## Путь миграции

### Forgejo → GitLab CE

GitLab поддерживает импорт проектов из Gitea через встроенный инструмент
([Import from Gitea](https://docs.gitlab.com/ee/user/import/gitea/)):

| Источник | Группы | Проекты | Миграционный инструмент | Post-migration mapping |
| --- | --- | --- | --- | --- |
| Gitea | Нет | Да | Встроенный | Да |
| Forgejo (как Gitea) | Нет | Да | Встроенный (через Gitea API) | Да |

Поскольку Forgejo является форком Gitea и API совместим, импорт проектов
из Forgejo в GitLab **возможен** через встроенный Gitea-импортёр.
Однако могут быть проблемы с метаданными (labels, milestones, wiki),
которые не полностью мигрируют.

Для миграции репозиториев через Git URL:
- `git clone --mirror` из Forgejo
- `git push --mirror` в GitLab
- Дополнительные данные (issues, PRs, wiki) — через API

### GitLab CE → Forgejo

Прямого пути миграции **не существует**. Возможны два варианта:
1. Поштоговая миграция репозиториев через `git clone` / `git push`
2. Использование Forgejo API для создания проектов и миграции issues

### Практический вывод для homelab

Миграция между платформами **сопряжена с трудностями** в обоих направлениях.
Ни Forgejo, ни GitLab не предоставляют прозрачного механизма полной миграции
со всеми метаданными (issues, PRs/MRs, wiki, labels, milestones).

## Сообщество и экосистема

### Forgejo

- **Хостинг**: [codeberg.org/forgejo/forgejo](https://codeberg.org/forgejo/forgejo)
  (на собственном Forgejo/Codeberg)
- **Члены Codeberg e.V.**: некоммерческая организация
- **Разработка**: исключительно на Codeberg (dogfooding)
- **Форумы**: Matrix ([#forgejo:matrix.org](https://matrix.to/#/#forgejo:matrix.org)),
  Mastodon ([@forgejo@floss.social](https://floss.social/@forgejo))
- **Деньги**: Liberapay, спонсорство через Codeberg e.V.
  ([Sustainability](https://codeberg.org/forgejo/sustainability))
- **Публичные инстансы**: перечень на
  [Delightful Forgejo](https://codeberg.org/forgejo-contrib/delightful-forgejo#public-instances)
- **Профессиональные услуги**: [Professional services](https://codeberg.org/forgejo/professional-services)

### GitLab CE

- **GitHub Stars** (mirror): ~24 500 ([gitlabhq/gitlabhq](https://github.com/gitlabhq/gitlabhq))
- **Forks**: ~5 900
- **Контрибьюторы**: 3 000+ (в основном репозитории GitLab.com)
  ([Open Hub](https://openhub.net/p/gitlab): 7 111 contributors)
- **Docker Pulls**: 100+ млн
  ([Docker Hub](https://hub.docker.com/r/gitlab/gitlab-ce))
- **Форумы**: [forum.gitlab.com](https://forum.gitlab.com/), GitLab.com issues
- **Коммерческая поддержка**: GitLab Inc. (Premium $29/user/month,
  Ultimate — custom pricing)
- **Образование**: бесплатный Ultimate для open source, education, startups
  ([Programs](https://about.gitlab.com/solutions/open-source/))
- **CNCF**: GitLab является CNCF-партнёром

### Сравнение экосистем

| Параметр | Forgejo | GitLab CE |
| --- | --- | --- |
| Платформа разработки | Codeberg (Forgejo) | GitLab.com |
| GitHub Stars (mirror) | N/A | ~24 500 |
| Docker Pulls | ~1 000+ (оценка) | 100+ млн |
| Контрибьюторы | ~200 (оценка) | 3 000+ |
| Коммерческая поддержка | Professional services | GitLab Inc. (официально) |
| Dogfooding | Да (Codeberg) | Да (GitLab.com) |
| Awesome-список | [Delightful Forgejo](https://codeberg.org/forgejo-contrib/delightful-forgejo) | [GitLab Awesome](https://gitlab.com/gitlab-org/gitlab/-/blob/master/AWESOME.md) |
| Интеграции | Через Webhooks, Actions | 200+ интеграций (Jira, Slack, Kubernetes и др.) |

## Управление (Governance)

### Forgejo

- **Контролируется**: [Codeberg e.V.](https://docs.codeberg.org/getting-started/what-is-codeberg/#what-is-codeberg-e.v.%3F) —
  некоммерческая демократическая организация (e.V. — немецкий аналог non-profit)
- **Управление**: полностью прозрачное, решения документируются публично
  ([Governance](https://codeberg.org/forgejo/governance))
- **Принятие решений**: демократическое
- **Финансы**: прозрачно задокументированы
  ([Sustainability](https://codeberg.org/forgejo/sustainability))

### GitLab CE

- **Контролируется**: GitLab Inc. — публичная компания (NASDAQ: GTLB)
- **Управление**: корпоративное, решения принимаются компанией
- **Handbook**: полностью публичный
  ([handbook.gitlab.com](https://handbook.gitlab.com/))
- **Open Source**: CE — MIT, но стратегия определяется компанией
- **CNCF/ Linux Foundation**: не является частью, но активный участник
  экосистемы

### Сравнение governance

| Параметр | Forgejo | GitLab CE |
| --- | --- | --- |
| Тип организации | Non-profit (Codeberg e.V.) | For-profit (GitLab Inc.,NASDAQ) |
| Демократическое управление | Да | Нет |
| Прозрачность решений | Полная (radical transparency) | Частичная (public handbook) |
| Контроль над доменом | Сообщество | Компания |
| Финансовая прозрачность | Полная | Публичная (публикуется в SEC) |
| Copyright assignment | Нет (DCO) | Нет (для CE) |

## Сложность и сложность эксплуатации

### Количество компонентов

| Компонент | Forgejo | GitLab CE |
| --- | --- | --- |
| Основной бинарник | 1 (`forgejo`) | 1 (Omnibus package) |
| База данных | SQLite (встроенная), PostgreSQL или MySQL | Только PostgreSQL (отдельно) |
| Redis/Valkey | Нет | Обязательно (Redis ≥ 7.0) |
| Sidekiq | Нет | Да (фоновые задачи) |
| Puma (web-server) | Нет (встроенный HTTP) | Да |
| Gitaly | Нет (Git через встроенный сервер) | Да (Git RPC service) |
| Prometheus/Grafana | Нет (опционально) | Да (встроены в Omnibus) |
| Container Registry | Встроен | Встроен (отдельный процесс) |
| GitLab Pages | Нет | Да (отдельный процесс, опционально) |
| Elasticsearch/Zoekt | Нет | Опционально (advanced search) |

### Docker Compose: Forgejo vs GitLab CE

**Forgejo** — минимальный compose:
```yaml
services:
  forgejo:
    image: codeberg.org/forgejo/forgejo:16.0.2
    volumes:
      - forgejo-data:/data
    ports:
      - "3000:3000"
      - "2222:22"
```

**GitLab CE** — значительно сложнее
([Install GitLab in Docker](https://docs.gitlab.com/install/docker/installation/)):
```yaml
services:
  gitlab:
    image: gitlab/gitlab-ce:latest
    hostname: 'gitlab.example.com'
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'https://gitlab.example.com'
    ports:
      - '80:80'
      - '443:443'
      - '22:22'
    volumes:
      - '$GITLAB_HOME/config:/etc/gitlab'
      - '$GITLAB_HOME/logs:/var/log/gitlab'
      - '$GITLAB_HOME/data:/var/opt/gitlab'
    shm_size: '256m'
```

Дополнительные требования GitLab:
- `shm_size: '256m'` (разделяемая память)
- 3 тома для конфигов, логов и данных
- PostgreSQL, Redis, Sidekiq, Gitaly, Puma — всё внутри контейнера
- Время запуска: 5–10 минут (инициализация всех компонентов)

### Бэкап и восстановление

| Аспект | Forgejo | GitLab CE |
| --- | --- |--- |
| Бэкап БД | `forgejo dump` (SQLite/PG/MySQL) | `gitlab-backup create` (PostgreSQL) |
| Бэкап репозиториев | Включён в dump | Включён в backup |
| Восстановление | `forgejo restore` | `gitlab-ctl restore` |
| Бэкап через Docker | `docker exec forgejo forgejo dump` | `docker exec gitlab gitlab-backup create` |
| Документация | [Upgrade guide](https://forgejo.org/docs/latest/admin/upgrade/) | [Backups](https://docs.gitlab.com/ee/administration/backup_restore/) |

### Maintenance burden для homelab

| Фактор | Forgejo | GitLab CE |
| --- | --- | --- |
| Время начальной настройки | 5–15 минут | 30–60 минут (первая загрузка + инициализация) |
| Время апгрейда | 1–5 минут | 15–30 минут (включая `reconfigure`) |
| Дисковое пространство | ~200 MB (данные + БД) | 10+ GB (данные + БД + логи + артефакты) |
| Мониторинг | Минимальный | Рекомендуется (Prometheus встроен) |
| Обновления безопасности | По мере необходимости | Критично — 2 патча в месяц |

## Тяжёлые решения

GitLab CE является «тяжёлым решением» для homelab по ряду причин:

1. **Ресурсы**: 16 GB RAM, 8 vCPU, 40+ GB диска — это сервер класса
   enterprise, а не Raspberry Pi или типичный homelab-сервер.
2. **Компоненты**: PostgreSQL, Redis, Sidekiq, Gitaly, Puma, Prometheus —
   каждый требует настройки и мониторинга.
3. **Апгрейды**: каждую неделю выходят патчи; пропуск нескольких версий
   может сделать апгрейд невозможным без промежуточных обновлений.
4. **Дисковое пространство**: образ 1.3 GB, распакованный — значительно
   больше; container registry и артефакты CI/CD быстро заполняют диск.
5. **Сложность**: при ошибке конфигурации PostgreSQL или Redis может
   потребоваться ручное восстановление.

Для homelab GitLab CE оправдан только при необходимости:
- Полноценной DevOps-платформы с встроенным CI/CD, security scanning,
  project management
- Работы с командой (5+ человек), где нужен SAML, audit logs, compliance
- Использования GitLab как OIDC-провайдера для других сервисов

## Рекомендация для homelab

### Forgejo — предпочтительный выбор для homelab

| Критерий | Forgejo | GitLab CE |
| --- | --- | --- |
| Ресурсы | **~104 MiB RAM, 80 MB образ** | 16+ GB RAM, 1.3 GB образ |
| Простота | **1 бинарник, SQLite** | 10+ компонентов, PostgreSQL + Redis |
| Апгрейды | **Простые, LTS 15 мес** | Ежемесячно, нет LTS |
| Лицензия | **GPL-3.0+ (FOSS guarantee)** | MIT (Open Core) |
| CI/CD | **Forgejo Actions (GitHub compatible)** | GitLab CI/CD (встроенный) |
| OIDC/LDAP | **Да** | Да |
| SAML | Нет | **Да (CE)** |
| Project Management | Базовый | **Полный** |
| Security Scanning | Нет | **CE: базовый, EE: полный** |

### Когда стоит выбрать GitLab CE вместо Forgejo

- **Команда 5+ человек**, нужен SAML, LDAP Group Sync, audit logs
- **Полноценная DevOps-платформа** с встроенным CI/CD, security scanning,
  DORA metrics
- **GitLab как OIDC-провайдер** для других сервисов (GitLab предоставляет
  OIDC/OAuth2 API)
- **Проект management** (Epics, Iterations, Roadmap, Time Tracking)
- **Достаточно ресурсов**: сервер с 16+ GB RAM и 8+ vCPU

### Когда Forgejo не подходит

- Нужен SAML 2.0 (только в GitLab CE для Self-Managed)
- Нужен Dependency Proxy / package forwarding (только EE)
- Нужен Geo / multi-region (только EE)
- Команда > 10 человек с требованиями к compliance

## Не подтверждённые утверждения

- **Замер idle RAM Forgejo (~104–125 MiB)** — локальные измерения
  `docker stats` от 2026-08-16 на Docker Desktop (macOS), а не цифры из
  официальных документов; официальных системных требований Forgejo не
  публикует.

- **Docker image size Forgejo (80.3 MB)** — получен из манифеста реестра
  (`docker manifest inspect`, 2026-08-16), а не из официальной документации.

- **Docker image size GitLab CE (~1.33 GB)** — из Docker Hub (тег `latest`,
  2026-08-17); размер зависит от версии и может варьироваться от 1.22 до
  1.70 GB.

- **GitLab CE minimum RAM (16 GB)** — официальное требование из
  [Installation requirements](https://docs.gitlab.com/install/requirements/):
  «For a single-node installation, 16 GB is the baseline.» В
  memory-constrained среде допускается 8 GB с ограничениями.

- **«GitLab CE не поддерживает SAML»** — это утверждение **неверно**:
  GitLab CE для Self-Managed поддерживает SAML SSO
  ([SAML SSO for GitLab Self-Managed](https://docs.gitlab.com/ee/integration/saml/)).
  Однако LDAP Group Sync и SAML Group Sync — только в Premium/Ultimate.

- **Forgejo не поддерживает SAML** — выведено из отсутствия соответствующей
  записи в документации Forgejo и на странице сравнения
  ([forgejo.org/compare/](https://forgejo.org/compare/)). Возможна реализация
  через_reverse proxy, но нативной поддержки нет.

- **«GitLab CE не имеет LTS»** — выведено из
  [Maintenance policy](https://docs.gitlab.com/policy/maintenance/), где
  описывается только поддержка текущих версий; долгосрочно поддерживаемых
  версий (как LTS в Forgejo) не предусмотрено.

- **Forgejo: даты поддержки релизов** — «16.0.2 до 2026-10-29»,
  «15.0.6 LTS до 2027-07-15» — по
  [forgejo.org/releases](https://forgejo.org/releases/) на 2026-08-17 и
  могут сдвигаться.

- **GitLab CE: количество контрибьюторов (3 000+)** — из
  [Open Hub](https://openhub.net/p/gitlab) и GitHub mirror; точное число
  зависит от метода подсчёта и включает как компаний-контрибьюторов, так
  и индивидуальных.

- **«Forgejo не поддерживает Project Management»** — Forgejo имеет Issues,
  Labels, Projects, Milestones, Kanban-доски; отсутствуют Epics, Iterations,
  Roadmap, Time Tracking (как в GitLab).

- **«GitLab CE не поддерживает Dependency Proxy»** — Dependency Proxy
  (pull-through cache для Docker images) доступен только в EE
  ([Dependency Proxy](https://docs.gitlab.com/ee/user/packages/dependency_proxy/)):
  Tier: Premium, Ultimate.

- **Путь миграции Forgejo → GitLab** — GitLab поддерживает импорт из Gitea
  ([Import from Gitea](https://docs.gitlab.com/ee/user/import/gitea/)).
  Поскольку Forgejo API совместим с Gitea, импорт **возможен**, но не
  документирован отдельно. Проверить полноту миграции метаданных
  (issues, labels, milestones) не удалось.

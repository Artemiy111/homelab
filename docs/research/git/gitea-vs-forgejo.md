# Gitea vs Forgejo: сравнение self-hosted Git-платформ для homelab

Дата проверки: 2026-08-20.

## Область исследования

Задача — сравнить **Gitea** и **Forgejo** как саморазмещаемые платформы для
хостинга Git-репозиториев в условиях homelab. Оба проекта являются форками
[Gogs](https://gogs.io) и имеют общую историю кодовой базы, но с начала 2024 года
стали развиваться независимо как «жёсткие форки» ([hard fork](https://forgejo.org/2024-02-forking-forward/)).

> **Условные обозначения** в таблицах:
> ✅ — поддерживается / доступно
> ❌ — не поддерживается / недоступно
> ⚠️ — ограниченно / только в платной версии
> 🚧 — в разработке

## Краткая история

- **2016** — Gitea создан как форк Gogs, распространяется под MIT-лицензией.
- **2022 (октябрь)** — домены и товарный знак Gitea переданы коммерческой
  компании CommitGo, Inc. без согласия сообщества; создан
  [открытый письм](https://gitea-open-letter.coding.social/).
- **2022 (декабрь)** — Forgejo создан как «мягкий форк» (soft fork) Gitea
  под эгидой некоммерческой организации Codeberg e.V.
  ([announcement](https://forgejo.org/2022-12-15-hello-forgejo/)).
- **2024 (начало года)** — Forgejo становится «жёстким форком» (hard fork),
  кодовые базы начинают расходиться
  ([Forking forward](https://forgejo.org/2024-02-forking-forward/)).
- **2024 (июль)** — Forgejo v9.0 переходит на лицензию GPL-3.0-or-later.
- **2024 (декабрь)** — объявлено, что Gitea v1.22 — последняя версия с прозрачным
  апгрейдом на Forgejo
  ([Gitea compatibility](https://forgejo.org/2024-12-gitea-compatibility/)).

---

## 1. Лицензия

| Аспект | Gitea (MIT) | Forgejo (GPL-3.0+) |
| --- | --- | --- |
| Лицензия | MIT — максимально permissive | GPL-3.0-or-later (с v9.0) |
| Использование в homelab | ✅ Без ограничений | ✅ Без ограничений |
| Модификация и пересборка | ✅ Без ограничений | ✅ Без ограничений |
| Интеграция с проприетарным ПО | ✅ Разрешено | ⚠️ Ограничено (copyleft) |
| Коммерческое использование | ✅ Без ограничений | ✅ Без ограничений |
| Гарантия FOSS навсегда | ❌ Open Core | ✅ Да |
| Copyright assignment | ⚠️ Да (для контрибьюторов) | ❌ Нет (DCO) |
| Файл лицензии | [LICENSE](https://github.com/go-gitea/gitea/raw/main/LICENSE) | [LICENSE](https://codeberg.org/forgejo/forgejo/raw/branch/forgejo/LICENSE) |

**Вывод**: Для homelab-сценария разница **практически незначима**. GPL-3.0 становится
актуальной только при распространении модифицированной версии.

---

## 2. Потребление ресурсов

### Docker-образы (linux/amd64)

| Параметр | Gitea 1.27.x | Forgejo 16.x |
| --- | --- | --- |
| Docker image (сжатый) | 68.7 MB | 80.3 MB |
| Тег образа | `docker.gitea.com/gitea:1.27.1` | `codeberg.org/forgejo/forgejo:16.0.2` |
| Rootless тег | ✅ `:1.27.1-rootless` | ✅ `:16-rootless` |
| Зеркало образов | ✅ Docker Hub | ✅ `data.forgejo.org` + Docker Hub |

### Системные требования

| Параметр | Gitea | Forgejo |
| --- | --- | --- |
| Минимум CPU | 1 ядро | 1 ядро (не документировано) |
| Рекомендуется CPU | 2 ядра | 2 ядра (community consensus) |
| Минимум RAM | 256–512 MB | 256–512 MB |
| Рекомендуется RAM | 1 GB | 1 GB |
| Для малой команды (10–30 чел.) | 2–4 GB RAM | 2–4 GB RAM |
| Raspberry Pi | ✅ «Достаточно мощно» | ✅ «Easily hosted on nearly every machine» |

### Потребление RAM (idle, Docker)

| Сценарий | Gitea | Forgejo | GitLab CE |
| --- | --- | --- | --- |
| Idle (SQLite, < 10 repos) | ~50–150 MiB | ~104–125 MiB | ~1.5–2.5 GB |
| Idle (PostgreSQL, < 50 repos) | ~150–300 MiB | ~150–300 MiB | ~2–3 GB |
| Под нагрузкой (50 юзеров, 4 GB RAM) | ~800 MiB | ~850 MiB | ~3.2 GB |
| Пик (YunoHost CI тесты) | ~372 MiB | ~231 MiB | — |

### Потребление ресурсов — общие рекомендации

| Компонент | Gitea | Forgejo |
| --- | --- | --- |
| Бинарник | ~100 MB | ~100 MB |
| БД (SQLite, малый объём) | 10–50 MB диска | 10–50 MB диска |
| БД (PostgreSQL, малый объём) | 50–200 MB диска | 50–200 MB диска |
| Git-репозитории | Пропорционально содержимому | Пропорционально содержимому |
| Артефакты/пакеты | Зависит от использования | Зависит от использования |
| LFS-хранилище | Отдельно от git-объектов | Отдельно от git-объектов |

### Сравнение с другими платформами

| Платформа | Idle RAM | Min RAM | Min CPU | Время старта |
| --- | --- | --- | --- | --- |
| **Gitea** | 50–150 MiB | 256–512 MB | 1 core | < 10s |
| **Forgejo** | 50–150 MiB | 256–512 MB | 1 core | < 10s |
| Gogs | 30–64 MiB | 64–256 MB | 1 core | < 5s |
| GitLab CE | 1.5–2.5 GB | 4 GB | 2–4 cores | 2–5 min |
| GitHub Enterprise | — | 16 GB+ | 8+ cores | ~10 min |

### Поддержка баз данных

| СУБД | Gitea | Forgejo |
| --- | --- | --- |
| SQLite | ✅ | ✅ |
| PostgreSQL | ✅ | ✅ |
| MySQL / MariaDB | ✅ | ✅ |
| TiDB | ✅ | ❌ |
| MS SQL | ✅ | ❌ |

---

## 3. Функциональное сравнение

### Основные возможности

| Возможность | Gitea | Forgejo | Примечания |
| --- | --- | --- | --- |
| Хостинг репозиториев | ✅ | ✅ | Базовая функциональность |
| Actions / CI/CD | ✅ | ✅ | Оба совместимы с GitHub Actions |
| Package Registry | ✅ | ✅ | 20+ форматов |
| Container Registry (OCI) | ✅ | ✅ | Хостинг Docker-образов |
| Webhooks | ✅ | ✅ | Интеграция с внешними сервисами |
| API (REST) | ✅ | ✅ | Полноценный REST API |
| OpenAPI 3.0 | ✅ | ✅ | Спецификация API |
| AGit workflow | ✅ | ✅ | Упрощённый Git workflow |
| Mirror-репозитории | ✅ | ✅ | Зеркалирование |
| Wiki | ✅ | ✅ | Встроенный вики-движок |
| Projects (доски) | ✅ | ✅ | Kanban-доски |
| Milestones | ✅ | ✅ | Планирование релизов |
| Labels | ✅ | ✅ | Метки для issues |
| Blame view | ✅ | ✅ | Просмотр авторов строк |
| README badges | ✅ | ✅ | Автоматические бейджи |
| Branch/tag protection | ✅ | ✅ | Защита веток |
| Issue/PR templates | ✅ | ✅ | Шаблоны |
| Merge message templates | ✅ | ✅ | Шаблоны коммитов |

### Аутентификация и авторизация

| Возможность | Gitea | Forgejo | Примечания |
| --- | --- | --- | --- |
| LDAP / Active Directory | ✅ | ✅ | Внешняя аутентификация |
| OIDC (вход через внешний провайдер) | ✅ | ✅ | Keycloak, Pocket ID и др. |
| SAML 2.0 | ⚠️ | ❌ | Только в Gitea Enterprise |
| OAuth2 Provider | ✅ | ✅ | Gitea/Forgejo как OAuth2-провайдер |
| WebAuthn / Passkeys | ✅ | ✅ | Аппаратные ключи |
| Двухфакторная аутентификация (TOTP) | ✅ | ✅ | Многофакторная аутентификация |
| Блокировка пользователей | ✅ | ✅ | Модерация |

### CI/CD и автоматизация

| Возможность | Gitea | Forgejo | Примечания |
| --- | --- | --- | --- |
| Встроенная CI/CD | ✅ | ✅ | Gitea Actions / Forgejo Actions |
| Совместимость с GitHub Actions | ✅ | ✅ | Переиспользование существующих workflow |
| Самостоятельный runner | ✅ | ✅ | act_runner (Go-бинарник) |
| Docker-in-Docker (в Actions) | ✅ | ✅ | Запуск Docker внутри CI |
| Secrets в Actions | ✅ | ✅ | Переменные окружения |
| Variables в Actions | ✅ | ✅ | Гибкая конфигурация |
| Scoped Workflows | ✅ | ✅ | Ограничение области видимости |

### Пакетные реестры

| Формат | Gitea | Forgejo |
| --- | --- | --- |
| npm | ✅ | ✅ |
| PyPI | ✅ | ✅ |
| Cargo (Rust) | ✅ | ✅ |
| Go | ✅ | ✅ |
| Maven | ✅ | ✅ |
| NuGet | ✅ | ✅ |
| RubyGems | ✅ | ✅ |
| Helm | ✅ | ✅ |
| Container (OCI) | ✅ | ✅ |
| Debian | ✅ | ✅ |
| RPM | ✅ | ✅ |
| Alpine | ✅ | ✅ |
| Arch | ✅ | ✅ |
| Conan | ✅ | ✅ |
| Conda | ✅ | ✅ |
| Composer (PHP) | ✅ | ✅ |
| Swift | ✅ | ✅ |
| Pub (Dart) | ✅ | ✅ |
| CRAN (R) | ✅ | ✅ |
| Chef | ✅ | ✅ |
| Vagrant | ✅ | ✅ |
| Generic | ✅ | ✅ |
| Pull-through cache / прокси | ❌ | ❌ | Только хостинг собственных пакетов |

### Что есть у Forgejo, но нет у Gitea

| Возможность | Forgejo | Gitea |
| --- | --- | --- |
| Federation (ActivityPub) | 🚧 В разработке | ❌ |
| Radical transparency | ✅ | ❌ |
| 100% Free Software guarantee | ✅ | ❌ |
| End-to-end тесты (в т.ч. browser) | ✅ | ⚠️ Только пример теста |
| Upgrade-тесты | ✅ | ❌ |
| Soft-Quota (гибкие лимиты хранилища) | ✅ | ❌ |
| Quota (квоты на хранилище) | ✅ | ⚠️ Ограниченно |
| Публичные security-уведомления | ✅ | ❌ (только для Enterprise) |

### Что есть у Gitea, но нет у Forgejo

| Возможность | Gitea | Forgejo |
| --- | --- | --- |
| SAML 2.0 | ⚠️ Enterprise | ❌ |
| Аудит-логи | ⚠️ Enterprise | ❌ |
| TiDB | ✅ | ❌ |
| MS SQL | ✅ | ❌ |
| Коммерческая поддержка (CommitGo) | ✅ | ❌ |
| SOC 2 Type 2 | ✅ (Cloud) | ❌ |

---

## 4. Поддержка Kubernetes

### Helm-чарты

| Параметр | Gitea | Forgejo |
| --- | --- | --- |
| Официальный Helm-чарт | ✅ [gitea/helm-gitea](https://gitea.com/gitea/helm-gitea) | ✅ [forgejo-helm/forgejo-helm](https://codeberg.org/forgejo-helm/forgejo-helm) |
| Репозиторий чартов | `https://dl.gitea.com/charts/` | Artifact Hub + Codeberg |
| Последняя версия чарта | v12.7.0 (июль 2026) | v17.1.4 (июль 2026) |
| Версия приложения | Gitea 1.27.1 | Forgejo 15.0.6 |
| Количество релизов чарта | 109 | 167 |
| Зрелость | Production-ready (с 2020) | Production-ready (на базе Gitea-чарта) |
| Kubernetes Operators | ✅ [hyperspike/gitea-operator](https://github.com/hyperspike/gitea-operator) | ⚠️ [dkirwan/forgejo-operator](https://codeberg.org/dkirwan/forgejo-operator) (Ansible-based, ранняя стадия) |

### High Availability

| Возможность | Gitea Helm | Forgejo Helm |
| --- | --- | --- |
| Мульти-реплики | ✅ Встроено | ⚠️ Требует внешней настройки |
| HA PostgreSQL | ✅ Bitnami PostgreSQL-HA (sub-chart) | ⚠️ CloudNative PG / Crunchy Operator |
| HA кэш (Redis/Valkey) | ✅ Bitnami Valkey (sub-chart) | ⚠️ Внешний Valkey/Redis |
| Внешняя БД | ✅ PostgreSQL, MySQL, MSSQL | ✅ PostgreSQL, MySQL |
| S3/NFS хранилище | ✅ | ✅ |
| Ingress | ✅ nginx, Traefik | ✅ nginx, Traefik |
| Gateway API | ✅ (с июля 2026) | ✅ |
| OpenShift Route | ✅ | ❌ |
| Prometheus / ServiceMonitor | ✅ | ✅ |
| SSH через K8s | ✅ ClusterIP, NodePort, LoadBalancer, HostPort | ✅ |

### Установка

**Gitea:**
```bash
helm repo add gitea-charts https://dl.gitea.com/charts/
helm install gitea gitea-charts/gitea
```

**Forgejo:**
```bash
helm repo add forgejo-helm https://artifacthub.io/packages/helm/forgejo-helm/forgejo
helm install forgejo forgejo-helm/forgejo
```

### Сравнение сложности развёртывания в Kubernetes

| Аспект | Gitea | Forgejo |
| --- | --- | --- |
| Простота старта | ✅ Низкая (defaults работают) | ⚠️ Средняя (нужно настроить БД отдельно) |
| Встроенные зависимости | ✅ PostgreSQL-HA + Valkey | ❌ Нет саб-чартов для БД |
| HA «из коробки» | ✅ Да | ❌ Нет |
| Зрелость оператора | ✅ Функциональный | ⚠️ Ранняя стадия / Ansible |

---

## 5. Reverse Proxy и HTTPS

| Параметр | Gitea | Forgejo |
| --- | --- | --- |
| Встроенный TLS | ✅ | ✅ |
| Встроенный ACME (Let's Encrypt) | ✅ HTTP-01, TLS-ALPN-01 | ✅ (тот же код) |
| Кастомный ACME CA (smallstep) | ✅ | ✅ |
| Авто-генерация self-signed cert | ✅ `gitea cert --host` | ✅ |
| Caddy (auto-HTTPS) | ✅ Простая конфигурация | ✅ |
| Traefik | ✅ Labels + certresolver | ✅ |
| Nginx | ✅ Полная документация | ✅ |
| Apache HTTPD | ✅ | ✅ |
| HAProxy | ✅ | ✅ |

| Реверс-прокси | Лучше для | Сложность | Особенности |
| --- | --- | --- | --- |
| **Caddy** | Простой single-service setup | Низкая | Auto-HTTPS, минимум конфигурации |
| **Traefik** | Docker/K8s, мульти-сервис | Средняя | Auto-discovery, DNS-01, HTTP/3 |
| **Nginx** | Максимальная производительность | Средняя | Тонкая настройка, статика |
| **Встроенный ACME** | Без внешнего прокси | Низкая | Прямой HTTPS, без зависимостей |

---

## 6. Частота релизов и поддержка

| Параметр | Gitea | Forgejo |
| --- | --- | --- |
| Частота релизов | ~2–3 мес (нестабильная) | 3 мес (фиксированное расписание) |
| LTS | ❌ Не объявлен | ✅ 15 месяцев (3 мес стабильная + 12 мес LTS) |
| Semantic Versioning | ❌ Не гарантирован | ✅ С версии 7.0 |
| Security-уведомления | ⚠️ Только для клиентов Enterprise | ✅ Публичные (для всех) |
| EOL политика | Неформальная | ✅ Документирована |
| Последний релиз | 1.27.2 (2026-08-13) | 16.0.2 (2026-07-30) |
| LTS релиз | — | 15.0.6 (до 2027-07-15) |

**Политика поддержки Forgejo:**
- Стабильная версия: поддерживается 3 месяца + 2 недели после следующего релиза
- LTS-версия: выходит в Q1 каждого года, поддерживается 15 месяцев
- [Release schedule](https://forgejo.org/docs/latest/admin/release-schedule/)

---

## 7. Путь миграции

### Gitea → Forgejo

| Версия Gitea | Целевая Forgejo | Способ |
| --- | --- | --- |
| ≤ v1.21 | v7.0+ (вплоть до v10.0) | ✅ Прозрачный апгрейд (замена образа) |
| v1.22 | v8.0+ (вплоть до v10.0) | ✅ Прозрачный апгрейд |
| v1.23+ | — | ❌ Прозрачный апгрейд невозможен |

**Для Gitea 1.23+** возможны два варианта:
1. Ручная правка базы данных + перемещение данных
2. Поштоговая миграция репозиториев через in-app migration tool

**Причины разрыва**: изменения в БД Gitea (индексы actions, priority для protected branches), diferente реализация некоторых функций, глубокое рефакторирование подсистем.

### Forgejo → Gitea

❌ Прямого пути миграции **не существует**. Только поштоговая миграция через API.

### Миграция между версиями Forgejo

✅ Forgejo поддерживает прямой апгрейд между любыми версиями (включая пропуск минорных версий). Рекомендации:
1. Бэкап перед апгрейдом
2. `forgejo doctor check --all` после апгрейда
3. Проверка через веб-интерфейс

---

## 8. Сообщество и экосистема

### Сравнение экосистем

| Параметр | Gitea | Forgejo |
| --- | --- | --- |
| Платформа разработки | GitHub | Codeberg (Forgejo) |
| GitHub Stars | ~57 400 | N/A (не на GitHub) |
| Forks | ~7 000 | N/A |
| Контрибьюторы | 500+ | 200+ |
| Docker Pulls | 4+ млн (заявлено) | N/A |
| Установки | 100k+ (заявлено) | N/A |
| Dogfooding (используют свой продукт) | ❌ | ✅ |
| Язык локализации | Crowdin | Weblate |
| Коммерческая поддержка | ✅ CommitGo | ⚠️ Professional services (через Codeberg) |
| Awesome-список | [Awesome Gitea](https://gitea.com/gitea/awesome-gitea) | [Delightful Forgejo](https://codeberg.org/forgejo-contrib/delightful-forgejo) |
| Публичные инстансы | Множество | Перечень на [Delightful Forgejo](https://codeberg.org/forgejo-contrib/delightful-forgejo#public-instances) |
| Форумы | [forum.gitea.com](https://forum.gitea.com), Discord | Matrix, Mastodon |
| Спонсоры | Google, Two Sigma, MediaTek, Mastercard | Liberapay, Codeberg e.V. |

---

## 9. Управление (Governance)

| Параметр | Gitea | Forgejo |
| --- | --- | --- |
| Тип организации | For-profit (CommitGo, Inc.) | Non-profit (Codeberg e.V.) |
| Демократическое управление | ⚠️ Ограниченно | ✅ Да |
| Прозрачность решений | ❌ Нет | ✅ Radical transparency |
| Контроль над доменом | Компания | ✅ Сообщество |
| Финансовая прозрачность | ❌ Неясно | ✅ Полная |
| Copyright assignment | ⚠️ Да (для контрибьюторов) | ❌ Нет (DCO) |
| Гарантия Free Software навсегда | ❌ Нет | ✅ Да |

---

## 10. Итоговая сравнительная таблица

| Параметр | Gitea 1.27.x | Forgejo 16.x | Лучше |
| --- | --- | --- | --- |
| **Лицензия** | MIT | GPL-3.0-or-later | — |
| **Гарантия FOSS** | ❌ | ✅ | Forgejo |
| **Docker image (amd64)** | 68.7 MB | 80.3 MB | Gitea |
| **RAM idle** | ~50–150 MiB | ~50–150 MiB | ≈ равны |
| **Min требования** | 1 CPU / 256 MB RAM | 1 CPU / 256 MB RAM | ≈ равны |
| **БД** | 5 вариантов | 3 варианта | Gitea |
| **Actions / CI** | ✅ (GitHub Actions compat) | ✅ (GitHub Actions compat) | ≈ равны |
| **Package Registry** | 20+ форматов | 20+ форматов | ≈ равны |
| **Container Registry** | ✅ | ✅ | ≈ равны |
| **LDAP** | ✅ | ✅ | ≈ равны |
| **OIDC** | ✅ | ✅ | ≈ равны |
| **SAML 2.0** | ⚠️ Enterprise | ❌ | — |
| **Federation** | ❌ | 🚧 | Forgejo (перспектива) |
| **LTS** | ❌ | ✅ (15 мес) | Forgejo |
| **SemVer** | ❌ | ✅ | Forgejo |
| **Security-уведомления** | ⚠️ Enterprise | ✅ Публичные | Forgejo |
| **Helm chart** | ✅ Зрелый | ✅ Зрелый | ≈ равны |
| **K8s HA** | ✅ Встроенное | ⚠️ Внешнее | Gitea |
| **Kubernetes Operator** | ✅ Функциональный | ⚠️ Ранняя стадия | Gitea |
| **Встроенный ACME** | ✅ | ✅ | ≈ равны |
| **Управление** | Компания | Non-profit | Forgejo |
| **Прозрачность** | ❌ | ✅ | Forgejo |
| **Миграция Gitea → Forgejo** | — | ✅ (до Gitea ≤ 1.22) | — |
| **Миграция Forgejo → Gitea** | ❌ | — | — |
| **Документация** | ✅ Обширная | ✅ Хорошая | Gitea |
| **Зрелость экосистемы** | ✅ Больше интеграций | ⚠️ Меньше | Gitea |

---

## 11. Вывод для homelab

### Рекомендация: **Forgejo**

Homelab ещё не имеет значимых данных в Gitea (тестовый инстанс), поэтому
стоимость миграции отсутствует. В этом случае **Forgejo является
предпочтительным выбором** по следующим причинам:

1. **Гарантия FOSS**: GPL-3.0+ исключает Open Core и появление функций
   только в платной версии (как SAML и аудит-логи у Gitea Enterprise).

2. **Документированный LTS**: 15 месяцев поддержки с фиксированными EOL-датами
   — критично для homelab, где апгрейды делаются вручную и нерегулярно.

3. **Публичные security-уведомления**: доступны всем, а не только клиентам
   Enterprise (как у Gitea).

4. **Прозрачное управление**: некоммерческая организация (Codeberg e.V.),
   демократическое принятие решений, полная финансовая прозрачность.

5. **Federation** (в разработке): потенциальная возможность взаимодействия
   между инстансами — перспектива для homelab-сети.

6. **Сопоставимые ресурсы**: образ 80.3 MB (vs 68.7 MB), RAM ~50–150 MiB
   — разница минимальна. Обе платформы работают на Raspberry Pi.

### Когда стоит выбрать Gitea вместо Forgejo

- **SAML 2.0 или аудит-логи** необходимы (только в Gitea Enterprise).
- **Максимальная совместимость** экосистемы и сторонних интеграций (57k
  GitHub Stars, больше готовых решений).
- **Коммерческая поддержка** через CommitGo нужна как опция.
- **HA в Kubernetes «из коробки»** — встроенные саб-чарты для PostgreSQL-HA и Valkey.
- **Текущий homelab уже использует Gitea 1.23+** — тогда миграция на Forgejo
  болезненна и не оправдана.
- **Нужна поддержка TiDB или MS SQL**.

---

## Не подтверждённые утверждения

- **Замер idle RAM Gitea** — отдельных локальных замеров потребления RAM
  для Gitea 1.27.x в данном исследовании не проводилось; цифра «~50–150 MiB»
  является экстраполяцией на основе Forgejo и community-бенчмарков.
  Для точного замера необходим `docker stats` на конкретной конфигурации.

- **Docker image size Forgejo 16.0.2 (80.3 MB)** — получен через
  `docker manifest inspect` / registry API (2026-08-16), а не из официальной
  документации; официальных системных требований Forgejo не публикует.

- **Docker image size Gitea 1.27.1 (68.7 MB)** — получена из реестра образов
  (2026-08-16); точный размер зависит от тега и архитектуры.

- **«Federation в Forgejo в разработке»** — подтверждено наличием
  [monthly progress reports](https://forgejo.org/tag/report/) и разделом
   [Focus on forge federation](https://forgejo.org/compare/), но точные сроки
   и функциональность не указаны.

- **«Gitea не поддерживает federation»** — выведено из [сравнительной таблицы Forgejo](https://forgejo.org/compare-to-gitea/)
  (обновление 13 декабря 2024) и отсутствия соответствующих записей в
  документации Gitea. Возможны обсуждения в issue-tracker, но реализации нет.

- **«Gitea не имеет end-to-end тестов»** — по утверждению Forgejo
  ([comparison](https://forgejo.org/compare-to-gitea/)): «As of 21 June 2025,
  Gitea only has an example browser test». Проверить актуальность на 2026-08-20
  не удалось.

- **Путь колбэка OIDC** (`{ROOT_URL}/user/oauth2/{name}/callback`) — из
  официальной документации не подтверждён ни для Gitea, ни для Forgejo.
  Важно для регистрации redirect URI в OIDC-провайдере (например, Pocket ID).

- **«Gitea требует передачу авторских прав» (copyright assignment)** — ссылка
  ведёт на [обсуждение в Forgejo](https://codeberg.org/forgejo/discussions/issues/67),
  а не на официальный документ Gitea. Точная политика может отличаться.

- **Docker Pulls Gitea (4+ млн)** — заявлено на сайте gitea.com, актуальность
  на 2026-08-20 не проверена; для сравнения: Docker Hub показывает
  значительно бо́льшие цифры.

- **Forgejo: даты поддержки релизов** — «16.0.2 до 2026-10-29»,
  «15.0.6 LTS до 2027-07-15» — по [forgejo.org/releases](https://forgejo.org/releases/)
  на 2026-08-20 и могут сдвигаться.

- **«Forgejo не поддерживает TiDB и MS SQL»** — выведено из документации
  [Database Preparation](https://forgejo.org/docs/v16.0/admin/installation/database-preparation/),
  где перечислены только SQLite, PostgreSQL и MySQL. Возможна поддержка через
  драйверы XORM, но официально не документирована.

- **Бенчмарки производительности** (page load 0.4s, git clone 8s, RAM под нагрузкой 800–850 MiB) — из сторонних сравнительных обзоров (pistack.xyz, selfhostr.com), не проводились локально.

# Valkey vs Redis

Дата исследования: 2026-08-23.

## Обзор

| | Valkey | Redis |
|---|---|---|
| **Назначение** | In-memory key-value хранилище (кэш, очереди, pub/sub), форк Redis 7.2.4 | In-memory key-value хранилище + встроенные модули (JSON, поиск, вектора, time series) |
| **Язык** | C | C |
| **Лицензия** | [BSD-3-Clause](https://github.com/valkey-io/valkey/blob/unstable/COPYING) | Трилицензия: [RSALv2 \| SSPLv1 \| AGPLv3](https://redis.io/blog/agplv3/) (выбор пользователя, начиная с Redis 8) |
| **Репозиторий** | [github.com/valkey-io/valkey](https://github.com/valkey-io/valkey) (~27k ⭐) | [github.com/redis/redis](https://github.com/redis/redis) (~76k ⭐) |
| **Актуальная версия** | [9.1.1](https://github.com/valkey-io/valkey/releases) (июль 2026); стабильные ветки 9.0.x, 8.1.x, 8.0.x, 7.2.x | [8.10.1](https://github.com/redis/redis/releases) (август 2026); поддерживаемые ветки 8.10/8.8/8.6/8.4/8.2 + LTS 7.4/7.2/6.2 |
| **Кто разрабатывает** | Linux Foundation / LF Projects; вклад AWS, Google Cloud, Oracle, Ericsson, Snap, Percona и др. | Redis Ltd. (компания), включая вернувшегося создателя antirez (Salvatore Sanfilippo) |
| **Governance** | Открытое сообщество под эгидой Linux Foundation ([leadership](https://valkey.io/leadership/)) | Единолично компания Redis Ltd. |

---

## Предыстория и хронология

| Дата | Событие |
|------|---------|
| Март 2024 | Redis Ltd. объявляет переход с BSD-3 на дуальную лицензию RSALv2/SSPLv1 начиная с Redis 7.4 — обе не одобрены OSI. Обоснование — борьба с «эксплуатацией» проекта гипскалерами ([источник](https://web.archive.org/web/20260116065952/https://redis.io/blog/agplv3/)) |
| Март–апрель 2024 | Linux Foundation объявляет форк последнего BSD-релиза Redis 7.2.4 под именем **Valkey** при поддержке AWS, Google Cloud, Oracle и др. Первый GA-релиз — [Valkey 7.2.5, 16 апреля 2024](https://valkey.io/blog/valkey-7-2-5-out/) |
| Сентябрь 2024 | [Valkey 8.0 GA](https://valkey.io/blog/valkey-8-ga/) — новая многопоточная архитектура Enhanced I/O Threading, >1 млн RPS ([блог](https://valkey.io/blog/unlock-one-million-rps/)) |
| Ноябрь 2024 | Salvatore Sanfilippo (antirez) возвращается в Redis Ltd. |
| Май 2025 | [Redis 8 выходит под трилицензией с опцией OSI-approved **AGPLv3**](https://web.archive.org/web/20260116065952/https://redis.io/blog/agplv3/); модули Redis Stack (JSON, Time Series, Bloom, Query Engine) интегрированы в ядро; новый тип данных Vector Sets от antirez |
| Апрель 2025 | [Valkey 8.1](https://valkey.io/blog/valkey-8-1-0-ga/) — новый hash table, улучшенная память и observability |
| Май 2025 | GA [Azure Managed Redis](https://learn.microsoft.com/en-us/azure/azure-cache-for-redis/managed-redis/managed-redis-overview) (на базе Redis Enterprise) и [Memorystore for Valkey](https://docs.cloud.google.com/memorystore/docs/valkey) у Google Cloud |
| Октябрь 2025 | [Valkey 9.0](https://valkey.io/blog/introducing-valkey-9/) — атомарные slot-миграции, hash field expiration, numbered DBs в cluster mode, до 1 млрд RPS в кластерах до 2000 нод |
| Август 2025 – август 2026 | Redis ускоряет релизный цикл: 8.2 (авг 2025) → 8.4 → 8.6 → 8.8 → [8.10.1](https://github.com/redis/redis/releases/tag/8.10.1) (авг 2026) |
| Май 2026 | [Valkey 9.1](https://valkey.io/blog/valkey-9-1-delivers-improvements-in-security-performance-and-more/) — database-level ACLs, безопасность, производительность; далее [снижение memory overhead до 44% в 9.1](https://valkey.io/blog/9.1-memory-efficiency/) |

Итог: лицензионная война закончилась компромиссом — Redis вернулся к OSI-approved лицензии (AGPLv3 как одна из опций), но гипскалеры (AWS, GCP) уже перешли на Valkey и продолжают инвестировать именно в него.

---

## ⚡ Производительность

| Критерий | Valkey | Redis |
|----------|:------:|:-----:|
| Однопоточное исполнение команд | ✅ Базовая архитектура сохранена | ✅ |
| Многопоточный I/O из коробки | ✅ Enhanced I/O Threading (Valkey 8+, динамическое число потоков) | ⚠️ io-threads существуют с Redis 6, но по умолчанию выключены и менее развиты |
| Заявленный throughput | ✅ До **1.19 млн RPS** на одном инстансе (c7g.16xlarge, +230% против 7.2, средняя латентность −69.8%) — [блог Valkey/AWS](https://valkey.io/blog/unlock-one-million-rps/) | ⚠️ Redis 8 заявляет «до 87% быстрее отдельных команд и 2× throughput» относительно 7.4 ([блог Redis](https://redis.io/blog/agplv3/)), но публичных цифр уровня 1M+ RPS для CE нет |
| Масштабирование кластера | ✅ До 2000 нод / **1 млрд RPS** суммарно ([Valkey 9.0](https://valkey.io/blog/1-billion-rps/)) | ⚠️ Кластер масштабируется, публичных рекордных цифр нет |
| Оптимизации памяти | ✅ Новый hash table (8.1), −44% overhead для строк и −8.5 байт на член sorted set (9.1) — [блог](https://valkey.io/blog/9.1-memory-efficiency/) | ⚠️ 15+ улучшений ресурсоутилизации в 8.2 ([release notes](https://github.com/redis/redis/releases/tag/8.2.0)) |
| SIMD / низкоуровневые оптимизации | ✅ SIMD для BITCOUNT и HyperLogLog (+200%), zero-copy ответы (+20%), pipeline memory prefetch (+40%) — [Valkey 9.0](https://valkey.io/blog/introducing-valkey-9/) | ❌ Публично о сопоставимом наборе оптимизаций не заявлено |
| Multipath TCP | ✅ Поддержка MPTCP, до −25% латентности ([PR #1811](https://github.com/valkey-io/valkey/pull/1811)) | ❌ |
| Независимые бенчмарки | ⚠️ Большинство доступных бенчмарков сделаны одной из сторон или облачными вендорами; нейтральных всесторонних сравнений Valkey 9.x vs Redis 8.x мало | ⚠️ То же самое |

> ⚠️ Все «рекордные» цифры — из блогов самих проектов (Valkey/AWS и Redis соответственно). В реальном homelab-контексте оба сервера дают субмиллисекундную латентность и упираются скорее в сеть, чем в движок.

---

## 📦 Функциональность и типы данных

| Возможность | Valkey | Redis |
|-------------|:-------:|:-----:|
| Strings, Lists, Sets, Sorted Sets, Hashes | ✅ | ✅ Идентично |
| Streams (consumer groups) | ✅ | ✅ |
| Bitmaps, HyperLogLog, Geospatial | ✅ (+ BYPOLYGON в 9.0) | ✅ |
| Pub/Sub, Sharded Pub/Sub | ✅ | ✅ |
| Lua-скрипты (EVAL) и Functions | ✅ | ✅ |
| Transactions / MULTI-EXEC / optimistic locking | ✅ | ✅ |
| Hash Field Expiration (HEXPIRE…) | ✅ С версии [9.0](https://valkey.io/blog/hash-fields-expiration/) (окт 2025) | ✅ Раньше — с Redis 7.4 (2024) |
| Numbered databases в cluster mode | ✅ С [9.0](https://valkey.io/blog/numbered-databases/) | ❌ Только db 0 в кластере |
| JSON (RedisJSON-совместимый) | ⚠️ Через расширение [valkey-json](https://valkey.io/blog/introducing-enhanced-json-capabilities-in-valkey/) / [valkey-bundle](https://valkey.io/blog/valkey-bundle-one-stop-shop-for-low-latency-modern-applications/) | ✅ Встроено в ядро с Redis 8 |
| Full-text search + aggregations | ⚠️ Через расширение [valkey-search 1.2](https://valkey.io/blog/valkey-search-1_2/) (март 2026) | ✅ Query Engine в ядре с Redis 8 (fuzzy search, агрегации) |
| Vector similarity search | ⚠️ Через [valkey-search](https://valkey.io/blog/introducing-valkey-search/) | ✅ Два механизма: Query Engine (HNSW/SVS-VAMANA) + нативный тип [Vector Sets](https://github.com/redis/redis) от antirez |
| Time Series | ❌ Нет официального аналога | ✅ Встроено в ядро с Redis 8 |
| Probabilistic структуры (Bloom/Cuckoo/TopK/t-digest) | ⚠️ Через [bloom-модуль](https://valkey.io/blog/introducing-bloom-filters/) (апр 2025, входит в valkey-bundle) | ✅ Встроено в ядро с Redis 8 |
| ACL (пользователи, права по ключам) | ✅ + database-level ACLs в 9.1 | ✅ |
| Атомарные миграции слотов в кластере | ✅ [Atomic Slot Migration](https://valkey.io/blog/atomic-slot-migration/) в 9.0 — без блокировок и потери доступа к ключам | ❌ Key-by-key миграция, возможны redirect-штормы и блокировка больших ключей |

---

## 🔌 Совместимость

| Критерий | Valkey | Redis |
|----------|:-------:|:-----:|
| Протокол RESP2 / RESP3 | ✅ Полная совместимость | ✅ Эталонная реализация |
| Замена Redis → Valkey без переписывания кода | ✅ Drop-in replacement: тот же бинарник-стиль конфигурации, те же команды, клиенты работают как есть ([FAQ](https://valkey.io/topics/faq/)) | — |
| Замена Valkey → Redis | ⚠️ Работает для базовых типов; фичи Valkey 9.x (hash field TTL в новых энкодингах, numbered DBs в кластере) обратно не переносимы | ✅ |
| Популярные клиенты (redis-py, node-redis, jedis, lettuce, go-redis) | ✅ Работают без изменений (RESP-совместимость) | ✅ |
| Выделенные клиенты Valkey | ✅ [GLIDE](https://github.com/valkey-io/valkey-glide) (Java/Python/Go/Node), Spring Data Valkey (апр 2026), valkey-swift 1.0 (апр 2026), iovalkey | ✅ Официальные клиенты для всех языков |
| Replication / Cluster protocol | ✅ Совместим с Redis 7.2 внутри мажорной линии | ✅ |
| RDB/AOF совместимость между проектами | ⚠️ База совместима; новые энкодинги (например, hash-field TTL) требуют соответствующей версии на реплике ([release 9.1.1 notes](https://github.com/valkey-io/valkey/releases/tag/9.1.1)) | ✅ |
| Экосистема self-hosted приложений (Nextcloud, Harbor, GitLab, Grafana…) | ✅ Практически везде поддерживается явно (`REDIS_HOST` принимает Valkey); [Harbor официально переключился на Valkey](https://valkey.io/blog/harbor-chose-valkey/) в v2.15.2 (июль 2026) | ✅ Исторически дефолт |

---

## 📜 Лицензия и открытость

| Критерий | Valkey | Redis |
|----------|:-------:|:-----:|
| Лицензия | ✅ BSD-3-Clause — максимально перmissive, без условий на хостинг как услугу ([COPYING](https://github.com/valkey-io/valkey/blob/unstable/COPYING)) | ⚠️ Трилицензия на выбор: [RSALv2 \| SSPLv1 \| AGPLv3](https://redis.io/blog/agplv3/). Только AGPLv3 одобрена OSI |
| Можно ли продавать hosted-версию без открытия кода | ✅ Да (BSD) | ❌ RSALv2 и SSPLv1 запрещают без коммерческого соглашения; AGPLv3 требует открыть исходники изменений сервиса |
| Governance | ✅ Linux Foundation / LF Projects, нейтральный техкомитет, открытые выборы лидерства ([leadership](https://valkey.io/leadership/)) | ❌ Полностью контролируется Redis Ltd. |
| Товарный знак | «Valkey» принадлежит LF Projects | «Redis» — зарегистрированный товарный знак Redis Ltd.; использование ограничено |
| Риск смены лицензии в будущем | ✅ Минимальный (нейтральный фонд) | ⚠️ Уже менялась один раз (март 2024); частично откат (AGPLv3) |
| Прозрачность roadmap | ✅ Публичные GitHub discussions, еженедельные встречи сообщества | ⚠️ Часть планов закрыта (коммерческие продукты) |

---

## 🏢 Экосистема и managed-хостинги

| Провайдер | Valkey | Redis |
|-----------|:------:|:-----:|
| AWS ElastiCache | ✅ [ElastiCache for Valkey](https://aws.amazon.com/elasticache/what-is-valkey/) — рекомендуемый движок, развивается активно; дешевле нод Redis OSS; также MemoryDB for Valkey | ⚠️ «ElastiCache for Redis OSS» существует, но линия заморожена на старой версии (7.x) и не получает новых фич |
| AWS MemoryDB | ✅ [MemoryDB for Valkey](https://aws.amazon.com/memorydb/) | ❌ |
| Google Cloud Memorystore | ✅ [Memorystore for Valkey](https://docs.cloud.google.com/memorystore/docs/valkey) (GA май 2025) с vector search, JSON, bloom filters | ⚠️ Memorystore for Redis (Cluster/Classic) продолжает существовать |
| Microsoft Azure | ❌ Azure не предлагает Valkey | ✅ [Azure Managed Redis](https://learn.microsoft.com/en-us/azure/azure-cache-for-redis/managed-redis/managed-redis-overview) (GA май 2025, на базе Redis Enterprise, Redis 7.4) заменяет Azure Cache for Redis |
| Redis Cloud (собственный хостинг Redis Ltd.) | ❌ | ✅ Redis Cloud / Redis Enterprise (активная гео-репликация, Flash tiers и т.д.) |
| Upstash, Aiven, Render, Railway | ✅ Многие serverless/PaaS-платформы перешли или предлагают Valkey | ⚠️ Upstash остаётся на Redis API |
| CNCF / инфраструктурные проекты | ✅ Harbor (CNCF graduated) [перешёл на Valkey](https://valkey.io/blog/harbor-chose-valkey/); официальный Helm-чарт от проекта ([блог](https://valkey.io/blog/valkey-helm-chart/)) | ✅ Историческая поддержка повсеместна |
| Linux distro / Bitnami-альтернативы | ✅ valkey в Debian/Ubuntu/Alpine; [официальный Helm chart](https://valkey.io/blog/valkey-helm-chart/) после ухода Bitnami | ✅ redis во всех дистрибутивах |

---

## 🛠️ Удобство эксплуатации

| Критерий | Valkey | Redis |
|----------|:-------:|:-----:|
| Конфигурация / формат | ✅ Идентичен Redis 7.2 (redis.conf → valkey.conf, redis-cli → valkey-cli) | ✅ |
| Интроспекция | ✅ INFO, LATENCY, CLIENT LIST с фильтрами, COMMANDLOG, SLOT-STATS, per-thread I/O метрики ([блог](https://valkey.io/blog/valkey-tooling-primitives/)) | ✅ INFO, LATENCY DOCTOR, per-slot метрики и распределение размеров ключей (8.2+) |
| GUI-инструменты | ✅ [Valkey Admin](https://valkey.io/blog/introducing-valkey-admin-1-0-visual-cluster-management-for-valkey/) (десктоп + web, кластеры, hot keys) | ✅ RedisInsight — зрелый, богатый функциональностью |
| Prometheus / observability экспортёры | ✅ Стандартные экспортёры redis-exporter работают; event-driven resource usage метрики (8.1+) | ✅ redis_exporter, встроенные метрики |
| Документация | ⚠️ Портирована с Redis, полнота растёт, но местами отстаёт ([valkey.io/docs](https://valkey.io/docs/)) | ✅ redis.io — эталонная документация и tutorials |
| Скорость релизов | ✅ Мажор раз в ~полгода, минорные патчи регулярно (9.0 окт 2025 → 9.1 май 2026) | ✅ Минор каждые ~3 месяца (8.2 авг 2025 → 8.10 авг 2026), LTS-ветки 6.2/7.2/7.4 |
| Сообщество | ✅ Быстро растущее, бэкед Linux Foundation, Slack/GitHub discussions активны | ✅ Огромное историческое сообщество, но вклад в open source ядро централизован компанией |
| Безопасность | ✅ Быстрые security-релизы одновременно во все ветки ([9.1.1](https://github.com/valkey-io/valkey/releases/tag/9.1.1)) | ✅ Security-релизы во все ветки ([8.10.1](https://github.com/redis/redis/releases/tag/8.10.1)) |

---

## 🧩 Модули и расширения

| Критерий | Valkey | Redis |
|----------|:-------:|:-----:|
| Module API | ✅ Совместим с API Redis 7.2 (многие Redis-модули работают) | ✅ Развитый Module API |
| Официальные расширения | ⚠️ Молодой, но растущий набор: [valkey-search](https://valkey.io/blog/introducing-valkey-search/), valkey-json, [bloom filters](https://valkey.io/blog/introducing-bloom-filters/), LDAP auth, [valkey-bundle](https://valkey.io/blog/valkey-bundle-one-stop-shop-for-low-latency-modern-applications/) (всё в одном контейнере) | ✅ Ядро уже включает JSON/Search/TS/Bloom; плюс коммерческие RedisAI, LangCache |
| SDK для написания модулей | ✅ Rust SDK активно развивается ([блог](https://valkey.io/blog/valkey-modules-rust-sdk-updates/)) | ✅ C API, сторонние обёртки |
| RDMA transport | ✅ Экспериментально в 9.x | ❌ |
| Зрелость поиска/векторов | ⚠️ valkey-search только с июля 2025, full-text с марта 2026 | ✅ RediSearch зрел годами: гибридные запросы, агрегации, компрессия индексов (SVS-VAMANA) |

---

## 💰 Стоимость / коммерческая поддержка

| Критерий | Valkey | Redis |
|----------|:-------:|:-----:|
| Self-hosted | ✅ Бесплатно, BSD-3, никаких ограничений | ✅ Бесплатно (под AGPLv3 — с обязательством открыть изменения сервиса; под RSALv2/SSPLv1 — ограничения) |
| Коммерческая поддержка | ✅ Percona (специализированная практика Redis/Valkey), интеграция через облачных вендоров | ✅ Redis Ltd.: Redis Software (self-managed enterprise), Redis Cloud, SLA |
| Managed-цены | ✅ ElastiCache/MemoryDB for Valkey дешевле эквивалентных Redis-нод; [Memorystore for Valkey](https://cloud.google.com/memorystore/valkey/pricing) конкурентен | ⚠️ Redis Cloud дороже; Azure Managed Redis — единственный вариант на Azure |
| Скрытые риски | ❌ Нет | ⚠️ AGPLv3 может требовать открытия кода при встраивании в SaaS; RSALv2 запрещает competitive use |

---

## 📋 Когда выбирать Valkey

- Self-hosted / Docker Compose / Kubernetes без лицензионных сомнений (чистая BSD-3)
- Нужен максимум производительности на многоядерном железе (Enhanced I/O threading из коробки)
- Кластеры: атомарные slot-миграции, numbered DBs в cluster mode, большие кластеры
- Хостится у AWS или GCP (managed-предложения развиваются именно вокруг Valkey)
- Критична независимость от решений одного вендора

## 📋 Когда выбирать Redis

- Нужны JSON + full-text/vector search + time series + probabilistic структуры «из коробки», одним контейнером без модулей
- Используется Azure Managed Redis (Azure не предлагает Valkey)
- Нужен зрелый RedisInsight, эталонная документация, коммерческий SLA от автора проекта
- Приложение использует новейшие фичи Redis (Vector Sets, fuzzy search), которых нет в Valkey
- Планируется переезд в Redis Cloud / Redis Enterprise

---

## 📌 Рекомендация для homelab

Контекст: Docker Compose на собственной машине, самообслуживание, типичные задачи — кэш, сессии, брокер задач, бэкенд для Nextcloud/Forgejo/Grafana/uptime-сервисов.

### ✅ Valkey — предпочтительный выбор

| # | Преимущество |
|---|-------------|
| 1 | Лицензия BSD-3-Clause — нулевые юридические риски для self-hosted, никакой AGPL/RSAL бухгалтерии |
| 2 | Полный drop-in replacement: любой сервис с `REDIS_URL=redis://...` работает с Valkey без правок |
| 3 | Образ `valkey/valkey` легче и потребляет меньше памяти (оптимизации 8.1/9.1) |
| 4 | Более быстрая функциональная эволюция именно в базовых сценариях кэша (I/O threading, memory efficiency) |
| 5 | Поддержан индустриальным консорциумом — риск «повторной смены лицензии» минимален |
| 6 | Для продвинутых сценариев (JSON, vector search, bloom) есть valkey-bundle одним контейнером |

### ⚠️ Redis — разумная альтернатива, если

| # | Условие |
|---|---------|
| 1 | Нужны time series или зрелый query engine (full-text + vectors) без дополнительных модулей |
| 2 | Уже используются фичи Redis ≥7.4/8.x (Vector Sets, SVS-VAMANA) |
| 3 | Проект жёстко завязан на документацию/туториалы redis.io и RedisInsight |
| 4 | В будущем планируется миграция на Azure Managed Redis |

Практический вывод для этого репозитория: использовать образ `valkey/valkey` (ветка 9.x) вместо `redis`; переменные окружения приложений менять не нужно.

---

## Источники

### Valkey (первоисточники)

- [Valkey Blog](https://valkey.io/blog/) — анонсы всех релизов
- [Unlock 1 Million RPS: Experience Triple the Speed with Valkey](https://valkey.io/blog/unlock-one-million-rps/) — бенчмарки Enhanced I/O threading (авг 2024)
- [Generally Available: Valkey 8.0.0](https://valkey.io/blog/valkey-8-ga/)
- [Valkey 8.1 GA](https://valkey.io/blog/valkey-8-1-0-ga/)
- [Introducing Hash Field Expirations](https://valkey.io/blog/hash-fields-expiration/)
- [Valkey 9.0: innovation, features, and improvements](https://valkey.io/blog/introducing-valkey-9/)
- [Scaling a Valkey Cluster to 1 Billion Request per Second](https://valkey.io/blog/1-billion-rps/)
- [Resharding, Reimagined: Introducing Atomic Slot Migration](https://valkey.io/blog/atomic-slot-migration/)
- [Numbered Databases in Valkey 9.0](https://valkey.io/blog/numbered-databases/)
- [Valkey 9.1 delivers improvements in security, performance, and more](https://valkey.io/blog/valkey-9-1-delivers-improvements-in-security-performance-and-more/)
- [Reducing Memory Overhead in Valkey 9.1](https://valkey.io/blog/9.1-memory-efficiency/)
- [Introducing Vector Search To Valkey](https://valkey.io/blog/introducing-valkey-search/)
- [Beyond Vectors: Introducing Full-Text Search and Aggregations to Valkey](https://valkey.io/blog/valkey-search-1_2/)
- [Introducing Bloom Filters for Valkey](https://valkey.io/blog/introducing-bloom-filters/)
- [valkey-bundle: One stop shop for real-time applications](https://valkey.io/blog/valkey-bundle-one-stop-shop-for-low-latency-modern-applications/)
- [Valkey Helm: The new way to deploy Valkey on Kubernetes](https://valkey.io/blog/valkey-helm-chart/)
- [Harbor Chose Valkey](https://valkey.io/blog/harbor-chose-valkey/)
- [Announcing Spring Data Valkey](https://valkey.io/blog/spring-data-valkey/)
- [Valkey COPYING (BSD-3-Clause)](https://github.com/valkey-io/valkey/blob/unstable/COPYING)
- [Releases valkey-io/valkey](https://github.com/valkey-io/valkey/releases) — 9.1.1 (июль 2026)
- [Valkey Leadership](https://valkey.io/leadership/)

### Redis (первоисточники)

- [Redis is now available under the AGPLv3 open source license](https://redis.io/blog/agplv3/) (архивная копия) — трилицензия, интеграция Stack в ядро, vector sets, «87% faster commands»
- [Releases redis/redis](https://github.com/redis/redis/releases) — 8.10.1 (август 2026), ветки 8.x
- [Redis 8.2.0 release notes](https://github.com/redis/redis/releases/tag/8.2.0) — XDELEX/XACKDEL, SVS-VAMANA, per-slot метрики

### Managed-хостинги

- [What is Azure Managed Redis? — Microsoft Learn](https://learn.microsoft.com/en-us/azure/azure-cache-for-redis/managed-redis/managed-redis-overview)
- [Memorystore for Valkey documentation — Google Cloud](https://docs.cloud.google.com/memorystore/docs/valkey)
- [Amazon ElastiCache for Valkey](https://aws.amazon.com/elasticache/what-is-valkey/)
- [Amazon ElastiCache and Amazon MemoryDB for Valkey — анонс AWS](https://aws.amazon.com/blogs/aws/cost-effective-and-familiar-in-memory-data-stores-with-amazon-elasticache-and-amazon-memorydb-for-valkey/)

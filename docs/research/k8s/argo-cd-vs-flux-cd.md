# Argo CD vs Flux CD

Дата исследования: 2026-08-24.

## Обзор

Оба инструмента решают одну задачу — декларативную непрерывную доставку (GitOps CD) для Kubernetes по модели pull-based reconciliation: агент в кластере сам подтягивает желаемое состояние из Git и приводит кластер к нему ([OpenGitOps](https://opengitops.dev/)). Различаются архитектурой, философией и «весом».

| | Argo CD | Flux CD |
|---|---|---|
| **Назначение** | Декларативная непрерывная доставка для Kubernetes с веб-UI и моделью «Application» | Набор компонуемых контроллеров GitOps Toolkit, «GitOps-движок» без монолитного приложения |
| **Язык** | Go (UI — React/TypeScript) | Go |
| **Лицензия** | [Apache-2.0](https://github.com/argoproj/argo-cd/blob/master/LICENSE) | [Apache-2.0](https://github.com/fluxcd/flux2/blob/main/LICENSE) |
| **Репозиторий** | [github.com/argoproj/argo-cd](https://github.com/argoproj/argo-cd) (~24k ⭐) | [github.com/fluxcd/flux2](https://github.com/fluxcd/flux2) (~8.4k ⭐) |
| **Актуальная версия** | [v3.5.1](https://github.com/argoproj/argo-cd/releases/tag/v3.5.1) (12 августа 2026); параллельно поддерживаются ветки 3.3.x и 3.4.x | [v2.9.4](https://github.com/fluxcd/flux2/releases/tag/v2.9.4) (7 августа 2026); [2.9 GA](https://fluxcd.io/blog/2026/06/flux-v2.9.0/) — июнь 2026 |
| **Кто разрабатывает** | Сообщество под эгидой CNCF; ключевой вклад Intuit (исторически), Akuity, Codefresh | Сообщество под эгидой CNCF; ключевой вклад ControlPlane, Microsoft, AWS, GitLab ([блог проекта](https://fluxcd.io/blog/2024/03/flux-project-gains-new-corporate-support-and-ecosystem-in-2024/)) |
| **Governance** | CNCF **graduated** с 6 декабря 2022 (incubating с марта 2020) — [CNCF](https://www.cncf.io/projects/argo/) | CNCF **graduated** с 30 ноября 2022 (incubating с марта 2021) — [CNCF](https://www.cncf.io/projects/flux/) |
| **Первая версия** | 2018 (Intuit), первый коммит Argo — июль 2017 ([CNCF](https://www.cncf.io/projects/argo/)) | Июль 2016 («[Flux turns 10!](https://fluxcd.io/blog/2026/07/flux-turns-10/)») |

---

## 🏛️ Архитектура и модель работы

### Argo CD — «приложение как единица»

- Центральный API-сервер + встроенный веб-UI + gRPC/REST API; состояние описывается CRD **Application** ([документация](https://argo-cd.readthedocs.io/en/stable/operator-manual/architecture/)).
- Контроллер приложений периодически сравнивает живое состояние кластера с целевым из Git (pull-based) и умеет автоматически или вручную синхронизировать; есть rich diff, sync waves, hooks (пре/пост-синхронизация), prune/self-heal ([документация](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/)).
- Паттерн **App-of-Apps**: корневое Application порождает дочерние Application'ы ([документация](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)).
- **ApplicationSet** — генерация множества приложений из шаблонов (Git-директории, cluster generator, PR-generator и др.) ([документация](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/)).
- Для HA требуется несколько компонентов: application-controller (шейды), repo-server, api-server, redis, notifications, applicationset-controller ([HA-документация](https://argo-cd.readthedocs.io/en/stable/operator-manual/high_availability/)).

### Flux v2 — «композиция специализированных контроллеров»

- Runtime построен на **GitOps Toolkit** — наборе CRD и контроллеров ([README flux2](https://github.com/fluxcd/flux2)):
  - `source-controller` — GitRepository, OCIRepository, HelmRepository, HelmChart, Bucket: скачивание артефактов;
  - `kustomize-controller` — Kustomization: применение манифестов через server-side apply, drift detection/correction;
  - `helm-controller` — HelmRelease: декларативное управление Helm-релизами с drift detection ([блог 2.2](https://fluxcd.io/blog/2023/12/flux-v2.2.0/));
  - `notification-controller` — Provider/Alert/Receiver: алерты и webhooks;
  - `image-reflector`/`image-automation-controller` — сканирование реестров и автокоммит новых тегов в Git;
  - начиная с 2.9 — CLI plugin system, source-watcher ([блог 2.9](https://fluxcd.io/blog/2026/06/flux-v2.9.0/)).
- Каждый CRD можно использовать независимо — можно взять только source-controller + kustomize-controller и не ставить остальное.
- Композиция вместо App-of-Apps достигается вложенными Kustomizations (`dependsOn`, `spec.path`) и новыми API ExternalArtifact/ArtifactGenerator ([блог 2.7](https://fluxcd.io/blog/2025/09/flux-v2.7.0/)).

**Суть различия:** у Argo CD одна крупная «платформа» с единым центром (UI/API), у Flux — Unix-way набор мелких контроллеров, каждый из которых потребляет минимум ресурсов и может использоваться отдельно.

---

## 📄 Поддерживаемые форматы манифестов

| Формат | Argo CD | Flux |
|--------|:-------:|:----:|
| Plain YAML (каталоги/git-репозитории) | ✅ ([application sources](https://argo-cd.readthedocs.io/en/stable/user-guide/application_sources/)) | ✅ (через Kustomization) |
| Kustomize | ✅ Нативно | ✅ Основной механизм (kustomize-controller) |
| Helm (charts из репозиториев и OCI) | ✅ Как source приложения | ✅ HelmRelease + HelmChart/HelmRepository/OCIRepository; Helm v4 с Flux 2.8 ([блог](https://fluxcd.io/blog/2026/02/flux-v2.8.0/)) |
| Jsonnet | ✅ ([config management plugins](https://argo-cd.readthedocs.io/en/stable/user-guide/application_sources/)) | ❌ Нет аналога |
| Произвольные плагины рендеринга | ✅ Config Management Plugin server | ⚠️ Ограниченно (post-build редакторы, patches) |
| OCI-артефакты как источник конфигурации | ✅ С недавних версий | ✅ OCIRepository — первоклассный источник с верификацией подписей Cosign ([документация](https://fluxcd.io/flux/components/source/ocirepositories/)) |

---

## 🖥️ UI

| Критерий | Argo CD | Flux |
|----------|:-------:|:-----:|
| Официальный веб-UI | ✅ Полноценный, встроен в дистрибутив (топология ресурсов, diff, rollback, логи) | ❌ Не существует официального UI — позиция проекта: «UI не является частью ядра» |
| CLI-инструментарий | ✅ `argocd` CLI | ✅ `flux` CLI считается основным интерфейсом наблюдения |
| Сторонние UI | ✅ Множество (Codefresh, Akuity Platform и т.д.) | ⚠️ Weave GitOps (развитие остановлено после закрытия Weaveworks), [Capacitor](https://fluxcd.io/blog/2024/02/introducing-capacitor/) — community UI, анонсирован в официальном блоге Flux |

Для Flux отсутствие UI — осознанный трейдофф: меньше компонентов, но диагностика идёт через `flux get`/`kubectl`. Если визуальный контроль важен — это аргумент за Argo CD.

---

## 🔐 Multi-tenancy, RBAC, SSO

| Критерий | Argo CD | Flux |
|----------|:-------:|:-----:|
| Единица изоляции команд | AppProject: ограничения на git-источники, кластеры, namespace'ы ([документация](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#projects)) | Namespace-scoped CRD + impersonation (ServiceAccount на Kustomization/HelmRelease) ([multi-tenancy](https://fluxcd.io/flux/security/#multi-tenancy)) |
| RBAC | ✅ Богатая политика на уровне app/project/action (CASL-политики) ([RBAC](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/)) | ⚠️ Делегируется Kubernetes RBAC поверх namespace'ов |
| SSO/OIDC/SAML/LDAP | ✅ Встроено: OIDC, Dex-коннектор для SAML/LDAP ([user management](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/)) | ❌ Нет собственного authn — доступ к кластеру через kubeconfig/OIDC провайдера кластера |
| Аудит действий пользователей | ✅ Централизованно (API-server логирует все операции) | ⚠️ Через Kubernetes audit logs |

Вывод: для платформы с несколькими командами и «самосервисом» через UI Argo CD заметно сильнее; для одного оператора/команды разница несущественна.

---

## 🗝️ Secret management

Ни один из инструментов не управляет секретами «из коробки» — оба работают со сторонними решениями:

| Решение | Argo CD | Flux |
|---------|:-------:|:-----:|
| Bitnami **Sealed Secrets** | ✅ Работает (контроллер ставится отдельно) | ✅ Исторически популярнейшая связка с Flux |
| **SOPS + age/KMS** | ⚠️ Через плагины/хуки | ✅ Нативная расшифровка в kustomize-controller и helm-controller ([SOPS guide](https://fluxcd.io/flux/guides/mozilla-sops/)) |
| HashiCorp Vault | ⚠️ argocd-vault-plugin, External Secrets Operator | ✅ Через External Secrets Operator; свежий пост про интеграцию с OpenBao ([блог](https://fluxcd.io/blog/2026/07/flux-openbao-secrets-signatures/)) |
| External Secrets Operator | ✅ ESO вендорно-нейтрален, работает с обоими | ✅ Рекомендуемая связка ([ecosystem](https://fluxcd.io/ecosystem/)) |

У Flux нативная поддержка SOPS — самое простое решение для небольшого кластера без дополнительного сервиса.

---

## 🐳 Автоматизация образов (Image automation)

| | Argo CD | Flux |
|---|---|---|
| Встроенная возможность | ❌ Нет | ✅ ImageRepository/ImagePolicy/ImageUpdateAutomation — контроллеры входят в дистрибутив; GA с Flux 2.7 ([блог](https://fluxcd.io/blog/2025/09/flux-v2.7.0/)) |
| Отдельный проект | ✅ [argocd-image-updater](https://github.com/Akuity/argocd-image-updater) (поддерживается Akuity) — пишет новый тег прямо в Git | — |
| Верификация подписей образов | — | ✅ Cosign keyless verification для OCI-источников |

---

## 🚀 Прогрессивная доставка (canary/blue-green)

| | Экосистема Argo | Экосистема Flux |
|---|---|---|
| Инструмент | [Argo Rollouts](https://github.com/argoproj/argo-rollouts) (~3.6k ⭐): CRD Rollout с canary/experiment/analysis | [Flagger](https://github.com/fluxcd/flagger) (~5.4k ⭐, входит в организацию fluxcd): canary/blue-green с метриками Prometheus, Gateway API/Istio/Linkerd |
| Совместимость | Rollouts работает с любым CD, включая Flux | Flagger изначально из экосистемы Flux, но официально работает и с Argo CD ([flagger.app](https://flagger.app)) |

Для homelab прогрессивная доставка обычно избыточна, но если понадобится — Flagger покрывает оба сценария.

---

## 📊 Популярность и adoption

| Критерий | Argo CD | Flux |
|----------|:-------:|:-----:|
| GitHub звёзды основного репозитория | ~24k | ~8.4k (проект распределён по нескольким репозиториям: source-controller, helm-controller и т.д.) |
| CNCF статус | Graduated (12.2022) | Graduated (11.2022) |
| Контрибьюторы проекта (LFX Insights, весь проект Argo) | ~15.6k контрибьюторов суммарно по проекту ([CNCF Insights](https://insights.linuxfoundation.org/project/argo)) | — |
| Enterprise adopters | USERS.md: сотни компаний | Adopters list: Cisco, Orange, Morgan Stanley ([user story](https://fluxcd.io/blog/2026/03/stairway-to-gitops-morgan-stanley/)), Tchibo ([блог](https://fluxcd.io/blog/2024/03/flux-project-gains-new-corporate-support-and-ecosystem-in-2024/)) |
| Облачные интеграции | — | ✅ GitOps-расширение Azure Arc/AKS построено на Flux; EKS Anywhere и AWS используют Flux; GitLab рекомендует Flux как GitOps-решение ([блог Flux](https://fluxcd.io/blog/2024/03/flux-project-gains-new-corporate-support-and-ecosystem-in-2024/)) |
| Managed-предложения | ✅ Akuity Platform, Codefresh — компании, основанные мейнтейнерами Argo | ⚠️ ControlPlane (enterprise-дистрибуция Flux, найм мейнтейнеров), Flux Operator от ControlPlane ([блог](https://fluxcd.io/blog/2024/03/flux-project-gains-new-corporate-support-and-ecosystem-in-2024/)) |

По «звёздам» и количеству туториалов Argo CD заметно популярнее; по проникновению в managed-платформы облаков (Azure, AWS, GitLab) лидирует Flux.

---

## ⚡ Потребление ресурсов

Прямых нейтральных бенчмарков «Argo CD vs Flux» мало (обе стороны публикуют свои), но сопоставление компонент даёт ясную картину:

| Критерий | Argo CD | Flux |
|----------|:-------:|:----:|
| Минимальный набор pod'ов | ~6–8 (api-server, application-controller, repo-server, redis, dex, notifications, applicationset) | 4–6 тонких контроллеров, каждый — одиночный Go-бинарник |
| Собственные бенчмарки | — | Публикует MTTP/память бенчмарки: 100 объектов — max memory 32–140 MiB на контроллер; 1000 объектов — до 620 MiB на helm-controller ([блог 2.2](https://fluxcd.io/blog/2023/12/flux-v2.2.0/), [flux-benchmark](https://github.com/fluxcd/flux-benchmark)) |
| Известные проблемы масштаба | repo-server — самый тяжёлый компонент, требует тюнинга при сотнях приложений ([HA guide](https://argo-cd.readthedocs.io/en/stable/operator-manual/high_availability/)) | Горизонтально масштабируется шардированием Kustomizations; бенчмарки публикуются открыто |

> ⚠️ Цифры памяти Flux — из блога самого проекта. Общий консенсус сообщества: минимальная установка Flux легче минимальной установки Argo CD примерно в разы (у Argo CD даже «non-HA» установка тянет redis + несколько сервисов), но строгих независимых измерений на август 2026 мы не нашли — это отмечено как непроверяемое утверждение.

---

## 🏢 Экосистема и судьба проектов

- **Weaveworks** (компания-основатель Flux) закрылась в феврале 2024. Проект выжил: он уже был CNCF graduated, корпоративную поддержку взяли ControlPlane (наняла ведущих мейнтейнеров Stefan Prodan и Soulé Ba), GitLab, Microsoft и AWS ([блог Flux, март 2024](https://fluxcd.io/blog/2024/03/flux-project-gains-new-corporate-support-and-ecosystem-in-2024/)). Продукт Weave GitOps прекратил активную разработку — ниша community-UI занята Capacitor ([блог Flux](https://fluxcd.io/blog/2024/02/introducing-capacitor/)).
- **Akuity** и **Codefresh** основаны мейнтейнерами Argo и коммерциализируют экосистему Argo (Argo CD + Rollouts + Workflows).
- Flux развивается активно: 2.7 (сент 2025) → 2.8 (февр 2026, Helm v4) → 2.9 (июнь 2026, CLI-плагины, MCP-сервер для AI-агентов) → плагины Flux Mirror и Flux Schema (август 2026) ([блог](https://fluxcd.io/blog/)). Прошёл две независимые security-аудита без найденных CVE во втором ([блог](https://fluxcd.io/blog/2024/03/flux-project-gains-new-corporate-support-and-ecosystem-in-2024/)).
- Argo CD перешёл на схему «3.x» с поддержкой трёх минорных веток одновременно (3.3/3.4/3.5 на август 2026) — [releases](https://github.com/argoproj/argo-cd/releases).

---

## 🧩 Что ещё есть (кратко об альтернативах)

| Инструмент | Суть | Примечание |
|------------|------|------------|
| [Jenkins X](https://jenkins-x.io/) | CI+CD-платформа с GitOps поверх Tekton | Тяжёлая, популярность упала; сейчас сфокусирована на jx3 pipeline-механике |
| [Spinnaker](https://spinnaker.io/) | Мощный CD для мультклауда | Не строго GitOps (push-based), очень тяжёлый |
| [Kargo](https://github.com/akuity/kargo) (~3.6k ⭐) | Promotion layer поверх GitOps (Argo CD/Flux): продвижение артефактов между стадиями (dev→staging→prod) с верификацией | Развивается Akuity, растущая популярность; дополняет, а не заменяет CD |
| [Carvel kapp-controller](https://carvel.dev/kapp-controller/) | Лёгкий декларативный деплой от Broadcom/VMware | Ниже экосистемная активность |
| CI-pipelines + `kubectl apply` | Для совсем маленьких кластеров иногда хватает GitLab Actions/Gitea Actions c kubectl | Теряется drift correction и self-heal — главная ценность GitOps |

---

## 📋 Когда выбирать Argo CD

- Нужен полноценный веб-UI: визуальный контроль, ручной sync/rollback, диффы — «из коробки»
- Мультикомандность: SSO, RBAC, AppProjects, аудит, self-service для разработчиков
- Используется Jsonnet или кастомные render-плагины
- Планируется managed-платформа (Akuity, Codefresh)
- Есть опыт эксплуатации и ресурсы: Argo CD тяжелее и сложнее в настройке (repo-server, HA)

## 📋 Когда выбирать Flux

- Минимальный footprint: маленький кластер, edge, ARM/Raspberry Pi
- Kubernetes-native подход: всё через CRD, ничего кроме контроллеров; композиция GitOps Toolkit
- Нужны встроенные image automation и нативная расшифровка SOPS
- Интеграция с облачными платформами (Azure Arc/AKS, EKS Anywhere, GitLab)
- Приемлема работа через CLI/kubectl вместо UI (или готовность поставить Capacitor)

---

## 📌 Рекомендация для homelab

Контекст этого репозитория: один сервер, Docker Compose, самообслуживание, миграция на Kubernetes не планируется; если k8s и появится — то однонодовый лёгкий кластер (k3s-класс), где каждый гигабайт RAM на счету и нет команды, которой нужен multi-tenant UI.

### ✅ Flux — предпочтительный выбор для однонодового homelab

| # | Преимущество |
|---|-------------|
| 1 | Заметно легче: 4–6 тонких контроллеров против 6–8 сервисов Argo CD с Redis; собственные бенчмарки Flux показывают десятки MiB на контроллер при малых масштабах ([блог](https://fluxcd.io/blog/2023/12/flux-v2.2.0/)) |
| 2 | Нативная расшифровка SOPS+age без дополнительных сервисов — самый простой путь к секретам в Git для одного человека |
| 3 | Встроенный image automation — автокоммит новых тегов образов в Git, удобно для «watchtower-без-watchtower» сценариев |
| 4 | Всё декларативно через CRD — состояние GitOps-стека само живёт в Git, легко восстановить кластер с нуля |
| 5 | Тот же движок, что используется в Azure Arc/AKS и GitLab — навыки переносимы |
| 6 | Проект устойчив: пережил закрытие Weaveworks, graduated в CNCF, мейнтейнеры финансируются ([блог](https://fluxcd.io/blog/2024/03/flux-project-gains-new-corporate-support-and-ecosystem-in-2024/)) |

### ⚠️ Argo CD — разумная альтернатива, если

| # | Условие |
|---|---------|
| 1 | Критичен визуальный интерфейс: без UI эксплуатация Flux сводится к CLI — если хочется «смотреть глазами», Argo CD даст это сразу |
| 2 | Планируется рост до нескольких пользователей/команд с разными правами (RBAC, SSO, AppProjects) |
| 3 | Манифесты на Jsonnet или нужны кастомные render-плагины |
| 4 | Ресурсы сервера позволяют (+~1 GB RAM на постоянной основе) и простота эксплуатации UI важнее экономии |

Практический вывод: для текущего Docker Compose homelab ни тот, ни другой инструмент не нужен вовсе — GitOps CD имеет смысл только при появлении Kubernetes. Когда это произойдёт, начать стоит с Flux (`flux bootstrap` за минуты, минимальный оверхед), оставив Argo CD запасным вариантом на случай, когда понадобится UI и многопользовательская модель.

---

## Не подтверждённые утверждения / оговорки

- **Относительное потребление ресурсов «Flux легче Argo CD»** — консенсус сообщества и следствие архитектуры (меньше компонентов); прямого независимого бенчмарка сравнения двух инструментов найти не удалось. Цифры памяти Flux — из [блога проекта](https://fluxcd.io/blog/2023/12/flux-v2.2.0/) (self-published).
- **Точное число звёзд argocd-image-updater и weaveworks/gitops** — GitHub API был rate-limited на момент проверки; звёзды argo-cd (24k) и flux2 (8.4k) сняты со страниц репозиториев 2026-08-24 и меняются ежедневно.
- **Статус Weave GitOps OSS** — развитие прекращено после закрытия Weaveworks (февраль 2024); формальный архив-статус репозитория не проверен напрямую.
- **Опросы CNCF о доле использования** — конкретные цифры из CNCF-опросов в исследование не включены, так как первичные отчёты не были проверены напрямую.

---

## Источники

### Argo CD

- [argo-cd.readthedocs.io — документация](https://argo-cd.readthedocs.io/)
- [Architecture](https://argo-cd.readthedocs.io/en/stable/operator-manual/architecture/)
- [Application Sources (Helm/Kustomize/Jsonnet)](https://argo-cd.readthedocs.io/en/stable/application_sources/)
- [App-of-Apps pattern (cluster bootstrapping)](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [ApplicationSet](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/)
- [RBAC](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/)
- [User Management / SSO](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/)
- [High Availability](https://argo-cd.readthedocs.io/en/stable/operator-manual/high_availability/)
- [Releases argoproj/argo-cd](https://github.com/argoproj/argo-cd/releases) — v3.5.1 (авг 2026)
- [Releases argoproj/argo-rollouts](https://github.com/argoproj/argo-rollouts/releases)
- [Akuity/argocd-image-updater](https://github.com/Akuity/argocd-image-updater)
- [CNCF Project Page: Argo](https://www.cncf.io/projects/argo/) — graduation 6 декабря 2022

### Flux

- [fluxcd.io — документация](https://fluxcd.io/flux/)
- [README fluxcd/flux2 — компоненты GitOps Toolkit](https://github.com/fluxcd/flux2)
- [Releases fluxcd/flux2](https://github.com/fluxcd/flux2/releases) — v2.9.4 (авг 2026)
- [Announcing Flux 2.9 GA](https://fluxcd.io/blog/2026/06/flux-v2.9.0/) — CLI plugins, MCP server
- [Announcing Flux 2.8 GA](https://fluxcd.io/blog/2026/02/flux-v2.8.0/) — Helm v4 support
- [Announcing Flux 2.7 GA](https://fluxcd.io/blog/2025/09/flux-v2.7.0/) — image automation GA, ExternalArtifact/ArtifactGenerator
- [Announcing Flux 2.2 GA](https://fluxcd.io/blog/2023/12/flux-v2.2.0/) — benchmark results (MTTP, память)
- [Flux project gains New Corporate Support and Ecosystem in 2024](https://fluxcd.io/blog/2024/03/flux-project-gains-new-corporate-support-and-ecosystem-in-2024/) — судьба проекта после закрытия Weaveworks, ControlPlane, GitLab/Microsoft/AWS
- [Introducing Capacitor, a general purpose UI for Flux](https://fluxcd.io/blog/2024/02/introducing-capacitor/)
- [Flux turns 10!](https://fluxcd.io/blog/2026/07/flux-turns-10/) — история проекта с 2016
- [Flux Security — multi-tenancy](https://fluxcd.io/flux/security/)
- [Guide: Manage Kubernetes secrets with Flux and SOPS](https://fluxcd.io/flux/guides/mozilla-sops/)
- [Flux and OpenBao: Secrets and Signatures](https://fluxcd.io/blog/2026/07/flux-openbao-secrets-signatures/)
- [Stairway to GitOps: Scaling Flux at Morgan Stanley](https://fluxcd.io/blog/2026/03/stairway-to-gitops-morgan-stanley/)
- [fluxcd/flux-benchmark](https://github.com/fluxcd/flux-benchmark)
- [CNCF Project Page: Flux](https://www.cncf.io/projects/flux/) — graduation 30 ноября 2022

### Смежные проекты

- [flagger.app — progressive delivery (работает с Flux и Argo CD)](https://flagger.app)
- [akuity/kargo](https://github.com/akuity/kargo) — promotion layer
- [OpenGitOps — определение GitOps](https://opengitops.dev/)

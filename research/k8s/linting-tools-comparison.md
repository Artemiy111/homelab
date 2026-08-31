# Сравнение утилит для линтинга и проверки манифестов Kubernetes

**Дата исследования:** 2026-08-31

## Обзор

Существует множество утилит для валидации и линтинга Kubernetes манифестов. Они различаются по функциональности, производительности, популярности и предназначению.

## Утилиты

### 1. Kubeconform
- **GitHub:** https://github.com/yannh/kubeconform
- **⭐ Stars:** 3.2k
- **Язык:** Go
- **Лицензия:** Apache-2.0
- **Статус:** ✅ Активно поддерживается

### 2. Kubeval
- **GitHub:** https://github.com/instrumenta/kubeval
- **⭐ Stars:** 3.2k
- **Язык:** Go
- **Лицензия:** Apache-2.0
- **Статус:** ❌ **DEPRECATED** (рекомендуется Kubeconform)

### 3. Kube-linter
- **GitHub:** https://github.com/stackrox/kube-linter
- **⭐ Stars:** 3.5k
- **Язык:** Go
- **Лицензия:** Apache-2.0
- **Статус:** ✅ Активно поддерживается (StackRox/Red Hat)

### 4. Polaris
- **GitHub:** https://github.com/FairwindsOps/polaris
- **⭐ Stars:** 3.4k
- **Язык:** Go
- **Лицензия:** Apache-2.0
- **Статус:** ✅ Активно поддерживается (Fairwinds)

### 5. Checkov
- **GitHub:** https://github.com/bridgecrewio/checkov
- **⭐ Stars:** 9.0k
- **Язык:** Python
- **Лицензия:** Apache-2.0
- **Статус:** ✅ Активно поддерживается (Bridgecrew/Prisma Cloud)

### 6. Kubesec
- **GitHub:** https://github.com/controlplaneio/kubesec
- **⭐ Stars:** 1.5k
- **Язык:** Go
- **Лицензия:** Apache-2.0
- **Статус:** ✅ Активно поддерживается

### 7. Pluto
- **GitHub:** https://github.com/FairwindsOps/pluto
- **⭐ Stars:** 2.6k
- **Язык:** Go
- **Лицензия:** Apache-2.0
- **Статус:** ✅ Активно поддерживается (Fairwinds)

### 8. Datree
- **GitHub:** https://github.com/datreeio/datree
- **⭐ Stars:** 6.3k
- **Язык:** Go
- **Лицензия:** Apache-2.0
- **Статус:** ❌ **ARCHIVED** (компания закрыта в июле 2023)

### 9. kubectl validate
- **GitHub:** Встроен в kubectl (начиная с v1.27)
- **Статус:** ✅ Встроен в Kubernetes

### 10. Kube-score
- **GitHub:** https://github.com/zegl/kube-score
- **⭐ Stars:** 3.1k
- **Язык:** Go
- **Лицензия:** MIT
- **Статус:** ✅ Активно поддерживается

### 11. Kubescape
- **GitHub:** https://github.com/kubescape/kubescape
- **⭐ Stars:** 11.7k
- **Язык:** Go
- **Лицензия:** Apache-2.0
- **Статус:** ✅ Активно поддерживается (CNCF Incubating)

### 12. Kube-bench
- **GitHub:** https://github.com/aquasecurity/kube-bench
- **⭐ Stars:** 8.2k
- **Язык:** Go
- **Лицензия:** Apache-2.0
- **Статус:** ✅ Активно поддерживается (Aqua Security)

---

## Сравнительная таблица

| Критерий | Kubeconform | Kubeval | Kube-linter | Polaris | Checkov | Kubesec | Pluto | Datree | kubectl validate | Kube-score | Kubescape | Kube-bench |
|----------|:-----------:|:-------:|:-----------:|:-------:|:-------:|:-------:|:-----:|:------:|:----------------:|:----------:|:---------:|:----------:|
| **Статус** | ✅ | ❌ DEPRECATED | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ ARCHIVED | ✅ | ✅ | ✅ | ✅ |
| **GitHub Stars** | 3.2k | 3.2k | 3.5k | 3.4k | 9.0k | 1.5k | 2.6k | 6.3k | N/A | 3.1k | 11.7k | 8.2k |
| **CNCF** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ Incubating | ❌ |
| **Валидация схемы** | ✅ | ✅ | ⚠️ | ⚠️ | ⚠️ | ✅ | ❌ | ⚠️ | ✅ | ⚠️ | ⚠️ | ❌ |
| **Бест-практики** | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ | ⚠️ |
| **Безопасность** | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ | ✅ |
| **CIS Benchmark** | ❌ | ❌ | ⚠️ | ❌ | ⚠️ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ |
| **MITRE ATT&CK** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **NSA/CISA** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **Helm** | ⚠️ | ⚠️ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ |
| **Kustomize** | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **CRD поддержка** | ✅ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ❌ | ⚠️ | ✅ | ⚠️ | ✅ | ❌ |
| **Производительность** | ⚡⚡⚡ | ⚡ | ⚡⚡ | ⚡⚡ | ⚡ | ⚡ | ⚡⚡ | ⚡ | ⚡⚡⚡ | ⚡⚡ | ⚡ | ⚡ |
| **Enterprise** | ✅ | ⚠️ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |
| **Homelab** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ | ✅ | ✅ | ✅ | ✅ |
| **CI/CD интеграция** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ | ✅ | ✅ | ✅ |
| **GitHub Actions** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ |
| **GitLab CI** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ |
| **Kubectl плагин** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **Pre-commit hook** | ⚠️ | ❌ | ✅ | ⚠️ | ✅ | ❌ | ✅ | ✅ | ❌ | ⚠️ | ✅ | ❌ |
| **Docker образ** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ |
| **Custom policies** | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ⚠️ |
| **OPA/Rego** | ❌ | ❌ | ❌ | ⚠️ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **JSON Schema** | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **Dashboard** | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ |
| **Admission Controller** | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **In-cluster operator** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ⚠️ |
| **Runtime защита** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ (eBPF) | ❌ |
| **Image scanning** | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ (Grype) | ❌ |
| **Auto-fix** | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **Score/Рейтинг** | ❌ | ❌ | ❌ | ⚠️ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ | ⚠️ |
| **Форматы вывода** | json,junit,tap,text | json,junit,text | json,sarif,junit | json,yaml | json,junit,sarif,csv,html | json,table,template | json,yaml,text | json,yaml,text | json,yaml | human,json,ci,sarif | json,junit,sarif,html,pdf,csv | json,junit,text |
| **Offline работа** | ✅ | ✅ | ⚠️ | ⚠️ | ⚠️ | ✅ | ✅ | ⚠️ | ✅ | ✅ | ✅ | ⚠️ |
| **Мульти-version K8s** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ | ✅ | ✅ | ✅ |

---

## Легенда

- ✅ — Полная поддержка
- ⚠️ — Ограниченная поддержка / через плагины
- ❌ — Не поддерживается / DEPRECATED
- ⚡⚡⚡ — Очень быстрая
- ⚡⚡ — Быстрая
- ⚡ — Средняя скорость

---

## Детальное описание

### 🏆 Kubeconform — Лучший выбор для валидации

**Назначение:** Валидация Kubernetes манифестов по OpenAPI схемам

**Ключевые особенности:**
- 🚀 **Производительность:** В 5-6 раз быстрее Kubeval (параллельная загрузка схем)
- 📦 **CRD поддержка:** Через Datree CRDs-catalog или кастомные схемы
- 🔧 **Гибкость:** Настраиваемые пути к схемам, поддержка offline
- 📊 **Форматы вывода:** JSON, JUnit, TAP, text
- 🔌 **Интеграция:** GitHub Actions, GitLab CI, Docker

**Пример использования:**
```bash
kubeconform -summary -kubernetes-version 1.28.0 manifests/
```

**Плюсы:**
- Максимальная скорость валидации
- Актуальные схемы для всех версий K8s
- Поддержка кастомных схем
- Легковесный бинарник

**Минусы:**
- Только валидация схем (не проверяет бест-практики)
- Нет встроенных проверок безопасности

---

### 🏆 Kube-linter — Лучший для бест-практик

**Назначение:** Статический анализ на соответствие best practices

**Ключевые особенности:**
- 📋 **Встроенные проверки:** 50+ проверок из коробки
- 🎯 **Фокус на production readiness:** Non-root, read-only FS, лимиты ресурсов
- 🔧 **Конфигурируемость:** YAML конфиг для включения/выключения проверок
- 📊 **Форматы вывода:** JSON, SARIF, JUnit (с мульти-форматом)
- 🔌 **Интеграция:** pre-commit, GitHub Actions, GitLab CI

**Пример использования:**
```bash
kube-linter lint manifests/
```

**Плюсы:**
- Готовые проверки для production readiness
- Поддержка Helm и Kustomize
- Отличная документация
- Поддержка StackRox/Red Hat

**Минусы:**
- Медленнее Kubeconform
- Нет встроенной валидации схем (только best practices)

---

### 🏆 Polaris — Лучший для полного цикла policy enforcement

**Назначение:** Policy engine для валидации и автоматического исправления

**Ключевые особенности:**
- 🎛️ **3 режима работы:** Dashboard, Admission Controller, CLI
- 🔧 **Автоматическое исправление:** Mutating webhook для исправления проблем
- 📊 **30+ встроенных политик:** Production readiness + Security
- 🎨 **Dashboard:** Красивый веб-интерфейс для аудита кластера
- 🔌 **Интеграция:** Fairwinds Insights (commercial)

**Пример использования:**
```bash
polaris audit --dashboard
polaris validate manifests/
```

**Плюсы:**
- Полный цикл: валидация → исправление
- Dashboard для визуализации
- Admission controller для превенции
- Интеграция с Fairwinds Insights

**Минусы:**
- Сложнее в настройке
- Fairwinds Insights — платный сервис

---

### 🏆 Checkov — Лучший для мульти-фреймворк IaC

**Назначение:** Статический анализ IaC (Terraform, K8s, CloudFormation, Docker и др.)

**Ключевые особенности:**
- 🌐 **Мульти-фреймворк:** Terraform, K8s, Helm, Docker, CloudFormation, и др.
- 📋 **1000+ политик:** Security + Compliance для всех облачных провайдеров
- 🔍 **Graph-based scanning:** Контекстно-зависимые проверки
- 📊 **Форматы вывода:** CLI, JSON, JUnit, SARIF, CycloneDX
- 🔌 **Интеграция:** VS Code, CI/CD, Prisma Cloud

**Пример использования:**
```bash
checkov -d manifests/
```

**Плюсы:**
- Самое большое количество политик (1000+)
- Поддержка всех основных IaC
- Отличная интеграция с IDE
- Графовый анализ для контекстных проверок

**Минусы:**
- Python (тяжелее Go-бинарников)
- Много ложных срабатываний
- Привязка к Prisma Cloud для расширенных фич

---

### 🏆 Kubesec — Лучший для безопасности

**Назначение:** Анализ безопасности Kubernetes ресурсов

**Ключевые особенности:**
- 🛡️ **Security scoring:** Система баллов для оценки безопасности
- 🔧 **HTTP сервер:** Встроенный API для сканирования
- 📊 **Форматы вывода:** JSON, table, template
- 🎯 **Фокус на Pod security:** capabilities, security context, привилегии
- 🔌 **Интеграция:** kubectl plugin, webhook

**Пример использования:**
```bash
kubesec scan manifests/
```

**Плюсы:**
- Специализация на безопасности
- Простой API для интеграции
- HTTP сервер для автоматизации
- Kubesec-as-a-Service (публичный API)

**Минусы:**
- Узкая специализация (только безопасность)
- Меньше проверок чем у Polaris/Checkov

---

### 🏆 Pluto — Лучший для миграций

**Назначение:** Поиск deprecated apiVersions в K8s манифестах

**Ключевые особенности:**
- 🔍 **Детектор deprecated API:** Находит устаревшие apiVersions
- 📊 **Helm releases:** Проверка deployed Helm релизов
- 🎯 **DEPRECATED vs REMOVED:** Различает deprecated и removed API
- 🔌 **Интеграция:** GitHub Actions, CircleCI

**Пример использования:**
```bash
pluto detect-files -d manifests/
pluto detect-helm
```

**Плюсы:**
- Незаменим для миграций между версиями K8s
- Проверка как кода, так и deployed релизов
- Интеграция с Helm

**Минусы:**
- Узкая специализация
- Не заменяет полноценный линтер

---

### 🏆 Kube-score — Лучший для reliability рекомендаций

**Назначение:** Статический анализ с рекомендациями по reliability и security

**Ключевые особенности:**
- 📊 **Score система:** Бальная оценка для каждого ресурса
- 🔍 **Рекомендации:** Конкретные советы по улучшению
- 🎯 **Фокус на reliability:** Limits, probes, anti-affinity, PDB
- 📊 **Форматы вывода:** human, json, ci, sarif
- 🔌 **Интеграция:** Helm, Kustomize, kubectl, Docker

**Пример использования:**
```bash
kube-score score manifests/
helm template my-app | kube-score score -
```

**Плюсы:**
- Понятные рекомендации с объяснениями
- Поддержка Helm и Kustomize
- Быстрая работа
- CI-friendly формат вывода

**Минусы:**
- Ограниченный набор проверок (только reliability + security)
- Нет custom policies

---

### 🏆 Kubescape — Лучший для comprehensive security

**Назначение:** Полная платформа безопасности для Kubernetes

**Ключевые особенности:**
- 🛡️ **CNCF Incubating:** Официальный проект CNCF
- 🔍 **Мульти-фреймворк:** NSA, MITRE ATT&CK, CIS Benchmark
- 🐳 **Image scanning:** Через Grype для CVE
- 🔧 **Auto-fix:** Автоматическое исправление проблем
- 📊 **Runtime защита:** eBPF-based мониторинг через Inspektor Gadget
- 🤖 **MCP сервер:** Интеграция с AI ассистентами

**Пример использования:**
```bash
kubescape scan manifests/
kubescape scan framework nsa
kubescape scan image nginx:latest
kubescape fix results.json
```

**Плюсы:**
- Самое большое количество проверок безопасности
- Поддержка всех основных фреймворков compliance
- In-cluster operator для continuous monitoring
- Auto-fix и image patching

**Минусы:**
- Тяжелее чем специализированные инструменты
- Сложнее в настройке
- Может быть много шума в выводе

---

### 🏆 Kube-bench — Лучший для CIS Benchmark

**Назначение:** Проверка соответствия CIS Kubernetes Benchmark

**Ключевые особенности:**
- 📋 **CIS Benchmark:** Точная реализация CIS проверок
- 🔍 **Кластерная проверка:** Проверка control plane и worker нод
- 📊 **YAML конфигурация:** Легко обновляется при изменении benchmark
- 🔌 **Интеграция:** Trivy, Trivy Operator

**Пример использования:**
```bash
kube-bench run
kube-bench run --targets master
kube-bench run --targets node
```

**Плюсы:**
- Официальная реализация CIS Benchmark
- Детальные отчёты с remediation
- Интеграция с Trivy ecosystem

**Минусы:**
- Только CIS Benchmark (не проверяет бест-практики)
- Требует доступа к нодам кластера
- Не для CI/CD (только для running cluster)

---

### ❌ Kubeval — DEPRECATED

**Статус:** Замещён Kubeconform

**Причина deprecation:** Kubeconform является прямым наследником с улучшениями:
- В 5-6 раз быстрее
- Более актуальные схемы
- CRD поддержка
- Аналогичный API

---

### ❌ Datree — ARCHIVED

**Статус:** Компания закрыта в июле 2023

**Причина:** Коммерческая поддержка прекращена. Возможен standalone запуск в offline mode, но без:
- Централизованного реестра политик
- Автоматической валидации K8s схем
- Dashboard

---

## Рекомендации по использованию

### 🏠 Homelab / Learning

**Минимальный стек:**
```bash
# Валидация схемы (быстро)
kubeconform -summary manifests/

# Бест-практики + reliability
kube-linter lint manifests/
kube-score score manifests/

# Безопасность (опционально)
kubesec scan manifests/
```

**Почему:**
- Kubeconform — быстрая валидация, понятные ошибки
- Kube-linter — учит бест-практики через ошибки
- Kube-score — показывает reliability проблемы с рекомендациями
- Kubesec — помогает понять security best practices

### 🏢 Enterprise / Production

**Полный стек:**
```yaml
# .gitlab-ci.yml / .github/workflows
stages:
  - validate

kubeconform:
  stage: validate
  script:
    - kubeconform -summary -kubernetes-version 1.28.0 manifests/

kube-linter:
  stage: validate
  script:
    - kube-linter lint --config .kube-linter.yaml manifests/

polaris:
  stage: validate
  script:
    - polaris validate --audit-path manifests/

kubescape:
  stage: validate
  script:
    - kubescape scan manifests/ --format sarif --output results.sarif

pluto:
  stage: validate
  script:
    - pluto detect-files -d manifests/ --target-versions k8s=v1.28.0
```

**Почему:**
- Kubeconform — быстрая валидация схем (gates)
- Kube-linter — compliance checks (SOC2, CIS Benchmark)
- Polaris — policy enforcement + dashboard
- Kubescape — глубокий security анализ (NSA, MITRE, CIS)
- Pluto — проверка deprecated API перед апгрейдами

### 🔒 Security-focused

**Стек:**
```bash
# Kubescape для полного security анализа
kubescape scan manifests/
kubescape scan framework nsa
kubescape scan framework mitre

# Kubesec для security scoring
kubesec scan manifests/

# Kube-linter для security best practices
kube-linter lint --config security-config.yaml manifests/

# Kube-bench для CIS Benchmark (в кластере)
kube-bench run
```

---

## Интеграции

### CI/CD

| Пользователь | GitHub Actions | GitLab CI | Jenkins | CircleCI |
|------------|:--------------:|:---------:|:-------:|:--------:|
| Kubeconform | ✅ | ✅ | ✅ | ✅ |
| Kube-linter | ✅ | ✅ | ✅ | ✅ |
| Polaris | ✅ | ✅ | ✅ | ✅ |
| Checkov | ✅ | ✅ | ✅ | ✅ |
| Kubesec | ✅ | ✅ | ✅ | ⚠️ |
| Pluto | ✅ | ✅ | ✅ | ✅ |
| Kube-score | ✅ | ✅ | ✅ | ✅ |
| Kubescape | ✅ | ✅ | ✅ | ✅ |
| Kube-bench | ⚠️ | ⚠️ | ⚠️ | ⚠️ |

### IDE

| Инструмент | VS Code | JetBrains | Vim/Neovim |
|------------|:-------:|:---------:|:----------:|
| Kubeconform | ⚠️ | ⚠️ | ⚠️ |
| Kube-linter | ⚠️ | ⚠️ | ⚠️ |
| Checkov | ✅ | ✅ | ⚠️ |
| YAML LSP | ✅ | ✅ | ✅ |

### Kubernetes

| Инструмент | Admission Controller | kubectl plugin | Webhook |
|------------|:--------------------:|:--------------:|:-------:|
| Polaris | ✅ | ❌ | ✅ |
| Kubesec | ✅ | ✅ | ✅ |
| Datree | ✅ | ✅ | ✅ |
| Checkov | ❌ | ❌ | ❌ |

---

## Заключение

### 🎯 Для homelab рекомендуется:
1. **Kubeconform** — быстрая валидация схем (обязательно)
2. **Kube-linter** — проверка best practices (рекомендуется)
3. **Kube-score** — reliability рекомендации (рекомендуется)
4. **Pluto** — проверка deprecated API (при апгрейдах)

### 🏢 Для enterprise рекомендуется:
1. **Kubeconform** + **Kube-linter** — базовый pipeline
2. **Kubescape** — comprehensive security (NSA, MITRE, CIS, CNCF)
3. **Polaris** — policy enforcement + dashboard
4. **Kube-bench** — CIS Benchmark (в кластере)
5. **Checkov** — если нужен мульти-фреймворк IaC анализ
6. **Pluto** — проверка deprecated API перед апгрейдами

### ❌ Не рекомендуется:
- **Kubeval** — deprecated, используйте Kubeconform
- **Datree** — archived, компания закрыта

---

## Установка через пакетные менеджеры

### Homebrew (macOS/Linux)

```bash
# Основные утилиты для linting
brew install kubeconform      # Валидация схем
brew install kube-linter      # Best practices
brew install kube-score       # Reliability рекомендации

# Безопасность
brew install kubescape        # Comprehensive security (CNCF)
brew install kube-bench       # CIS Benchmark

# Специализированные
brew install polaris          # Policy engine
brew install pluto            # Deprecated API detector
brew install kubesec          # Security scoring
brew install checkov          # Multi-framework IaC

# Утилиты (не для linting, но полезны)
brew install kubectx          # Переключение контекстов
brew install kubent           # Deprecated API ( alternative)
```

### Krew (kubectl plugin manager)

```bash
# Установка krew если还没有
kubectl krew install score    # kube-score как kubectl plugin
kubectl krew install kubescape
```

### Go install

```bash
go install github.com/yannh/kubeconform/cmd/kubeconform@latest
go install golang.stackrox.io/kube-linter/cmd/kube-linter@latest
go install github.com/zegl/kube-score/cmd/kube-score@latest
go install github.com/controlplaneio/kubesec/v2@latest
go install github.com/FairwindsOps/pluto@latest
```

### pip (Python)

```bash
pip install checkov
```

---

## Дополнительные критерии сравнения

### Количество проверок

| Инструмент | Количество проверок | Тип проверок |
|------------|:-------------------:|--------------|
| Checkov | 1000+ | Security, Compliance, Best Practices |
| Kubescape | 200+ | Security (NSA, MITRE, CIS) |
| Kube-linter | 50+ | Best Practices, Security |
| Polaris | 30+ | Best Practices, Security |
| Kube-score | 15+ | Reliability, Security |
| Kubesec | 20+ | Security |
| Kubeconform | N/A | Только валидация схем |
| Kube-bench | 100+ | CIS Benchmark |

### Поддержка фреймворков

| Инструмент | Terraform | CloudFormation | Helm | Kustomize | Dockerfile | Ansible |
|------------|:---------:|:--------------:|:----:|:---------:|:----------:|:-------:|
| Checkov | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Kubescape | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ |
| Kube-linter | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ |
| Polaris | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| Kube-score | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ |
| Kubesec | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| Kubeconform | ❌ | ❌ | ⚠️ | ❌ | ❌ | ❌ |

### Compliance фреймворки

| Инструмент | CIS | NSA | MITRE ATT&CK | SOC2 | PCI-DSS | HIPAA |
|------------|:---:|:---:|:------------:|:----:|:-------:|:-----:|
| Kubescape | ✅ | ✅ | ✅ | ⚠️ | ⚠️ | ⚠️ |
| Kube-bench | ✅ | ❌ | ❌ | ⚠️ | ❌ | ❌ |
| Kube-linter | ⚠️ | ❌ | ❌ | ⚠️ | ❌ | ❌ |
| Checkov | ⚠️ | ❌ | ❌ | ⚠️ | ⚠️ | ⚠️ |

### Поддержка Kubernetes версий

| Инструмент | Поддержка версий | Обновление схем |
|------------|:----------------:|:---------------:|
| Kubeconform | Все версии | Автоматическое |
| Kubeval | До 1.14 | ❌ Заброшено |
| Kube-linter | Все версии | Ручное |
| Polaris | Все версии | Ручное |
| Checkov | Все версии | Ручное |
| Kubescape | Все версии | Автоматическое |
| Kube-bench | Все версии | Ручное |

---

## Источники

- [Kubeconform GitHub](https://github.com/yannh/kubeconform)
- [Kube-linter GitHub](https://github.com/stackrox/kube-linter)
- [Polaris GitHub](https://github.com/FairwindsOps/polaris)
- [Checkov GitHub](https://github.com/bridgecrewio/checkov)
- [Kubesec GitHub](https://github.com/controlplaneio/kubesec)
- [Pluto GitHub](https://github.com/FairwindsOps/pluto)
- [Kubeval GitHub](https://github.com/instrumenta/kubeval)
- [Datree GitHub](https://github.com/datreeio/datree)
- [Kube-score GitHub](https://github.com/zegl/kube-score)
- [Kubescape GitHub](https://github.com/kubescape/kubescape)
- [Kube-bench GitHub](https://github.com/aquasecurity/kube-bench)
- [Homebrew K8s packages](https://formulae.brew.sh/formula?q=kube)
- [Krew plugins](https://krew.sigs.k8s.io/docs/user-guide/quickstart/)

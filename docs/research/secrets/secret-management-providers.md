# Провайдеры управления секретами: сравнительный обзор

Дата проверки: 2026-08-19.

## Короткий вывод

Для данного homelab (Docker Compose + Kubernetes, платформонезависимость) нет
единого «идеального» провайдера; реалистичное решение — комбинация из двух
уровней:

1. **Основной self-hosted vault: Infisical** (MIT, веб-UI, CLI, SDK, RBAC,
   версионирование, Docker Compose + Helm). Закрывает ~80% задач: хранение
   статических секретов, environment injection, доступ по HTTP API, аудит. Одно
   ограничение: образ тяжёлый (~670 МБ сжатый), PostgreSQL + Redis — 4 ГБ RAM
   минимум. Если ресурсы критичны, а нужен только CLI/API и GitOps — **SOPS +
   age** проще и легче на порядок.

2. **Дополнение для Kubernetes: External Secrets Operator (ESO)** — лёгкий
   operator (~100 МБ RAM суммарно), который тянет секреты из Infisical (или
   Vault, или cloud KMS) и синхронизирует их в нативные K8s Secrets. Для
   Docker Compose не нужен — достаточно CLI/webhook Infisical.

**Если нужен именно «gold standard» vault с dynamic secrets, PKI, transit
encryption** — это HashiCorp Vault, но он требует значительного изучения и
управления (unseal, HA, storage backend). Для homelab он избыточен, если задача
— просто хранить и раздавать API keys/пароли.

Практическое решение:

1. Начать с **SOPS + age** для GitOps-хранилища секретов (минимум компонентов,
   нет сервера, шифрование в git).
2. По мере роста (команды, больше сервисов, нужен UI/RBAC/audit) перейти на
   **Infisical** (self-hosted) + **ESO** для Kubernetes.
3. Vault изучить отдельным временным стендом; не ставить как основной пока нет
   конкретного сценария (dynamic secrets, PKI, transit).
4. Cloud-native решения (AWS/Azure/GCP) использовать только если homelab уже
   привязан к конкретному облаку.

## Сначала разложим термины

### Что такое секреты

**Секреты (secrets)** — любые данные, которые дают доступ к ресурсам: API ключи,
пароли баз данных, TLS-сертификаты, SSH-ключи, токены доступа, encryption keys.
Отличие от обычных конфигов: утечка секретов немедленно компрометирует систему.

### Статические vs динамические секреты

- **Статические (static)** — фиксированные значения, созданные вручную или
  генерируемые один раз: пароль PostgreSQL, API-ключ Stripe, TLS-сертификат.
  Хранятся как есть; ротация требует обновления во всех местах потребления.

- **Динамические (dynamic)** — генерируются on-demand для каждого потребителя с
  коротким TTL: временный пароль для MySQL с автоматическим отзывом через час,
  краткосрочные AWS credentials через STS. Только Vault и несколько
  cloud-провайдеров поддерживают это из коробки.

### Transit encryption (Encryption as a Service)

Режим, когда vault выполняет шифрование/дешифрование на своей стороне: приложение
отправляет открытый текст → vault шифрует → возвращает шифротекст. Приложение не
знает ключа шифрования. Это позволяет децентрализовать хранение данных (they stay
in your DB) при централизованном контроле ключей.

### PKI (Public Key Infrastructure)

Vault может выступать корневым или промежуточным CA и выдавать TLS-сертификаты
динамически для каждого сервиса. Это позволяет отказаться от статических
сертификатов Let's Encrypt для внутренних сервисов.

### RBAC / ABAC

- **RBAC (Role-Based Access Control)** — права назначаются по ролям (admin,
  developer, viewer). Большинство vault-решений поддерживают.
- **ABAC (Attribute-Based Access Control)** — права зависят от атрибутов
  (environment, team, service name). Сложнее в реализации, встречается в Vault и
  enterprise-решениях.

### Lease и TTL

Каждый секрет в vault имеет thời hạn жизни (lease/TTL). По истечении срока
секрет автоматически отзывается (revoked). Для динамических секретов это
означает автоматическую ротацию; для статических — напоминание об обновлении.

### Seal/Unseal (Vault-специфика)

После перезапуска Vault находится в «sealed» состоянии — данные зашифрованы и
недоступны. Для разблокировки нужно предоставить часть unseal-ключей (Shamir's
Secret Sharing) или использовать auto-unseal с KMS. Это мера безопасности, но
добавляет operational overhead.

---

## Сравнительная таблица: возможности

> Порядок колонок: сначала Open Source решения, затем Closed / SaaS / Paid.

| Критерий | SOPS + age | Sealed Secrets | ESO | CSI Secrets Store | Infisical CE | OpenBao | Vault (BSL) | Conjur OSS | Bitwarden SM | 1Password | Doppler | AWS SM | Azure KV | GCP SM |
| --- |:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Тип** | File encryptor | K8s encryptor | K8s operator | K8s CSI driver | Secrets platform | Full vault | Full vault | Full vault | Password mgr + SM | Password mgr + SM | Secrets platform | Cloud service | Cloud service | Cloud service |
| **Лицензия** | MPL-2.0 | Apache 2.0 | Apache 2.0 | Apache 2.0 | MIT (CE) | MPL-2.0 | BSL 1.1 ¹ | Apache 2.0 (OSS) | GPL-3.0 (сервер) | Проприетарная | Проприетарная | ❌ | ❌ | ❌ |
| **Self-hosted** | ✅ (нет сервера) | ⚠️ Только K8s | ⚠️ Только K8s | ⚠️ Только K8s | ✅ | ✅ | ✅ | ✅ (OSS + Enterprise) | ✅ (Enterprise) | ⚠️ (Connect) | ⚠️ On-prem (Enterprise) | ❌ | ❌ | ❌ |
| **Веб-UI** | ❌ | ❌ | ❌ (через backend) | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ (AWS Console) | ✅ (Azure Portal) | ✅ (GCP Console) |
| **CLI** | `sops` | `kubeseal` | `kubectl` | `kubectl` | `infisical` | `bao` | `vault` | `conjur` | `bws` | `op` | `doppler` | `aws` | `az` | `gcloud` |
| **Native environments** | ❌ (через git branches/paths) | ❌ | ❌ | ❌ | ✅ (из коробки, UI) | ⚠️ Через namespaces/policies | ⚠️ Через namespaces (Enterprise) / paths (OSS) | ⚠️ Через policies | ⚠️ Projects | ⚠️ Vaults | ✅ (из коробки, UI) | ⚠️ Через path hierarchy | ⚠️ Через resource groups | ⚠️ Через projects |
| **Dynamic secrets** | ❌ | ❌ | ⚠️ Через backend | ⚠️ Через provider | ❌ | ✅ (планируется) | ✅ (DB, AWS, PKI...) | ⚠️ Ограниченно (.rotation) | ❌ | ❌ | ⚠️ Ограниченно | ⚠️ Ограниченно (rotation) | ⚠️ Ограниченно (rotation) | ⚠️ Ограниченно (rotation) |
| **Transit EaaS** | ❌ | ❌ | ⚠️ Через backend | ⚠️ Через provider | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **PKI** | ❌ | ❌ | ⚠️ Через Vault | ⚠️ Через provider | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **RBAC** | ❌ (file-level) | ❌ (scope) | ⚠️ Через backend | ❌ | ✅ (CE) | ✅ | ✅ (policies) | ✅ | ✅ | ✅ (vaults) | ✅ | ⚠️ IAM | ⚠️ IAM + RBAC | ⚠️ IAM |
| **Версионирование** | ❌ (через git) | ❌ | ⚠️ Через backend | ⚠️ Через provider | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Ротация** | ❌ Manual | ❌ (30 дней ключ) | ✅ (interval) | ✅ (rotation) | ❌ (manual) | ✅ (планируется) | ✅ Авто (dynamic) | ✅ | ✅ Авто | ❌ | ⚠️ Ограниченно | ✅ Авто | ✅ Авто | ✅ Авто |
| **Аудит** | ⚠️ Git history | ❌ | ❌ | ❌ | ⚠️ Enterprise | ✅ | ✅ (audit log) | ✅ | ✅ (Enterprise) | ⚠️ Ограниченно | ✅ | ✅ CloudTrail | ✅ Azure Audit | ✅ Cloud Audit Logs |
| **OIDC (SSO вход)** | ❌ | ❌ | ⚠️ Через backend | ⚠️ Через provider | ⚠️ Enterprise | ✅ | ✅ Вход + провайдер | ⚠️ Enterprise | ❌ | ❌ | ⚠️ Enterprise | ✅ (AWS IAM) | ✅ (Azure AD) | ✅ (Google) |
| **LDAP** | ❌ | ❌ | ⚠️ Через backend | ❌ | ⚠️ Enterprise | ✅ | ✅ | ✅ | ❌ | ❌ | ⚠️ Enterprise | ❌ | ❌ | ❌ |
| **Terraform / IaC provider** | ⚠️ Непрямо (file resource) | ❌ | ✅ (helm_provider) | ✅ (helm_provider) | ✅ (community) | ✅ (планируется) | ✅ (официальный) | ✅ (community) | ✅ (официальный) | ❌ | ✅ (официальный) | ✅ (официальный) | ✅ (официальный) | ✅ (официальный) |
| **Webhook / event-driven** | ❌ | ❌ | ⚠️ Через backend | ❌ | ✅ (webhooks при изменении) | ✅ | ✅ (via leases/TTL) | ✅ | ✅ | ❌ | ✅ (webhooks) | ✅ (EventBridge) | ✅ (Event Grid) | ✅ (Pub/Sub) |
| **Disaster recovery** | ✅ Git history (полный бэкап) | ⚠️ keypair backup | ❌ (нет storage) | ❌ (нет storage) | ⚠️ pg_dump | ✅ Raft snapshots | ✅ Raft snapshots | ✅ pg_dump | ⚠️ Бэкап БД | ⚠️ 1Password cloud | ⚠️ SaaS backup | ✅ Cloud-native | ✅ Cloud-native | ✅ Cloud-native |
| **Secret payload size** | Без ограничений (файлы) | 1 MiB (K8s Secret limit) | Зависит от backend | Зависит от provider | 50 KiB | Зависит от engine | 1 MiB (KV v2) | Зависит от engine | 10 KiB | 64 KiB | 64 KiB | 64 KiB | 250 KiB | 64 KiB |
| **Multi-tenancy (CI/CD)** | ⚠️ Git access control | ❌ | ⚠️ Через backend | ❌ | ✅ Machine Identity + scopes | ✅ Namespaces + policies | ✅ Namespaces + policies | ✅ | ✅ Machine accounts | ⚠️ Service Accounts | ✅ Tokens + env scopes | ✅ IAM policies | ✅ RBAC | ✅ IAM policies |
| **Стоимость владения** | ~$0 (2 бинарника) | ~$0 (1 контейнер) | ~$0 (RAM) | ~$0 (RAM/нода) | ~$0 (CE) + 4 ГБ RAM | ~$0 (CE) + RAM | ~$0 + RAM | ~$0 + 4 ГБ RAM | ~$0 (CE) + RAM | $7.99/user/mo | Free–$12K/y | $0.40/secret/mo | $0.03/10K ops | $0.06/10K ops |
| **S/MIME (email)** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ (через PKI) | ⚠️ Через PKI (S/MIME) | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Homelab оценка** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ | ⭐⭐ | ⭐⭐⭐ | ⭐⭐ | ⭐ ³ | ⭐ ³ | ⭐ ³ |
| **Работа оценка** | ⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |

> ¹ HashiCorp перешёл с MPL-2.0 на BSL 1.1 (Business Source License) в августе
> 2023. BSL разрешает бесплатное использование, но запрещает конкурентные
> hosted-сервисы. Для self-hosting в homelab это некритично. OpenBao — форк
> под MPL-2.0.
>
> ² Размер образа Bitwarden зависит от количества компонентов; Lite-образ
> (`ghcr.io/bitwarden/lite`) легче, но требования к MSSQL сохраняются.
>
> ³ Cloud-провайдеры оценены низко для homelab, потому что не соответствуют
> требованию платформонезависимости и привязывают к облаку.

## Сравнительная таблица: методы аутентификации и SSO

| Метод аутентификации | SOPS + age | Sealed Secrets | ESO | CSI Secrets Store | Infisical CE | OpenBao | Vault (BSL) | Conjur OSS | Bitwarden SM | 1Password | Doppler | AWS SM | Azure KV | GCP SM |
| --- |:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **OIDC** | ❌ | ❌ | ⚠️ Через backend | ⚠️ Через provider | ⚠️ Enterprise | ✅ | ✅ Вход + провайдер | ⚠️ Enterprise | ❌ | ❌ | ⚠️ Enterprise | ✅ (IAM) | ✅ (Azure AD) | ✅ (Google) |
| **LDAP** | ❌ | ❌ | ⚠️ Через backend | ❌ | ⚠️ Enterprise | ✅ | ✅ | ✅ | ❌ | ❌ | ⚠️ Enterprise | ❌ | ❌ | ❌ |
| **SAML** | ❌ | ❌ | ❌ | ❌ | ⚠️ Enterprise | ✅ | ✅ | ✅ | ❌ | ❌ | ⚠️ Enterprise | ❌ | ❌ | ❌ |
| **Token/AppRole** | ❌ | ❌ | ⚠️ Через backend | ⚠️ Через provider | ✅ (API keys) | ✅ | ✅ | ✅ | ✅ (Access tokens) | ✅ (Service Accounts) | ✅ (Service tokens) | ⚠️ IAM keys | ⚠️ Service Principal | ⚠️ SA key |
| **Kubernetes SA** | ❌ | ⚠️ (keypair) | ⚠️ Через backend | ⚠️ Через provider | ✅ (Operator) | ✅ | ✅ | ✅ | ✅ (Operator) | ✅ (Injector) | ✅ (Operator) | ❌ | ❌ | ❌ |
| **TLS Certificate** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ⚠️ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **AWS IAM** | ❌ | ❌ | ⚠️ Через backend | ⚠️ Через provider | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| **AppRole (machine)** | ❌ | ❌ | ⚠️ | ⚠️ | ⚠️ | ✅ | ✅ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |

### Поддержка OIDC-провайдеров (вход в vault)

| OIDC-провайдер | OpenBao | Vault (BSL) | Conjur OSS | Infisical | Doppler |
| --- |:---:|:---:|:---:|:---:|:---:|
| **ZITADEL** | ✅ Через generic OIDC | ✅ Через generic OIDC | ⚠️ Через SAML | ✅ Через General OIDC | ⚠️ Через SAML |
| **Keycloak** | ✅ Нативный шаблон | ✅ Нативный шаблон | ⚠️ Enterprise | ⚠️ | ⚠️ Enterprise |
| **Authentik** | ✅ Через generic OIDC | ✅ Через generic OIDC | ⚠️ | ⚠️ | ⚠️ |
| **Authelia** | ✅ Через generic OIDC | ✅ Через generic OIDC | ⚠️ | ⚠️ | ⚠️ |
| **Google Workspace** | ✅ Нативный шаблон | ✅ Нативный шаблон | ❌ | ❌ | ⚠️ |
| **Azure AD** | ✅ Нативный шаблон | ✅ Нативный шаблон | ❌ | ❌ | ❌ |
| **GitHub** | ❌ (OAuth only) | ❌ (OAuth only) | ❌ | ✅ | ✅ |

---

## Подробные описания

> Порядок: сначала Open Source решения, затем Closed / SaaS / Paid.

### 1. SOPS (Mozilla) + Age

**Что это:** File-level encryption tool для YAML/JSON/ENV файлов. SOPS шифрует
только значения, сохраняя структуру файла читаемой. Age — современный замена
PGP для асимметричного шифрования.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|:---------:|------------|
| **OIDC** | ❌ | CLI tool, нет аутентификации |
| **LDAP** | ❌ | CLI tool, нет аутентификации |
| **SAML** | ❌ | CLI tool, нет аутентификации |
| **Kubernetes** | ⚠️ | Нативная поддержка в Flux CD |
| **AppRole** | ❌ | Контроль через git access |
| **TLS Certificate** | ❌ | Нет PKI engine |

**Возможности:**
- Шифрование YAML, JSON, ENV, INI, binary файлов
- Мульти-recipients: каждый holder может расшифровать независимо
- `encrypted_regex` для частичного шифрования
- Интеграция с Flux CD (нативная), ArgoCD (через плагины)
- Нет серверного компонента — чистый CLI

**OIDC-интеграция:**
- SOPS + age — это CLI tool без серверного компонента; OIDC не
  применяется. Аутентификация осуществляется через age-ключи (asymmetric)
  и git access control.

**Docker интеграция:**
- Нет серверного компонента
- CLI: `sops --encrypt --age <pubkey> secrets.yaml`
- CI/CD: `SOPS_AGE_KEY` environment variable

**Kubernetes интеграция:**
- **Flux CD**: нативная поддержка SOPS через `decryption` в Kustomization
- **ArgoCD**: через ksops, helm-secrets плагины
- **Ручной**: `sops --decrypt | kubectl apply -f -`
- Нет operator/CRD — это файловый утилита

**Ресурсы:**
- SOPS binary: ~5 МБ (Go, statically linked)
- Age binary: ~3 МБ
- RAM: минимально (CLI tool)
- Нет сервера, нет БД, нет зависимостей
  ([source](https://www.systemshardening.com/articles/cicd/sops-age-gitops-secrets/))

**Плюсы для homelab:**
- **Минимум компонентов**: два бинарника, ноль серверов
- Secrets хранятся в git (GitOps-native)
- Flux CD имеет встроенную поддержку
- Нет network dependencies для дешифрования
- Age ключи проще чем PGP
- Идеально для air-gapped сред
- MPL-2.0 лицензия

**Минусы для homelab:**
- Нет UI
- Нет RBAC (контроль через git access)
- Нет audit logging (только git history)
- Нет dynamic secrets
- Нет automatic rotation
- Key rotation требует re-encryption всех файлов
- Нужна дисциплина: если plaintext секрет попадёт в git до шифрования — он
  навсегда в истории

**Источники:**
- [GitHub SOPS](https://github.com/getsops/sops)
- [Flux SOPS guide](https://fluxcd.io/flux/guides/mozilla-sops/)
- [Age integration](https://getsops.io/docs/usage/identities/age/)
- [SOPS + age guide](https://www.systemshardening.com/articles/cicd/sops-age-gitops-secrets/)

### 2. Sealed Secrets (Bitnami)

**Что это:** Kubernetes-native решение для шифрования Secret YAML файлов в git.
Controller в кластере расшифровывает SealedSecret → нативный K8s Secret.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|:---------:|------------|
| **OIDC** | ❌ | Controller-level аутентификация через keypair |
| **LDAP** | ❌ | Нет поддержки |
| **SAML** | ❌ | Нет поддержки |
| **Kubernetes** | ✅ | CRD SealedSecret, controller в кластере |
| **AppRole** | ❌ | Контроль через git access + namespace scope |
| **TLS Certificate** | ❌ | Нет PKI engine |

**Возможности:**
- Шифрование K8s Secret файлов для safe хранения в git
- RSA encryption (cluster keypair)
- Scope: cluster-wide или namespace-scoped
- Key renewal (по умолчанию 30 дней)
- `kubeseal` CLI для шифрования

**OIDC-интеграция:**
- Sealed Secrets не поддерживает OIDC. Аутентификация идёт через
  RSA keypair: controller генерирует ключ, `kubeseal` шифрует с помощью
  публичного ключа.

**Docker интеграция:**
- Не предназначен для Docker Compose — только Kubernetes
- Controller образ: ~29 МБ (amd64)
  ([Docker Hub](https://hub.docker.com/r/bitnami/sealed-secrets-controller))

**Kubernetes интеграция:**
- CRD: `SealedSecret`
- Controller deployment в `kube-system`
- Helm chart: `sealed-secrets/sealed-secrets`
- Compat с ArgoCD, Flux, и другими GitOps-инструментами

**Ресурсы:**
- Controller образ: 28.6 МБ (amd64, сжатый)
  ([Docker Hub](https://hub.docker.com/r/bitnami/sealed-secrets-controller))
- RAM: 32–64 МБ (один Go-бинарь, минимальные требования)
- Disk: минимум
- Последний релиз: v0.38.4 (3 июля 2026)
  ([GitHub](https://github.com/bitnami/sealed-secrets))

**Плюсы для homelab:**
- Минимальный footprint: один маленький контейнер
- Простой workflow: kubeseal → git commit → controller decrypt
- Apache 2.0
- Нет внешних зависимостей (всё в кластере)
- Хорошая интеграция с GitOps

**Минусы для homelab:**
- Только Kubernetes (не для Docker Compose)
- Нет UI, нет RBAC, нет audit
- Нет dynamic secrets
- Key recovery: если потерять master keypair — все SealedSecrets недоступны
- Single-cluster scope (net cross-cluster)
- Plaintext секреты в etcd после расшифровки controller-ом
- Нет rotation секретов (только key renewal)

**Источники:**
- [GitHub](https://github.com/bitnami/sealed-secrets)
- [Docker Hub](https://hub.docker.com/r/bitnami/sealed-secrets-controller)
- [ArtifactHub](https://artifacthub.io/packages/helm/sealed-secrets/sealed-secrets)

### 3. External Secrets Operator (ESO)

**Что это:** Kubernetes operator, который тянет секреты из внешних store
(Vault, AWS/Azure/GCP, Infisical, 1Password и др.) и создаёт нативные K8s
Secrets.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|:---------:|------------|
| **OIDC** | ⚠️ | Через backend store (Vault/Infisical). Сам ESO не аутентифицируется через OIDC |
| **LDAP** | ⚠️ | Через backend store |
| **SAML** | ❌ | Не применяется напрямую |
| **Kubernetes** | ✅ | CRD: ExternalSecret, SecretStore, ClusterSecretStore |
| **AppRole** | ⚠️ | Через backend store tokens |
| **TLS Certificate** | ⚠️ | Через backend store (Vault PKI) |

**Возможности:**
- 30+ providers (AWS, Azure, GCP, Vault, Infisical, 1Password, Doppler, etc.)
- CRD: `ExternalSecret`, `SecretStore`, `ClusterSecretStore`
- Автоматическая синхронизация с настраиваемым refresh interval
- Push secrets (из кластера наружу)
- Templating для генерации секретов

**OIDC-интеграция:**
- ESO сам по себе не аутентифицируется через OIDC; он использует
  токены/секреты для подключения к backend store. OIDC аутентификация
  происходит на уровне самого backend store (Vault, Infisical и т.д.).

**Docker интеграция:**
- Не предназначен для Docker Compose — только Kubernetes

**Kubernetes интеграция:**
- CRD: `ExternalSecret`, `SecretStore`, `ClusterSecretStore`
- Helm chart
- 3 пода: operator + webhook + cert-controller
- Нативные K8s Secrets как target

**Ресурсы:**
- Operator: ~2 CPU / ~29 МБ RAM (idle)
  ([GitHub issue](https://github.com/external-secrets/external-secrets/issues/5407))
- Webhook: ~24 МБ RAM
- Cert controller: ~43 МБ RAM
- Итого: ~100 МБ RAM для всех компонентов
- Образ: `ghcr.io/external-secrets/external-secrets` — ~100 МБ

**Плюсы для homelab:**
- Универсальный «мост» между любым vault и K8s
- Если vault уже есть (Infisical, Vault) — ESO просто доставляет
- Apache 2.0
- Автоматическая синхронизация
- Нет own storage — всё во внешнем vault

**Минусы для homelab:**
- Только Kubernetes
- Требует внешний store (не vault сам по себе)
- 3 пода в кластере (хотя лёгкие)

**Источники:**
- [GitHub](https://github.com/external-secrets/external-secrets)
- [Документация](https://external-secrets.io/)
- [Helm chart](https://github.com/external-secrets/external-secrets/tree/main/deploy/charts/external-secrets)

### 4. CSI Secrets Store Driver

**Что это:** Kubernetes CSI driver, который монтирует секреты из внешних
хранилищ как файлы в поды. Работает на уровне storage, а не API.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|:---------:|------------|
| **OIDC** | ⚠️ | Через provider (Vault, cloud). Сам CSI driver не аутентифицируется |
| **LDAP** | ⚠️ | Через provider |
| **SAML** | ❌ | Не применяется |
| **Kubernetes** | ✅ | SecretProviderClass CRD, DaemonSet |
| **AppRole** | ⚠️ | Через provider tokens |
| **TLS Certificate** | ⚠️ | Через provider (Vault PKI) |

**Возможности:**
- Монтирование секретов как файлов (CSI inline volume)
- SecretProviderClass CRD для конфигурации
- Auto-rotation (alpha в v1.6.0 через RequiresRepublish)
- Sync с K8s Secrets (alpha)
- Множество providers: AWS, Azure, GCP, Vault, Infisical, 1Password

**OIDC-интеграция:**
- CSI Secrets Store Driver работает через providers; OIDC аутентификация
  происходит на уровне провайдера (Vault, cloud IAM и т.д.). Сам driver
  не аутентифицируется напрямую.

**Docker интеграция:**
- Не предназначен для Docker Compose

**Kubernetes интеграция:**
- CRD: `SecretProviderClass`
- DaemonSet на каждой ноде
- Helm chart: `secrets-store-csi-driver/secrets-store-csi-driver`
- Последний релиз: v1.6.0 (29 апреля 2026)
  ([GitHub](https://github.com/kubernetes-sigs/secrets-store-csi-driver/releases/tag/v1.6.0))

**Ресурсы:**
- DaemonSet: ~80 МБ RAM на ноду
- Образ: ~50 МБ (compressed)
- Minikube/kind: работает

**Плюсы для homelab:**
- Secrets как файлы (некоторые приложения требуют именно файлы)
- Нативный Kubernetes подход (SIG Auth project)
- Apache 2.0
- Множество providers

**Минусы для homelab:**
- Только Kubernetes
- Только для secrets-as-files (не env vars напрямую)
- Auto-rotation всё ещё alpha
- Сложнее чем ESO для простых случаев
- RequiresRepublish: каждая нода опрашивает provider

**Источники:**
- [GitHub](https://github.com/kubernetes-sigs/secrets-store-csi-driver)
- [Документация](https://secrets-store-csi-driver.sigs.k8s.io/)
- [v1.6.0 release](https://github.com/kubernetes-sigs/secrets-store-csi-driver/releases/tag/v1.6.0)

### 5. Infisical

**Что это:** Современная open-source платформа управления секретами с веб-UI,
CLI, SDK и интеграциями. Заменяет Doppler и упрощённые vault-решения для
команд.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|:---------:|------------|
| **OIDC** | ⚠️ | General OIDC (любой совместимый провайдер). Paid feature: Pro Tier / Enterprise для self-hosted. Discovery URL + Callback URL + JWT Algo RS256. Нет шаблона для ZITADEL, но generic flow работает |
| **LDAP** | ⚠️ | Только в Enterprise-редакции |
| **SAML** | ⚠️ | Только в Enterprise-редакции |
| **Kubernetes** | ✅ | Infisical Secrets Operator + ESO provider |
| **AppRole** | ✅ | Machine Identity tokens + API keys |
| **TLS Certificate** | ❌ | Нет PKI engine |

**Возможности:**
- Хранение секретов с версионированием
- Environment-based organization (dev/staging/prod) — **нативные environments**
- RBAC (в Community Edition)
- Secret approval workflows (Enterprise)
- SAML SSO (Enterprise)
- Audit log streaming (Enterprise)
- CLI для локальной разработки (`infisical run`)
- Native интеграции: Docker, Kubernetes, CI/CD, Terraform

**Нативные environments:**
Infisical имеет environments как первый класс — каждая environment (dev, staging,
prod) изолирована в UI и через API. Один проект → несколько environments →
разные секреты для каждого окружения. Это главное отличие от Vault, где
environments моделируются через paths/policies.

```bash
# Environments в Infisical:
infisical secrets --env dev     # → секреты для dev
infisical secrets --env prod    # → секреты для prod
```

**OIDC-интеграция:**
- **General OIDC:** Infisical поддерживает любой OIDC-совместимый провайдер
  через опцию «General OIDC» при настройке SSO. Нужны: Discovery URL
  (`https://<zitadel-domain>/oauth/v2/.well-known/openid-configuration`),
  Callback URL (автоматическая), JWT Algorithm: RS256
- **ZITADEL:** Нет специального шаблона, но generic OIDC flow работает
  без модификаций. Создать OIDC-приложение в ZITADEL → скопировать
  Client ID / Client Secret → ввести в Infisical при настройке SSO
- **Ограничение:** OIDC — платная функция (Pro Tier для SaaS,
  Enterprise license для self-hosted)
- **Нет PKI:** Infisical не выдаёт сертификаты и не может заменить
  vault для S/MIME или TLS-сертификатов

**Docker интеграция:**
- Docker Compose: PostgreSQL + Redis + Infisical backend
- Инъекция через `infisical run --env .env -- docker compose up`
- Нативная поддержка Docker Compose

**Kubernetes интеграция:**
- Официальный Helm chart
- Infisical Secrets Operator (CRD: InfisicalSecret)
- External Secrets Operator с Infisical provider (community)

**Ресурсы:**
- Docker Hub: `infisical/infisical` — ~672 МБ (amd64, сжатый)
  ([источник](https://hub.docker.com/r/infisical/infisical/tags))
- RAM: 4 ГБ минимум (все компоненты вместе), 8 ГБ рекомендовано
  ([источник](https://infisical.com/docs/self-hosting/configuration/requirements))
- CPU: 2 cores минимум, 4 рекомендовано
- PostgreSQL + Redis обязательны
- Disk: 20 ГБ минимум
- Подробнее: ~300 МБ idle, ~500 МБ под нагрузкой (только backend)
  ([selfhosting.sh](https://selfhosting.sh/apps/infisical/))

**Плюсы для homelab:**
- MIT лицензия (Community Edition) — полностью free для self-host
- Современный и приятный UI
- CLI очень удобен для локальной разработки
- Версионирование и **environments из коробки**
- GitHub integration для секретов
- Растущее community

**Минусы для homelab:**
- Тяжёлый образ (~672 МБ) — Node.js стек
- Требует PostgreSQL и Redis — 3 дополнительных контейнера
- 4 ГБ RAM минимум (много для homelab)
- Enterprise-функции (audit, SAML, approval, OIDC) за плату
- Нет dynamic secrets
- Нет PKI / transit encryption

**Источники:**
- [GitHub](https://github.com/Infisical/infisical)
- [Документация](https://infisical.com/docs)
- [Hardware requirements](https://infisical.com/docs/self-hosting/configuration/requirements)
- [Docker Compose](https://infisical.com/docs/self-hosting/deployment-options/docker-compose)
- [SSO / OIDC](https://infisical.com/docs/documentation/platform/sso)

### 6. OpenBao

**Что это:** Open-source форк HashiCorp Vault под MPL-2.0 лицензией. Создан
после перехода HashiCorp на BSL 1.1. Сохраняет все возможности Vault без
лицензионных ограничений.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|:---------:|------------|
| **OIDC** | ✅ | Аналогично Vault: OIDC-потребитель и провайдер. Generic OIDC для ZITADEL, Keycloak и др. |
| **LDAP** | ✅ | Нативный auth method + LDAP secrets engine |
| **SAML** | ✅ | Через OIDC-посредник или нативный плагин |
| **Kubernetes** | ✅ | ServiceAccount token review, natивный auth method |
| **AppRole** | ✅ | Machine-to-machine auth с role_id + secret_id |
| **TLS Certificate** | ✅ | mTLS auth для сервисов |

**Возможности:**
- Все возможности Vault: KV v1/v2, database, AWS, Azure, GCP, PKI, transit,
  SSH, RabbitMQ и др.
- Dynamic secrets с автоматическим отзывом
- Transit encryption (EaaS)
- Audit logging
- Seal/unseal: Shamir's Secret Sharing или auto-unseal через KMS
- Raft integrated storage
- OIDC provider

**Environments в OpenBao:**
Аналогично Vault — через namespaces (в community-ветке) или через отдельные
mount paths:

```bash
# Разные paths для окружений
bao secrets enable -path=secret-dev kv-v2
bao secrets enable -path=secret-prod kv-v2

# Policies для контроля доступа
path "secret-dev/*" { capabilities = ["read", "list"] }
path "secret-prod/*" { capabilities = ["deny"] }
```

**OIDC-интеграция:**
- Аналогична Vault: `bao auth enable oidc` + настройка `oidc_discovery_url`,
  `oidc_client_id`, `oidc_client_secret`
- Generic OIDC для ZITADEL, Keycloak, Authentik и др.
- OIDC provider: OpenBao может выступать как IdP для других сервисов

**Docker интеграция:**
- Образ: `openbao/openbao` — ~180 МБ (amd64, сжатый, ожидаемо)
- Требует `--cap-add=IPC_LOCK`
- Dev-режим: `bao server -dev`
- Prod-режим: Raft storage + TLS + unseal workflow

**Kubernetes интеграция:**
- Helm chart (community, не официальный от HashiCorp)
- Injector sidecar
- CSI driver (planned)

**Ресурсы:**
- RAM: 512 МБ idle, 1–2 ГБ под нагрузкой (аналогично Vault)
- CPU: минимальный
- Production: аналогичные требования Vault (3 ноды для HA)

**Плюсы для homelab:**
- MPL-2.0 лицензия (полностью open source, без ограничений BSL)
- Все возможности Vault без ограничений
- Нет привязки к HashiCorp ecosystem
- Активное community, растущая экосистема
- Возможность миграции с Vault (совместимые API)

**Минусы для homelab:**
- Относительно молодой проект (форк с 2024)
- Меньше документации и community, чем у Vault
- Некоторые интеграции могут быть не-tested
- Helm chart не от HashiCorp (community-maintained)
- Production-ready развёртывание требует HA кластер (3 ноды)

**Источники:**
- [GitHub](https://github.com/openbao/openbao)
- [Документация](https://openbao.org/docs/)
- [Docker Hub](https://hub.docker.com/r/openbao/openbao)

### 7. HashiCorp Vault

**Что это:** Полноценный vault с dynamic secrets, transit encryption, PKI,
leases, audit logging и сложной политикой доступа. «Золотой стандарт» для
enterprise secret management.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|:---------:|------------|
| **OIDC** | ✅ | Одновременно OIDC-потребитель (вход через внешний IdP) и OIDC-провайдер (Vault выдаёт JWT-токены другим сервисам). Конфиг: `vault auth enable oidc` + `oidc_discovery_url`. Для ZITADEL: generic OIDC + Action для flatten role claims |
| **LDAP** | ✅ | Нативный auth method + LDAP secrets engine для ротации bind-паролей |
| **SAML** | ✅ | Через OIDC-посредник или нативный плагин |
| **Kubernetes** | ✅ | ServiceAccount token review, natивный auth method |
| **AppRole** | ✅ | Machine-to-machine auth с role_id + secret_id |
| **TLS Certificate** | ✅ | mTLS auth для сервисов |

**Возможности:**
- Secret engines: KV v1/v2, database, AWS, Azure, GCP, PKI, transit, SSH, RabbitMQ
  и др.
- Dynamic secrets: генерация временных credentials для MySQL, PostgreSQL, AWS
  IAM и др. с автоматическим отзывом
- Transit encryption: EaaS без раскрытия ключей приложению
- Audit logging: детальные логи всех операций
- Seal/unseal: Shamir's Secret Sharing или auto-unseal через KMS
- Raft integrated storage: встроенный кластерный storage без Consul
- OIDC provider: Vault может выступать как IdP для других сервисов

**Environments в Vault:**
Vault не имеет нативных environments как первый класс (в отличие от Infisical).
environments моделируются следующими способами:

1. **Namespace isolation (Enterprise):** Полная изоляция через `namespace`:
   ```
   ns=dev → secret/data/app/db_password
   ns=prod → secret/data/app/db_password
   ```

2. **Разные mount paths (OSS):** Отдельные KV-движки для каждого окружения:
   ```bash
   vault secrets enable -path=secret-dev kv-v2
   vault secrets enable -path=secret-prod kv-v2
   ```

3. **Policies по paths:** Контроль доступа через policies:
   ```hcl
   path "secret-dev/*" { capabilities = ["read", "list"] }
   path "secret-prod/*" { capabilities = ["deny"] }
   ```

4. **Разные auth roles:** Dev и prod роли с разными TTL и policies:
   ```bash
   vault write auth/approle/role/dev token_policies="app-dev" token_ttl=4h
   vault write auth/approle/role/prod token_policies="app-prod" token_ttl=1h
   ```

5. **Разные Vault instances:** Два отдельных сервера — максимальная изоляция.

**OIDC-интеграция:**
- **Вход (consumer):** `vault auth enable oidc` → настройка `oidc_discovery_url`,
  `oidc_client_id`, `oidc_client_secret`. Поддерживает generic OIDC для любого
  совместимого провайдера (ZITADEL, Keycloak, Authentik и др.)
- **Выход (provider):** Vault может быть OIDC-провайдером — другие сервисы
  аутентифицируются через Vault JWT. Конфигурируется через `oidc/` auth mount
- **ZITADEL:** Использовать generic OIDC flow. ZITADEL может потребовать Action
  (запрос в ZITADEL UI) для flatten role claims в формат, понятный Vault.
  Указать `oidc_discovery_url = https://<zitadel-domain>/oauth/v2` и
  `oidc_client_id` / `oidc_client_secret` из ZITADEL приложения.
- **PKI для S/MIME:** Vault PKI engine может выдавать сертификаты с
  `email_protection_flag=true`, что позволяет использовать его как CA для
  S/MIME-сертификатов. Это уникальная возможность среди рассмотренных vault.

**Docker интеграция:**
- Образ: `hashicorp/vault:2.0` — ~183 МБ (amd64, сжатый)
- Требует `--cap-add=IPC_LOCK` для блокировки памяти
- Dev-режим: `vault server -dev` — один контейнер без persistent storage
- Prod-режим: Raft storage + TLS + unseal workflow

**Kubernetes интеграция:**
- Официальный Helm chart (`hashicorp/vault`)
- Injector sidecar для автоматической инъекции секретов в поды
- CSI driver (beta)
- Vault Agent sidecar

**Ресурсы:**
- Docker Hub: `hashicorp/vault:2.0.4` — 183.5 МБ (amd64)
  ([источник](https://hub.docker.com/r/hashicorp/vault/tags))
- RAM: 512 МБ idle, 1–2 ГБ под нагрузкой
  ([источник](https://selfhosting.sh/apps/vault/))
- CPU: минимальный, пик при хешировании паролей и PKI-генерации
- Production по HashiCorp: 2 CPU / 8–16 ГБ RAM / 100 ГБ SSD
  ([источник](https://developer.hashicorp.com/vault/docs/concepts/integrated-storage/migration-checklist))

**Плюсы для homelab:**
- Самый функциональный vault: dynamic secrets, transit, PKI, leases
- Нет внешних зависимостей (Raft storage встроен)
- Огромная экосистема интеграций
- Полезный для изучения enterprise-практик

**Минусы для homelab:**
- Кривая обучения: seal/unseal, policies, auth methods
- BSL 1.1 лицензия (не MPL как раньше)
- Production-ready развёртывание требует HA кластер (3 ноды)
- Избыточен если нужны только статические секреты

**Источники:**
- [Документация](https://developer.hashicorp.com/vault/docs)
- [Docker Hub](https://hub.docker.com/r/hashicorp/vault)
- [Docker deployment](https://developer.hashicorp.com/vault/docs/deploy/run-on-docker)
- [OIDC Auth Method](https://developer.hashicorp.com/vault/docs/auth/oidc)
- [Vault OIDC Provider](https://developer.hashicorp.com/vault/docs/secrets/identity/oidc-provider)

### 8. CyberArk Conjur

**Что это:** Enterprise-ориентированный vault для machine identity и управления
секретами. Open Source версия (Conjur OSS) доступна, но ключевые возможности — в
коммерческой редакции.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|:---------:|------------|
| **OIDC** | ⚠️ | Только в Enterprise версии |
| **LDAP** | ✅ | Нативная интеграция |
| **SAML** | ✅ | Нативная интеграция |
| **Kubernetes** | ✅ | Kubernetes authenticator |
| **AppRole** | ⚠️ | API key based machine auth |
| **TLS Certificate** | ⚠️ | Ограниченно |

**Возможности:**
- Secret storage с RBAC
- Dynamic secrets (ограниченно, в Enterprise)
- Rotation (в Enterprise)
- SSH key management
- API key management
- Audit logging (в Enterprise)

**OIDC-интеграция:**
- OIDC доступен только в Enterprise-редакции
- ZITADEL: прямая интеграция не документирована; возможна через SAML
  (ZITADEL поддерживает SAML 2.0)

**Docker интеграция:**
- Образ: `cyberark/conjur` — ~144 МБ (amd64, сжатый)
- PostgreSQL обязателен как backing store
- Quickstart через docker-compose (conjur-quickstart репозиторий)

**Kubernetes интеграция:**
- Helm chart для Followers (не Leader/Standby)
- Conjur provider для Secrets Store CSI Driver
- Kubernetes authenticator

**Ресурсы:**
- Docker Hub: `cyberark/conjur:latest` — 144.37 МБ (amd64)
  ([источник](https://hub.docker.com/r/cyberark/conjur/tags))
- RAM: 4 ГБ (development/POC), 16 ГБ (production)
  ([источник](https://docs.cyberark.com/secrets-manager-sh/13.4/en/content/deployment/platforms/dap-sysreqs-server.htm))
- Disk: 20 ГБ (development), 50 ГБ (production)
- Зависимость: PostgreSQL

**Плюсы для homelab:**
- Apache 2.0 лицензия (OSS версия)
- Хорошая интеграция с Kubernetes
- Небольшой образ

**Минусы для homelab:**
- Минимальные 4 ГБ RAM даже для POC
- PostgreSQL обязателен
- Ключевые функции (dynamic secrets, rotation, audit) только в Enterprise
- Документация ориентирована на enterprise-развёртывание
- Маленькое community по сравнению с Vault

**Источники:**
- [GitHub](https://github.com/cyberark/conjur)
- [Документация](https://docs.cyberark.com/conjur-open-source/Latest/en/Content/HomeTilesLPs/LP-Tile2.htm)
- [System requirements](https://docs.cyberark.com/secrets-manager-sh/13.4/en/content/deployment/platforms/dap-sysreqs-server.htm)

### 9. Bitwarden Secrets Manager

**Что это:** Расширение Bitwarden Password Manager для инфраструктурных секретов.
CLI-first подход с self-hosting для Enterprise.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|:---------:|------------|
| **OIDC** | ❌ | Нет поддержки OIDC для SM |
| **LDAP** | ❌ | Нет поддержки для SM |
| **SAML** | ❌ | Нет поддержки для SM |
| **Kubernetes** | ✅ | Bitwarden Secrets Manager Kubernetes Operator |
| **AppRole** | ✅ | Machine accounts + Access tokens |
| **TLS Certificate** | ❌ | Нет PKI engine |

**Возможности:**
- Хранение секретов с project-based organization
- Machine accounts для автоматизации
- Access tokens для CI/CD
- CLI (`bws`)
- SDK для популярных языков

**OIDC-интеграция:**
- Bitwarden Secrets Manager не поддерживает OIDC для аутентификации
- Использует собственную систему machine accounts + access tokens
- ZITADEL:OIDC → Bitwarden Password Manager (если используется) → SM
  недоступен напрямую через OIDC

**Docker интеграция:**
- Self-hosted: множество контейнеров + MSSQL
- Lite-образ: `ghcr.io/bitwarden/lite` (один контейнер)
- CLI в Docker: `ghcr.io/bitwarden/bws`

**Kubernetes интеграция:**
- Bitwarden Secrets Manager Kubernetes Operator (CRD: BitwardenSecret)
- Helm chart
- Синхронизация секретов в K8s Secrets

**Ресурсы:**
- Self-hosted: 2 ГБ RAM минимум, 4 ГБ рекомендовано
  ([Bitwarden docs](https://bitwarden.com/help/install-on-premise-manual/))
- MSSQL обязателен (или Express)
- Disk: 12 ГБ минимум, 25 ГБ рекомендовано

**Плюсы для homelab:**
- Если уже используется Bitwarden — единая экосистема
- GPL-3.0 (сервер)
- Хороший K8s operator

**Минусы для homelab:**
- Secrets Manager требует Enterprise подписку ($6/user/month минимум)
- MSSQL — тяжёлая зависимость для homelab
- Много контейнеров для развёртывания
- Ограниченные возможности по сравнению с dedicated vault-решениями

**Источники:**
- [Bitwarden Secrets Manager](https://bitwarden.com/products/secrets-manager)
- [K8s Operator](https://github.com/bitwarden/sm-kubernetes)
- [Self-hosting](https://bitwarden.com/help/self-host-bitwarden/)

### 10. 1Password CLI / Secrets Automation

**Что это:** Password manager с автоматизацией через CLI. Connect Server —
self-hosted прокси для инфраструктурных секретов. Service Accounts — managed
альтернатива без сервера.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|:---------:|------------|
| **OIDC** | ❌ | Использует собственную аутентификацию 1Password |
| **LDAP** | ❌ | Нет поддержки |
| **SAML** | ❌ | Нет поддержки |
| **Kubernetes** | ✅ | 1Password Kubernetes Injector + Operator |
| **AppRole** | ✅ | Service Accounts + Connect tokens |
| **TLS Certificate** | ❌ | Нет PKI engine |

**Возможности:**
- CLI (`op`) для доступа к секретам
- Connect Server: self-hosted REST API, кеширование данных
- Service Accounts: managed, rate-limited, без self-hosted сервера
- Environments для organization секретов по stages
- Secret references: `op://vault/item/field`

**OIDC-интеграция:**
- 1Password не поддерживает OIDC для аутентификации
- Использует собственную систему: master password + secret key + biometric
- Connect Server и Service Accounts работают через 1Password API
- ZITADEL:OIDC → 1Password недоступно напрямую

**Docker интеграция:**
- Connect Server: 2 контейнера (`connect-api` ~26 МБ + `connect-sync`)
- `op run` для инъекции secrets в Docker Compose
- SDK для чтения secrets внутри контейнера

**Kubernetes интеграция:**
- 1Password Kubernetes Injector (mutating webhook)
- 1Password Kubernetes Operator (CRD: OnePasswordItem)
- Helm chart для Connect + Operator
- Service Accounts для auth без Connect

**Ресурсы:**
- Connect API: ~26 МБ (amd64, сжатый)
  ([Docker Hub](https://hub.docker.com/r/1password/connect-api))
- Connect Sync: ~25 МБ (amd64, сжатый)
- RAM: 128 МБ лимит на каждый контейнер
  ([K8s deployment](https://github.com/1Password/connect/blob/main/examples/kubernetes/op-connect-deployment.yaml))
- Итого: ~256 МБ RAM для 2 контейнеров
- Требуется 1Password подписка (Business $7.99/user/month)

**Плюсы для homelab:**
- Отличный CLI и developer experience
- Если уже используется 1Password — единая экосистема
- Лёгкие контейнеры
- K8s operator и injector

**Минусы для homelab:**
- Требуется 1Password подписка ($7.99/user/month минимум)
- Connect Server кеширует данные, но всё равно обращается к 1Password API
- Нет dynamic secrets
- Нет transit encryption
- Привязка к 1Password экосистеме

**Источники:**
- [1Password Secrets Automation](https://www.1password.dev/secrets-automation)
- [K8s Integrations](https://www.1password.dev/k8s/integrations)
- [Connect Get Started](https://www.1password.dev/connect/get-started)

### 11. Doppler

**Что это:** SaaS-платформа управления секретами с опцией on-prem для
enterprise. Ориентирована на developer experience и интеграции.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|:---------:|------------|
| **OIDC** | ⚠️ | Только в Enterprise-версии. Поддерживает generic OIDC |
| **LDAP** | ⚠️ | Только в Enterprise-версии |
| **SAML** | ⚠️ | Только в Enterprise-версии |
| **Kubernetes** | ✅ | Doppler Kubernetes Operator + ESO provider |
| **AppRole** | ✅ | Service tokens для CI/CD |
| **TLS Certificate** | ❌ | Нет PKI engine |

**Возможности:**
- Secret versioning и rollbacks
- Secret referencing (ссылки между секретами)
- Webhooks для обновлений
- Dynamic secrets (Enterprise)
- SAML SSO (Enterprise)
- Activity log с rollback
- Environment-level access controls

**OIDC-интеграция:**
- OIDC доступен только в Enterprise ($12K/year за on-prem)
- ZITADEL:OIDC → Doppler Enterprise → Secrets Access
- Бесплатная версия не поддерживает OIDC

**Docker интеграция:**
- CLI в Docker image: `doppler run -- docker compose up`
- Инъекция env vars через CLI
- Нет self-hosted Docker Compose развёртывания (SaaS-first)

**Kubernetes интеграция:**
- Doppler Kubernetes Operator (CRD: DopplerSecret)
- External Secrets Operator с Doppler provider
- Автоматический redeploy при обновлении секретов

**Ресурсы:**
- SaaS: нет self-hosted ресурсов
- On-prem (Enterprise): Docker-based, требования не публичны
- Стоимость: Free (3 пользователя), Team $21/user/month, Enterprise $12,000/year
  ([pricing](https://www.doppler.com/pricing))

**Плюсы для homelab:**
- Отличный developer experience
- MCP-сервер для AI-агентов
- Без per-agent pricing

**Минусы для homelab:**
- Self-hosted (on-prem) только в Enterprise ($12K/year)
- Основной product — SaaS, привязка к Doppler infrastructure
- Нет free self-hosted опции
- Относительно новая on-prem опция (2026)

**Источники:**
- [Doppler](https://www.doppler.com/)
- [Docker integration](https://www.doppler.com/integrations/docker)
- [Kubernetes integration](https://www.doppler.com/integrations/kubernetes)
- [On-prem](https://www.doppler.com/doppler-on-prem)

### 12. AWS Secrets Manager

**Что это:** Cloud-сервис для хранения и ротации секретов с глубокой
интеграцией в AWS-экосистему.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|:---------:|------------|
| **OIDC** | ✅ | Через AWS IAM Identity Center (SSO) |
| **LDAP** | ❌ | Через AWS Directory Service (отдельный сервис) |
| **SAML** | ❌ | Нет нативной поддержки в Secrets Manager |
| **Kubernetes** | ❌ | Через CSI/ESO провайдеры |
| **AppRole** | ⚠️ | IAM access keys + policies |
| **TLS Certificate** | ❌ | Через ACM (отдельный сервис) |

**Возможности:**
- Хранение статических секретов (KV)
- Автоматическая ротация (Lambda-based)
- Шифрование AES-256 (KMS)
- Cross-account access
- CloudTrail для аудита
- Генерация секретов RDS, Redshift, DocumentDB

**OIDC-интеграция:**
- AWS Secrets Manager сам использует IAM для аутентификации, OIDC используется
  на уровне IAM Identity Center для входа в AWS Console
- ZITADEL:OIDC → AWS SSO → IAM roles → Secrets Manager access

**Docker интеграция:**
- Нет серверного компонента — это managed service
- CLI: `aws secretsmanager get-secret-value`
- SDK для всех популярных языков

**Kubernetes интеграция:**
- Secrets Store CSI Driver с AWS Provider
- External Secrets Operator с AWS provider
- ESO: `clusterSecretStore` → `aws`

**Ресурсы:**
- Нет self-hosted компонентов
- Стоимость: $0.40/secret/месяц + $0.05/10,000 API вызовов
  ([AWS pricing](https://aws.amazon.com/secrets-manager/pricing/))

**Плюсы для homelab:**
- Нулевое сопровождение (managed service)
- Автоматическая ротация
- Интеграция с CSI Driver и ESO

**Минусы для homelab:**
- Привязка к AWS — не платформонезависимо
- Стоимость растёт с числом секретов
- Нет self-hosted опции
- Не работает в air-gapped средах

**Источники:**
- [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/)
- [CSI Provider](https://github.com/aws/secrets-store-csi-driver-provider-aws)

### 13. Azure Key Vault

**Что это:** Cloud-сервис для управления ключами, секретами и сертификатами в
Azure.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|:---------:|------------|
| **OIDC** | ✅ | Через Azure AD (Entra ID) |
| **LDAP** | ❌ | Нет нативной поддержки |
| **SAML** | ❌ | Нет нативной поддержки |
| **Kubernetes** | ❌ | Через CSI/ESO провайдеры |
| **AppRole** | ⚠️ | Service Principal + client secret |
| **TLS Certificate** | ✅ | Нативный certificate management |

**Возможности:**
- HSM-backed keys (FIPS 140-2 Level 2/3)
- Secret storage с версионированием
- Certificate management (auto-renewal с Key Vault)
- RBAC + access policies
- Azure AD интеграция
- Private Link для изоляции сети

**OIDC-интеграция:**
- Azure AD (Entra ID) используется для аутентификации в Key Vault
- ZITADEL:OIDC → Azure AD → Managed Identity / Service Principal → Key Vault

**Docker интеграция:**
- Нет серверного компонента
- Azure CLI / REST API

**Kubernetes интеграция:**
- CSI Secrets Store Driver с Azure Provider (популярная связка)
- External Secrets Operator с Azure provider
- Pod Identity для аутентификации

**Плюсы для homelab:**
- Лучший CSI интеграция (Azure Provider — референтная реализация)
- HSM-backed keys
- Certificate management

**Минусы для homelab:**
- Привязка к Azure
- Стоимость: $0.03/10,000 операций с секретами + HSM тарифы
- Нет self-hosted опции

**Источники:**
- [Azure Key Vault](https://azure.microsoft.com/en-us/products/key-vault/)
- [CSI Provider](https://github.com/Azure/secrets-store-csi-driver-provider-azure)

### 14. GCP Secret Manager

**Что это:** Cloud-сервис для хранения секретов с versioning, IAM и audit в
GCP.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|:---------:|------------|
| **OIDC** | ✅ | Через Google Identity / Workload Identity Federation |
| **LDAP** | ❌ | Нет нативной поддержки |
| **SAML** | ❌ | Нет нативной поддержки |
| **Kubernetes** | ❌ | Через CSI/ESO провайдеры |
| **AppRole** | ⚠️ | Service Account key |
| **TLS Certificate** | ❌ | Через ACM (отдельный сервис) |

**Возможности:**
- Versioning секретов
- IAM-based access control
- Audit logging (Cloud Audit Logs)
- Шифрование: Google-managed или CMEK (Customer-Managed Encryption Keys)
- Payload size: до 64 KiB
- Rotation через Cloud Scheduler + Cloud Functions

**OIDC-интеграция:**
- Google Identity используется для аутентификации в Secret Manager
- ZITADEL:OIDC → Google Identity → Workload Identity → Secret Manager

**Docker интеграция:**
- Нет серверного компонента
- `gcloud secrets` CLI

**Kubernetes интеграция:**
- CSI Secrets Store Driver с GCP Provider
- External Secrets Operator с GCP provider
- Workload Identity для аутентификации

**Плюсы для homelab:**
- Простой API
- Хорошая интеграция с ESO и CSI

**Минусы для homelab:**
- Привязка к GCP
- Нет self-hosted опции
- Платится за каждый API вызов

**Источники:**
- [GCP Secret Manager](https://cloud.google.com/secret-manager/)
- [CSI Provider](https://github.com/GoogleCloudPlatform/secrets-store-csi-driver-provider-gcp)

---

## Ресурсы: размеры образов и потребление RAM

| Провайдер | Docker image (amd64, compressed) | RAM (idle) | RAM (recommended) | Зависимости |
| --- | --- | --- | --- | --- |
| SOPS + age | ~5 МБ (CLI) | 0 | 0 | Нет |
| Sealed Secrets | 28.6 МБ | 32 МБ | 64 МБ | K8s кластер |
| External Secrets | ~100 МБ | 100 МБ | 256 МБ | K8s + backend store |
| CSI Secrets Store | ~50 МБ | 80 МБ/нода | 128 МБ/нода | K8s + provider |
| Infisical | 672 МБ | 300 МБ ¹ | 4–8 ГБ | PostgreSQL, Redis |
| OpenBao | ~180 МБ ² | 512 МБ | 2 ГБ | Нет (Raft) |
| HashiCorp Vault | 183.5 МБ | 512 МБ | 2 ГБ | Нет (Raft) |
| CyberArk Conjur | 144.4 МБ | 4 ГБ | 16 ГБ | PostgreSQL |
| Bitwarden SM | ~500+ МБ | 2 ГБ | 4 ГБ | MSSQL |
| 1Password Connect | 26 МБ (API) + 25 МБ (sync) | ~100 МБ | 256 МБ | 1Password аккаунт |

> ¹ 300 МБ — только backend-контейнер Infisical (по
> [selfhosting.sh](https://selfhosting.sh/apps/infisical/)); официальная рекомендация
> для полного стека (backend + PostgreSQL + Redis) — 4 ГБ.
>
> ² Размер образа OpenBao — ожидаемый (аналогичен Vault ~180 МБ). Точные данные
> будут доступны после первого стабильного релиза.

---

## Интеграция с почтовыми серверами (SMTP-секреты)

Управление секретами для email-инфраструктуры — отдельная тема. Почтовые серверы
(Postfix, Dovecot, Haraka и др.) требуют учётных данных для SMTP-аутентификации
и, опционально, S/MIME-сертификатов для шифрования писем.

### Общая картина

| Задача | OpenBao | Vault (BSL) | Infisical | SOPS + age | Другие |
| --- |:---:|:---:|:---:|:---:|:---:|
| **Хранение SMTP-паролей** | ✅ KV engine | ✅ KV engine | ✅ Secret storage | ✅ Encrypted файл | ✅ (любой vault) |
| **Ротация SMTP-паролей** | ⚠️ Через LDAP engine | ⚠️ Через LDAP engine | ❌ Manual | ❌ Manual | ❌ |
| **S/MIME-сертификаты** | ✅ PKI engine (`email_protection_flag=true`) | ✅ PKI engine (`email_protection_flag=true`) | ❌ | ❌ | ❌ |
| **Ротация S/MIME** | ✅ Динамическая через PKI | ✅ Динамическая через PKI | ❌ | ❌ | ❌ |

### Хранение SMTP-credential-ов

Все vault-решения могут хранить SMTP-учётные данные (username, password, host,
port) как обычные KV-секреты. Это не требует специальных engine.

**HashiCorp Vault / OpenBao:**
- Использовать KV v2 engine: `vault kv put secret/smtp/default user=admin pass=...`
- Альтернатива: database engine для ротации паролей bind-user в LDAP, который
  используется для SMTP-аутентификации

**Infisical:**
- Создать секрет `SMTP_PASSWORD` в нужном environment
- Использовать `infisical run` или webhook для передачи пароля в контейнер

### Ротация SMTP-паролей через LDAP Secrets Engine (Vault / OpenBao)

Если SMTP-сервер аутентифицирует пользователей через LDAP (Dovecot, Postfix +
saslauthd), Vault/OpenBao может динамически генерировать и ротировать bind-пароли:

```
vault secrets enable ldap
vault write ldap/config/config \
    binddn="cn=admin,dc=example,dc=com" \
    bindpass="..." \
    url="ldap://ldap.example.com" \
    password_policy="smtp-password-policy"

vault read ldap/creds/smtp-role  # → временный bind credentials
```

Это позволяет автоматически ротировать пароли, которые используются
SMTP-сервером для подключения к LDAP.

### PKI для S/MIME-сертификатов (уникальная возможность Vault / OpenBao)

Vault/OpenBao PKI engine может выдавать сертификаты с флагом `email_protection`:

```
vault secrets enable pki
vault write pki/root/generate/internal \
    common_name="Example.com Email CA" \
    ttl=87600h

vault write pki/roles/smtp-email \
    allowed_domains="example.com" \
    allow_subdomains=true \
    key_type="rsa" \
    key_bits=2048 \
    email_protection_flag=true \
    ext_key_usage="emailProtection"
```

Затем для каждого почтового сервера или пользователя генерируется
S/MIME-сертификат:

```bash
vault write pki/issue/smtp-email \
    common_name="smtp.example.com" \
    ip_sans="10.0.0.1" \
    ttl=720h
```

Это позволяет:
- Автоматически ротировать S/MIME-сертификаты
- Использовать短期 сертификаты вместо длинноживущих
- Централизованно управлять PKI для email

### Итого

| Провайдер | SMTP secret storage | SMTP secret rotation | S/MIME PKI | S/MIME rotation |
| --- |:---:|:---:|:---:|:---:|
| **OpenBao** | ✅ KV v2 | ⚠️ Через LDAP engine | ✅ PKI engine | ✅ Динамическая |
| **HashiCorp Vault** | ✅ KV v2 | ⚠️ Через LDAP engine | ✅ PKI engine | ✅ Динамическая |
| **Infisical** | ✅ Secrets | ❌ Manual | ❌ | ❌ |
| **SOPS + age** | ✅ Encrypted файл | ❌ Manual | ❌ | ❌ |
| **Doppler** | ✅ Secrets | ❌ Manual | ❌ | ❌ |
| **1Password** | ✅ Secure notes | ❌ Manual | ❌ | ❌ |
| **Bitwarden SM** | ✅ Secrets | ❌ Manual | ❌ | ❌ |
| **Cloud KMS** | ✅ | ⚠️ Через cloud CA | ⚠️ Через cloud CA | ⚠️ |

---

## OIDC-интеграция с ZITADEL

ZITADEL — open-source IdP (Identity Provider), который поддерживает OIDC 1.0,
SAML 2.0 и SCIM. Интеграция ZITADEL с vault-решениями позволяет
централизовать аутентификацию и использовать единый SSO для всех сервисов.

### Общая схема

```
Пользователь → ZITADEL (OIDC) → Vault/Infisical → Секреты
```

### ZITADEL → HashiCorp Vault / OpenBao

**Режим:** Vault/OpenBao как OIDC-потребитель (вход через ZITADEL)

**Конфигурация (одинакова для Vault и OpenBao):**

```bash
# Включить OIDC auth method
vault auth enable oidc  # или bao auth enable oidc

# Настроить connection с ZITADEL
vault write auth/oidc/config \
    oidc_discovery_url="https://<zitadel-domain>/oauth/v2" \
    oidc_client_id="<client-id>" \
    oidc_client_secret="<client-secret>" \
    default_role="default"

# Создать роль
vault write auth/oidc/role/default \
    bound_audiences="<client-id>" \
    allowed_redirect_uris="https://<vault-domain>/ui/vault/auth/oidc/oidc/callback" \
    allowed_redirect_uris="https://localhost:8250/oidc/callback" \
    user_claim="sub" \
    policies="default"
```

**Особенности ZITADEL-интеграции:**
- ZITADEL использует `email` claim, а не `sub` по умолчанию в некоторых
  конфигурациях. Убедиться, что `user_claim` настроен корректно
- Если Vault/OpenBao не понимает формат role claims из ZITADEL, создать
  **ZITADEL Action** для преобразования claims:

```json
{
  "flow_type": "external_authentication",
  "trigger_type": "post_authentication",
  "actions": [{
    "name": "flatten_claims",
    "script": "// JavaScript для добавления roles в access token"
  }]
}
```

- Audiences: в ZITADEL указать `https://<vault-domain>` как audience

### ZITADEL → Infisical

**Режим:** Infisical как OIDC-потребитель (вход в Infisical через ZITADEL)

**Поддержка:** Paid feature (Pro Tier для SaaS, Enterprise license для
self-hosted). Generic OIDC доступен без специального шаблона.

**Конфигурация ZITADEL:**

1. Создать приложение в ZITADEL (Application → OIDC)
2. Настроить Redirect URI: `https://<infisical-domain>/api/v1/sso/oidc/callback`
3. Выбрать PKCE (Code с PKCE) или Code flow
4. Скопировать Client ID и Client Secret

**Конфигурация Infisical:**

1. Settings → Authentication → SSO → General OIDC
2. Ввести:
   - **Issuer/OIDC Discovery URL:** `https://<zitadel-domain>/oauth/v2`
   - **Callback URL:** `https://<infisical-domain>/api/v1/sso/oidc/callback`
   - **JWT Algorithm:** RS256
   - **Client ID:** из ZITADEL
   - **Client Secret:** из ZITADEL
3. Соединить (Claims mapping не требуется для базовой работы)

**Особенности:**
- ZITADEL OIDC discovery URL: `https://<domain>/oauth/v2/.well-known/openid-configuration`
- Infisical не требует специальных claims; стандартный OIDC flow достаточен
- OIDC-аутентификация доступна только для Pro/Enterprise tier

### ZITADEL → Doppler

**Поддержка:** Только Enterprise ($12K/year за on-prem).

**Конфигурация:** OIDC через стандартный flow в Doppler Enterprise SSO
настройках. ZITADEL подключается как generic OIDC provider.

### ZITADEL → CyberArk Conjur

**Поддержка:** OIDC только в Enterprise-редакции.

**Альтернатива:** ZITADEL поддерживает SAML 2.0, Conjur OSS также
поддерживает SAML — можно использовать SAML-интеграцию вместо OIDC.

### Сводная таблица OIDC с ZITADEL

| Провайдер | OIDC с ZITADEL | Уровень лицензии | Особенности настройки |
| --- |:---:| --- | --- |
| **OpenBao** | ✅ | MPL-2.0 (free) | Аналогично Vault; generic OIDC |
| **HashiCorp Vault** | ✅ | BSL 1.1 (self-hosted free) | Generic OIDC; возможно потребуется Action для claims |
| **Infisical** | ✅ | Pro Tier / Enterprise | General OIDC flow; JWT Algo RS256; discovery URL + callback |
| **Doppler** | ⚠️ | Enterprise ($12K/year) | Generic OIDC через Enterprise SSO |
| **CyberArk Conjur** | ⚠️ | Enterprise | OIDC или SAML 2.0 |
| **Bitwarden SM** | ❌ | — | OIDC не поддерживается для SM |
| **SOPS + age** | ❌ | — | CLI tool, нет аутентификации |
| **1Password** | ❌ | — | Собственная аутентификация |
| **Cloud KMS** | ⚠️ | IAM-level | OIDC через IdP → cloud IAM → KMS |

---

## Рекомендация для данного homelab

### Этап 1: GitOps-хранилище секретов (SOPS + age)

Для текущего Docker Compose + K8s homelab:

1. Установить `sops` и `age`
2. Сгенерировать age key pair: `age-keygen -o ~/.config/sops/age/keys.txt`
3. Добавить `.sops.yaml` в корень репозитория
4. Шифровать YAML/ENV файлы с секретами
5. Для Flux CD: создать `sops-age` secret в `flux-system` namespace
6. Коммитить зашифрованные файлы в git

Это даёт:
- Нулевой overhead (нет серверов)
- GitOps-native workflow
- Нативная поддержка Flux CD
- Мульти-recipients для команды

### Этап 2: Добавление ESO (по мере необходимости)

Когда понадобится:
- Автоматическая синхронизация секретов в K8s
- Secrets из внешних store (не только git)
- Dynamic rotation

1. Установить ESO через Helm
2. Настроить SecretStore (Infisical, Vault, или другой)
3. Создать ExternalSecret для каждого сервиса

### Этап 3: Infisical (при росте команды/сервисов)

Когда понадобится:
- Веб-UI для управления секретами
- RBAC для разных ролей
- Approval workflows
- Интеграция с CI/CD без git

1. Развернуть Infisical через Docker Compose (PostgreSQL + Redis + backend)
2. Настроить Machine Accounts для CI/CD
3. Подключить ESO для Kubernetes
4. Опционально: настроить OIDC через ZITADEL для SSO (Pro Tier)

### Этап 4: Vault / OpenBao (при enterprise-задачах)

Если появятся:
- Dynamic secrets (временные DB credentials)
- Transit encryption (EaaS)
- PKI (автоматические TLS-сертификаты или S/MIME)
- Ротация SMTP-паролей через LDAP engine

1. Развернуть Vault/OpenBao с Raft storage (3 ноды)
2. Настроить auth methods (OIDC через ZITADEL)
3. Подключить ESO как provider
4. Опционально: PKI engine для S/MIME-сертификатов

**OpenBao vs Vault:** Если критична MPL-2.0 лицензия — выбирать OpenBao. Если
нужна зрелость и огромная экосистема — HashiCorp Vault. API-совместимы, миграция
возможна.

### Когда избегать

- **Cloud-провайдеры** (AWS/Azure/GCP): только если homelab уже привязан к
  облаку. Не соответствуют требованию платформонезависимости.
- **Doppler**: только если готовы платить $12K/year за on-prem. Бесплатная
  версия — SaaS, не self-hosted.
- **Bitwarden SM**: только если уже есть Bitwarden Enterprise. MSSQL — тяжёлая
  зависимость.
- **Conjur**: избыточен для homelab; 4 ГБ RAM минимум.
- **Sealed Secrets**: хорош для K8s-only, но нет UI/audit/dynamic. Рассматривать
  как альтернативу SOPS, а не дополнение.

---

## Не подтверждённые утверждения

Следующие утверждения требуют дополнительной проверки или являются оценочными:

1. **Infisical Community Edition**: Утверждается MIT лицензия для CE. Точная
   граница между CE и Enterprise features может отличаться — проверять
   [лицензионный файл](https://github.com/Infisical/infisical/blob/main/licenses/ee/LICENSE)
   перед развёртыванием.

2. **Bitwarden Secrets Manager**: Утверждается, что SM требует Enterprise
   подписку. Точная стоимость и доступность для individual/homelab пользователей
   может отличаться — проверять [pricing](https://bitwarden.com/pricing/).

3. **Doppler On-prem**: Информация о on-prem доступна только с 2026 года.
   Требования к ресурсам и процесс развёртывания не публичны — запрашивать у
   Doppler при заинтересованности.

4. **RAM для Vault**: Official minimum 512 МБ для dev; production requirements
   8–16 ГБ для кластера из 3 нод. Точные цифры зависят от нагрузки и типа
   storage backend.

5. **Infisical image size**: ~672 МБ (сжатый) — измерено по Docker Hub тегам.
   Реальный распакованный размер может быть значительно больше (~2.9 ГБ по
   [user report](https://github.com/Infisical/infisical/discussions/5209)).

6. **Conjur OSS vs Enterprise**: Граница возможностей между OSS и Enterprise
   версиями не полностью документирована. Dynamic secrets и rotation могут
   работать в OSS с ограничениями — проверять
   [документацию](https://docs.cyberark.com/conjur-open-source/).

7. **1Password Connect**: Rate limits для Service Accounts не публичны. Connect
   Server кеширует данные, но initial fetch может быть медленным при большом
   количестве секретов.

8. **CSI Secrets Store Driver auto-rotation**: В v1.6.0 rotation перешла на
   RequiresRepublish; stability этой функции для production пока не полностью
   подтверждена.

9. **Sealed Secrets key recovery**: Recovery workflow описан в документации, но
   на практике потеря master keypair приводит к необходимости пересоздания всех
   SealedSecrets. Нет built-in backup mechanism.

10. **Vault BSL 1.1**: Лицензия разрешает self-hosting, но запрещает
    предоставление vault-as-a-service конкурентам HashiCorp. Для homelab это
    неактуально, но стоит учитывать при возможном переходе на OpenBao.

11. **Vault PKI для S/MIME**: Возможность выдачи S/MIME-сертификатов через
    PKI engine (`email_protection_flag=true`) документирована, но не является
    типичным сценарием использования. Требуется ручная настройка и тестирование.

12. **Infisical OIDC с ZITADEL**: Generic OIDC flow работает теоретически;
    интеграция не тестировалась с конкретной версией ZITADEL. Claims mapping
    может потребовать дополнительной настройки.

13. **Vault OIDC Provider**: Возможность использования Vault как OIDC-провайдера
    документирована, но для homelab это нетипичный сценарий; чаще Vault
    выступает как OIDC-потребитель.

14. **OpenBao**: Форк Vault под MPL-2.0, начат в 2024. API-совместим с Vault,
    но некоторые интеграции (Helm chart, CSI driver) ещё community-maintained.
    Требуется проверять статус стабильности перед production-use. Docker image
    size и RAM потребление аналогичны Vault (ожидаемо).

Все размеры образов получены из Docker Hub (сжатые, amd64). RAM потребление — из
официальной документации или проверенных third-party обзоров (selfhosting.sh,
GitHub issues). Цены — актуальные на момент проверки (август 2026).

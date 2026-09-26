# Layout секретов в Vault: иерархия путей и структура ACL

Дата исследования: 2026-09-26.

Документ отвечает на вопрос «как проектировать пути и ACL внутри Vault» и проверяет
каждое утверждение по первичным источникам: [документация
developer.hashicorp.com/vault](https://developer.hashicorp.com/vault/docs) и исходники
HashiCorp на GitHub. Сравнение провайдеров (SOPS / Sealed Secrets / ESO / Vault /
Infisical) здесь намеренно не повторяется — см. [Связанные документы](#связанные-документы).

Термины: **capability** — разрешение (`read`, `create`, …), **policy** — набор
правил `path`+`capabilities`, **path** — адрес в пространстве имён Vault, **lease** —
договор на время жизни выданного секрета, **mount** — точка монтирования secrets
engine или auth method.

---

## Обзор

| # | Вопрос | Ответ документации HashiCorp | Статус |
|---|---|---|---|
| 1 | Строить ли иерархию путей | Документация утверждает, что Vault path-based и пути ведут себя как виртуальная ФС, но **не содержит правила** «стройте иерархию». Есть trade-off таблица «один mount с подпутями vs mount на команду» | Частично: фактура есть, доктрины нет |
| 2 | Namespaces — Enterprise? | Да, явно: «Appropriate Vault Enterprise license or HCP Vault Dedicated cluster required» | ✅ Подтверждено |
| 3 | Грамматика policy HCL | `path`, `capabilities` (10 значений), `*` только последним символом, `+` в пределах сегмента, `deny` с приоритетом, parameter constraints, templated policies | ✅ Подтверждено |
| 4 | Default deny и ceiling | Default deny подтверждён дословно. `default-ceiling` **не описан в документации**, но подтверждён исходником: встроенная, неудаляемая, создаётся при init, к токенам не присоединяется | Default deny ✅ / ceiling ⚠️ только по исходнику |
| 5 | Kubernetes auth role | `bound_service_account_names` / `_namespaces` / `audience` / `token_policies` / `token_ttl` / `token_max_ttl`. Глобы **не документированы**, но реализованы через `go-glob` | Поля ✅ / глобы ⚠️ только по исходнику |
| 6 | Динамические vs статические | Database `creds/<role>` = новый логин на каждый запрос + lease + revoke; static role = 1:1 маппинг с ротацией. PKI: роль ограничивает SAN, «if any requested names do not match role policy, the entire request will be denied» | ✅ Подтверждено |
| 7 | KV v2 pinning версий | `version` на read — подтверждено дословно. «Ротация без поломки потребителей» как сценарий — **не описан** | Параметр ✅ / сценарий ⚠️ |
| 8 | Transit — API или хранилище | Дословно: «Vault doesn't store the data sent to the secrets engine». Ценообразование HCP (per-encryption-operation) **не удалось проверить** | Транзит ✅ / цены ⚠️ |
| 9 | Аудит | «record all API requests and responses», тип записи `request`\|`response`, есть `auth.policy_results`, `auth.entity_created`, `request.wrap_ttl`; перечислены неаудируемые endpoint'ы | ✅ Подтверждено |
| 10 | IaC для Vault | `hashicorp/vault`, ресурсы `vault_policy`, `vault_kubernetes_auth_backend_config/role`. Страницы Terraform Registry **гео-блокированы** из этой среды, поэтому атрибуты взяты из docs репозитория провайдера (v5.12.0). OpenTofu нигде не упоминается | Ресурсы ✅ / Registry ⚠️ / OpenTofu ❌ не подтверждено |
| 11 | Анти-паттерны | Production hardening прямо запрещает «limit the use of globs, wildcards, and templates». Утверждения вида «никогда не пиши `kv/data/*`» в документации **нет** | ✅ / ❌ соответственно |

---

## 🗂️ Путь в Vault: что именно говорят документы

### Vault — path-based по построению

Дословно со страницы [Policies](https://developer.hashicorp.com/vault/docs/concepts/policies):

> Everything in Vault is path-based, and policies are no exception. Policies provide
> a declarative way to grant or forbid access to certain paths and operations in Vault.

Оттуда же про устройство:

> Vault's architecture is similar to a filesystem. Every action in Vault has a
> corresponding path and capability - even Vault's internal core configuration
> endpoints live under the `"sys/"` path.

И со страницы [Secrets engines](https://developer.hashicorp.com/vault/docs/secrets):
secrets engine монтируется в путь, «In this way, each secrets engine defines its own
paths and properties», и «To the user, secrets engines behave similar to a virtual
filesystem, supporting operations like read, write, and delete».

Следствия, которые документированы явно:

| Правило | Формулировка | Источник |
|---|---|---|
| Пути регистрозависимы | «Case-sensitive: The path where you enable secrets engines is case-sensitive» — `kv/` и `KV/` это два разных инстанса | [secrets](https://developer.hashicorp.com/vault/docs/secrets) |
| Mount'ы не могут конфликтовать | «you cannot have a mount which is prefixed with an existing mount»; «the mounts `foo/bar` and `foo/baz` can peacefully coexist with each other whereas `foo` and `foo/baz` cannot» | [secrets](https://developer.hashicorp.com/vault/docs/secrets) |
| Secrets engine изолирован | Barrier view «a lot like a chroot», UUID становится data root: «it is impossible for an enabled secrets engine to access the data from any other engine» | [secrets](https://developer.hashicorp.com/vault/docs/secrets) |
| `list` работает по префиксу | «since listing always operates on a prefix, policies must operate on a prefix because Vault will sanitize request paths to be prefixes» | [policies](https://developer.hashicorp.com/vault/docs/concepts/policies) |
| Lease ID = путь + ID | «Lease IDs are structured in a way that their prefix is always the path where the secret was requested from. This lets you revoke trees of secrets» | [lease](https://developer.hashicorp.com/vault/docs/concepts/lease) |

Последнее — самый сильный документированный аргумент **за** иерархию: префиксная
ревокация (`sys/leases/revoke-prefix`) работает только если путь осмысленно
структурирован. Один и тот же факт — с обратной стороны — аргумент **против**
`:vault read sys/leases/revoke-prefix/secret/data` слишком широк.

### Строить ли иерархию: единственное место, где это обсуждается

Единственная страница с явными рекомендациями по структуре путей —
[Best practices for namespaces and mount paths](https://developer.hashicorp.com/vault/docs/enterprise/namespaces/namespace-structure)
(раздел Vault Enterprise). Она задаёт рамку:

> Everything in Vault is path-based. Each path corresponds to an operation or secret
> in Vault, and the Vault API endpoints map to these paths; therefore, writing
> policies configures the permitted operations to specific secret paths.

Дальше — «General guidance» с пятью принципами: *Use namespaces sparingly*,
*Leverage Vault identities*, *Understand Vault's mount points*, *Granularity of
paths*, *Standardized onboarding process*. Про granularity сказано ровно следующее
(и это **таблица trade-off, а не правило**):

| Подход | Benefit | Risk |
|---|---|---|
| Один KV mount, под-путь на команду | reduces potential of hitting mount table limits | the KV mount is accidentally deleted causing all users of that secret engine to be impacted |
| Уникальный mount на LOB | can limit the blast-radius of an errant change to a single mount | unique KV mounts per team becomes inefficient from a mount management perspective |

Заметьте формулировку: «It is up to you to find the right balance of granularity
between the various mounts needed and the roles defined within the mounts». То есть
документация **делегирует** выбор.

### «Path = контракт с потребителем»: статус

Эта формулировка **в документации не встречается**. Ближайшее — два документированных
паттерна, из которых она выводится:

1. [Kubernetes auth → Workflows](https://developer.hashicorp.com/vault/docs/auth/kubernetes#working-with-templated-policies)
   описывает ровно привязку пути к потребителю: аннотация
   `vault.hashicorp.com/alias-metadata-env: demo/app` на ServiceAccount → Vault
   рендерит `env = demo/app` → путь `env-kv/data/{{identity.entity.aliases.<accessor>.metadata.env}}`.
   Постановка задачи в документе: «Applications can perform read operations on their
   allocated key/value secret path: `(env-kv/data/<env>)`». Слово «allocated»
   («выделенный потребителю») — из документации; слово «contract» — нет.
2. Там же на странице namespace-structure: «You can use the default names and
   associated metadata that are created for aliases and entities as part of policy
   templates **and deciding on naming conventions for secrets paths/roles**».

**Вывод:** «путь = контракт с потребителем» — это корректная и широко
распространённая практика, но в документации она не сформулирована как принцип.
Ссылаться на неё можно как на вывод из [tutorials/policies/policy-templating](https://developer.hashicorp.com/vault/tutorials/policies/policy-templating)
и [auth/kubernetes#workflows](https://developer.hashicorp.com/vault/docs/auth/kubernetes#working-with-templated-policies),
но не как на цитату HashiCorp.

Дополнительно: та же Enterprise-страница рекомендует, что self-service стоит
переносить **не** в namespace, а в onboarding-слой:

> HashiCorp recommends providing the self-service capability by implementing an
> onboarding layer rather than directly through Vault. The onboarding layer can
> enforce a standard naming convention, secrets path structure, and templated policies.

---

## 🏢 Namespaces: Enterprise-фича

Лицензионное требование заявлено явно на
[странице Namespaces](https://developer.hashicorp.com/vault/docs/enterprise/namespaces)
(блок Enterprise):

> Appropriate Vault Enterprise license or HCP Vault Dedicated cluster required.

Для Community Edition (BSL, как в этом homelab) namespaces недоступны — это
подтверждено документацией, а не выводом из памяти.

### Что именно изолировано

Дословно:

> When you create a namespace, you establish an isolated environment with separate
> login paths that functions as a mini-Vault instance within your Vault installation.
> Users can then create and manage their sensitive data within the confines of that
> namespace, including: secret engines, authentication methods, ACL, EGP, and RGP
> policies, password policies, entities, identity groups, tokens

| Изоляция | Что подтверждено | Источник |
|---|---|---|
| Отдельный policy namespace | ACL/EGP/RGP policies перечислены как управляемые **внутри** namespace | [namespaces](https://developer.hashicorp.com/vault/docs/enterprise/namespaces) |
| Отдельная таблица mount'ов | «each namespace must have at least two secret engine mounts (for sys and identity), one local secret engine (cubbyhole) and one auth engine mount (token)»; «By default, each namespace is created with a token auth mount (/auth/), an identity mount (/identity/), and system mount (/sys/)» | [limits](https://developer.hashicorp.com/vault/docs/internals/limits), [namespace-structure](https://developer.hashicorp.com/vault/docs/enterprise/namespaces/namespace-structure) |
| Отдельные auth methods | authentication methods в списке namespace-scoped; «separate login paths» | [namespaces](https://developer.hashicorp.com/vault/docs/enterprise/namespaces) |
| Delegation админов | delegate admins могут управлять своим namespace и создавать дочерние; administrative namespaces дают доступ к подмножеству privileged `sys/` путей | [namespaces](https://developer.hashicorp.com/vault/docs/enterprise/namespaces) |

### Важные оговорки

- **Изоляция не абсолютна.** «Namespaces are isolated environments, but Vault
  administrators can still share and enforce global policies across namespaces with
  the group-policy-application endpoint» ([namespaces](https://developer.hashicorp.com/vault/docs/enterprise/namespaces)).
- **Имена ограничены.** Нельзя заканчивать на `/`, нельзя пробелы, зарезервированы
  `root`, `sys`, `audit`, `auth`, `cubbyhole`, `identity` ([namespaces](https://developer.hashicorp.com/vault/docs/enterprise/namespaces)).
- **Есть storage-лимит.** «The entire list of namespaces must fit in a single storage
  entry» ([limits](https://developer.hashicorp.com/vault/docs/internals/limits)).
- **Часть `sys/` остаётся только root.** В таблице restricted API paths `sys/audit`,
  `sys/auth/:path`, `sys/seal`, `sys/raw`, `sys/storage` — Root `YES`, Admin `NO`
  ([namespaces](https://developer.hashicorp.com/vault/docs/enterprise/namespaces)).
- Рекомендация HashiCorp — «Use namespaces sparingly»: «in many cases, most of the
  desired level of isolation can be enforced via ACL policies»
  ([namespace-structure](https://developer.hashicorp.com/vault/docs/enterprise/namespaces/namespace-structure)).

Вывод для BSL-сборки: namespace заменяется одним KV mount'ом на команду либо
просто префиксом пути + политикой.

---

## 📜 Структура политик: грамматика

### Базовый вид

```
path "secret/foo" {
  capabilities = ["read"]
}
```

Политика пишется на [HCL](https://github.com/hashicorp/hcl) или JSON, загружается в
Vault и адресуется **по имени** ([policies](https://developer.hashicorp.com/vault/docs/concepts/policies)):

> You can think of the policy's name as a pointer or symlink to its set of rules.
> Tokens are attached policies by name, which are then mapped to the set of rules
> corresponding to that name.

### Capabilities — полный список

Раздел [Capabilities](https://developer.hashicorp.com/vault/docs/concepts/policies#capabilities)
определяет **10** значений. Шесть отображаются на HTTP-глаголы:

| Capability | HTTP | Формулировка документации |
|---|---|---|
| `create` | POST/PUT | «Allows creating data at the given path. **Very few parts of Vault distinguish between `create` and `update`**, so most operations require both `create` and `update` capabilities» |
| `read` | GET | «Allows reading the data at the given path» |
| `update` | POST/PUT | «Allows changing the data at the given path. In most parts of Vault, this implicitly includes the ability to create the initial value at the path» |
| `patch` | PATCH | «Allows partial updates to the data at a given path» |
| `delete` | DELETE | «Allows deleting the data at the given path» |
| `list` | LIST | «Allows listing values at the given path. **Note that the keys returned by a `list` operation are *not* filtered by policies. Do not encode sensitive information in key names.** Not all backends support listing» |

Ещё четыре — без привязки к глаголу:

| Capability | Формулировка |
|---|---|
| `sudo` | «Allows access to paths that are *root-protected*. Tokens are not permitted to interact with these paths unless they have the `sudo` capability (in addition to the other necessary capabilities… ). For example, modifying the audit log backends requires a token with `sudo` privileges» |
| `deny` | «Disallows access. **This always takes precedence regardless of any other defined capabilities, including `sudo`**» |
| `subscribe` | «Allows subscribing to [events](https://developer.hashicorp.com/vault/docs/concepts/events) for the given path» (Events — Enterprise) |
| `recover` | «Allows recovering the data on the given path from a snapshot» |

Критичная оговорка о маппинге capability → действие ([policies](https://developer.hashicorp.com/vault/docs/concepts/policies)):

> **Note:** Capabilities usually map to the HTTP verb, and not the underlying action
> taken. This can be a common source of confusion. Generating database credentials
> *creates* database credentials, but the HTTP request is a GET which corresponds to
> a `read` capability.

Практический вывод: `vault read database/creds/<role>` требует `read`, а
`vault write pki/issue/<role>` — `create`/`update`.

Список root-protected путей (например, `sys/audit`, `sys/seal`, `sys/raw`,
`auth/token/accessors`) с указанием нужного HTTP-глагола приведён в
[Root protected API endpoints](https://developer.hashicorp.com/vault/docs/concepts/policies#root-protected-api-endpoints).

### Glob-паттерны: точная семантика

| Символ | Поведение | Цитата |
|---|---|---|
| `*` | Только **последним** символом пути; это не regex | «The glob character referred to in this documentation is the asterisk (`*`). It *is not a regular expression* and is only supported **as the last character of the path**!» ([policies](https://developer.hashicorp.com/vault/docs/concepts/policies#priority-matching)) |
| `+` | Любое число символов **в пределах одного сегмента** (с Vault 1.1) | «a `+` can be used to denote any number of characters bounded within a single path segment» ([policies](https://developer.hashicorp.com/vault/docs/concepts/policies#policy-syntax)) |

Примеры из документации: `secret/foo` — только ровно этот путь; `secret/bar/*` — всё
под `secret/bar`; `secret/zip-*` — всё с префиксом `zip-` (включая вложенные
`secret/zip-zap/zong`); `secret/+/teamb` — сегмент `teamb` под любым top-level путём
внутри `secret/`.

### Приоритет совпадения

Раздел [Priority matching](https://developer.hashicorp.com/vault/docs/concepts/policies#priority-matching)
даёт и правило разрешения, и правило приоритета:

> **Note:** The policy rules that Vault applies are determined by the most-specific
> match available… If the same pattern appears in multiple policies, **we take the
> union of the capabilities**. If different patterns appear in the applicable
> policies, we take only the highest-priority match from those policies.

Пять правил приоритета (из более специфичного к менее):

1. более ранний первый `+`/`*` в `P1` → `P1` ниже приоритетом;
2. `P1` заканчивается на `*`, а `P2` нет → `P1` ниже;
3. больше сегментов с `+` → ниже;
4. короче → ниже;
5. лексикографически меньше → ниже.

**Это ключ к пониманию «почему широкий `deny` работает»:** union даётся только внутри
одного паттерна. Если один policy даёт `path "secret/*"` c `read`, а другой
`path "secret/root/*"` c `["deny"]` — по правилу 2 второй путь специфичнее, и `deny`
выигрывает. Именно такой пример приведён в документации
([policies](https://developer.hashicorp.com/vault/docs/concepts/policies#policy-syntax)):

```
# This section grants all access on "secret/*". further restrictions can be
# applied to this broad policy, as shown below.
path "secret/*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list", "recover"]
}
# Even though we allowed secret/*, this line explicitly denies
# secret/super-secret. this takes precedence.
path "secret/super-secret" {
  capabilities = ["deny"]
}
```

### Переиспользование политик и wildcards

Что документация говорит про переиспользование (прямых указаний «создавайте
переиспользуемые политики» нет, но механизм описан однозначно):

- Политика адресуется именем; токен получает **набор имён**, а не содержимое
  ([policies](https://developer.hashicorp.com/vault/docs/concepts/policies#associating-policies)).
- «However, the *contents* of policies are parsed in real-time whenever the token is
  used. As a result, if a policy is modified, the modified rules will be in force the
  next time a token, with that policy attached, is used to make a call to Vault» —
  то есть правка политики применяется ко всем токенам без перевыпуска
  ([policies](https://developer.hashicorp.com/vault/docs/concepts/policies#tokens)).
- «There is no way to modify the policies associated with a token once the token has
  been issued» — то же место.
- «Normally the only policies that may be specified are those which are present in the
  current token's (i.e. the new token's parent's) token policies. However, root users
  can assign any policies.»

Про wildcards — самая жёсткая цитата, [Production hardening](https://developer.hashicorp.com/vault/docs/concepts/production-hardening),
baseline-рекомендации:

> **Least privilege and bias towards simple policies.** We recommend enforcing the
> principle of least privilege when creating policies. **Limit the use of globs,
> wildcards, and templates.** Instead, we recommend creating policies that are as
> simple and as explicit as possible.

И [tutorial по политикам](https://developer.hashicorp.com/vault/tutorials/policies/policies):

> Restrict the use of the root policy, and write fine-grained policies to follow the
> practice of least privilege. For example, if an app gets AWS credentials from Vault,
> write a policy that grants read from AWS secrets engine, but not delete

### Parameter constraints (где работает, где нет)

`required_parameters`, `allowed_parameters`, `denied_parameters` умеют ограничивать
значения параметров запроса. Важные оговорки:

- «The use of globs may result in **surprising or unexpected behavior**» — с примером,
  где `allowed_parameters = {"bar" = ["baz/*"]}` пропускает `baz/quux,wibble,wobble`
  ([policies](https://developer.hashicorp.com/vault/docs/concepts/policies#parameter-constraints-limitations)).
- «Evaluation of policies with `allowed_parameters`… happens **without consideration of
  parameters' default values**» ([Default values](https://developer.hashicorp.com/vault/docs/concepts/policies#default-values)).
- **На KV v2 не работает**: «The `allowed_parameters`, `denied_parameters`, and
  `required_parameters` fields are **not supported for policies used with the version 2
  kv secrets engine**» ([policies](https://developer.hashicorp.com/vault/docs/concepts/policies#parameter-constraints)).
- `min_wrapping_ttl = "1s"` фактически делает response wrapping обязательным для пути
  ([policies](https://developer.hashicorp.com/vault/docs/concepts/policies#required-response-wrapping-ttls)).

### Templated policies

Подстановка `{{identity.*}}` работает **только в ключах `path`**
([Templated policies](https://developer.hashicorp.com/vault/docs/concepts/policies#templated-policies)):

| Параметр | Что достаёт |
|---|---|
| `identity.entity.id` / `identity.entity.name` | ID / имя entity |
| `identity.entity.metadata.<key>` | metadata entity |
| `identity.entity.aliases.<mount accessor>.name` | имя alias на конкретном mount |
| `identity.entity.aliases.<mount accessor>.metadata.<key>` | metadata alias (например, `service_account_namespace`) |
| `identity.groups.ids.<id>.name` / `identity.groups.names.<name>.id` | соответствие группа↔ID |

Ограничения, важные для дизайна:

- «Using wildcards (`+`) and globs (`*`) in the rendered output of identity templates
  will result in a "permission denied" response from Vault».
- Поведение слэшей в отрендеренном значении регулируется опцией
  [`deny_slash_in_templated_paths`](https://developer.hashicorp.com/vault/docs/configuration#deny_slash_in_templated_paths).
- «When developing templated policies, **use IDs wherever possible**. Each ID is unique
  to the user, whereas names can change over time and can be reused».
- Обязательный разделитель `data` / `metadata` виден в примере документации:
  `secret/data/{{identity.entity.id}}/*` + `secret/metadata/{{identity.entity.id}}/*`
  c `list` только на metadata.

### Как проверить политику, не гадая

- `vault kv put -output-policy kv/secret value=…` печатает минимальную политику для
  команды: [Construct the required Vault policy](https://developer.hashicorp.com/vault/docs/commands#construct-the-required-vault-policy).
- `POST /sys/capabilities-self` — «The capabilities returned will be derived from the
  policies that are on the token, and from the policies to which the token is entitled
  to through the entity and entity's group memberships»; «Paths that do not exist or
  have no capabilities return `[deny]` in the response»
  ([capabilities-self](https://developer.hashicorp.com/vault/api-docs/system/capabilities-self)).

---

## 🚫 Default deny и ceiling policies

### Default deny — подтверждено дословно

Два утверждения со страницы [Policies](https://developer.hashicorp.com/vault/docs/concepts/policies):

> Policies are **deny by default**, so an empty policy grants no permission in the system.

> Because policies are **deny by default**, the token would have no other access in Vault.

Плюс поведение при запросе неизвестного пути — `[deny]`
([capabilities-self](https://developer.hashicorp.com/vault/api-docs/system/capabilities-self)).
Отдельно стоит учесть: встроенная политика `default` приаттачена **ко всем**
токенам по умолчанию, и её содержимое Vault не навязывает («It can be modified to
suit your needs; Vault will never overwrite your modifications») —
[Built-in policies](https://developer.hashicorp.com/vault/docs/concepts/policies#built-in-policies).

### `default-ceiling` — есть в коде, нет в документации

**В документации HashiCorp слово `ceiling` про политики не встречается** — проверено
по [concepts/policies](https://developer.hashicorp.com/vault/docs/concepts/policies)
(и его mdx-исходнику), [api-docs/system/policies](https://developer.hashicorp.com/vault/api-docs/system/policies),
[api-docs/system/policy](https://developer.hashicorp.com/vault/api-docs/system/policy),
[concepts/tokens](https://developer.hashicorp.com/vault/docs/concepts/tokens),
[glossary](https://developer.hashicorp.com/vault/docs/glossary), [tutorials/policies/policies](https://developer.hashicorp.com/vault/tutorials/policies/policies)
и [CHANGELOG v2.0.4](https://github.com/hashicorp/vault/blob/v2.0.4/CHANGELOG.md).
Что удалось подтвердить по исходникам
[hashicorp/vault @ v2.0.4, `vault/policy_store.go`](https://github.com/hashicorp/vault/blob/v2.0.4/vault/policy_store.go):

| Факт | Где в коде |
|---|---|
| Имя встроенной политики — `"default-ceiling"` | `defaultCeilingPolicyName = "default-ceiling"` (стр. 39–40) |
| Создаётся при инициализации, как и `default` | `c.policyStore.loadACLPolicy(ctx, defaultCeilingPolicyName, defaultCeilingPolicy)` (стр. 302–305) |
| Содержимое по умолчанию — три `read`-пути: `agent-registry/registration/entity_id/{{identity.entity.id}}`, `policy/default`, `policy/default-ceiling` | `defaultCeilingPolicy` (стр. 167–181) |
| Удалить нельзя | `if name == defaultPolicyName \|\| name == defaultCeilingPolicyName { return fmt.Errorf("cannot delete %s policy", name) }` (стр. 861) |
| К токенам **не** присоединяется автоматически | авто-attach в коде есть только для `default` (`SanitizePolicies(..., addDefault)`, [`vault/token_store.go`](https://github.com/hashicorp/vault/blob/v2.0.4/vault/token_store.go)) |

### Про «intersection of attached policies and ceiling»

Это утверждение **не проверяется по первичным источникам**:

- В документации формулировки «effective permissions = пересечение присоединённых
  политик и ceiling» нет. Документировано другое: union внутри совпадающих паттернов
  и most-specific-match для разных паттернов
  ([Priority matching](https://developer.hashicorp.com/vault/docs/concepts/policies#priority-matching)).
- В Community Edition-репозитории `vault/acl.go` логики отдельного «ceiling ACL» нет:
  [`NewACL`](https://github.com/hashicorp/vault/blob/v2.0.4/vault/acl.go) (стр. 79)
  сливает **все** присоединённые политики в один radix-дерево, а
  `vault/policy_store_util.go` и `vault/acl_util.go` — заглушки, делегирующие
  Enterprise-реализации (`entPolicyStore`, `performEntPolicyChecks`).
  Соответственно, «потолок» — Enterprise-механика, и в CE-сборке её не проверить.

Что **можно** противопоставить этому как документированный инвариант: токен не может
получить больше прав, чем есть у родительского токена, если только он не root —
«Normally the only policies that may be specified are those which are present in the
current token's… token policies. However, root users can assign any policies»
([policies](https://developer.hashicorp.com/vault/docs/concepts/policies#tokens)).
Это ограничение по «происхождению», а не «потолок сверху».

Аудит, кстати, показывает фактический результат: в `auth.policy_results` пишется
`allowed` и список `granted_policies`
([audit schema](https://developer.hashicorp.com/vault/docs/audit/schema)) — по
аудиту можно проверить, что политика сработала ожидаемо, без гадания о внутренностях.

---

## ☸️ Kubernetes auth: привязка ролей

Reference: [Kubernetes auth method](https://developer.hashicorp.com/vault/docs/auth/kubernetes)
(гайд) и [Kubernetes auth method (API)](https://developer.hashicorp.com/vault/api-docs/auth/kubernetes)
(полный список параметров).

### Поля роли

`POST /auth/kubernetes/role/:name`:

| Параметр | Тип / дефолт | Документация |
|---|---|---|
| `bound_service_account_names` | array, **required** | «List of service account names able to access this role. If set to `*` all names are allowed» |
| `bound_service_account_namespaces` | array, `[]` | «List of namespaces allowed to access this role. If set to `*` all namespaces are allowed» |
| `bound_service_account_namespace_selector` | string, `""` | LabelSelector (JSON/YAML); «Currently, label selectors with `matchExpressions` are not supported»; требует «Vault must have permission to read namespaces»; «If set with `bound_service_account_namespaces`, the conditions are `OR`ed» |
| `audience` | string, `""` | «Audience claim to verify in the JWT» |
| `token_policies` | array или comma-string | «List of token policies to encode onto generated tokens» |
| `policies` | — | **DEPRECATED**, «Please use the `token_policies` parameter instead» |
| `token_ttl` | int (секунды) или duration string | «The incremental lifetime for generated tokens» |
| `token_max_ttl` | int или duration string | «The maximum lifetime for generated tokens» |
| `token_type` | string | `service` / `batch` / `default`; «For machine based authentication cases, you should use `batch` type tokens» |
| `token_period` | int/duration | «The maximum allowed period value when a periodic token is requested from this role» |
| `token_explicit_max_ttl` | int/duration | «a hard cap even if `token_ttl` and `token_max_ttl` would otherwise allow a renewal» |
| `token_num_uses` | int, `0` = unlimited | ограничение числа использований |
| `token_no_default_policy` | bool, `false` | «the `default` policy will not be set on generated tokens» |
| `token_bound_cidrs` | array | привязка токена к CIDR |
| `alias_name_source` | `serviceaccount_uid` (дефолт) | «Using a service account UID is both the default and the recommended method as it the more secure option» |

Команда создания роли из гайда целиком помещается в одну строку HCL-конфигурации
([Configuration](https://developer.hashicorp.com/vault/docs/auth/kubernetes#configuration)):

```
$ vault write auth/kubernetes/role/demo \
    bound_service_account_names=myapp \
    bound_service_account_namespaces=default \
    policies=default \
    audience=myapp \
    ttl=1h
```

### Глобы: документация молчит, код говорит

**Документация не утверждает, что в `bound_service_account_names*` разрешены глобы.**
Она упоминает только специальное значение `"*"`. Проверено по исходникам плагина
(в CE-репозитории Vault его нет — auth method вынесен в отдельный репозиторий
[`hashicorp/vault-plugin-auth-kubernetes`](https://github.com/hashicorp/vault-plugin-auth-kubernetes),
на подключении в `go.mod` v1.21.4: `github.com/hashicorp/vault-plugin-auth-kubernetes v0.23.1`):

| Поведение | Код |
|---|---|
| Сопоставление имени SA — **glob** | [`path_login.go`](https://github.com/hashicorp/vault-plugin-auth-kubernetes/blob/main/path_login.go) стр. 390: `if !strutil.StrListContainsGlob(role.ServiceAccountNames, sa.name())` |
| Сопоставление namespace — **glob** | там же стр. 399: `if role.ServiceAccountNamespaces[0] == "*" \|\| strutil.StrListContainsGlob(role.ServiceAccountNamespaces, sa.namespace())` |
| `"*"` нельзя смешивать с другими значениями | [`path_role.go`](https://github.com/hashicorp/vault-plugin-auth-kubernetes/blob/main/path_role.go) стр. 313–314 и 338–339: `return logical.ErrorResponse("can not mix %q with values", "*")` |
| `_namespaces` не может быть пустым без selector | там же, ~стр. 324–328 |
| Пустой `audience` даёт warning | там же, ~стр. 347–353: «Role %s does not have an audience configured. While audiences are not required, consider specifying one if your use case would benefit from additional JWT claim verification» |
| `StrListContainsGlob` использует `ryanuber/go-glob` | [`go-secure-stdlib/strutil`](https://github.com/hashicorp/go-secure-stdlib/blob/main/strutil/strutil.go) (в `main`); та же реализация в зафиксированной версии `strutil/v0.1.2` |

Семантика `*` в `go-glob` ([исходник](https://github.com/ryanuber/go-glob/blob/master/glob.go)):
`*` — единственный glob-символ, и он матчит **любые символы, включая `/`**
(реализация через `strings.Split(pattern, "*")` + `strings.Index`, а не path-segment
aware). Практические следствия:

- `bound_service_account_namespaces = ["*"]` ≡ «любой namespace»;
- паттерн вида `app-*` совпадёт и с `app-prod`, и с `app-prod/sub`;
- `+` (segment-bounded glob из политик) здесь **не работает** — только `*`.

Вывод: глобы в k8s-роли — это работающая, но **недокументированная** возможность,
опирающаяся на реализацию, а не на контракт. Для homelab правильнее опираться на
явный список либо на `bound_service_account_namespace_selector`.

### Про `audience` отдельно

Гайд по Kubernetes 1.21+ ([Kubernetes 1.21](https://developer.hashicorp.com/vault/docs/auth/kubernetes#kubernetes-121))
и [api-docs](https://developer.hashicorp.com/vault/api-docs/auth/kubernetes#deprecated-parameters)):
`disable_iss_validation` и `issuer` **deprecated**, дефолт `disable_iss_validation`
теперь `true`. Это же объясняет, почему в примере `audience=myapp` стоит задавать
явно: audience — это дополнительная проверка claim'а, которую Vault не делает сам.

Отдельно: JWT reviewer. Рекомендуемый вариант — «use the pod's local service account
token» (Vault 1.9.3+), альтернативы и их trade-off таблица — в
[How to work with short-lived Kubernetes tokens](https://developer.hashicorp.com/vault/docs/auth/kubernetes#how-to-work-with-short-lived-kubernetes-tokens).

---

## 🔄 Динамические секреты против статических

### Механика lease

[Lease, renew, and revoke](https://developer.hashicorp.com/vault/docs/concepts/lease):

> With every dynamic secret and service type authentication token, Vault creates a
> **lease**: metadata containing information such as a time duration, renewability,
> and more. Vault promises that the data will be valid for the given duration, or
> Time To Live (TTL).

> **All dynamic secrets in Vault are required to have a lease.** Even if the data is
> meant to be valid for eternity, a lease is required to force the consumer to check
> in routinely.

> When a lease is revoked, it invalidates that secret immediately and prevents any
> further renewals. For example, with the AWS secrets engine, the access keys will be
> deleted from AWS the moment a lease is revoked.

Про KV: «The Key Value Backend which stores arbitrary secrets **does not issue
leases** although it will sometimes return a lease duration».

### Database secrets engine

[Database secrets engine](https://developer.hashicorp.com/vault/docs/secrets/databases):

| Аспект | Документировано |
|---|---|
| Назначение | «generates database credentials dynamically based on configured roles… services that need to access a database no longer need to hardcode credentials» |
| Аудит | «Since every service is accessing the database with unique credentials, it makes auditing much easier when questionable data access is discovered. You can track it down to the specific instance of a service based on the SQL username» |
| Динамический кред | `GET /database/creds/:name` ([api-docs](https://developer.hashicorp.com/vault/api-docs/secret/databases)) — новый `username`/`password` + `lease_id` на каждый вызов |
| Static role | «Static roles are a 1-to-1 mapping of Vault roles to usernames in a database… Vault stores and automatically rotates passwords… **anyone with the proper Vault policies can access the associated user account in the database**» |
| Отзыв | «Vault makes use of its own internal revocation system to ensure that users become invalid within a reasonable time of the lease expiring»; на роли есть `revocation_statements`, `rollback_statements`, `renew_statements` |
| TTL роли | `default_ttl` (дефолт 1h) и `max_ttl` (дефолт 24h) — [Setup](https://developer.hashicorp.com/vault/docs/secrets/databases#setup) |

То есть разница принципиальная: `database/creds/<role>` даёт **нового** SQL-пользователя
на каждый запрос, а `database/static-roles/<role>` — **тот же** логин с ротацией
пароля по расписанию. Аудит по первому варианту однозначно указывает на конкретный
инстанс сервиса; по второму — нет.

### PKI

[PKI secrets engine](https://developer.hashicorp.com/vault/docs/secrets/pki):

> The PKI secrets engine generates dynamic X.509 certificates. With this secrets
> engine, services can get certificates without going through the usual manual process
> of generating a private key and CSR, submitting to a CA, and waiting for a
> verification and signing process to complete.

> By keeping TTLs relatively short, revocations are less likely to be needed… this
> allows each instance of a running application to have a **unique certificate,
> eliminating sharing and the accompanying pain of revocation and rollover**.

> Certificates can be fetched and stored in memory upon application startup and
> discarded upon shutdown, without ever being written to disk.

`POST /pki/issue/:name` ([api-docs](https://developer.hashicorp.com/vault/api-docs/secret/pki)):

> **Note:** The private key is not stored. If you do not save the private key from the
> response, you will need to request a new certificate.

Роль — это и есть enforcement point:

> If the CN is allowed by role policy, it will be issued. […] If any requested names
> do not match role policy, **the entire request will be denied**.

Поля роли, которые задают границу: `allowed_domains`, `allowed_domains_template`,
`allowed_uri_sans`, `allowed_other_sans`, `allow_bare_domains`, `allow_subdomains`,
`allow_glob_domains`, `allow_any_name`, `allow_localhost`, `allow_ip_sans`,
`require_cn`, `use_csr_common_name`, `use_csr_sans`, `server_flag`, `client_flag`,
`code_signing_flag`, `ext_key_usage`, `key_usage`, `not_before_duration`, `ttl`,
`max_ttl`, `key_type`, `key_bits`.

### Почему каждому потребителю — своя роль

Связка трёх документированных фактов:

1. Роль задаёт **имя, TTL и набор capability** — при `deny`/`allowed_domains`
   нарушение отбрасывает **весь** запрос, а не отдельное поле
   ([api-docs/secret/pki](https://developer.hashicorp.com/vault/api-docs/secret/pki)).
2. Роль DB определяет `creation_statements` / `revocation_statements` и TTL, поэтому
   две роли на одну БД дают раздельные lease-деревья, а префиксная ревокация
   работает по префиксу пути ([lease](https://developer.hashicorp.com/vault/docs/concepts/lease)).
3. Роль k8s auth определяет, **какой** SA и в каком namespace может получить эти
   права ([api-docs/auth/kubernetes](https://developer.hashicorp.com/vault/api-docs/auth/kubernetes)).

То есть роль — это одновременно и enforcement point, и единица blast radius.
Документация требует per-role конфигурации и там, где это неочевидно:

> Vault will use the user specified here to create/update/revoke database credentials.
> […] **It is highly recommended a user within the database is created specifically for
> Vault to use.**

и отдельно запрет:

> **Do not use static roles for root database credentials.** […] Vault does not
> distinguish between standard credentials and root credentials when rotating
> passwords.

---

## 📚 KV v2: pinning версий и ротация

### Параметр `version` — подтверждён дословно

[KV v2 API](https://developer.hashicorp.com/vault/api-docs/secret/kv/kv-v2),
«Read secret version», `GET /:secret-mount-path/data/:path?version=:version`:

| Параметр | Тип / дефолт | Описание |
|---|---|---|
| `version` | `int: 0` | **«Specifies the version to return. If not set the latest version is returned.»** |

Ответ содержит `metadata.version` плюс `created_time`, `deletion_time`, `destroyed`,
`custom_metadata`; `custom_metadata` «is part of the secret's key metadata and is
included in the response whether or not the calling token has read access to the
associated metadata endpoint».

Сопутствующие механизмы:

| Механизм | Что делает | Источник |
|---|---|---|
| `options.cas` | оптимистичная блокировка записи; требуется, если `cas_required` | [api-docs/secret/kv/kv-v2](https://developer.hashicorp.com/vault/api-docs/secret/kv/kv-v2) |
| soft delete | `vault kv delete` — недоступно, но восстановимо | [cookbook/destroy-data](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2/cookbook/destroy-data) |
| destroy | необратимое удаление версии | там же |
| `max_versions` | «permanently deletes (destroys) older data versions automatically» | [cookbook/max-versions](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2/cookbook/max-versions) |
| «The `kv` v2 plugin uses soft deletes to make data inaccessible while allowing data recovery» | общее описание движка | [secrets/kv/kv-v2](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2) |

### Про ротацию «без поломки работающих потребителей»

**Такого сценария в документации нет.** KV v2 — не dynamic secret, lease не
выдаётся ([lease](https://developer.hashicorp.com/vault/docs/concepts/lease)), и
страницы [secrets/kv/kv-v2](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2) +
[tutorial Store versioned Key/value secrets](https://developer.hashicorp.com/vault/tutorials/secrets-management/versioned-kv)
описывают версионирование, откат и защиту от случайного удаления, но не сценарий
«поднять новую версию, убедиться что все потребители переехали, удалить старую».

Практически это значит:

- «пиннинг версии в конфиге потребителя» — **наша практика**, а не документированный
  контракт; поддерживается параметром `version`, но в HCL/манифестах потребителя
  его обычно нет;
- единственный документированный рычаг против «сломать соседей» — `cas` при записи
  и `max_versions`, чтобы старое не пропало раньше времени;
- `parameter constraints` (`allowed_parameters` и т. п.) на KV v2 **не поддерживаются**,
  так что ограничить «кто какие ключи читает» на уровне политики нельзя
  ([policies](https://developer.hashicorp.com/vault/docs/concepts/policies#parameter-constraints)).

---

## 🔐 Transit: API шифрования, а не хранилище

[Transit secrets engine](https://developer.hashicorp.com/vault/docs/secrets/transit) —
дословно, без интерпретаций:

> The transit secrets engine handles cryptographic functions on data in-transit.
> **Vault doesn't store the data sent to the secrets engine.** It can also be viewed
> as "cryptography as a service" or "encryption as a service".

> The primary use case for `transit` is to encrypt data from applications while still
> storing that encrypted data in some primary data store.

И в разделе Usage:

> Note that Vault does not *store* any of this data. The caller is responsible for
> storing the encrypted ciphertext.

Остальное, что важно для дизайна ACL:

| Наблюдение | Цитата |
|---|---|
| Ключ на приложение | «**Usually each application has its own encryption key.**» |
| Разделение ролей через ACL | «Using ACLs, it is possible to restrict using the transit secrets engine such that **trusted operators can manage the named keys, and applications can only encrypt or decrypt using the named keys they need access to**» |
| `rewrap` не раскрывает plaintext | «This process **does not** reveal the plaintext data. As such, a Vault policy could grant almost an untrusted process the ability to "rewrap" encrypted data» |
| Версионирование ключа в ciphertext | «The returned ciphertext starts with `vault:v1:`… when you rotate keys, Vault knows which version to use for decryption» |
| Ротация по NIST | «For AES-GCM keys, rotation should occur before approximately 2^32 encryptions have been performed by a key version, following the guidelines of NIST publication 800-38D»; пример: «40 million operations per day, then rotating a key every three months is sufficient» |
| Лимит запроса | «Vault HTTP API imposes a maximum request size of 32MB» |
| Минимальная decryption-версия | `min_decryption_version`: старые версии архивируются, «by disallowing decryption of old versions of keys, found ciphertext corresponding to obsolete (but sensitive) data can not be decrypted by most users» |

### Про cost model

Утверждение «у HCP Vault transit тарифицируется по числу операций шифрования, а
self-hosted стоимость хранения определяется объёмом storage» **не удалось
подтвердить первичным источником**: `hashicorp.com/products/vault/pricing` отдаёт
HTTP 429 из этой среды, а
[HCP Vault tiers and features](https://developer.hashicorp.com/hcp/docs/vault/tiers-and-features)
не содержит прайсинга. Документация Vault вообще не делает утверждений о
ценообразовании. Помечено как непроверенное.

Что проверить можно самостоятельно и что действительно в документации: transit
хранит только ключи и метаданные, а не данные, поэтому объём storage растёт от
числа ключей и версий, а не от объёма шифротекста.

---

## 📋 Аудит

### Что пишется по умолчанию

[Audit logging](https://developer.hashicorp.com/vault/docs/audit):

> With a small set of exceptions, **Vault audit devices record all API requests and
> responses in detail.** An audit device can be a `file`, a `syslog` server, or a
> `socket`.

> Audit logs differ from server logs (also known as operational logs). […] Audit logs
> record the details of **every request received and response sent by the Vault API**.

> When you initialize a new Vault cluster, **auditing is disabled.**

Не аудируются ([Audit logging → Exempted API endpoints](https://developer.hashicorp.com/vault/docs/audit#exempted-api-endpoints)):
`sys/init`, `sys/seal-status`, `sys/seal`, `sys/step-down`, `sys/unseal`,
`sys/leader`, `sys/health`, `sys/rekey/init|update|verify`,
`sys/rekey-recovery-key/init|update|verify`, `sys/storage/raft/bootstrap`,
`sys/storage/raft/join`, `sys/internal/ui/feature-flags`; и дополнительно
`sys/metrics`, `sys/pprof/*`, `sys/in-flight-req` — когда listener разрешает
неаутентифицированный доступ.

### Формат записи

[Audit log entry schema](https://developer.hashicorp.com/vault/docs/audit/schema):

| Поле | Тип | Что даёт |
|---|---|---|
| `type` | string | **«One of request or response»** — это и есть «тип события» в схеме |
| `auth` | object | principal: `accessor`, `client_token` («in hashed form»), `display_name`, `policies`, `num_uses`, `remaining_uses`, `entity_created`, `token_type`, `token_period`, `token_ttl` |
| `auth.entity_created` | boolean | «Whether the request resulted in an entity being created, i.e. when an authorized principal logs into Vault for the first time» |
| `auth.policy_results` | object | «JSON object containing a boolean attribute `allowed` and `granted_policies`, a list of ACL policies associated with either the Vault token or the corresponding entity that resulted in the request being allowed» |
| `request.operation` | string | «Whether the request is a `create`, `read`, `update`, `delete`, or `list` operation» |
| `request.path` | string | «API path that received the request» |
| `request.mount_accessor` / `mount_type` / `mount_running_version` | string | «Unique identifier of the Vault mount (secret engine or authentication backend) that received the API request» |
| `request.wrap_ttl` | integer | «If the client requested the response to be wrapped, the number of seconds for which the wrapped response will be available» |
| `request.data` / `response.data` | object | payload; у `response` — «Omitted for request entries» |
| `request.headers` | object | по умолчанию логируются `User-Agent`, `Correlation-Id`, `X-Correlation-Id` |
| `error` | string | «Error string generated by the request or returned in the response» |

Про response wrapping: из [Response Wrapping](https://developer.hashicorp.com/vault/docs/concepts/response-wrapping)
в аудите видны `Creation Path: The API path that was called in the original request`
и `Wrapped Accessor: If the wrapped response is an authentication response containing a
Vault token, this is the value of the wrapped token's accessor`. То есть факт
выдачи одноразового токена и исходный путь остаются в логе.

### Эксплуатационные свойства, которые меняют дизайн

| Свойство | Цитата | Практическое следствие |
|---|---|---|
| Fail-closed | «Vault sends the audit log entry of **every** API request and response to all enabled audit devices and **guarantees that it saves to at least one** of the enabled devices. As a result, if […] Vault cannot log information to at least one of the enabled devices, **Vault refuses to service the corresponding API request**» | Недоступный файловый лог = недоступный Vault |
| Минимум два устройства | «HashiCorp recommends that you: Enable at least two audit devices» | Один локальный `file` device без вывоза наружу — точка отказа |
| Хеширование | «By default, Vault only writes a keyed hash (HMAC-SHA256) of most string values to audit logs… Vault does not hash non-string values, such as integers and booleans» | Значения в логе не читаются; сверка — через `POST /sys/audit-hash` |
| Секреты в именах | см. `list` capability выше | Имя ключа утекает в лог даже при хешировании значений |
| `sys/audit` под root | в таблице [root-protected API endpoints](https://developer.hashicorp.com/vault/docs/concepts/policies#root-protected-api-endpoints) `sys/audit` (GET/LIST) и `sys/audit/:path` (POST/DELETE) требуют root или `sudo` | Настроить аудит обычным токеном нельзя |
| Пресечение `elide_list_responses` | «…replace `keys` and `key_info` values in audit log entries for LIST responses with the number of objects those fields contain» | Экономит место, но прячет список путей |

---

## 🏗️ Vault-конфигурация как код

Официальный провайдер — `hashicorp/vault`. **Страницы Terraform Registry из этой
среды недоступны** (гео-блокировка: `registry.terraform.io` отдаёт
«Content not available in your region», `registry.opentofu.org` — 403), поэтому
атрибуты ресурсов ниже взяты из собственной документации провайдера в репозитории
[hashicorp/terraform-provider-vault @ v5.12.0](https://github.com/hashicorp/terraform-provider-vault)
(последний релиз на момент исследования — v5.12.0, 17 сентября 2026). Ссылки на
Registry даны там, где их приводит сама документация Vault, но помечены как
непроверенные.

| Ресурс | Ключевые аргументы | Источник |
|---|---|---|
| `vault_policy` | `name` (required), `policy` (required, строка с HCL), `allow_overwrite` (дефолт `true`, «will be removed in the next major release and the default behavior will be not overwrite policies»), `namespace` — «*Available only for Vault Enterprise*» | [`website/docs/r/policy.html.md`](https://github.com/hashicorp/terraform-provider-vault/blob/v5.12.0/website/docs/r/policy.html.md) |
| `vault_kubernetes_auth_backend_role` | `bound_service_account_names` (required), `bound_service_account_namespaces`, `bound_service_account_namespace_selector`, `audience`, `token_ttl`, `token_max_ttl`, `token_policies`, … | [`website/docs/r/kubernetes_auth_backend_role.html.md`](https://github.com/hashicorp/terraform-provider-vault/blob/v5.12.0/website/docs/r/kubernetes_auth_backend_role.html.md) |
| `vault_kubernetes_auth_backend_config` | `kubernetes_host`, `kubernetes_ca_cert`, `token_reviewer_jwt`, `disable_local_ca_jwt`, `use_annotations_as_alias_metadata` | [`website/docs/r/kubernetes_auth_backend_config.md`](https://github.com/hashicorp/terraform-provider-vault/blob/v5.12.0/website/docs/r/kubernetes_auth_backend_config.md) |
| `vault_kv_secret_backend_v2`, `vault_transit_secret_backend_key` | — | ссылки из [secrets/kv/kv-v2](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2#terraform) и [secrets/transit](https://developer.hashicorp.com/vault/docs/secrets/transit#terraform) |

Аргументы в провайдере совпадают с API Vault один в один, включая формулировку
про `*`: «If set to `["*"]` all names are allowed, **both this and
`bound_service_account_namespaces` can not be "\*"**».

Главное предупреждение из документации провайдера
([`website/docs/index.html.markdown`](https://github.com/hashicorp/terraform-provider-vault/blob/v5.12.0/website/docs/index.html.markdown)):

> **Important** Interacting with Vault from Terraform causes any secrets that you read
> and write to be **persisted in both Terraform's state file *and* in any generated
> plan files**.

То есть на Vault-конфиг это не распространяется (политики и роли — не секреты), но
на `vault_kv_secret_v2` — распространяется, и это причина держать секреты в Git
(SOPS) а не в state.

Документация Vault требует IaC прямо:

> You should treat Vault configuration as code, and use version control to manage
> policies ([production hardening](https://developer.hashicorp.com/vault/docs/concepts/production-hardening))

> Many HashiCorp users are using Terraform for managing infrastructure on-prem and in
> the cloud. Terraform can also be used to codify Vault configuration tasks such as
> creation of namespaces, policies, and mounts
> ([namespace-structure](https://developer.hashicorp.com/vault/docs/enterprise/namespaces/namespace-structure))

### Про OpenTofu

**Не подтверждено.** Ни в [документации Vault](https://developer.hashicorp.com/vault/docs),
ни в документации провайдера v5.12.0 (проверено: слово `OpenTofu` не встречается ни
разу, везде «Terraform») нет утверждения о переходе HashiCorp на OpenTofu или о
совместимости. Страницы Registry, где это обычно указано, недоступны из этой среды.
Ориентироваться следует на то, что провайдер официально называется
`hashicorp/vault` и документирован для Terraform.

---

## ⚠️ Анти-паттерны: что запрещают документы, а что — нет

### Запрещено/предостережено явно

| # | Анти-паттерн | Цитата | Источник |
|---|---|---|---|
| 1 | Массовое использование glob'ов и шаблонов | «**Limit the use of globs, wildcards, and templates.** Instead, we recommend creating policies that are as simple and as explicit as possible» | [production hardening](https://developer.hashicorp.com/vault/docs/concepts/production-hardening) |
| 2 | Regex-подобное понимание `*` | «It *is not a regular expression* and is only supported **as the last character of the path**!» | [policies](https://developer.hashicorp.com/vault/docs/concepts/policies#priority-matching) |
| 3 | Секреты в именах ключей | «the keys returned by a `list` operation are *not* filtered by policies. **Do not encode sensitive information in key names**» | [policies](https://developer.hashicorp.com/vault/docs/concepts/policies#capabilities) |
| 4 | Имена в identity-шаблонах | «**use IDs wherever possible.** Each ID is unique to the user, whereas names can change over time and can be reused» | [policies](https://developer.hashicorp.com/vault/docs/concepts/policies#templated-policies) |
| 5 | Ожидание, что parameter constraints защитят KV | «not supported for policies used with the version 2 kv secrets engine» | [policies](https://developer.hashicorp.com/vault/docs/concepts/policies#parameter-constraints) |
| 6 | Надежда на ограничение по glob в значениях параметров | «the use of globbing may result in **surprising or unexpected behavior**» | [policies](https://developer.hashicorp.com/vault/docs/concepts/policies#parameter-constraints-limitations) |
| 7 | Оставление root-токена | «it is **highly recommended** that you revoke any root tokens before running Vault in production» | [policies](https://developer.hashicorp.com/vault/docs/concepts/policies#root-policy) |
| 8 | Static role на root-креды БД | «**Do not use static roles for root database credentials** […] any dynamic or static users managed by that database configuration will fail after rotation» | [databases](https://developer.hashicorp.com/vault/docs/secrets/databases#static-roles) |
| 9 | Общий пользователь БД для всех и Vault | «**It is highly recommended a user within the database is created specifically for Vault to use**» + `vault write -force database/rotate-root/my-database` | [databases](https://developer.hashicorp.com/vault/docs/secrets/databases#setup) |
| 10 | Mount, который является префиксом другого mount | «mount points cannot conflict with each other in Vault» | [secrets](https://developer.hashicorp.com/vault/docs/secrets) |
| 11 | Один audit device | «Enable at least two audit devices» | [audit](https://developer.hashicorp.com/vault/docs/audit#availability-of-audit-devices) |
| 12 | Namespace на каждую команду по умолчанию | «**Use namespaces sparingly** […] most of the desired level of isolation can be enforced via ACL policies» | [namespace-structure](https://developer.hashicorp.com/vault/docs/enterprise/namespaces/namespace-structure) |
| 13 | Смешивание `"*"` с конкретными значениями в k8s-роли | `can not mix "*" with values` | [path_role.go](https://github.com/hashicorp/vault-plugin-auth-kubernetes/blob/main/path_role.go) |
| 14 | Долгоживущие креды | «**Use short TTLs.** When possible, credentials issued from Vault […] should be short-lived» | [production hardening](https://developer.hashicorp.com/vault/docs/concepts/production-hardening) |
| 15 | Отсутствие off-boarding | «Removing accounts in Vault or associated identity providers **may not immediately revoke token-based access**» | [production hardening](https://developer.hashicorp.com/vault/docs/concepts/production-hardening) |

### Не является официальной рекомендацией (community practice)

Важно не выдавать за документацию то, чего в ней нет:

| Распространённое мнение | Статус |
|---|---|
| «Никогда не пишите `path "kv/data/*"`» | **В документации отсутствует.** Наоборот, собственный пример документации использует `path "secret/*"` и *сужает* его через `deny`. Документация не запрещает широкие пути — она требует, чтобы они были максимально специфичны, и объясняет механизм приоритета |
| «Один KV mount на каждый сервис» | **Не рекомендация.** [namespace-structure](https://developer.hashicorp.com/vault/docs/enterprise/namespaces/namespace-structure) даёт это как trade-off с явным «Risk» и завершает «It is up to you to find the right balance» |
| «Один policy на каждый сервис, шаблонных политик не надо» | Прямого запрета нет, но [production hardening](https://developer.hashicorp.com/vault/docs/concepts/production-hardening) велит «Limit the use of globs, wildcards, and templates», а [tutorials/policies/policy-templating](https://developer.hashicorp.com/vault/tutorials/policies/policy-templating) показывает шаблоны как механизм. Выбор — за вами |
| «Vault не для хранения данных, только для секретов» | **Формулировки нет.** Документация говорит, что KV «stores and versions arbitrary static secrets» ([secrets/kv/kv-v2](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2)) и отдельно предупреждает о лимитах хранения ([limits](https://developer.hashicorp.com/vault/docs/internals/limits)). Запрет на «большие блобы» — практический совет, а не цитата |
| «Namespace per team обязателен» | Прямо противоположно: «Use namespaces sparingly» ([namespace-structure](https://developer.hashicorp.com/vault/docs/enterprise/namespaces/namespace-structure)) |

---

## Не подтверждённые утверждения / оговорки

- **`default-ceiling` и «потолок прав»** — в документации HashiCorp не описаны
  (проверено: [concepts/policies](https://developer.hashicorp.com/vault/docs/concepts/policies)
  и mdx-исходник, [api-docs/system/policies](https://developer.hashicorp.com/vault/api-docs/system/policies),
  [concepts/tokens](https://developer.hashicorp.com/vault/docs/concepts/tokens),
  [glossary](https://developer.hashicorp.com/vault/docs/glossary),
  [CHANGELOG v2.0.4](https://github.com/hashicorp/vault/blob/v2.0.4/CHANGELOG.md) —
  слово `ceiling` не встречается). Подтверждено только по исходнику
  [`vault/policy_store.go`](https://github.com/hashicorp/vault/blob/v2.0.4/vault/policy_store.go):
  имя, встроенность, неудаляемость, создание при init, отсутствие авто-attach.
  Формулировка «effective permissions = intersection of attached policies and
  ceiling» в CE-сборке **не проверяема**: её реализация находится в Enterprise-части
  (в CE-репозитории [`NewACL`](https://github.com/hashicorp/vault/blob/v2.0.4/vault/acl.go)
  сливает все политики в одно дерево, а `acl_util.go` / `policy_store_util.go` —
  заглушки).
- **Страницы Terraform Registry** (`registry.terraform.io/providers/hashicorp/vault/...`,
  на которые ссылается документация Vault, например
  [auth/kubernetes#terraform](https://developer.hashicorp.com/vault/docs/auth/kubernetes#terraform))
  недоступны из среды проверки: HTTP 404 с телом «Content not available in your
  region». Аргументы ресурсов взяты из docs репозитория провайдера v5.12.0.
- **Ценообразование HCP Vault** (per-encryption-operation vs стоимость storage) —
  `hashicorp.com/products/vault/pricing` отдаёт 429, HCP-документация прайсинга не
  содержит. Утверждение не проверялось.
- **OpenTofu** — ни одного упоминания в проверенных источниках; переход HashiCorp на
  OpenTofu не подтверждён и не опровергнут.
- **Глобы в `bound_service_account_names*`** — не документированы, но реализованы
  (`strutil.StrListContainsGlob` → `ryanuber/go-glob`). Поведение `*`, пересекающего
  `/`, выведено из кода `go-glob`, а не из контракта.
- **Версия документации.** Страницы прочитаны в ветке `v2.x (latest)`
  (актуальная линия — Vault 2.1.1). Ветки v1.21.x и v1.20.x содержат мелкие
  отличия (например, список parameter-констрейнтов для списков отличается до
  v1.21.0) — при сверке с конкретной версией проверяйте нужную ветку.
- **Плагин kubernetes auth** в CE-репозитории Vault отсутствует
  (`builtin/credential/` содержит только approle, aws, cert, github, ldap, okta,
  radius, token, userpass) — проверялось по дереву тегов v1.21.4 и v2.0.4; код
  взят из отдельного репозитория `hashicorp/vault-plugin-auth-kubernetes` (ветка
  `main`), который в `go.mod` Vault v1.21.4 зафиксирован на `v0.23.1`.

---

## Связанные документы

- [`docs/research/secret-management-providers.md`](./secret-management-providers.md) —
  сравнение **провайдеров** (SOPS, Sealed Secrets, External Secrets Operator, Vault,
  Infisical). Этот документ не повторяет его: здесь про layout и ACL внутри Vault.
- [`docs/adr/0005-vault-secrets-operator.md`](../adr/0005-vault-secrets-operator.md) —
  решение использовать `hashicorp/vault-secrets-operator` (VSO) вместо External
  Secrets Operator. VSO stateless, и именно поэтому конфигурация Vault (роли,
  политики, mount'ы) остаётся единственным источником правды.
- [`docs/research/secrets-consumers-inventory.md`](./secrets-consumers-inventory.md) —
  обследование текущего состояния: 40 файлов SealedSecret, реестр паролей ролей
  CNPG, хаб креденшелов в Secret `vmagent`. Входные данные для выбора раскладки,
  включая два подтверждённых дубля значений.

---

## Источники

### Политики, токены, пути

- [Vault Docs — Policies](https://developer.hashicorp.com/vault/docs/concepts/policies) —
  грамматика HCL, capabilities, priority matching, built-in policies, templated
  policies, parameter constraints, root-protected endpoints
- [Vault Docs — Secrets engines](https://developer.hashicorp.com/vault/docs/secrets) —
  path-based модель, mount conflicts, barrier view, case sensitivity
- [Vault Docs — Production hardening](https://developer.hashicorp.com/vault/docs/concepts/production-hardening) —
  «Limit the use of globs, wildcards, and templates», root tokens, short TTLs,
  configuration as code, off-boarding
- [Vault Docs — Lease, renew, and revoke](https://developer.hashicorp.com/vault/docs/concepts/lease) —
  семантика lease, префиксная ревокация, KV без lease
- [Vault Docs — Response Wrapping](https://developer.hashicorp.com/vault/docs/concepts/response-wrapping)
- [Vault API — /sys/capabilities-self](https://developer.hashicorp.com/vault/api-docs/system/capabilities-self)
- [Vault CLI — Construct the required Vault policy](https://developer.hashicorp.com/vault/docs/commands#construct-the-required-vault-policy)
- [Vault Tutorial — Vault Policies](https://developer.hashicorp.com/vault/tutorials/policies/policies)
- [Vault Tutorial — ACL Policy Path Templating](https://developer.hashicorp.com/vault/tutorials/policies/policy-templating)
- [Vault Docs — Limits and maximums](https://developer.hashicorp.com/vault/docs/internals/limits) —
  namespace limits, mount table limits

### Namespaces (Enterprise)

- [Vault Docs — Namespace and secure multi-tenancy (SMT)](https://developer.hashicorp.com/vault/docs/enterprise/namespaces) —
  Enterprise-лицензия, что изолировано, naming restrictions, restricted API paths
- [Vault Docs — Best practices for namespaces and mount paths](https://developer.hashicorp.com/vault/docs/enterprise/namespaces/namespace-structure) —
  granularity of paths, use namespaces sparingly, mount table trade-offs
- [Vault Docs — Create an administrative namespace](https://developer.hashicorp.com/vault/docs/enterprise/namespaces/create-admin-namespace)

### Secrets engines

- [Vault Docs — Database secrets engine](https://developer.hashicorp.com/vault/docs/secrets/databases)
- [Vault API — Database secrets engine](https://developer.hashicorp.com/vault/api-docs/secret/databases)
- [Vault Docs — PKI secrets engine](https://developer.hashicorp.com/vault/docs/secrets/pki)
- [Vault API — PKI secrets engine](https://developer.hashicorp.com/vault/api-docs/secret/pki)
- [Vault Docs — Transit secrets engine](https://developer.hashicorp.com/vault/docs/secrets/transit)
- [Vault Docs — Key/Value v2](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2)
- [Vault API — KV v2](https://developer.hashicorp.com/vault/api-docs/secret/kv/kv-v2) —
  параметр `version`
- [Vault Docs — KV v2 cookbook: Set max data versions](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2/cookbook/max-versions)
- [Vault Docs — KV v2 cookbook: Permanently delete data](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2/cookbook/destroy-data)
- [Vault Tutorial — Store versioned Key/value secrets](https://developer.hashicorp.com/vault/tutorials/secrets-management/versioned-kv)

### Auth

- [Vault Docs — Kubernetes auth method](https://developer.hashicorp.com/vault/docs/auth/kubernetes)
- [Vault API — Kubernetes auth method](https://developer.hashicorp.com/vault/api-docs/auth/kubernetes) —
  полный справочник полей роли

### Аудит

- [Vault Docs — Audit logging](https://developer.hashicorp.com/vault/docs/audit)
- [Vault Docs — Audit log entry schema](https://developer.hashicorp.com/vault/docs/audit/schema)
- [Vault Docs — Audit best practices](https://developer.hashicorp.com/vault/docs/audit/best-practices)

### Исходники

- [hashicorp/vault @ v2.0.4 — `vault/policy_store.go`](https://github.com/hashicorp/vault/blob/v2.0.4/vault/policy_store.go) —
  `default-ceiling`, `default`, `response-wrapping`
- [hashicorp/vault @ v2.0.4 — `vault/acl.go`](https://github.com/hashicorp/vault/blob/v2.0.4/vault/acl.go) —
  `NewACL`, слияние политик
- [hashicorp/vault-plugin-auth-kubernetes — `path_role.go`](https://github.com/hashicorp/vault-plugin-auth-kubernetes/blob/main/path_role.go)
- [hashicorp/vault-plugin-auth-kubernetes — `path_login.go`](https://github.com/hashicorp/vault-plugin-auth-kubernetes/blob/main/path_login.go) —
  glob-сопоставление SA и namespace
- [hashicorp/go-secure-stdlib — `strutil.StrListContainsGlob`](https://github.com/hashicorp/go-secure-stdlib/blob/main/strutil/strutil.go)
- [ryanuber/go-glob — `Glob`](https://github.com/ryanuber/go-glob/blob/master/glob.go) —
  семантика `*`
- [hashicorp/terraform-provider-vault @ v5.12.0 — docs ресурсов](https://github.com/hashicorp/terraform-provider-vault/tree/v5.12.0/website/docs/r)

---

## Что применимо к этому homelab

> **Это наша оценка, а не цитаты из документации.** Раздел намеренно отделён от
> проверенного материала выше: здесь мы сопоставляем документацию с нашим контекстом
> (одноузловой k0s, Vault 2.0.4 Community Edition / BSL, VSO 1.6.0, ~48 сервисов,
> каждый в своём namespace, команда из одного человека, секреты пока на 40
> SealedSecret + SOPS-реестре).

### Что важно и применяется сразу

| # | Практика | Почему именно у нас |
|---|---|---|
| 1 | **Default deny + одна политика на сервис, привязанная к его k8s namespace** | 48 сервисов × один `bound_service_account_namespaces` + узкий `path` — это ровно то, что даёт изоляцию «бесплатно». Namespace'ы Vault Enterprise недоступны, но изоляция на уровне path + policy эквивалентна для нашего масштаба |
| 2 | **Путь = `<mount>/<namespace>/<service>/<key>`** | Не из-за «так красиво», а по двум документированным причинам: префиксная ревокация работает по префиксу пути, и `list` по префиксу отдаёт осмысленный список. Плюс это делает возможным templated policy через `identity.entity.aliases.<accessor>.metadata.service_account_namespace` — рецепт есть в [auth/kubernetes#workflows](https://developer.hashicorp.com/vault/docs/auth/kubernetes#working-with-templated-policies) |
| 3 | **Один KV mount, а не mount-на-сервис** | Прямо по trade-off таблице [namespace-structure](https://developer.hashicorp.com/vault/docs/enterprise/namespaces/namespace-structure): один mount снижает риск упереться в лимиты mount-таблицы, а цена («accidentally deleted mount impact all») закрывается тем, что mount пересоздаётся из Git, и тем, что политики у потребителей явные |
| 4 | **`read` только на `data/`, `list` только на `metadata/`** | Проверяемо: `list` не фильтруется политиками, имена ключей видны. Ещё и `allowed_parameters` на KV v2 не работают — единственная защита от «прочитал чужое» — узкий `path` |
| 5 | **Явный `audience` в каждой k8s-роли** | Vault сам предупреждает warning'ом, если `audience` пуст. Для 48 ролей это 48 строк конфигурации — дёшево |
| 6 | **Никаких `"*"` в `bound_service_account_names*`** | Глобы там не документированы, работают через `go-glob` и `*` пересекает `/`. Нечего полагаться на недокументированную семантику в ACL, который раздаёт 48 сервисам |
| 7 | **Аудит: минимум два device** | HashiCorp прямо требует. На k0s это `file` на local disk + `socket`/`syslog` наружу (например, в Fluent Bit → Loki). Учтём fail-closed: если sink недоступен, Vault откажется обслуживать запрос |
| 8 | **Vault-конфигурация в Git через `vault_policy` / `vault_kubernetes_auth_backend_role`** | Прямое требование [production hardening](https://developer.hashicorp.com/vault/docs/concepts/production-hardening): «treat Vault configuration as code». Секретов в этих ресурсах нет, поэтому предупреждение про state-файл на них не распространяется |
| 9 | **Проверка политик через `-output-policy` и `sys/capabilities-self`** | Дёшево, ловит опечатки в путях до деплоя |
| 10 | **TTL на k8s-роли — короткие, `token_type = batch`** | HashiCorp прямо: «For machine based authentication cases, you should use `batch` type tokens» + «Use short TTLs» |

### Что НЕ нужно в нашем масштабе

| # | Практика | Почему не нужна |
|---|---|---|
| 1 | Vault namespaces | Enterprise-only, а HashiCorp сама пишет «Use namespaces sparingly» и «most of the desired level of isolation can be enforced via ACL policies». Мы и так без namespace |
| 2 | `default-ceiling` | Реализация — Enterprise, в CE-сборке не проверяема. Держать в голове как принцип («роль не должна выдавать больше, чем нужно потребителю»), но не как настраиваемый механизм |
| 3 | Database dynamic credentials | У нас нет внешних БД, к которым Vault должен выдавать логины. Единственный кандидат — CNPG внутри кластера, но там ровно один пользователь на кластер, и динамика не даёт выигрыша |
| 4 | PKI | Внутренние сервисы общаются по HTTP в cluster network. PKI оправдана при mTLS между сервисами или для внешних клиентов — этого нет |
| 5 | Transit | Нет задачи «шифровать данные в своей БД ключом из Vault». Если появится — тогда уж отдельное решение, потому что transit хранит ключи, а не данные |
| 6 | Разделение `data/` и `metadata/` policies на уровне шаблонов | С 48 сервисами явные политики читаются лучше шаблонов, а production hardening всё равно велит «limit the use of … templates». Шаблоны имели бы смысл при десятках команд, а не при одном человеке |
| 7 | Несколько audit backends «для отказоустойчивости» | Один человек + один узел: два device — это `file` + вывоз в существующий Loki. Три разных типа device избыточны |

### Что я бы всё-таки завёл

- **Response wrapping** там, где секрет передаётся через посредника. В нашем
  контексте посредник — это сам VSO, и VSO работает по `VaultAuth`/`VaultStaticSecret`
  напрямую, так что оборачивать нечего. Но если появится шаг «CI забирает секрет из
  Vault» — `min_wrapping_ttl = "1s"` на соответствующем пути делает wrapping
  обязательным (документированный приём).
- **`-output-policy` в CI** как проверка, что манифесты VSO соответствуют
  выданным политикам. Прямой аналог drift detection для ACL.

### Честно не решённый вопрос

Документация не описывает сценарий «ротация KV-секрета без поломки работающих
потребителей». Для 48 сервисов, которые читают секрет при старте, это значит
следующее: **сначала выкатить новое значение, потом убедиться, что все
перезапустились, и только потом считать старую версию неактуальной** —
`max_versions` и `cas` помогают, но автоматики «проверь, кто ещё держит v1» в Vault
нет. Это кандидат в issue, а не в готовое решение.

# Technitium (Terraform)

DNS-записи зоны стенда и bootstrap-зоны `cloudflare-dns.com`. Развёртывание
самого сервера — `apps/casa/technitium/`, здесь только записи через HTTP API.

## Запуск

С macOS провайдер ходит в `https://dns.<домен>` (через Traefik), поэтому нужен
маршрут в домашнюю сеть (Tailscale).

```sh macOS
cd infra/casa/terraform/technitium
terraform init
terraform plan
```

## Доступ провайдера

Technitium рекомендует не выпускать токен для `admin`, а завести отдельного
пользователя. Готовится один раз в консоли:

1. **Administration → Users → Add** — пользователь `terraform`, с правом
   View/Modify на нужные зоны.
2. Меню пользователя (справа сверху) → **Create API Token** — имя `terraform`.
   Токен показывается **один раз**, сохранить его.
3. Значение — в Vault, рядом с админским паролем (`kv/technitium/secret`).

Провайдер берёт токен из окружения `TECHNITIUM_API_TOKEN`: в конфиге стоит
`api_token = var.api_token`, а переменная по умолчанию пустая — при пустом
значении провайдер падает на окружение. Аргументы блока `provider` Terraform в
state не сохраняет, поэтому токен в state не попадает. Ввод без истории оболочки:

```sh macOS
read -rs TECHNITIUM_API_TOKEN && echo
export TECHNITIUM_API_TOKEN
```

## Состояние после переезда на `biplane.casa`

State канонический: зона — `technitium_zone.domain_zone`, записи — `apex`,
`wildcard`, `dns`; адресов с суффиксом `_new` не осталось, зона
`biplane.v6.rocks` в Technitium удалена.

`terraform plan` перед `apply` обязателен: `technitium_zone` не управляет
содержимым зоны, поэтому замена зоны (смена `name`) удаляет её целиком вместе с
записями, включая неуправляемые ACME-челленджи cert-manager. Сами записи
объявляют `depends_on` на зону: без него при пересоздании они уходят в API
раньше, чем зона появится, и падают с `No such zone was found`.

## Значения

```hcl
domain  = "biplane.casa" # тот же домен, что в Gateway (platform/casa/traefik/manifests/gateway-homelab.yaml)
host_ip = "192.0.2.10"   # адрес сервера
```

Оба внутренние, в git не идут; реальные лежат в
`infra/casa/terraform/technitium/terraform.tfvars` (gitignored).

## Что управляется

| Ресурс | Запись |
| --- | --- |
| `technitium_record.apex` | `<домен>` A → сервер: wildcard apex не покрывает, а на него ссылается federation delegation Element (`m.server: <домен>:443`) |
| `technitium_record.wildcard` | `*.<домен>` A → сервер |
| `technitium_record.dns` | `dns.<домен>` A → сервер |
| `technitium_record.cloudflare_bootstrap_*` | две A-записи зоны `cloudflare-dns.com` (обход DPI, см. `apps/casa/technitium/README.md`) |

Две bootstrap-записи живут в одном RRset, поэтому у них `overwrite = false` —
иначе вторая затирала бы первую.

## Первый apply

Записи уже существуют, поэтому `imports.tf` переносит их в state. Проверять надо
именно план:

```sh macOS
terraform plan
```

Ожидается `No changes`. Записи — scoped-ресурсы: неуправляемые не затрагиваются
(например, ACME-челленджи, которые cert-manager пишет по RFC2136). После apply
`terraform plan` обязан быть пустым.

## Чего модуль не делает

- **Зоны.** `technitium_zone` не управляется: смена атрибутов зоны пересоздаёт её
  вместе с записями. Зоны остаются в консоли.
- **Настройки сервера.** Forwarders, blocking, recursion — отдельный этап:
  `technitium_server_settings` — singleton и перезаписывает настройки целиком.
- **STIG-валидатор.** Не включается: для управления одними записями находки
  неинформативны, а `enabled = true` требует ещё блок `categorization`.

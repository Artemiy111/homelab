# Technitium (Terraform)

DNS-записи зоны стенда и bootstrap-зоны `cloudflare-dns.com`. Развёртывание
самого сервера — `apps/technitium/`, здесь только записи через HTTP API.

## Запуск

С macOS провайдер ходит в `https://dns.<домен>` (через Traefik), поэтому нужен
маршрут в домашнюю сеть (Tailscale).

```sh macOS
cd terraform/technitium
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

## Значения

```hcl
domain  = "example.com"   # тот же домен, что в platform/homelab
host_ip = "192.0.2.10"    # адрес сервера
```

Оба внутренние, в git не идут; реальные лежат в
`terraform/technitium/terraform.tfvars` (gitignored).

## Что управляется

| Ресурс | Запись |
| --- | --- |
| `technitium_record.wildcard` | `*.<домен>` A → сервер |
| `technitium_record.dns` | `dns.<домен>` A → сервер |
| `technitium_record.cloudflare_bootstrap_*` | две A-записи зоны `cloudflare-dns.com` (обход DPI, см. `apps/technitium/README.md`) |

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

# Tailscale (Terraform)

DNS tailnet: MagicDNS и split DNS (restricted nameserver на домашний домен).
Развёртывание Tailscale на хосте — `apps/tailscale/`, здесь только содержимое
tailnet через API.

## Запуск

Провайдер ходит в API Tailscale напрямую, маршрут в домашнюю сеть не нужен.

```sh macOS
cd terraform/tailscale
terraform init
terraform plan
```

API key создаётся в admin console (Settings → Keys → Generate access token) и
передаётся провайдеру через окружение: `TAILSCALE_API_KEY`. Аргументы блока
`provider` Terraform в state не сохраняет, поэтому ключ в state не попадает.
Без попадания в историю оболочки:

```sh macOS
read -rs TAILSCALE_API_KEY && echo
export TAILSCALE_API_KEY
```

`read -rs` читает молча (ввод не отображается), приглашение не печатается, и
работает и в zsh, и в bash: у zsh флаг `-p` означает чтение из coprocess, а не
prompt. `export` обязателен — без него значение остаётся переменной оболочки, и
запущенный как потомок `terraform` её не видит.

Ключ по правилам `docs/agents/information-handling.md` — секрет, в репозиторий
и `terraform.tfvars` он не идёт. Если tailnet создан после октября 2025 и ключ
не привязан к нему однозначно, задаётся `TAILSCALE_TAILNET`.

## Значения

```hcl
domain  = "example.com"   # основной домен, тот же что в platform/homelab
host_ip = "192.0.2.10"    # адрес Technitium: ему tailnet отдаёт зоны
```

Значения — внутренние, в git не идут; реальные лежат в
`terraform/tailscale/terraform.tfvars` (gitignored).

Домен переезда (`biplane.casa`) задан в `dns.tf` литералом и в переменную не
вынесен: реальный домен стенда публичен (wildcard-сертификат Let's Encrypt
публикуется в Certificate Transparency, `docs/agents/information-handling.md`),
поэтому держать его в приватном слое нечего. `var.domain` остаётся основным
доменом — тем, что в `platform/homelab/values.yaml`; когда переезд завершится
и старый домен уйдёт, литерал в `dns.tf` удаляется вместе с ним.

## Что управляется

Один ресурс `tailscale_dns_configuration.tailnet` описывает DNS целиком:

- `magic_dns = true`;
- `override_local_dns = false` — имена вне перечисленных зон устройства
  резолвят своими резолверами;
- `search_paths = []` — пустой список: домашний DNS не должен подмешиваться
  к запросам других зон;
- по блоку `split_dns` на каждую зону, обе на `host_ip` (Technitium): запросы
  идут в домашний DNS через одобренный subnet route, а не в публичные
  резолверы. `use_with_exit_node = true` сохраняет маршрут и при использовании
  exit node.

Зон две: `var.domain` — основной домен, и `biplane.v6.rocks` литералом, на
время переезда. Старый домен нужен как страховка: пока он в списке, откат
переезда не блокирует DNS.

Ресурс описывает **всю** DNS-конфигурацию, поэтому заодно чистит устаревшие
split-DNS записи, которые в admin console приходилось удалять руками
(`apps/tailscale/README.md`).

Провайдер помечает `tailscale_dns_configuration` как **alpha**: схема может
меняться между версиями. При обновлении провайдера читать release notes, а не
только план.

## Первый apply

Конфигурация уже существует в admin console, поэтому `imports.tf` переносит её
в state (`id = "dns_configuration"`). Проверять надо именно план:

```sh macOS
terraform plan
```

Ожидается `No changes`. Любое изменение означает, что конфиг расходится с admin
console, — сначала чинить конфиг, а не нажимать apply. Ресурс перезаписывает DNS
целиком, поэтому перед apply убедиться, что в плане нет удаления нужных
глобальных nameserver'ов.

После apply `terraform plan` обязан быть пустым. Повторный импорт ничего не
меняет, `imports.tf` можно оставить.

## Чего модуль не делает

- **ACL-policy.** По `docs/agents/information-handling.md` это секрет (раскрывает
  топологию), в репозиторий и state не попадает. Остаётся в admin console.
- **Auth keys.** `tailscale_key` кладёт сгенерированный ключ в state — запрещено
  теми же правилами.
- **Устройства** (одобрение subnet route, key expiry, теги). Отдельный этап:
  требует имён нод, которые тоже внутренние.

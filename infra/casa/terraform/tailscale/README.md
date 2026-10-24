# Tailscale (Terraform)

DNS tailnet: MagicDNS и split DNS (restricted nameserver на домашний домен).
Развёртывание Tailscale на хосте — `apps/casa/tailscale/`, здесь только содержимое
tailnet через API.

Tailnet общий на аккаунт, а не на стенд, поэтому state этого модуля лежит под
ключом `global/tailscale/terraform.tfstate`, хотя каталог пока внутри
`infra/casa/terraform/`. Тег `tag:k8s` из `acl.tf` использует и `yc` — это не
ресурс casa. Перенос каталога в `infra/global/terraform/` запланирован отдельно,
после миграции state в RustFS.

## Запуск

Провайдер ходит в API Tailscale напрямую, маршрут в домашнюю сеть не нужен.

```sh macOS
cd infra/casa/terraform/tailscale
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
locals {
  domain  = "biplane.casa"
  host_ip = "192.168.1.254"
}
```

Переменных у модуля нет: значения лежат в `locals` (`main.tf`). Прятать их не в
чем — домен публичен (wildcard-сертификат Let's Encrypt публикуется в Certificate
Transparency), а адрес Technitium уже стоит открытым текстом в
`infra/casa/terraform/technitium/locals.tf` и в values Forgejo. Приватного слоя
(`terraform.tfvars`) у модуля больше нет.

`local.domain` — основной домен, тот же, что в манифестах Traefik.

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

Зона одна: `local.domain`. На время переезда домен был прописан дважды — вторым
`split_dns` шёл литерал старого имени как страховка, чтобы откат не блокировал
DNS. Со сменой домена он убран, и `terraform apply` заберёт его из tailnet:
ресурс описывает конфигурацию целиком, поэтому запись исчезнет сама.

Ресурс описывает **всю** DNS-конфигурацию, поэтому заодно чистит устаревшие
split-DNS записи, которые в admin console приходилось удалять руками
(`apps/casa/tailscale/README.md`).

Провайдер помечает `tailscale_dns_configuration` как **alpha**: схема может
меняться между версиями. При обновлении провайдера читать release notes, а не
только план.

### Политика (ACL)

`acl.tf` описывает файл политики tailnet целиком (`tailscale_acl`). Провайдер
проверяет политику при `plan`, поэтому синтаксическая ошибка видна до `apply`.

- `tag:k8s` объявлен и принадлежит `autogroup:admin`: под этим тегом узлы
  кластера `yc` подключаются к tailnet (`infra/yc/ansible/tailscale.yml`);
- `tag:k8s-operator` убран: он остался от Kubernetes-оператора, который ставили и
  откатили (`docs/troubleshoot/tailscale-k8s-ingress-access.md`), и через него же
  был объявлен владелец `tag:k8s`;
- `grants` перенесены как были: `src` и `dst` — `*`, то есть правило действует и
  для пользователей, и для тегированных устройств;
- `ssh`, `nodeAttrs` (Funnel) и `autoApprovers.services` перенесены как были: это
  части того же файла, и терять их при переносе нельзя;
- идентификаторов людей в файле нет: вместо email'ов `autogroup:member` и
  `autogroup:admin`. Если понадобится правило для отдельного человека или
  группы, email идёт в untracked `terraform.tfvars`, а в `acl.tf` остаётся
  переменная;
- tailnet-адресов и имён в файле нет: `hosts` не используется, адресация задана
  тегами. Причина — «внутреннее» в `docs/agents/information-handling.md`.

Файл, как и DNS, описывает политику целиком: правка в admin console
перезапишется на следующем `apply`. Решение и границы — `docs/adr/0017`.

## Первый apply

Конфигурация уже существует в admin console, поэтому `imports.tf` переносит её
в state (`id = "dns_configuration"` для DNS, `id = "acl"` для политики).
Проверять надо именно план:

```sh macOS
terraform plan
```

Ожидается `No changes`. Любое изменение означает, что конфиг расходится с admin
console, — сначала чинить конфиг, а не нажимать apply. Ресурс перезаписывает DNS
целиком, поэтому перед apply убедиться, что в плане нет удаления нужных
глобальных nameserver'ов.

У политики та же цена ошибки выше: план покажет, какие разделы из console
исчезнут (`ssh`, `nodeAttrs`, `hosts`, отдельные `grants`). Если в них есть
что-то нужное, это переносится в `acl.tf` до apply, а не после.

После apply `terraform plan` обязан быть пустым. Повторный импорт ничего не
меняет, `imports.tf` можно оставить.

## Чего модуль не делает

- **Auth keys.** `tailscale_key` кладёт сгенерированный ключ в state — запрещено
  `docs/agents/information-handling.md`.
- **Устройства** (одобрение subnet route, key expiry, теги). Отдельный этап:
  требует имён нод, которые тоже внутренние.

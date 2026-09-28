# Forgejo (Terraform)

Управляет настройками репозитория `artemiy/homelab`, защитой его ветки `main` и
пилотным pull-зеркалом `actions/checkout`. Развёртывание самого инстанса —
`apps/forgejo/` (Argo CD + `forgejo-helm`), здесь только его содержимое.

## Что управляется

| Ресурс | Объект | Что фиксирует |
| --- | --- | --- |
| `forgejo_repository.homelab` | репозиторий `artemiy/homelab` | squash — единственный стиль merge, набор unit'ов, wiki, трекер |
| `forgejo_branch_protection.main` | ветка `main` | запрет прямого push, обязательные status checks |
| `forgejo_repository.mirror["..."]` | pull-зеркала `actions/*` | upstream и интервал синхронизации |

## Запуск

С macOS: провайдер ходит в `https://forgejo.<домен>` напрямую.

Токен вводится командой ниже: ввод не отображается и не попадает в историю.

```sh macOS
cd terraform/forgejo
read -rs FORGEJO_API_TOKEN && echo
export FORGEJO_API_TOKEN
terraform init
terraform plan
```

## Доступ провайдера

Токен читается из переменной окружения `FORGEJO_API_TOKEN`. В блок `provider`
он не пишется: аргументы блока в state не сохраняются, а ресурсов с секретами
здесь вообще нет (см. «Чего модуль не делает»).

Токен заводится один раз в веб-интерфейсе: **Settings → Applications → Access
tokens → Generate new token**. Достаточно скоупа `write:repository`.

Самоподписанный сертификат Forgejo-клиент игнорировать не умеет — хост должен
отдавать сертификат, которому доверяет macOS. Публичный домен стенда этому
условию удовлетворяет; для тестового самоподписи в README провайдера есть
`openssl s_client`.

## Значения

```hcl
domain = "example.com"
```

`domain` — корневой домен стенда, а не адрес инстанса: в провайдер
подставляется `forgejo.${var.domain}`, как в `apps/forgejo`. Реальное значение —
в `terraform.tfvars`, который не коммитится.

## Импорт

`imports.tf` переносит в state три уже существующих объекта. Id импорта —
человекочитаемые, числовые ID из базы не нужны:

| Ресурс | Id |
| --- | --- |
| `forgejo_repository.homelab` | `artemiy/homelab` |
| `forgejo_branch_protection.main` | `artemiy/homelab/main` |
| `forgejo_repository.mirror["checkout"]` | `actions/checkout` |

```sh macOS
terraform init
terraform plan     # 3 to import
terraform apply    # импорт + правка write-only полей (см. ниже)
terraform plan     # No changes
```

Блоки `import` идемпотентны и остаются в репозитории: повторный импорт тех же
объектов ничего не меняет.

Если plan предлагает правку, сначала сравнить её с `curl`-выводом текущего
состояния, а не нажимать apply:

```sh macOS
curl -fsS -H "Authorization: token $FORGEJO_API_TOKEN" \
  "https://forgejo.$DOMAIN/api/v1/repos/artemiy/homelab"
curl -fsS -H "Authorization: token $FORGEJO_API_TOKEN" \
  "https://forgejo.$DOMAIN/api/v1/repos/actions/checkout"
```

## Осторожно: репозиторий и зеркала

`forgejo_repository` пересоздаёт репозиторий при изменении create-only полей —
`auto_init`, `gitignores`, `license`, `readme`, `issue_labels`, `template`,
`clone_addr`, `mirror`, `mirror_interval`. На ресурсе стоит
`lifecycle.prevent_destroy` как страховка.

Для `homelab` эти поля не заданы (они `Optional + Computed`), поэтому обычная
правка репозитория их не трогает. Поле `auth_token` содержит секрет и не задаётся.

Для зеркал `clone_addr` и `mirror` заданы намеренно и обязаны совпадать с
сервером символ в символ — см. «Зеркала actions/».

## Зеркала actions/

`mirrors.tf` описывает pull-зеркала организации `actions` картой `local.mirrors`
(имя → upstream): сейчас это 15 зеркал. Добавление зеркала — запись в карте плюс
блок `import`. `actions/cache` в карту не входит: это не зеркало, а ручной
снапшот (`apps/forgejo/README.md`).

Upstream большей части зеркал — `data.forgejo.org/actions/*`, у
`renovate-config` — `code.forgejo.org/actions/renovate-config`. Интервал у всех
`8h0m0s` и вынесен в `local.mirror_interval`. Описание генерируется из upstream:
`Mirror of <host>/actions/<name> for offline CI`.

Значения берутся из дампа сервера, потому что `mirror` и `clone_addr` —
create-only (`RequiresReplaceIfConfigured`): любое расхождение даёт
destroy+recreate. Поэтому `clone_addr` — это ровно `original_url` с сервера
(вместе с `.git`), а `mirror_interval` — гошная строка (`8h0m0s`).

Организация `actions` при этом не управляется (см. ниже): репозитории
импортируются независимо от неё.

Ненужные зеркалу unit'ы (issues, wiki, projects, packages, actions) и PR
выключены, а merge-настройки не заданы вовсе: у них статичные дефолты, а
валидатор `RequiresTrueIfConfigured` требует `has_pull_requests = true`, если
любая из них задана (даже `false` считается «configured»). При этом провайдер
читает merge-поля только когда PR включены (`from()` в `repository_resource.go`),
так что при выключенных PR они не управляются и не дрейфуют — задавать их не
нужно.

## Ограничения провайдера

**`forgejo_organization` не импортируется.** В `organization_resource.go` нет
`ResourceWithImportState`, поэтому `import` падает с `Resource Import Not
Implemented` ещё до обращения к API (это не про скоупы токена). Существующую
организацию, в частности `actions` с зеркалами экшенов, под Terraform завести
нельзя — только создавать новые. Пока организация вне модуля.

**У `forgejo_repository` часть полей write-only.** Их провайдер не читает
обратно в `Read`: `default_delete_branch_after_merge`, `wiki_branch`,
`allow_rebase_update`, `default_update_style`, `enable_prune`,
`globally_editable_wiki`, `default_allow_maintainer_edit`,
`allow_fast_forward_only`, `allow_manual_merge`, `autodetect_manual_merge`,
`auto_init`, `gitignores`, `issue_labels`, `license`, `readme`, `trust_model`,
`auth_token`, `lfs`, `lfs_endpoint`, `milestones`, `labels`, `service`,
`archive_on_destroy`. Значения таких полей берутся из конфига, а не с сервера,
поэтому дрейф по ним Terraform не увидит.

Следствие для импорта: `ImportState` выставляет `default_delete_branch_after_merge
= false` и `wiki_branch = ""`, а конфиг — серверные `true` и `main`. Первый
`apply` после импорта обновит эти два поля, но на сервере значения уже такие —
правка идёт в них же.

## Почему часть полей не задана

Все настройки, кроме обязательных, в схеме провайдера — `Optional + Computed`:
не объявив их, Terraform берёт серверное значение в state и не следит за дрейфом.
Значения, которые нужно удерживать (стиль merge, набор unit'ов), выписаны явно.
Пустые строки (`description`, `website`) не заданы: пустое значение и отсутствие
значения неотличимы на сервере.

Whitelist-поля защиты ветки (`*_whitelist_usernames`, `*_whitelist_teams`,
`push_whitelist_deploy_keys`) не заданы сознательно: сейчас все соответствующие
`enable_*_whitelist` выключены, а провайдер на уровне `ValidateConfig` запрещает
whitelist-атрибут при выключенном флаге. Когда понадобится ограничить
push/merge/approvals кругом лиц, флаги и списки добавляются вместе.

Два поля защиты провайдер не умеет: `apply_to_admins` и `ignore_stale_approvals`.
Они остаются как есть и вне Terraform.

## Чего модуль не делает

Ресурсы провайдера, чьи атрибуты содержат секреты, сюда сознательно не
заводятся — иначе секрет попадёт в локальный state (правило «Секреты в state» в
`terraform/README.md`):

- `forgejo_personal_access_token`, `forgejo_repository_action_secret` —
  токены (`PACKAGES_TOKEN` и подобные);
- `forgejo_user` — пароль пользователя;
- `forgejo_repository_webhook` — секрет вебхука;
- `forgejo_deploy_key`, `forgejo_ssh_key`, `forgejo_gpg_key` — ключи.

То же решение, что `client_secret` приложений Zitadel и уведомления Uptime Kuma.
Push-зеркало в GitHub тоже вне модуля: URL зеркала содержит токен.

Провайдер также не умеет OAuth2-приложения, защиту тегов, instance-настройки
(`app.ini`) и регистрацию раннера — последняя делается через
`forgejo-cli actions register` (`apps/forgejo/README.md`).

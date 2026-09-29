# Zitadel (Terraform)

Организация `homelab`, проект `Homelab`, OIDC-приложения, роли проекта,
членства, гранты и политика логина организации. Развёртывание самого инстанса —
`apps/zitadel/`, здесь только его содержимое.

## Запуск

С macOS нужен маршрут в домашнюю сеть (Tailscale): провайдер ходит в
`https://id.<домен>` напрямую.

```sh macOS
cd terraform/zitadel
terraform init
terraform plan
```

## Значения

```hcl
domain = "example.com"
```

`domain` — корневой домен стенда, а не адрес инстанса: в блок `provider`
подставляется `id.${var.domain}`, ровно как `ZITADEL_EXTERNALDOMAIN` в
`apps/zitadel/k8s/zitadel.deployment.yaml`. Из того же `var.domain` собираются
домен организации (`homelab.id.<домен>`) и redirect URI приложений. Реальное
значение — в `terraform.tfvars`, который не коммитится; без него Terraform
спросит его интерактивно.

## Доступ провайдера

Провайдер ходит в management API и в v2 API, поэтому service account нужна с
instance-уровнем, а не только `ORG_OWNER` в организации. Готовится один раз в
консоли Zitadel:

1. **Organization → ZITADEL → Service accounts → Add** — имя `terraform`.
   Instance-администраторы живут в отдельной организации именно для этого:
   организация приложений не должна совпадать с организацией администраторов
   инстанса.
2. **Keys → Add key → JSON → Download** — сохранить файл как
   `~/.config/homelab/zitadel-terraform.json`, `chmod 600`. В git он не идёт.
3. **Instance → Administrators → Add** — этот service account, роль
   `IAM_OWNER`.
4. **Organization → homelab → Administrators → Add** — тот же service account,
   роль `ORG_OWNER`.

Файл ключа выглядит так, `pathexpand` в провайдере разворачивает `~`:

```json
{
  "type": "serviceaccount",
  "keyId": "…",
  "key": "<приватный ключ в PEM>",
  "userId": "…",
  "serviceAccountId": "…",
  "clientId": "…"
}
```

Путь переопределяется переменной `jwt_profile_file`. Альтернатива — Personal
Access Token (`access_token`), но он долгоживущий, попадает в state и по
документации Zitadel слабее private key JWT, поэтому не используется.

## Первый apply

`imports.tf` переносит в state то, что уже создано в консоли: создания и
удаления на первом apply нет. Проверять надо именно это:

```sh macOS
terraform plan
```

Ожидается `No changes`. Любое create, update или destroy означает, что
hand-written значение в конфиге не совпало с тем, что лежит на сервере, —
сначала чинить конфиг, а не нажимать apply. После apply импорты можно удалить
одним коммитом: повторный импорт тех же объектов ничего не меняет.

План показывает правку, но `apply` может упасть — ZITADEL отклоняет обновление,
результат которого совпал с текущим. Это не тупик, а сигнал, что в конфиге
придумано значение там, где сервер ничего не отдаёт. Подробности в «Ловушках
провайдера».

## client_secret приложений

`client_secret` в `import`-блоки не попадает: это коммит секрета в публичное
зеркало. Импорт идёт без него, и это безопасно — приложения продолжают работать,
секрет не ротируется. Секрета просто нет в state и нет в output.

Секрет остаётся в Vault (`kv/oauth2-proxy/oidc` и подобные пути), оттуда его
доставляет External Secrets Operator. Если конкретный секрет потеряется,
генерируется новый через *Generate client secret* в консоли, обновляется в
Vault, приложение перечитывает его при рестарте.

Приложение, созданное `apply` (а не импортом — например `forgejo`), получает
секрет от ZITADEL, и провайдер записывает его в state. Это локальный
untracked-файл (`*.tfstate` в `.gitignore`), в публичное зеркало он не
попадает; в Vault значение кладёт человек из вывода `apply`.

## Ловушки провайдера

Проверено по исходникам v3.8.7, обе объясняют, почему конфиг такой.

**Optional, но не Computed.** В `zitadel_application_v2` `app_type`,
`auth_method_type`, `version`, `access_token_type`, `clock_skew` и
`post_logout_redirect_uris` сервер возвращает всегда, а `flattenOIDC` пишет их
в state. Не объявив их явно, plan будет постоянно предлагать перезаписать
конфигурацию приложения. Булевы поля в этом списке не нужны: unset даёт `false`
и совпадает с сервером. `clock_skew` приходит как `"0s"` — ровно так и задан.

**Длительности в login policy.** В state они попадают как
`AsDuration().String()`, то есть `240h0m0s`, а не `864000s` из protobuf.
Сравнение строковое, поэтому в конфиге нужен формат из state.

**`login_version` объявляется только там, где его реально отдаёт v2 API.** Блок
`Optional + Computed`, и `flattenOIDC` пишет его в state только когда сервер
ответил значением. Так версию вернули только Home Assistant — у него
`login_version { login_v2 {} }`, у остальных семи блока нет, и они следуют
instance feature.

Проекция `apps7_oidc_configs.login_version` для v2 API не показательна: у
Oauth Proxy, Beszel, Immich и test в ней лежит `1`, но v2 API для них значения не
возвращает. Почему они расходятся — не выяснено; на конфиг это не влияет, но
выводить `login_version` из проекции нельзя.

**ZITADEL отклоняет no-op обновления, и ресурс на этом не сходится.** Если
объявить значение, совпадающее с эффективным, plan покажет правку, apply вернёт
`FailedPrecondition: No changes (COMMAND-1m88i)`, state не обновится, и следующий
plan покажет ту же правку. Причина: `UpdateApplication` сравнивает результат с
текущим и отказывается, если разницы нет. Поэтому «безобидное» добавление
атрибута может оказаться неприменимым, и plan это не показывает — ошибка
возникает только на apply.

Пока `zitadel_instance_features.login_v2.required = true`, все приложения идут в
V2 независимо от per-app настройки: код ZITADEL в `ActiveOIDCClientByID` при
`Required` безусловно ставит `LoginVersion2`. Это подтверждено запросом к
`/oauth/v2/authorize`, который уводит на `/ui/v2/login/login?authRequest=V2_…`.

## Чего модуль не делает

- **Системные объекты.** Организация `ZITADEL`, проект `ZITADEL`, приложения
  `Management Console`, `Admin-API`, `Auth-API`, `Management-API`, service
  account `login-client`, его `IAM_LOGIN_CLIENT` и `SystemAPIUsers` из
  `apps/zitadel/config/zitadel.yaml`. Они создаются при инициализации инстанса,
  и их удаление ломает вход.
- **Human users.** `zitadel_human_user` требует initial password и конфликтует
  с passkey-only политикой из `apps/zitadel/README.md`. Пользователи остаются в
  консоли; Terraform ссылается на их ID в `iam.tf`.
- **Service account `homelab-service` и его PAT.** Импорт `zitadel_pat`
  требует само значение токена, то есть состояние с секретом и его попадание в
  командную строку. Пока аккаунт живёт руками, он вне Terraform.
- **Instance default policies и instance features.** Отдельный этап: там
  значения выведены из проекций БД, а не из API, и часть схемы имеет
  `Default`, расходящийся с тем, что отдаёт сервер (`theme_mode` =
  `THEME_MODE_AUTO` против `THEME_MODE_UNSPECIFIED`).
- **Удаление мусора.** Приложение `test`, роль `wtf` и грант пользователя
  `test` импортированы, чтобы state был полным, но не удалены.

## Следующий этап

`instance_secret_generator` — 11 генераторов на дефолтах, по ресурсу на тип;
пользы от управления ими нет.

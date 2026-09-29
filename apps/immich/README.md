# Immich

Фотографии и видео. Развёртывание — `apps/immich/k8s/`, пароль БД приходит из
Vault через External Secrets Operator.

## Вход

OIDC через Zitadel. Настраивается **в интерфейсе** — Administration →
Settings → Authentication → OAuth Authentication.

Значения, заданные в UI:

| Поле | Значение |
|---|---|
| Issuer URL | `https://id.<домен>` |
| Client ID | `388541482971234332` |
| Scope | `openid email profile` |
| Storage label claim | `preferred_username` |
| Role claim | `role` |
| Auto register | вкл. |
| Mobile redirect URI override | вкл. |
| Mobile redirect URI | `https://immich.<домен>/api/oauth/mobile-redirect` |

Client ID соответствует приложению `immich` в Zitadel
(`terraform/zitadel/applications.tf`), там же объявлены redirect URI:
`/auth/login`, `/user-settings`, `/api/oauth/mobile-redirect`.

`<домен>` — плейсхолдер: реальный корневой домен лежит в
`terraform/zitadel/terraform.tfvars` (untracked) и по
`docs/agents/information-handling.md` в git не пишется. `client_id` в таблице
при этом настоящий — он не секрет и в state лежит открытым текстом.

## Почему это не в Terraform

OIDC-конфиг Immich хранится в БД приложения, а не в конфигурации развёртывания.
Проверено по исходникам: `server/src/dtos/env.dto.ts` — схема `EnvSchema`
принимает 46 переменных, и ни одна не про аутентификацию. Env читается
`EnvSchema.safeParse(process.env)` в
`server/src/repositories/config.repository.ts` и инициализирует инфраструктуру
(БД, Redis, порты, логи); OIDC — состояние приложения, а не параметр процесса.

Описать в Terraform можно было бы через `PUT /system-config`, но:

- запрос принимает `AdminConfigDto` целиком — 22 обязательных блока
  (`backup`, `ffmpeg`, `image`, `job`, `map`, `oauth`, `server`, `theme`,
  `trash`, ...). Отправка только `oauth` затрёт остальные настройки, поэтому
  пришлось бы держать в конфиге весь системный конфиг Immich;
- авторизация — только API-ключ админа, у него доступ ко всей библиотеке;
- `clientSecret` попал бы в state и в plan открытым текстом, что противоречит
  `docs/agents/information-handling.md`.

Секрет Zitadel при этом в `terraform/zitadel` отсутствует — как и у остальных
приложений, он лежит в Vault (`kv/immich/oidc`).

Дрейф возможен: если перенастроить OIDC в UI, поправь таблицу выше.

## Роль `admin` из Zitadel

`roleClaim: role` заставляет Immich читать claim `role` из токена Zitadel.
Claim кладёт action `addRole` (`terraform/zitadel/actions.tf`) на триггере
`POST_AUTHENTICATION` — при входе в Zitadel, а не при выдаче токена.

Значение `admin` даёт админ-права в Immich, `user` — обычный доступ.
`autoRegister` создаёт пользователя при первом входе.

Действие на `POST_AUTHENTICATION` нужно именно Immich: этот триггер срабатывает
при входе в Zitadel и кладёт claim в профиль. Headlamp использует другой
триггер, `PRE_USERINFO_CREATION`, потому что apiserver проверяет подпись и
читает claim из самого токена.

## Проверка настройки

```sh
kubectl -n immich logs deploy/immich-server --since=5m | grep -i oauth
```

Значения в UI: Administration → Settings → Authentication.

## Диагностика

```sh
kubectl -n immich get pods
kubectl -n immich logs deploy/immich-server --since=10m
kubectl -n immich get vaultstaticsecret immich-db
```

Если вход не работает, проверь в Zitadel, что у пользователя есть роль в
проекте Homelab: без неё `addRole` кладёт `user`, и Immich не пустит в админку.

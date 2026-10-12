# Forgejo: эксплуатация

## Регистрация раннера

Регистрация оффлайн (без UI), идемпотентно:

```sh
SECRET=$(openssl rand -hex 20)   # 40 hex-символов
kubectl -n forgejo exec -i deploy/forgejo -c forgejo -- \
  forgejo forgejo-cli actions register --name homelab-runner \
  --secret-stdin --scope ""
```

Команда печатает UUID (это не случайное значение, а UUID из первых 16 символов
секрета) — он идёт в конфиг раннера; сам секрет — `token` в пути
`kv/forgejo/runner`. Токен в ConfigMap не попадает: раннер читает его из файла
(`server.connections.forgejo.token_url`), смонтированного из Secret'а.

## Обновление снапшота actions/cache

```sh
tmp=$(mktemp -d)
git clone --depth 1 --branch v4 https://data.forgejo.org/actions/cache.git "$tmp"
git -C "$tmp" checkout --orphan snapshot
git -C "$tmp" add -A && git -C "$tmp" commit -m "actions/cache v4 (offline snapshot)"
git -C "$tmp" tag -f v4
git -C "$tmp" push --force https://forgejo.example.com/actions/cache.git HEAD:refs/heads/main refs/tags/v4
```

## Порядок включения OIDC

1. `terraform apply` в `infra/terraform/vault` — иначе VSO не прочитает
   `kv/forgejo/oidc` (политика `app/forgejo`).
2. `terraform apply` в `infra/terraform/zitadel` — в выводе `client_id` и
   `client_secret` приложения `Forgejo`. В state и в git секрета нет
   (см. `infra/terraform/zitadel/README.md`), значения живут только в Vault.
3. Vault: `kv/forgejo/oidc` с ключами `key` и `secret`.
4. `clusters/casa/platform/forgejo/app.yaml`, поверх — приватный merge-patch с
   реальным discovery URL, затем sync и рестарт пода.
5. Привязать учётки (см. ниже) — по одной на логин.

## Привязка учёток

Порядок ручных действий — по одному на учётку: зайти в Zitadel логином
`homelab admin`, нажать в Forgejo «Sign in with Zitadel», на странице привязки
ввести локальные `forgejo-admin` и его пароль (лежит в `kv/forgejo/admin`).
То же для `artemiy` — только учётка и пароль свои.

## Проверка

```sh
kubectl -n argocd get application forgejo
kubectl -n forgejo get pods,pvc,svc,ingress

curl -fsS --resolve forgejo.example.com:443:<node1-ip> \
  https://forgejo.example.com/api/healthz   # status: pass, database:ping: pass

kubectl -n forgejo exec deploy/forgejo -- forgejo admin user list --admin

# SSH: порт открыт и отдаёт баннер Forgejo
ssh -T -p 2222 -o StrictHostKeyChecking=no git@<node1-ip>
```

Раннер:

```sh
kubectl -n forgejo get pods -l app=forgejo-runner
kubectl -n forgejo logs deploy/forgejo-runner -c runner
```

Раннер виден в UI: `/admin/actions/runners` (idle — значит зарегистрирован).

Источник OIDC:

```sh
kubectl -n forgejo exec deploy/forgejo -c forgejo -- forgejo admin auth list
```

Ожидается строка `zitadel` с типом `OAuth2` — значит init-контейнер источник
создал.

## Очистка тома dind

Том dind растёт от образов: чистить

```sh
kubectl -n forgejo exec deploy/forgejo-runner -c dind -- docker system prune -af
```

## Что проверено на живом стенде

Прогон workflow в `user/test` (`.forgejo/workflows/smoke.yml`), 14 job'ов:
работают `actions/checkout@v6`, node-экшены, `docker build`/`docker run` внутри
dind, сервис-контейнеры (`services:`), матрицы, `needs`/outputs, кэш
(`actions/cache@v4` save/restore), `jobs.<id>.container`, доступ к API через
`${{ github.token }}`.

Там же проверены `release.yml` (тег + опубликованный релиз с ассетами) и
`packages.yml` (push образа в реестр контейнеров и generic-пакет через PAT).

## Сборка языков

В `user/test` лежат hello-world проекты со своими workflow'ами: `go/`,
`node/`, `python/`, `java/`, `rust/`, `bun/` и одноимённые `build-*.yml`. Все
собираются и тестируются на раннере.

Общие грабли:

- **Неявного checkout у раннера нет.** Без `actions/checkout` рабочая директория
  пустая (`/workspace/<owner>/<repo>`), так что checkout нужен везде.
- **`actions/checkout` — node-экшен.** В языковых образах (`rust:1`,
  `python:3.x`, `oven/bun`) node нет, поэтому там он не отработает. Либо ставить
  тулчейн шагом в стандартный образ (где node есть), либо брать языковой образ и
  клонировать репозиторий вручную (в `rust`/`python` git есть).

По языкам:

- **Go** — `actions/setup-go@v5` работает, тулчейн качается с go.dev.
- **Node** — `actions/setup-node` зависает: с мажорной версией не может получить
  список версий (`actions-versions.githubusercontent.com` отдаёт 500), с точной
  скачивает Node и всё равно висит на `dist/setup/index.js`. Берём образ
  job-контейнера `node:NN-bookworm`.
- **Python** — 3.10 уже в образе; тест на stdlib `unittest`, ставить нечего.
- **Java** — `actions/setup-java` в зеркале нет. Через `apt` доступен **JDK 25**,
  но Maven из Ubuntu 22.04 (3.6.3) для него слишком старый — качаем Maven 3.9.9
  с archive.apache.org. Плагины в `pom.xml` нужно пинить
  (`maven-compiler-plugin` 3.13.0 с `release`, `surefire` 3.5.x), иначе дефолтный
  компилятор 3.1 падает с «Source option 5 is no longer supported».
- **Rust** — `rustup` тянет тулчейн со `static.rust-lang.org`, и это периодически
  таймаутит. Берём образ `rust:1-bookworm` и клонируем репо сами.
- **Bun** — скрипт `bun.sh/install` качает бинарь из GitHub-релиза и падает по
  таймауту; `npm install -g bun` берёт тот же бинарь из registry.npmjs.org.

Грабли:

- **Артефакты только `@v3`.** `upload-artifact`/`download-artifact` `@v4+`
  используют `@actions/artifact v2` и новый API, которого в Forgejo нет —
  падают с `GHESNotSupportedError`. Использовать `@v3`.
- **`GITHUB_SERVER_URL` внутренний.** Job'ы получают `http://forgejo-http`
  (адрес из `server.connections`), а не публичный URL. Checkout и API по нему
  работают, но ссылки, которые экшены печатают в лог, будут внутренними.
  Публичный URL в конфиге даст красивее ссылки, но добавит зависимость от
  Traefik и DNS.

## Обновление

1. Посмотреть release notes Forgejo и тег чарта (`forgejo-helm` на Codeberg).
2. В `clusters/casa/platform/forgejo/app.yaml` поднять `targetRevision` (тег чарта) и
   `image.tag`/`image.digest` (образ Forgejo) — это две независимые вещи.
3. Дождаться sync: правка в git доезжает сама, отдельная команда не нужна.
4. Миграции схемы выполняет init-контейнер чарта (`forgejo migrate`); если он
   циклится, смотреть его логи: обычно это недоступная база.

Откат — вернуть прежние теги в values коммитом. Образ и чарт пинятся по
версии/дайджесту, поэтому откат детерминированный.

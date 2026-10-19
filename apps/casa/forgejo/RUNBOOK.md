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

## Смена образа job-контейнера

Метки (`runs-on`), дайджесты образов и лимиты job'ов — в ConfigMap'е
`forgejo-runner` (`manifests/runner.configmap.yaml`). Argo применяет его сам, но
job'ы переключаются только после перезапуска пода: раннер читает конфиг при
старте, а автоматического рестарта на изменение ConfigMap'а нет.

```sh
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl -n forgejo rollout restart deploy/forgejo-runner
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl -n forgejo rollout status deploy/forgejo-runner
```

Перезапуск обрывает job'ы, которые уже идут: их поды умирают вместе с раннером, а
в UI прогон остаётся в статусе `running` навсегда. Поэтому перезапускать раннер
перед сменой образа стоит, когда очередь пуста, а оборванные прогоны — заводить
заново руками.

Образ для job'ов тянет dind, а не containerd узла, поэтому проверяется он из
сайдкара — дайджест должен совпасть с меткой в ConfigMap'е:

```sh
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl -n forgejo exec deploy/forgejo-runner -c dind -- docker images
```

## Обновление actions/cache

`actions/cache` — не mirror, а репозиторий с **реальной историей** апстрима,
долитой вручную: mirror-миграцию Forgejo валит объект `largePathname` в старой
истории `cache` (`fsck error in packed object`), а обычный `git fetch` fsck не
включает. Историю затягиваем изнутри пода:

```sh
kubectl -n forgejo exec deploy/forgejo -- sh -c '
cd /data/git/gitea-repositories/actions/cache.git &&
git remote remove upstream 2>/dev/null;
git remote add upstream https://github.com/actions/cache.git &&
git fetch --prune upstream "+refs/heads/*:refs/heads/*" "+refs/tags/*:refs/tags/*" &&
git remote remove upstream'
```

Теги нужны целиком: экшены (`setup-trivy`, `trivy-action`) пинят `actions/cache`
по конкретному SHA (`v5.0.1`, `v5.0.5`, `v6.1.0` …), а снапшот одного коммита их
теряет. Автообновления нет — это не mirror; новые теги подтягиваются тем же
`git fetch`.

Проверка:

```sh
git ls-remote https://forgejo.example.com/actions/cache.git | grep -E 'refs/tags/v[456]$'
```

## Порядок включения OIDC

1. `terraform apply` в `infra/casa/terraform/vault` — иначе VSO не прочитает
   `kv/forgejo/oidc` (политика `app/forgejo`).
2. `terraform apply` в `infra/casa/terraform/zitadel` — в выводе `client_id` и
   `client_secret` приложения `Forgejo`. В state и в git секрета нет
   (см. `infra/casa/terraform/zitadel/README.md`), значения живут только в Vault.
3. Vault: `kv/forgejo/oidc` с ключами `key` и `secret`.
4. `clusters/casa/argocd/platform/forgejo.yaml`, поверх — приватный merge-patch с
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

## Учётная запись бота Renovate

Renovate ходит в Forgejo под отдельной учёткой: ветки и PR подписаны ботом, а
токен отзывается, не задевая личные доступы.

Пользователь заводится из админского UI (`https://forgejo.<домен>/admin/users/new`):
логин `renovate-bot`, полное имя `Renovate Bot`, почта любая — Forgejo её не
проверяет. Затем учётке нужно право записи в репозитории: репозиторий →
Settings → Collaborators → `renovate-bot` с доступом **Write**.

Токен выпускается под самим ботом (Settings → Applications), scope:
`read:repository`, `write:repository`, `read:issue`, `write:issue`, `read:user`.
Чужому пользователю токен через API не выпустить — нужен вход под ботом.

## Секрет Renovate в Vault

```sh
vault kv put kv/forgejo/@renovate/token RENOVATE_TOKEN=<pat>
```

Право чтения даёт политика `app/forgejo`; её текст — в
`infra/casa/terraform/vault/policies/issued.tf`, применяется с macOS:

```sh
cd infra/casa/terraform/vault && terraform apply
```

Vault Secrets Operator приносит значение в Secret:

```sh
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl -n forgejo get secret forgejo-renovate
```

Ожидается Secret с ключом `RENOVATE_TOKEN` и непустым значением.

## Прогон Renovate вручную

Расписания ждать не обязательно:

```sh
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl -n forgejo create job --from=cronjob/renovate renovate-manual
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl -n forgejo logs -f job/renovate-manual
```

В логе ожидаются `Repository started`, `Dependency extraction complete` со
счётчиком зависимостей и созданные ветви. Пустая выдача без ошибок поломкой не
является: если обновлять нечего, Renovate не создаёт ничего.

Дальше смотреть в Forgejo: issue `Dependency Dashboard` — список найденного,
включая отложенное из-за лимита; ветви `renovate/*` и PR от учётки бота.

## Токен github.com для Renovate

Нужен, чтобы подтягивались release notes и не упираться в анонимный лимит GitHub
(60 запросов в час). Токен — **классический, без скоупов**: публичных данных
достаточно, а лишние права ни к чему. Подойдёт и fine-grained с одним
разрешением «Public repositories → read».

```sh
vault kv put kv/github/api-token RENOVATE_GITHUB_COM_TOKEN=<pat>
```

Право чтения — в политике `app/forgejo`, применяется с macOS:

```sh
cd infra/casa/terraform/vault && terraform apply
```

Проверка — следующим прогоном задания: в дашборде не должно быть строк
`GitHub token is required for some dependencies` и `No github.com token has been
configured`. Ключ в Secret необязательный, поэтому под стартует и без него —
просто без release notes.

## Прокси 3x-ui для Renovate

Renovate ходит наружу через HTTP-прокси `xui-egress`: реестр HashiCorp и часть
других апстримов режут запросы из этой сети по геолокации. Учётная запись у
прокси отдельная на потребителя и заводится в панели 3x-ui вручную (как для
`gatus` и `dns01-webhook`), в базу панели, а не в окружение.

```sh
vault kv put kv/3x-ui/@renovate/egress \
  username=renovate password=<пароль>
```

Пароль подставляется в URL прокси, поэтому допустимы только буквы, цифры и
`-`, `_`, `.`: `@`, `:`, `/`, `#`, `%` и пробелы ломают разбор. Право чтения —
в политике `app/forgejo` (`infra/casa/terraform/vault`), применяется с macOS:

```sh
cd infra/casa/terraform/vault && terraform apply
```

Порт прокси открыт для namespace `forgejo` в NetworkPolicy чарта 3x-ui — без
этого соединения из пода отбиваются по политике, и в логе задания видно
`connection refused`.

Проверка — прогоном:

```sh
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl -n forgejo create job --from=cronjob/renovate renovate-manual
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl -n forgejo logs -f job/renovate-manual
```

Признак, что прокси работает: в логе больше нет `Failed to look up
terraform-provider package …: no-result` — версии провайдеров находятся все
восемь. Если они снова пропали, а прокси отвечает — смотреть пару в Vault и
совпадение ключей в Secret:

```sh
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl -n forgejo get secret forgejo-renovate-egress \
  -o go-template='{{range $k,$v := .data}}{{$k}}{{"\n"}}{{end}}'
```

Ожидаются `username` и `password`.

## Кэш Renovate

Метаданные реестров и инструменты, которые Renovate ставит сам, лежат на томе
`forgejo-renovate-cache`. Том помечен `Prune=false` — Argo его не удаляет, — и
содержимое его восстановимо: это кэш, а не данные.

```sh
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl -n forgejo get pvc forgejo-renovate-cache
```

Холодный прогон (например, если кэш подозревается в порче): удалить том, Argo
создаст его заново.

```sh
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl -n forgejo delete pvc forgejo-renovate-cache
```

## Ротация токена бота

1. Отозвать PAT под ботом: Settings → Applications → Revoke.
2. Выпустить новый и положить тем же `vault kv put` (см. выше).
3. Следующий прогон возьмёт новое значение: Secret обновляет VSO, а само задание
   читает токен при старте.

## Что проверено на живом стенде

Прогон workflow в `user/test` (`.forgejo/workflows/smoke.yml`), 14 job'ов:
работают `actions/checkout@v6`, node-экшены, `docker build`/`docker run` внутри
dind, сервис-контейнеры (`services:`), матрицы, `needs`/outputs, кэш
(`actions/cache@v6` save/restore), `jobs.<id>.container`, доступ к API через
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
- **`GITHUB_SERVER_URL` внутренний.** Job'ы получают
  `http://forgejo-http.forgejo.svc.cluster.local` (адрес из `server.connections`),
  а не публичный URL. Checkout и API по нему работают, но ссылки, которые экшены
  печатают в лог, будут внутренними.
  Публичный URL в конфиге даст красивее ссылки, но добавит зависимость от
  Traefik и DNS.

## Обновление

Чарт и образ обновляются независимо: тег чарта — `targetRevision` в
`clusters/casa/argocd/platform/forgejo.yaml`, образ — `image.tag` и
`image.digest` в `platform/casa/forgejo/values.yaml`. Чарт рендерит
`<tag>@<digest>`, то есть разворачивается именно дайджест: поднятый без дайджеста
тег на стенде ничего не меняет. Дайджест версии:

```sh
crane digest data.forgejo.org/forgejo/forgejo:<версия>-rootless
```

Мажор необратим: миграции схемы БД идут только вперёд, поэтому откат образа на
прежний дайджест после первого старта новой версии не поднимется.

1. Прочитать release notes Forgejo (раздел breaking changes) и сверить их с
   конфигурацией из values.

2. Бэкап: дамп базы и снапшот тома с репозиториями и вложениями.

   Дамп пишется в файл внутри пода, а не в поток на macOS: поток через
   `kubectl exec` рвётся на этом канале, а оборванный `pg_dump` остаётся жить в
   базе и держит блокировки — так миграция на старте новой версии встаёт в
   ожидании `ALTER TABLE`.

   ```sh
   kubectl -n databases exec shared-1 -c postgres -- sh -c \
     'pg_dump -U postgres -d forgejo -Fc -f /var/lib/postgresql/data/forgejo-pre-upgrade.dump &&
      pg_restore -l /var/lib/postgresql/data/forgejo-pre-upgrade.dump | wc -l'

   kubectl cp databases/shared-1:/var/lib/postgresql/data/forgejo-pre-upgrade.dump \
     -c postgres ./forgejo-$(date +%F).dump
   ```

   Файл остаётся в томе базы до удаления руками, поэтому копию на macOS можно
   снять и позже. Дальше — снапшот тома:

   ```sh
   kubectl apply -f - <<EOF
   apiVersion: snapshot.storage.k8s.io/v1
   kind: VolumeSnapshot
   metadata:
     name: forgejo-data-pre-upgrade
     namespace: forgejo
   spec:
     volumeSnapshotClassName: longhorn-snapshot
     source:
       persistentVolumeClaimName: forgejo-data
   EOF
   ```

   Снапшот лежит в Longhorn на том же узле: от неудачной миграции он спасает, от
   потери узла — нет, backup target не настроен.

3. Дренировать очереди на текущей версии — они содержат сериализованные данные,
   которые между версиями несовместимы:

   ```sh
   kubectl -n forgejo exec deploy/forgejo -c forgejo -- forgejo manager flush-queues
   ```

4. Поднять `image.tag` и `image.digest` в values (плюс `targetRevision`, если
   вышел чарт под новый мажор).

5. Дождаться sync: правка в git доезжает сама, отдельная команда не нужна.
   Миграции схемы выполняет init-контейнер чарта (`forgejo migrate`); если он
   циклится, смотреть его логи: обычно это недоступная база.

6. Проверить по разделу «Проверка», плюс `forgejo doctor check --all --log-file
   /tmp/doctor.log` в поде, вход по OIDC, push по ssh и прогон workflow.
   В выводе doctor ожидаема одна ошибка — `/data/log` не существует: каталога
   нет, потому что логи идут в console (`[log] MODE` не переопределён).

7. Когда новая версия отстоится — удалить дамп из тома базы и VolumeSnapshot:

   ```sh
   kubectl -n databases exec shared-1 -c postgres -- \
     rm /var/lib/postgresql/data/forgejo-pre-upgrade.dump
   kubectl -n forgejo delete volumesnapshot forgejo-data-pre-upgrade
   ```

# Forgejo

Forgejo — лёгкая self-hosted Git-платформа (форк Gitea), которая задумана как
основной дом для этого репозитория.

URL — `https://forgejo.example.com/`, Git over SSH —
`ssh://git@forgejo.example.com:2222/OWNER/REPO.git`.

Самостоятельная регистрация выключена, новые репозитории и профили приватны.

Домен, `service.ssh.externalIPs` и discovery URL Zitadel заданы прямо в
`valuesObject` (см. `docs/adr/0009`). Credentials — пароль админа,
`client-secret` — приходят из Vault и в values не попадают: в Application лежат
ссылки `existingSecret`.

## Как развёрнуто

Официального Helm-чарта у Forgejo нет; де-факто стандарт — **forgejo-helm** из
организации `forgejo-contrib` на Codeberg (форк чарта Gitea под Forgejo:
внешняя база, rootless-образ, admin-пользователь и метрики из коробки).

Две вещи, которые важно знать про этот чарт:

- **`appVersion` в git-дереве неверный.** В `Chart.yaml` на теге `v16.0.1`
  лежит `appVersion: 14.0.1` — настоящий appVersion подставляется только в
  OCI-артефакт при релизе. Поэтому `image.tag` и `image.digest` заданы явно,
  иначе Argo развернул бы Forgejo 14. Тег/дайджест — те же, что были в
  манифестах до переезда на чарт.
- **Веб-мастера установки нет.** Чарт всегда ставит `INSTALL_LOCK=true`, вся
  конфигурация приезжает из values, а админ создаётся init-контейнером.

## Actions и runner

Forgejo Actions — CI/CD из `.forgejo/workflows/`, синтаксис близок к GitHub
Actions. Сервер только планирует задачи и хранит логи с артефактами; исполняет
их отдельный процесс **Forgejo Runner**.

Два контейнера в одном поде: `runner` и `dind` (`docker:dind`). Они делят
сетевой namespace, поэтому раннер ходит к dockerd по `tcp://127.0.0.1:2375`, а
job-контейнеры внутри dind достают тот же демон по имени `dind`
(`--add-host=dind:host-gateway`). Job'ы получают Docker, но не демон узла: у
dind свой `/var/lib/docker` на PVC. Том — `local-path`, а не Longhorn: кластер
одноузловой, у Longhorn одна реплика (избыточности нет), а кэш образов можно
потерять без последствий; Longhorn остаётся под важными данными. `local-path`
не enforce'ит квоту — размер тома лишь заявка, реальный предел задаёт очистка
(`docker system prune`, ниже).

**Конкурентность workflow.** По умолчанию Forgejo отменяет предыдущий прогон
того же workflow при новом событии `push` или `pull_request (synchronize)`:
«If no concurrency settings are provided, Forgejo will automatically manage the
concurrency of a workflow that is executed by the `on.push` and `on.pull_request`
(synchronize) events in the following manner: whenever a new event triggers a new
workflow invocation, any other invocations of the same workflow will be canceled
automatically»
([Forgejo Actions reference, раздел `concurrency`](https://forgejo.org/docs/latest/user/actions/reference/#concurrency)).
Там, где это нежелательно (важен результат каждого коммита, а не только
последнего), в workflow задаётся `concurrency: { cancel-in-progress: false }` —
без `group` Forgejo перестаёт управлять конкурентностью: «If evaluated to
`false`, then no concurrency management will occur»
([`concurrency.cancel-in-progress`](https://forgejo.org/docs/latest/user/actions/reference/#concurrencycancel-in-progress)).

Это поведение именно Forgejo, а не общая грамматика Actions: у GitHub отмена
существует только внутри объявленной группы, «The default behavior of GitHub
Actions is to allow multiple jobs or workflow runs to run concurrently»
([Control the concurrency of workflows and jobs](https://docs.github.com/en/actions/how-tos/writing-workflows/choosing-what-your-workflow-does/control-the-concurrency-of-workflows-and-jobs)).
Поэтому в парном наборе `.github/workflows/` блока `concurrency` нет ни в одном
файле: отсутствие блока и даёт то поведение, которое `040-commitlint` и
`080-secrets` просят явно. Число одновременно исполняемых job'ов ограничивает
`runner.capacity` в ConfigMap'е (сейчас `4`); параллельные job'ы делят dockerd
сайдкара. Лимиты ресурсов задаются там же, в `container.options`
(`--cpus`/`--memory`): job'ы создаёт внутренний dockerd, и лимиты контейнеров
runner/dind на них не распространяются.

**Очередь задач и имена файлов workflow.** При `capacity: 4` задачи ждут слота, и
порядок ожидания задаёт не джоб, а имя файла workflow: Forgejo обходит каталог
`.forgejo/workflows` по алфавиту и в этом же порядке выдаёт номера задач, а раннер
забирает их по возрастанию номера. Поэтому имя файла — это приоритет выдачи, и
тяжёлые гейты названы так, чтобы попадать в первую волну: `010-ansible.yml`
(ansible-lint ~46 с), `020-trivy.yml` (~30 с), `030-kubeconform.yml` (~20 с),
дальше по убыванию, номера с шагом 10 для вставки новых. Порядок по алфавиту без
префиксов ставил самое долгое в конец — `trivy` стартовал после восьми лёгких
джобов и заканчивался последним в 100 группах из 152 (замеры и модель — issue
#1168). Переименование файла меняет только `workflow_id` в API и URL прогона;
имя проверки в PR собирается из `name:` и имени джоба и не меняется.

**Метки** (`runs-on`) и образы заданы в ConfigMap'е. `ubuntu-latest` и
`ubuntu-24.04` указывают на `ghcr.io/catthehacker/ubuntu:act-24.04` (Ubuntu
24.04, python 3.12), `ubuntu-22.04` — на `act-22.04` и оставлена для отката.
Ссылка несёт и тег, и дайджест (`:act-24.04@sha256:…`): резолвится дайджест —
docker по тегу уже скачанный образ не обновляет, — а тег называет версию.
Вариант `act-*` — slim-сборка с git, docker CLI, python и node; `full-*` — копия
полного GitHub-образа на десятки GB, гейтам не нужна. Голый `node:lts` не
подходит: в нём нет docker CLI, и `docker build` в job'е падает.
Смена дайджеста переключает job'ы только после перезапуска пода раннера —
конфиг читается при старте (`RUNBOOK.md`).

**Кэш образов.** Job-образы тянутся не напрямую из внешних реестров, а через
pull-through кэш **Zot** (`clusters/casa/apps/zot`): в метках указан путь
`zot.zot.svc.cluster.local/<реестр>/...` с тем же дайджестом. Zot отдаётся
по http, поэтому его хост добавлен в `insecure-registries` через конфиг
dockerd раннера (монтируется в сайдкар `dind`). Дайджесты и ограничения
(Docker-демон умеет mirror только для Docker Hub) — в
`clusters/casa/apps/zot/README.md`.

Безопасность: раннер — это RCE по определению. Область instance-wide означает,
что workflow любого репозитория инстанса может запускать job'ы; при появлении
внешних контрибьюторов раннер надо сузить до репозитория/организации или
вынести на отдельную ВМ. Кэш держит сам раннер (`emptyDir`, теряется при
рестарте), логи и артефакты — Forgejo (ретеншн `actions.LOG_RETENTION_DAYS` /
`ARTIFACT_RETENTION_DAYS`, по умолчанию 365/90 дней). Том dind растёт от
образов — очистка в `RUNBOOK.md`.

### Зеркало экшенов

Раннер забирает экшены (`uses: actions/...`) **с локального инстанса**, а не с
`data.forgejo.org`: тот периодически недоступен (мониторится в Gatus), и job
падает на загрузке экшена ещё до старта шагов. Задаёт источник
`actions.DEFAULT_ACTIONS_URL` в `valuesObject` (`http://forgejo-http`).

Настройка **instance-wide**: любой `uses: <owner>/<repo>` без схемы
разворачивается в `<URL>/<owner>/<repo>`, поэтому под локальным инстансом должен
быть весь используемый набор. В организации `actions` зазеркалены все 15
репозиториев из `data.forgejo.org/actions` (плюс `setup-java`); все public,
чтобы раннер клонировал их анонимно. Native mirror'ы Forgejo обновляются сами
(`mirror_interval: 8h`). Сторонние экшены (`<owner>/<repo>` не из `actions`)
тоже пойдут на локальный инстанс — их нужно зазеркалить в соответствующий owner;
`uses: ./local` и `docker://...` это не затрагивает.

Исключение — `actions/cache`: это не mirror, а репозиторий с **реальной
историей** апстрима, долитой вручную. Миграцию mirror'а Forgejo валит на объекте
со сверхдлинным путём (`largePathname`) в старой истории `cache`
(`fsck error in packed object`), поэтому историю затягивает обычный `git fetch`
внутри пода — он fsck не включает. Снапшот одного коммита (как было раньше)
теряет теги и SHA выше `v4`, а экшены вроде `setup-trivy` пинят `actions/cache`
по конкретному SHA. Обновление — вручную, тем же `git fetch`; команды — в
`RUNBOOK.md`.

### Релизы и пакеты

**Релизы** работают с автоматическим токеном workflow (у него есть write на
репозиторий, кроме событий `pull_request` из форка). Официальный экшен
`actions/forgejo-release@v2` создаёт тег (если его нет), **draft**-релиз и
заливает файлы из `release-dir` как assets. Draft публикуется отдельным шагом
через `PATCH /repos/{owner}/{repo}/releases/{id}` — экшен сам этого не делает:

```yaml
- uses: actions/forgejo-release@v2
  with:
    direction: upload
    tag: ${{ github.ref_name }}
    token: ${{ github.token }}
```

**Пакеты** требуют отдельного токена. Автоматический токен workflow даёт write
на репозиторий, но не на пакеты — `docker push` и `PUT /api/packages/...`
возвращают `401`. Нужен personal access token со scope `write:package` (+
`read:repository`), положенный секретом (например, `PACKAGES_TOKEN`) в
Settings → Actions → Secrets репозитория. Детали:

- реестр контейнеров — публичный хост Forgejo (`docker login`/`docker push` по
  `forgejo.example.com`). Внутренний `github.server_url`
  (`http://forgejo-http`) не годится: там нет TLS;
- реестр пакетов живёт под `/api/packages/{owner}/...`, а не `/api/v1`;
- generic-пакеты: `PUT /api/packages/{owner}/generic/{package}/{version}/{file}`;
- **пакет не привязывается к репозиторию сам.** URL push'а содержит только
  владельца, поэтому пакет виден на `/{owner}/-/packages`, а во вкладке Packages
  репозитория (`/{owner}/{repo}/packages`) его нет. Привязка отдельная:
  `POST /api/v1/packages/{owner}/{type}/{name}/-/link/{repo}` (нужен
  `write:package`) либо вручную: версия пакета → Settings → выбор репозитория.
  Для повторных версий привязка сохраняется — линковать нужно один раз.

## Обновления зависимостей

Обновления предлагает Renovate: он запускается заданием по расписанию в этом
неймспейсе, ходит в Forgejo под отдельной учётной записью бота и открывает PR из
ветвей `renovate/*`. Перечень найденного живёт issue `Dependency Dashboard` в
самом репозитории — это источник правды о том, что ждёт обновления.

Почему здесь, а не в job'ах раннера: Renovate обращается наружу — на github.com
за релизами и changelog, в реестры образов, в registry.terraform.io, — а job'ы
идут через кэш и до части внешних хостов не дотягиваются. Токен ему выдаёт
Forgejo, поэтому рядом с ним он и живёт.

Учётка бота отдельная намеренно: PR и коммиты подписаны ботом, а не человеком, а
отзыв токена не задевает личные доступы. Подпись коммитов задана явно
(`RENOVATE_GIT_AUTHOR`), потому что она уезжает в публичное зеркало вместе с
ветками. Политика обновлений лежит в `renovate.json` в корне репозитория, а не в
манифесте: её читает Renovate, а не кластер.

Отдельный токен есть и на github.com: Renovate ходит туда за release notes и
частью инструментов, а анонимный лимит — 60 запросов в час на IP, чего при
семидесяти с лишним зависимостями в Actions не хватает. Это кред внешнего
провайдера, поэтому лежит он в `kv/github/`, а не рядом с секретом Renovate:
значение одно на кластер, а доступ выдаётся строкой в политике потребителя
(`docs/adr/0006`). Достаточно токена на чтение — ни один скоуп ему не нужен.

**Наружу — через прокси 3x-ui.** Часть апстримов режет запросы из этой сети:
реестр HashiCorp отвечает `x-amzn-waf-reason: geo` и страницей «Content not
available in your region», из-за чего версии terraform-провайдеров не находились
вовсе, а `releases.hashicorp.com` и `registry.opentofu.org` отвечали тем же. Через
HTTP-прокси `xui-egress`, который выходит в другой стране, находятся все восемь.
Учётка у прокси своя на каждого потребителя — как у Gatus и DNS-01-webhook; в
Vault это пара `username`/`password`. Внутренние адреса (Forgejo и
`*.svc.cluster.local`) идут мимо прокси: возвращаться к своему же инстансу из
чужой страны незачем. Туда же — реестр Yandex Cloud: он российский, и через
зарубежный выход запрос к нему висит до таймаута, хотя напрямую отвечает за
доли секунды.

**Чего Renovate не умеет у нас.** Версия bun зашита в трёх местах сразу: в
`artifacts.tsv` (это зеркало в RustFS), в `tools.tsv` devcontainer'а и в
`bun-download-url` workflow. Renovate видит только последнее, и такой PR ломает
CI по существу — скачивается старая версия из зеркала, а номер в манифесте
меняется. Поэтому обновление этой зависимости выключено правилом в
`renovate.json`, а версия bun поднимается руками и синхронно во всех четырёх
местах. Так же руками — версии в `artifacts.tsv` и `tools.tsv`.

**Кэш переживает прогон.** Renovate хранит метаданные реестров и инструменты,
которые ставит сам, в `cacheDir`; у задания это том на Longhorn, а не `emptyDir`.
Без тома каждый запуск заново тянет метаданные всех зависимостей и заново
распаковывает инструменты — при выходе через прокси это десятки минут. Том взят
без `retain`: содержимое кэша восстановимо, а держать его после удаления PVC
незачем.

**Частный реестр.** Образ `structurizr` лежит в Yandex Cloud Registry, и без
учётных данных Renovate не может получить его digest — в логе это
`Could not determine new digest for update`. Ключ уже есть в Vault для самого
structurizr; здесь он подставляется в переменные окружения, из которых Renovate
собирает `hostRules` (`detectHostRulesFromEnv`), потому что в конфиге репозитория
секретов быть не может.

**Мажоры не приезжают PR'ом.** Обновление на новую мажорную версию ждёт
подтверждения в дашборде: пока галочка не поставлена, ветка и PR не создаются.
Причина простая — мажор здесь это чаще всего платформа или хранилище данных
(сам Forgejo, база образов, Redis для nextcloud и dawarich), и такое решение
принимается отдельно, а не вместе с рутиной.

**Очередь обновлений.** Число одновременных PR ограничено
(`prConcurrentLimit`), поэтому предложения сверх него ждут в разделе
`Rate-Limited` дашборда: чекбокс рядом с пунктом создаёт PR немедленно, а по мере
мержей слоты освобождаются сами. Почасового лимита нет (`prHourlyLimit: 0`) — он
сдерживал только первый прогон, когда обновлений накопилось больше, чем слотов.

**Теги образов в манифестах.** Зависимости из `Dockerfile`, `compose.yaml` и
`values.yaml` Renovate видит сам, а теги образов в манифестах юнитов — только
после того, как ему сказано, где их искать: у менеджера `kubernetes` нет
файловых шаблонов по умолчанию, потому что общего соглашения об именовании
манифестов не существует. Шаблон задан на `clusters/casa/**/manifests/`, где
лежат манифесты обоих видов юнитов. Образы, зашитые в ConfigMap (метки
`runs-on` раннера), он не видит — их по-прежнему обновляют руками.

**Заголовки PR ограничены.** Тема PR становится темой squash-коммита вместе с
` (#<n>)`, а `commitlint` держит заголовок в 70 символов. Поэтому в теме
docker-зависимостей стоит только имя образа — без реестра и пути (`replace` в
`commitMessageTopic`), — а для имён, которые длинны и сами по себе
(`opentelemetry-collector-contrib`), задан короткий топик. Иначе PR не смержить:
гейт краснеет на самом PR, а если смержить вопреки — остаётся красным на push в
`main`, потому что линтится уже собранная тема коммита.

## Хранилище

`persistence.claimName: forgejo-data`, класс `longhorn-retain`, 5Gi. Стратегия
деплоймента — `Recreate` (дефолт чарта): том RWO, два пода одновременно его не
смонтируют. Менять имя PVC после установки нельзя — это будет новый том.

Что лежит в томе: `git/repositories` (сами репозитории), LFS-объекты,
вложения, аватары, `custom/` и сгенерированный `gitea/conf/app.ini`. **База — не
здесь**: она в CNPG. Для полного восстановления нужны обе половины.

## База

Кластер `shared` (namespace `databases`), роль `forgejo`, база `forgejo`.
Подключение идёт на `shared-rw.databases.svc.cluster.local:5432`, доступ
разрешён в `clusters/casa/platform/cnpg/manifests/networkpolicy.yaml` (`allow-shared-from-consumers`).

Пароль роли лежит в `databases/forgejo-db-auth` и он же — в `forgejo/forgejo-db`,
оба из пути `kv/forgejo/db`.
Подставляется в
app.ini через `FORGEJO__database__PASSWD` из `gitea.additionalConfigFromEnvs`,
поэтому секрет чарту не нужен.

## Merge-сообщения

Тело merge/squash-коммита задаёт серверный шаблон
`{CustomPath}/default_merge_message/SQUASH_TEMPLATE.md` (`CustomPath` — это
`/data/gitea`, не `/data/git`). Файл приезжает из ConfigMap
`forgejo-merge-message` через `extraVolumes`/`extraContainerVolumeMounts`
и делает тело пустым: без него Forgejo дописывает `Reviewed-on: <url>`, а это
внутренний домен, которого не должно быть в публичной истории (#25).

Шаблоны Forgejo читает один раз при старте, поэтому после правки ConfigMap нужен
рестарт пода. Есть и per-repo вариант — `.gitea/default_merge_message/` в базовой
ветке репозитория (в 16.0.2 путь `.forgejo/` не читается), но он переопределяет
шаблон только для одного репозитория.

`fj pr merge` шаблон для тела не использует и без `-m` дописывает
`Reviewed-on: <url>` сам, поэтому мёржить нужно с `-m ""`
(`docs/agents/commit-conventions.md`).

## Секреты

| Путь Vault | Ключи | Secret | Кто читает |
|---|---|---|---|
| `kv/forgejo/db` | `username`, `password` | `forgejo-db` | чарт (env → app.ini) |
| `kv/forgejo/@monitoring/forgejo-metrics-token` | `FORGEJO_METRICS_TOKEN` | `forgejo-metrics` | чарт (env → app.ini) |
| `kv/forgejo/@renovate/token` | `RENOVATE_TOKEN` | `forgejo-renovate` | CronJob `renovate` |
| `kv/github/api-token` | `RENOVATE_GITHUB_COM_TOKEN` | `forgejo-renovate-github` | CronJob `renovate` |
| `kv/3x-ui/@renovate/egress` | `username`, `password` | `forgejo-renovate-egress` | CronJob `renovate` (egress) |
| `kv/yc/cloud-registry` | `key` | `forgejo-renovate-yc` | CronJob `renovate` (частный реестр) |
| `kv/forgejo/admin` | `username`, `password` | `forgejo-admin` | чарт (init-контейнер) |
| `kv/forgejo/runner` | `token` | `forgejo-runner` | регистрация раннера |
| `kv/forgejo/oidc` | `key`, `secret` | `forgejo-oidc` | чарт (init-контейнер) |

Все девять — `VaultStaticSecret`, значения в Vault заводит человек.

**Про админа:** это служебная учётка (`forgejo-admin`, почта
`admin@example.com`), а не личный аккаунт человека: роль в сервисе и
человек — разные сущности, у них разные пароли и разные последствия утечки.
Логин `admin` использовать нельзя — Forgejo резервирует это имя («name is
reserved»), поэтому имя с суффиксом сервиса; почта при этом короткая.

Режим `initialOnlyNoReset`: чарт выставляет пароль при создании пользователя и
больше его не трогает (режим `keepUpdated` перетирал бы пароль при каждом
рестарте пода). Важно: чарт создаёт админа только если такого пользователя ещё
нет — на живом стенде он его не создал, потому что в базе уже был другой админ;
после пересоздания базы учётки заведены руками (`forgejo admin user create`).

Пользователи: `forgejo-admin` (служебный админ), `artemiy` (личный, без прав
админа) и `renovate-bot` (бот Renovate, право записи в этот репозиторий).

Осторожно с именами: чарт создаёт Secret с именем релиза (`forgejo`) для своих
init-скриптов, поэтому секреты сервиса названы с префиксом `forgejo-`.
Совпадение имён означало бы двух владельцев одного объекта (VSO и Argo), и они
затирали бы ключи друг друга.

## Вход через Zitadel (OIDC)

Локальная форма входа остаётся включённой намеренно: это страховка, если
Zitadel недоступен или сломан issuer, и она же доказывает право на привязку.
Через OIDC ходят и `forgejo-admin`, и `artemiy` — учётки не создаются заново, а
привязываются к существующим.

Источник создаёт не человек, а init-контейнер чарта: блок `gitea.oauth[]` в
`valuesObject` превращается в `forgejo admin auth add-oauth`, а если источник
уже есть — в `update-oauth`. Значит значения живут в GitOps, а правка источника
в UI будет затёрта следующим sync.

| | |
|---|---|
| Имя источника | `zitadel` |
| Провайдер | `openidConnect`, auto discovery |
| Redirect URI | `https://forgejo.<домен>/user/oauth2/zitadel/callback` |
| Приложение в Zitadel | `infra/terraform/zitadel` → `zitadel_application_v2.forgejo` |
| Client id/secret | `kv/forgejo/oidc` → Secret `forgejo-oidc` |
| Секция app.ini | `[oauth2_client]` — `ENABLE_AUTO_REGISTRATION`, `ACCOUNT_LINKING`, `OPENID_CONNECT_SCOPES` |

Проверить, что источник создан, и увидеть список — команда в `RUNBOOK.md`.

### Как привязываются учётки

Через OIDC **не создаётся ни одной новой учётки**: `ENABLE_AUTO_REGISTRATION:
false`. Незнакомый Forgejo логин после колбэка попадает на
`/user/link_account` — страницу с формой локального входа. Привязка происходит
только после того, как человек ввёл пароль существующей учётки; если на
учётке включён 2FA, Forgejo запрашивает и его (намеренно игнорируя «пропустить
2FA для внешних источников» — привязка идёт к уже существующему пользователю).

Дальше Forgejo помнит связь: в таблице внешних логинов у пользователя лежит
пара `login_type=OAuth2`, `login_source=<id источника>`, `login_name=<sub из
Zitadel>`. По ней он находит пользователя при каждом следующем входе, больше ни
по имени, ни по почте не сверяясь. Поэтому привязка делается один раз и
переживает смену почты; отвязать можно в Settings → Linked accounts.

Порядок привязки — в `RUNBOOK.md`.

Почему не `ACCOUNT_LINKING: auto`: Forgejo тогда сначала ищет совпадение по
имени, потом по почте, и при совпадении привязывает учётку **молча**, без
пароля и без 2FA. Для публично доступного identity-провайдера с
`allow_register` это значит, что контроль над почтой в Zitadel даёт контроль
над чужой учёткой Forgejo.

### Грабли

- **Имя источника = сегмент в колбэке.** Forgejo ищет источник по имени
  (`GetActiveOAuth2SourceByName`), а не по id, и подставляет это же имя в
  ссылку кнопки входа: `/user/oauth2/<имя>/callback`. Переименование источника
  без правки `name` в values и `redirect_uris` в Terraform ломает вход.
- **Ключи в Secret задаёт чарт:** `key` и `secret` (env `GITEA_OAUTH_KEY_0` и
  `GITEA_OAUTH_SECRET_0`), а не `OIDC_CLIENT_ID`/`OIDC_CLIENT_SECRET`, как у
  соседних приложений, которые читают их в env.
- **Список `gitea.oauth` патчится целиком.** Приватный merge-patch обязан
  повторять его целиком с реальным discovery URL, иначе после patch
  автосоздание источника уедет на плейсхолдер.
- **Имя `admin` в Forgejo зарезервировано** («name is reserved») — логин Zitadel
  `admin` (instance-админ) не сможет получить учётку, пока автосоздание
  выключено, и привязаться к существующей тоже не сможет: страница привязки
  спрашивает пароль от `admin`, которого нет.
- **Дальше источник — в руках Forgejo, а не Zitadel.** Синхронизации ролей нет:
  новый грант в Zitadel не даёт прав в Forgejo, а удаление гранта не отбирает.
  Права живут в учётке Forgejo.
- **`DISABLE_REGISTRATION: true` не мешает автосозданию через OIDC** (оно
  проверяет отдельный флаг), поэтому включать `ENABLE_AUTO_REGISTRATION` без
  отдельного решения нельзя.

## Резервное копирование

Пока **не настроено**, и это главный незакрытый пункт: под `shared` задуман
ObjectStore + ScheduledBackup в rustfs (Barman Cloud Plugin), см.
`clusters/casa/platform/cnpg/README.md`. До этого репозитории (PVC) и база (CNPG) живут без
резервных копий, а `longhorn-retain` защищает только от удаления PVC, не от
отказа диска или логической порчи.

Когда база будет покрыта бэкапами, для репозиториев останется второй путь:
push-зеркало в GitHub — git распределённый, и код переживёт потерю сервера даже
без бэкапов. Планируемый порядок: сначала зеркало, потом перенос `origin`.

## Грабли, проверенные на живом стенде

- **`lookup` в чарте ломается под Argo.** Чарт умеет генерировать пароль админа
  и хранить его в своём Secret'е, читая существующий объект через `lookup`. Argo
  рендерит чарт без доступа к кластеру, поэтому пароль менялся бы при каждом
  sync. Лечится `gitea.admin.existingSecret` — что и сделано.
- **Ingress под Argo вечно `Progressing`.** Traefik не пишет
  `status.loadBalancer.ingress`, а Argo считает такой Ingress нездоровым.
  Сейчас на Ingress стоит аннотация `argocd.argoproj.io/ignore-healthcheck`;
  когда Ingress'ов под Argo станет больше, чище завести
  `resource.customizations.health.networking.k8s.io_Ingress` в `argocd-cm`.
- **Пины образов: версия в теге, digest для воспроизводимости.** Свои образы и
  образы с версионными тегами пинятся по digest. Для `docker:dind` тег
  версионный только у апстрима: в зеркале `data.forgejo.org/oci/docker` есть
  лишь плавающие `29-dind` и `29-cli`, и digest плавающего тега умирает, когда
  апстрим перезаливает индекс — registry подчищает старый, и под уходит в
  `ImagePullBackOff` (issue #716). Поэтому dind берётся из Docker Hub явным
  patch-тегом с digest: `docker.io/library/docker:29.8.2-dind@sha256:7dcdfc4a…`.
  Обновление — руками: новый тег, новый digest, тег в манифесте приводится в
  соответствие.

Эксплуатация — в `RUNBOOK.md`.

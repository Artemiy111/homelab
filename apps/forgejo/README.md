# Forgejo

Forgejo — лёгкая self-hosted Git-платформа (форк Gitea), которая задумана как
основной дом для этого репозитория.

| | |
|---|---|
| URL | `https://forgejo.example.com/` |
| Git over SSH | `ssh://git@forgejo.example.com:2222/OWNER/REPO.git` |
| Namespace | `forgejo` |
| Развёртывание | Argo CD: `argocd/applications/forgejo.yaml`, чарт `forgejo-helm` |
| Данные | PVC `forgejo-data` на `longhorn-retain` (Longhorn) |
| База | CNPG-кластер `shared` в namespace `databases`, роль и база `forgejo` |
| Actions | включены; runner `homelab-runner` (Deployment + DinD), instance-wide |

Самостоятельная регистрация выключена, новые репозитории и профили приватны.

## Как развёрнуто

Официального Helm-чарта у Forgejo нет; де-факто стандарт — **forgejo-helm** из
организации `forgejo-contrib` на Codeberg (форк чарта Gitea под Forgejo:
внешняя база, rootless-образ, admin-пользователь и метрики из коробки).
Application ставит его как git-источник с `path: .`, как local-path-provisioner.

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
их отдельный процесс **Forgejo Runner** (`apps/forgejo/k8s/runner.*`).

| | |
|---|---|
| Deployment | `apps/forgejo/k8s/runner.deployment.yaml` |
| Конфиг | `apps/forgejo/k8s/runner.configmap.yaml` |
| Секрет регистрации | `apps/forgejo/k8s/runner.sealedsecret.yaml` |
| Том dockerd | PVC `forgejo-runner-dind` (`local-path`, 10Gi) |
| Область | instance-wide (`--scope ""`), раннер `homelab-runner` |

Два контейнера в одном поде: `runner` и `dind` (`docker:dind`). Они делят
сетевой namespace, поэтому раннер ходит к dockerd по `tcp://127.0.0.1:2375`, а
job-контейнеры внутри dind достают тот же демон по имени `dind`
(`--add-host=dind:host-gateway`). Job'ы получают Docker, но не демон узла: у
dind свой `/var/lib/docker` на PVC. Том — `local-path`, а не Longhorn: кластер
одноузловой, у Longhorn одна реплика (избыточности нет), а кэш образов можно
потерять без последствий; Longhorn остаётся под важными данными. `local-path`
не enforce'ит квоту — размер тома лишь заявка, реальный предел задаёт очистка
(`docker system prune`, ниже).

Регистрация оффлайн (без UI), идемпотентно:

```sh
SECRET=$(openssl rand -hex 20)   # 40 hex-символов
kubectl -n forgejo exec -i deploy/forgejo -c forgejo -- \
  forgejo forgejo-cli actions register --name homelab-runner \
  --secret-stdin --scope ""
```

Команда печатает UUID (это не случайное значение, а UUID из первых 16 символов
секрета) — он идёт в `runner.configmap.yaml`; сам секрет — `token` в
SealedSecret'е. Токен в ConfigMap не попадает: раннер читает его из файла
(`server.connections.forgejo.token_url`), смонтированного из Secret'а.

**Метки** (`runs-on`) и образы заданы в ConfigMap'е. `ubuntu-latest` и
`ubuntu-22.04` указывают на `ghcr.io/catthehacker/ubuntu:act-22.04` —
GitHub-подобный образ с git, docker CLI, python и build-essential. Голый
`node:lts` не подходит: в нём нет docker CLI, и `docker build` в job'е падает.
Образы пинятся дайджестом: docker по тегу уже скачанный образ не обновляет.

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
  (`http://forgejo-http:3000`) не годится: там нет TLS;
- реестр пакетов живёт под `/api/packages/{owner}/...`, а не `/api/v1`;
- generic-пакеты: `PUT /api/packages/{owner}/generic/{package}/{version}/{file}`;
- **пакет не привязывается к репозиторию сам.** URL push'а содержит только
  владельца, поэтому пакет виден на `/{owner}/-/packages`, а во вкладке Packages
  репозитория (`/{owner}/{repo}/packages`) его нет. Привязка отдельная:
  `POST /api/v1/packages/{owner}/{type}/{name}/-/link/{repo}` (нужен
  `write:package`) либо вручную: версия пакета → Settings → выбор репозитория.
  Для повторных версий привязка сохраняется — линковать нужно один раз.

### Что проверено на живом стенде

Прогон workflow в `user/test` (`.forgejo/workflows/smoke.yml`), 14 job'ов:
работают `actions/checkout@v6`, node-экшены, `docker build`/`docker run` внутри
dind, сервис-контейнеры (`services:`), матрицы, `needs`/outputs, кэш
(`actions/cache@v4` save/restore), `jobs.<id>.container`, доступ к API через
`${{ github.token }}`.

Там же проверены `release.yml` (тег + опубликованный релиз с ассетами) и
`packages.yml` (push образа в реестр контейнеров и generic-пакет через PAT).

Грабли:

- **Артефакты только `@v3`.** `upload-artifact`/`download-artifact` `@v4+`
  используют `@actions/artifact v2` и новый API, которого в Forgejo нет —
  падают с `GHESNotSupportedError`. Использовать `@v3`.
- **`GITHUB_SERVER_URL` внутренний.** Job'ы получают `http://forgejo-http:3000`
  (адрес из `server.connections`), а не публичный URL. Checkout и API по нему
  работают, но ссылки, которые экшены печатают в лог, будут внутренними.
  Публичный URL в конфиге даст красивее ссылки, но добавит зависимость от
  Traefik и DNS.

Проверка:

```sh
kubectl -n forgejo get pods -l app=forgejo-runner
kubectl -n forgejo logs deploy/forgejo-runner -c runner
```

Раннер виден в UI: `/admin/actions/runners` (idle — значит зарегистрирован).

Безопасность: раннер — это RCE по определению. Область instance-wide означает,
что workflow любого репозитория инстанса может запускать job'ы; при появлении
внешних контрибьюторов раннер надо сузить до репозитория/организации или
вынести на отдельную ВМ. Кэш держит сам раннер (`emptyDir`, теряется при
рестарте), логи и артефакты — Forgejo (ретеншн `actions.LOG_RETENTION_DAYS` /
`ARTIFACT_RETENTION_DAYS`, по умолчанию 365/90 дней). Том dind растёт от
образов: чистить `kubectl -n forgejo exec deploy/forgejo-runner -c dind -- docker system prune -af`.

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
разрешён в `platform/cnpg/networkpolicy.yaml` (`allow-shared-from-consumers`).

Пароль роли лежит в `databases/forgejo-db-auth` и он же — в
`forgejo/forgejo-secrets` (один плейнтекст, два запечатанных SealedSecret'а —
принятая в репозитории схема, см. `platform/cnpg/README.md`). Подставляется в
app.ini через `FORGEJO__database__PASSWD` из `gitea.additionalConfigFromEnvs`,
поэтому секрет чарту не нужен.

## Секреты

| SealedSecret | Что внутри | Кто читает |
|---|---|---|
| `apps/forgejo/k8s/secrets.sealedsecret.yaml` | `POSTGRES_PASSWORD`, `FORGEJO_METRICS_TOKEN` | чарт (env → app.ini) |
| `apps/forgejo/k8s/admin.sealedsecret.yaml` | `username` (`forgejo-admin`), `password` админа | чарт (init-контейнер) |

Перезапечатать можно только на сервере: `kubeseal` привязан к namespace и
имени, а приватный ключ контроллера доступен лишь там
(`docs/agents/server-access.md`).

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

Пользователи: `forgejo-admin` (служебный админ) и `user` (личный, без прав
админа).

Осторожно с именами: чарт создаёт Secret с именем релиза (`forgejo`) для своих
init-скриптов, поэтому секреты сервиса названы `forgejo-secrets` и
`forgejo-admin`. Совпадение имён означало бы двух владельцев одного объекта
(SealedSecret-контроллер и Argo), и они затирали бы ключи друг друга.

## Проверка

```sh
kubectl -n argocd get application forgejo
kubectl -n forgejo get pods,pvc,svc,ingress

curl -fsS --resolve forgejo.example.com:443:192.0.2.10 \
  https://forgejo.example.com/api/healthz   # status: pass, database:ping: pass

kubectl -n forgejo exec deploy/forgejo -- forgejo admin user list --admin

# SSH: порт открыт и отдаёт баннер Forgejo
ssh -T -p 2222 -o StrictHostKeyChecking=no git@192.0.2.10
```

## Резервное копирование

Пока **не настроено**, и это главный незакрытый пункт: под `shared` задуман
ObjectStore + ScheduledBackup в rustfs (Barman Cloud Plugin), см.
`platform/cnpg/README.md`. До этого репозитории (PVC) и база (CNPG) живут без
резервных копий, а `longhorn-retain` защищает только от удаления PVC, не от
отказа диска или логической порчи.

Когда база будет покрыта бэкапами, для репозиториев останется второй путь:
push-зеркало в GitHub — git распределённый, и код переживёт потерю сервера даже
без бэкапов. Планируемый порядок: сначала зеркало, потом перенос `origin`.

## Обновление

1. Посмотреть release notes Forgejo и тег чарта (`forgejo-helm` на Codeberg).
2. В `argocd/applications/forgejo.yaml` поднять `targetRevision` (тег чарта) и
   `image.tag`/`image.digest` (образ Forgejo) — это две независимые вещи.
3. `kubectl apply -f argocd/applications/forgejo.yaml`, дождаться sync.
4. Миграции схемы выполняет init-контейнер чарта (`forgejo migrate`); если он
   циклится, смотреть его логи: обычно это недоступная база.

Откат: вернуть прежние теги в values и снова `kubectl apply`. Образ и чарт
пинятся по версии/дайджесту, поэтому откат детерминированный.

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
- **`image.pullPolicy` и digest.** Образ пинится дайджестом, тег остаётся
  человекочитаемым маркером версии.

# Доступ агентов к серверу

Инструкция для работы с домашним сервером. Рабочая копия репозитория одна — на
macOS; на сервере её нет.

## Модель доступа

Два независимых канала, и их не надо путать.

**Кластер** доступен с macOS напрямую: kubeconfig лежит в
`~/.kube/configs/homelab.yaml`. Через него идут все `kubectl`-проверки, и
ходить по SSH ради них не нужно.

**Сервер** доступен по SSH от имени пользователя **`ai-agent`** — это
изолированный аккаунт: домашний каталог `ops` (а с ним приватные ключи) ему
недоступен. Всё, что лежит на диске сервера, выполняется от имени **`ops`**
через `sudo -u ops` (пароль не требуется). Перед записью агент запрашивает
разрешение пользователя.

| Сценарий | Канал | Команда |
|---|---|---|
| Кластер: `kubectl`, `argocd`, состояние подов и ресурсов | macOS | `KUBECONFIG=~/.kube/configs/homelab.yaml kubectl …` |
| Рендер и apply чартов, чьи values в git | macOS | `helm template … \| kubectl apply -f -` |
| `terraform` | macOS | запуск в рабочей копии репозитория |
| `ansible` (host, dotfiles, `ai-agent`) | macOS | `cd infra/casa/ansible && ansible-playbook …` |
| Проверки хоста: DNS с узла, `systemctl`, `tailscale` | SSH | `ssh homelab-agent` |

Правило выбора: **если проверку можно сделать через API-сервер — делать её с
macOS, без SSH.** SSH нужен только для того, что через API не видно: состояние
юнитов systemd, `k0s status` (нужен root), резолв DNS с самого узла, `curl` с
узла, состояние Tailscale и файлы на диске сервера.

`sudo` у `ai-agent` ограничен только запуском команд от `ops` (`NOPASSWD`);
root-прав у агента нет.

## Подключение

### Кластер с macOS

Kubeconfig: `~/.kube/configs/homelab.yaml`, контекст `k0s`. Права те же, что у
`ops` на сервере, — отдельного sudo не нужно. Чтобы не писать префикс в
каждой команде:

```sh
export KUBECONFIG=~/.kube/configs/homelab.yaml
```

Kubeconfig не в `~/.kube/config` намеренно: там лежат другие кластеры, и
переключение контекста их бы ломало. Имя файла без расширения не работает —
`KUBECONFIG=~/.kube/configs/homelab` отдаст `localhost:8080`.

### Сервер по SSH

- SSH alias для `ops`: `homelab`.
- SSH alias для `ai-agent`: `homelab-agent`.
- LAN-адрес: `<node1-ip>`.
- Операционная система: Fedora Server 44.
- Основной пользователь сервера: `ops`.
- Пользователь агента: `ai-agent`.
- Чекаута репозитория на сервере нет: `git pull` и Ansible выполняются на macOS.
- Постоянные данные: `/storage` (`apps`, `media`, `backups`).
- Кластер: k0s, systemd unit `k0scontroller.service`. `k0s status` требует root.

## Команды для пользователя

Пользователь обычно уже подключён к серверу как `ops`. Поэтому в ответах,
предназначенных для ручного выполнения пользователем, ВСЕГДА давать только чистую
команду для текущей оболочки: без `ssh homelab-agent`, `ssh homelab`,
`sudo -u ops bash -lc` и иной обвязки агента. Обёртки из этого документа
нужны только когда команду выполняет сам агент через SSH.

Оба канала требуют маршрута в домашнюю сеть. Перед любой записью сначала
выполнить безопасную проверку:

```sh
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl get nodes
```

```sh
ssh homelab-agent 'hostname; systemctl is-active k0scontroller'
```

## Единственный процесс доставки

Рабочая копия репозитория одна — на macOS. Правки попадают в `main` только
через PR: ветка защищена, прямой push отклоняется
(`docs/agents/commit-conventions.md`, `docs/agents/issue-tracker.md`). Порядок
всегда следующий:

1. Завести issue под задачу и отдельное рабочее дерево (см. `AGENTS.md`).
2. Изменить файлы в дереве.
3. Проверить diff, манифесты и отсутствие секретов в открытом виде.
4. Создать локальный commit в ветке дерева.
5. Выполнить push ветки и merge PR в `main` (squash).
6. Кластер подхватывает изменение через Argo CD сам; что Argo не
   синхронизирует, применить руками с macOS (см. «Применение манифестов»).
7. Прогнать Ansible с macOS, если затронуты файлы узла или dotfiles
   (`ops.yml` — dotfiles, `host.yml` — системные конфиги, `agent.yml` —
   окружение `ai-agent`); на сервере плейбуки не запускаются.
8. Проверить состояние подов, DNS, HTTP и логи.

Запрещено:

- редактировать отслеживаемые файлы на сервере и держать там рабочую копию
  репозитория (разовые bootstrap-скрипты копируются на узел только на время
  запуска);
- переписывать опубликованную историю для исправления развёртывания;
- применять `git reset --hard`, `git clean` или удаление данных без явного
  разрешения пользователя.

Если после развёртывания обнаружена ошибка, исправить её локально и доставить
отдельным PR, не переписывая уже слитую историю.

## Секреты

Секреты живут в HashiCorp Vault. В кластер их доставляет Vault Secrets
Operator (VSO): `VaultStaticSecret`
(`apps/casa/<сервис>/manifests/vaultstaticsecret.yaml`) создаёт и обновляет обычный
Secret, который читает приложение. Значение задаёт пользователь в Vault по
пути из `docs/adr/0006-vault-secret-path-layout.md`.

Само значение секрета агент не читает: `kubectl describe`/`get -o yaml` на
VaultStaticSecret и destination Secret показывают только имена ключей и
метаданные.

Изменение секрета:

1. Обновить значение в Vault по нужному пути (`kv/<сервис>/<секрет>`).
2. Если меняется набор ключей или путь — обновить `VaultStaticSecret`,
   `deployment` и policy в `infra/casa/terraform/vault/policies/`, затем выполнить
   `terraform apply` в `infra/casa/terraform/`.
3. Доставить через merge в `main` по схеме из «Единственный процесс доставки».

VSO перечитывает значение по `refreshAfter` (1 час). Форсировать
перечитывание, не удаляя CR: удаление сносит и destination Secret, значение
придётся заводить заново.

```sh
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl -n <ns> annotate vaultstaticsecret <имя> \
  vso.secrets.hashicorp.com/force-sync="$(date +%s)" --overwrite
```

Расшифровываемого реестра значений в репозитории нет, единственная копия —
Vault. Резервную копию Vault пользователь делает сам (снапшот raft).
Не выводить значения в логи или ответы: для диагностики показывать имена
ключей и метаданные.

```sh
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl -n <ns> get vaultstaticsecret -o json | \
  jq -r '.items[]|select(.status.conditions[0].status!="True")|.metadata.name'
```

Изменять или перевыпускать секреты только когда это необходимо для задачи и
после определения затронутых сервисов.

## Kubernetes и права

`kubectl` на macOS работает с `KUBECONFIG=~/.kube/configs/homelab.yaml` и имеет
те же права, что `ops` на сервере. `helm` и `argocd` на macOS тоже стоят; там же
лежит приватный слой (`terraform`, `terraform.tfvars`). State Terraform при этом
не на macOS, а в бакете `terraform-state` в RustFS — см.
`infra/casa/terraform/README.md`.

SELinux находится в режиме enforcing, firewalld включён. Не отключать их ради
обхода ошибок доступа.

## Как оборачивать команды (типовые ошибки)

Ошибки повторяются и обе выглядят как «внезапно нет прав». Причина — не тот
пользователь или не то экранирование, а не доступы на сервере.

**1. Не ходить по SSH ради того, что видно через API.** `kubectl get pods` с
macOS и `kubectl get pods` через `sudo -u ops bash -lc` дают одинаковый
результат. Второй способ нужен только когда команда трогает файлы на диске
сервера или приватные ключи `ops`.

**2. `sudo -u ops` нужен на каждую команду целиком.** Пустая передача
`bash -s` в ssh выполняется от `ai-agent`: доступ к приватным ключам `ops`
упадёт с `Permission denied`. Нельзя смешивать уровни — либо вся команда
внутри `sudo -u ops bash -lc "…"`, либо она от `ai-agent` и не трогает ресурсы
`ops`.

```sh
# Плохо: только часть обёрнута, остаток уйдёт от ai-agent.
ssh homelab-agent 'sudo -u ops bash -lc "ls ~/.ssh" && cat ~/.ssh/config'

# Хорошо: единая оболочка ops.
ssh homelab-agent 'sudo -u ops bash -lc "ls ~/.ssh && cat ~/.ssh/config"'
```

**3. Многострочный ввод — через stdin, а не через вложенные кавычки.** В
`ssh '…'` уже занят один слой одинарных кавычек, внутри `sudo -u ops bash -lc
"…"` — второй; текст со своими кавычками превращается в кашу из экранирований,
а двойные кавычки становятся идентификаторами (`column "pg_catalog" does not
exist`). Если строк несколько или внутри есть кавычки — передавать их на stdin:

```sh
ssh homelab-agent 'sudo -u ops bash -lc "kubectl exec -i POD -c postgres -- psql -U postgres -d db"' <<'SQL'
select count(*) from pg_tables;
SQL
```

Тот же приём для файлов: инструменту, читающему stdin, данные передаются
перенаправлением, а не аргументом командной строки.

Для команд, требующих доступа от `ops`, сначала выполнить доступные
read-only проверки локально через kubectl, затем запросить разрешение
пользователя:

```sh
# Read-only, без SSH и без пароля:
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl get pods -A
```

Остаётся SSH для того, что через API не видно:

```sh
# Read-only от ai-agent (без пароля):
ssh homelab-agent 'systemctl is-active k0scontroller; dig +short @<node1-ip> uptime.example.com A'
```

## Применение манифестов

Изменения доставляются через Argo CD: Application подхватывает путь из git сам,
отдельно применять ничего не нужно. Локальная проверка результата:

```sh
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl apply -k apps/casa/grafana/ --dry-run=server
```

Ручной `kubectl apply` нужен только там, где Argo ещё не подхватил коммит: все
маршруты кластера, включая панель Argo, применяет сам Argo. Команда идёт с macOS
из рабочей копии репозитория.

Чарта `platform/homelab` больше нет: он распущен на `platform/casa/traefik` и
`platform/casa/cert-manager`, Gateway и GatewayClass живут в
`platform/casa/traefik/manifests/`, `Certificate` и `ClusterIssuer` —
в `platform/casa/cert-manager/manifests/`. Домен и адрес сервера
берутся из `externalIPs` в values Traefik, который лежит в репозитории
(`docs/adr/0009`) — отдельного приватного values-файла нет.

Не перезапускать все сервисы, если изменение касается только одного. После
применения дождаться, пока поды перейдут в `Running`/`Ready`, прежде чем
проверять HTTP.

### Кто применяет HTTPRoute

Маршруты не все едут одним способом, и это легко перепутать: Argo не знает о
трёх файлах из четырёх, поэтому правка в git для них молча не доезжает.

| Файл | Кто применяет |
|---|---|
| `apps/casa/<сервис>/manifests/route.yaml` | Argo, `spec.sources[].path` у Application |
| `apps/casa/3x-ui/chart/templates/route.yaml`, `apps/casa/element/chart/templates/route.yaml` | Argo, `chart` в Application |
| `apps/casa/seafile/manifests/onlyoffice.route.yaml` | Argo, вместе с каталогом `apps/casa/seafile/manifests` |
| `platform/casa/headlamp/manifests/route.yaml`, `platform/casa/longhorn/manifests/route.yaml` | Argo, `spec.sources[].path` |
| `platform/casa/traefik/manifests/dashboard.route.yaml` | Argo, `spec.sources[].path` |
| `platform/casa/argocd/manifests/route.yaml` | Argo, `spec.sources[].path` |

Маршрутов вне Argo не осталось: юнит `argocd` получил `Application` и ставит
свой чарт сам. Компромисс осознанный — ошибка в юните может отрезать доступ к
самому GitOps, поэтому у приложения `Prune=false`, а восстановление простое:
revert коммита и `argocd app sync argocd`, а если сломан контроллер — `helm
install` с values из юнита (`clusters/casa/argocd/bootstrap/README.md`).

Проверяется это так — вывести все каталоги, которые Argo берёт как источники,
и найти среди них каталог маршрута:

```sh
kubectl -n argocd get application -o \
  jsonpath='{range .items[*].spec.sources[*]}{.path}{"\n"}{end}' | sort -u
```

Маршрут внутри `chart/templates/` в этом списке не появится: его рендерит чарт,
а не каталог. Такие проверяются наличием соответствующего `chart:` в источниках
того же Application.

Имя каталога не всегда совпадает с именем Application, поэтому по имени
каталога искать Application нельзя: `apps/casa/forgejo` — это Application
`forgejo-extras`, `apps/casa/vault` — `vault-extras`, `platform/casa/eck-operator` —
`elastic-operator`. Первые два разведены по имени, чтобы не столкнуться с
`platform/casa/forgejo` и `platform/casa/vault`.

Проверить, что маршрут из git действительно применён:

```sh
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl -n traefik get gateway homelab \
  -o json | jq -r '.status.listeners[]|[.name,.attachedRoutes]|@tsv'
```

Маршрут, которого нет в кластере, попадает в `attachedRoutes` только после
apply. `NoMatchingListenerHostname` в статусе HTTPRoute означает, что ни один
слушатель не объявлен на этот домен, — проверять Gateway в traefik,
а не маршрут.

## Проверка платформы

Состояние подов (ожидается `Running`/`Completed`):

```sh
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl get pods -A
```

Синхронизация Argo:

```sh
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl -n argocd get applications
```

Резолв DNS — это SSH: запрос идёт с самого узла, а не с клиента, и так
проверяется именно то, что отдаёт домашний Technitium и split DNS Tailscale.

```sh
ssh homelab-agent 'dig +short @<node1-ip> uptime.example.com A'
```

Ожидаемый ответ: `<node1-ip>`.

HTTP-маршруты проверяются с macOS через `--resolve`: DNS клиента тут не
участвует, а адрес узла известен.

```sh
curl -sk --resolve uptime.example.com:443:<node1-ip> \
  -o /dev/null -sS -w "%{http_code}\n" https://uptime.example.com/
```

Ожидаемое внешнее поведение:

- Gatus (`uptime.…`) и Technitium (`dns.…`): `200`.
- Сервисы за `oauth2-proxy` (`grafana.…`, `vm.…`, `longhorn.…` и др.): `302`
  на форму Zitadel.
- `5xx`, transport error и отсутствие DNS-ответа считаются ошибкой.

Проверка свежих ошибок выполняется отдельно для затронутого сервиса:

```sh
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl logs deploy/grafana-deployment --since=5m
```

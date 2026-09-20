# Доступ агентов к серверу

Инструкция для работы с домашним сервером без расхождения локальной и серверной
копий репозитория.

## Модель доступа

Агент подключается по SSH от имени пользователя **`ai-agent`** — это
изолированный аккаунт: домашний каталог `artlab` (а с ним репозиторий,
kubeconfig, `sops`-ключ и приватные ключи) ему недоступен. Всё, что касается
репозитория и кластера, выполняется от имени **`artlab`** через
`sudo -u artlab` (пароль не требуется). Перед записью агент запрашивает
разрешение пользователя.

| Сценарий | Пользователь | Команда |
|---|---|---|
| Проверки хоста: DNS, `curl`, `systemctl`, `tailscale` | `ai-agent` | `ssh homelab-agent` |
| git, kubectl, helm, sops, запись в проект | `artlab` | `sudo -u artlab bash -lc "…"` |

`sudo` у `ai-agent` ограничен только запуском команд от `artlab` (`NOPASSWD`);
root-прав у агента нет.

## Подключение

- SSH alias для artlab: `homelab`.
- SSH alias для ai-agent: `homelab-agent`.
- LAN-адрес: `<node1-ip>`.
- Операционная система: Fedora Server 44.
- Основной пользователь сервера: `artlab`.
- Пользователь агента: `ai-agent`.
- Репозиторий на сервере: `/home/artlab/projects/homelab` (для `ai-agent` не
  читается — работать с ним только через `sudo -u artlab`).
- Постоянные данные: `/storage` (`apps`, `media`, `backups`).
- Кластер: k0s, systemd unit `k0scontroller.service`. `kubectl` доступен
  `artlab`; `k0s status` требует root.

## Команды для пользователя

Пользователь обычно уже подключён к серверу как `artlab`. Поэтому в ответах,
предназначенных для ручного выполнения пользователем, ВСЕГДА давать только чистую
команду для текущей оболочки: без `ssh homelab-agent`, `ssh homelab`,
`sudo -u artlab bash -lc` и иной обвязки агента. Обёртки из этого документа
нужны только когда команду выполняет сам агент через SSH.

Подключение работает только при наличии маршрута в домашнюю сеть. Перед любой
записью сначала выполнить безопасную проверку (от `ai-agent`, без пароля):

```sh
ssh homelab-agent 'hostname; systemctl is-active k0scontroller'
```

Состояние рабочей копии на сервере (от `artlab`, только чтение):

```sh
ssh homelab-agent 'sudo -u artlab bash -lc "cd /home/artlab/projects/homelab && git status --short && git log -1 --oneline"'
```

## Единственный процесс доставки

Источником отслеживаемых изменений является рабочая копия на macOS. Порядок
всегда следующий:

1. Изменить файлы локально.
2. Проверить diff, манифесты и отсутствие секретов в открытом виде.
3. Создать локальный commit.
4. Выполнить push в `origin/main`.
5. На сервере выполнить `git pull --ff-only`.
6. Применить затронутые манифесты (`kubectl apply`).
7. Проверить состояние подов, DNS, HTTP и логи.

Команда обновления сервера:

```sh
ssh homelab-agent 'sudo -u artlab bash -lc "cd /home/artlab/projects/homelab && git pull --ff-only origin main"'
```

Запрещено:

- редактировать отслеживаемые файлы непосредственно на сервере;
- переносить отслеживаемые файлы между рабочими копиями через `rsync` или `scp`;
- выполнять `git pull` при грязной серверной рабочей копии, не выяснив источник
  изменений;
- переписывать опубликованную историю для исправления развёртывания;
- применять `git reset --hard`, `git clean` или удаление данных без явного
  разрешения пользователя.

Если после развёртывания обнаружена ошибка, исправить её локально и доставить
отдельным новым commit.

## Секреты

Доставка секретов в кластер — только SealedSecret
(`apps/<сервис>/k8s/sealedsecret.yaml`). Контроллер sealed-secrets в
`kube-system` расшифровывает его в обычный Secret внутри кластера. Шифрует
`kubeseal`, которому нужен доступ к контроллеру (то есть kubeconfig на сервере).

Файлы `apps/<сервис>/secrets.enc.env` (SOPS поверх age) в доставке не
участвуют, но поддерживаются в актуальном состоянии как расшифровываемый
реестр значений. SealedSecret необратим, поэтому именно
age-файл позволяет достать исходные значения. Приватный age-ключ существует
**только на сервере**: `/home/artlab/.config/sops/age/keys.txt` (`0600`). На macOS
есть лишь публичный ключ, поэтому расшифровать существующий файл можно только на
сервере.

Изменение или добавление секрета:

1. Внести значение в реестр на сервере (там живёт age-ключ):
   `sops apps/<сервис>/secrets.enc.env`. `sops` перешифровывает файл целиком.
2. Запечатать значение в SealedSecret через `kubeseal` (контроллер
   `sealed-secrets-controller` в `kube-system`); имя Secret должно совпадать с
   тем, что читает приложение.
3. Перенести оба зашифрованных файла (`secrets.enc.env`, `sealedsecret.yaml`) в
   рабочую копию на macOS (шифротекст можно передавать открыто) и доставить
   стандартной схемой commit → push → `git pull --ff-only`.

Приватный age-ключ на macOS не копировать и в Git не добавлять. Plaintext-файлы
с секретами не создавать и не хранить. Не выводить расшифрованные значения в
логи или ответы — для диагностики показывать только имена переменных:

```sh
ssh homelab-agent 'sudo -u artlab bash -lc "cd /home/artlab/projects/homelab && sops -d apps/nextcloud/secrets.enc.env | cut -d= -f1 | sort | grep -v ^sops"'
```

Потеря приватного age-ключа означает потерю расшифровываемого реестра
(`secrets.enc.env`); на работу кластера это не влияет — SealedSecret
расшифровывает контроллер своим ключом. Резервную копию age-ключа пользователь
хранит вне репозитория. Установку `sops` и `kubeseal` делает `ansible/host.yml`.

Изменять или перевыпускать секреты только когда это необходимо для задачи и
после определения затронутых сервисов.

## Kubernetes и права

`kubectl` (`/usr/local/sbin/kubectl`) и `kubeconfig` (`~/.kube/config`, `0600`)
доступны `artlab`; `ai-agent` их не видит, поэтому кластерные команды — только
через `sudo -u artlab`. `helm`, `kubeseal`, `argocd` и `sops` установлены так же.

SELinux находится в режиме enforcing, firewalld включён. Не отключать их ради
обхода ошибок доступа.

## Как оборачивать команды (типовые ошибки)

Две ошибки повторяются и обе выглядят как «внезапно нет прав». Причина —
не тот пользователь или не то экранирование, а не доступы на сервере.

**1. `sudo -u artlab` нужен на каждую команду целиком.** Пустая передача
`bash -s` в ssh выполняется от `ai-agent`: доступ к репозиторию, `kubeconfig` и
приватным ключам `artlab` упадёт с `Permission denied`. Нельзя смешивать
уровни — либо вся команда внутри `sudo -u artlab bash -lc "…"`, либо она от
`ai-agent` и не трогает ресурсы `artlab`.

```sh
# Плохо: только часть обёрнута, остаток уйдёт от ai-agent.
ssh homelab-agent 'sudo -u artlab bash -lc "git pull" && cat ~/.kube/config'

# Хорошо: единая оболочка artlab.
ssh homelab-agent 'sudo -u artlab bash -lc "cd /home/artlab/projects/homelab && git pull && kubectl get pods"'
```

**2. Многострочный ввод — через stdin, а не через вложенные кавычки.** В
`ssh '…'` уже занят один слой одинарных кавычек, внутри `sudo -u artlab bash -lc
"…"` — второй; текст со своими кавычками превращается в кашу из экранирований,
а двойные кавычки становятся идентификаторами (`column "pg_catalog" does not
exist`). Если строк несколько или внутри есть кавычки — передавать их на stdin:

```sh
ssh homelab-agent 'sudo -u artlab bash -lc "kubectl exec -i POD -c postgres -- psql -U postgres -d db"' <<'SQL'
select count(*) from pg_tables;
SQL
```

Тот же приём для файлов: инструменту, читающему stdin, данные передаются
перенаправлением, а не аргументом командной строки.

Для команд, требующих доступа от `artlab`, сначала выполнить все доступные
read-only проверки от `ai-agent`, затем запросить разрешение пользователя:

```sh
# Read-only от ai-agent (без пароля):
ssh homelab-agent 'systemctl is-active k0scontroller; dig +short @<node1-ip> uptime.example.com A'
```

## Применение манифестов

Сначала проверить diff/server-side результат, затем применить:

```sh
ssh homelab-agent 'sudo -u artlab bash -lc "cd /home/artlab/projects/homelab && kubectl apply -f apps/grafana/k8s/ && kubectl get pods"'
```

Общая конфигурация (`homelab-config`) и все HTTP-маршруты живут в Helm-чарте
`platform/homelab` и применяются одной командой. Реальные домен и адрес сервера
берутся из untracked `platform/homelab/values.private.yaml`; в git лежит только
`values.yaml` с плейсхолдерами:

```sh
ssh homelab-agent 'sudo -u artlab bash -lc "cd /home/artlab/projects/homelab && helm template platform/homelab -f platform/homelab/values.private.yaml | kubectl apply -f -"'
```

`values.private.yaml` существует только на сервере и не коммитится (см.
`.gitignore`). Формат:

```yaml
config:
  domain: <реальный домен>
  serverIp: <адрес сервера>
```

Не перезапускать все сервисы, если изменение касается только одного. После
применения дождаться, пока поды перейдут в `Running`/`Ready`, прежде чем
проверять HTTP.

## Проверка платформы

Состояние подов (ожидается `Running`/`Completed`):

```sh
ssh homelab-agent 'sudo -u artlab bash -lc "kubectl get pods -A"'
```

Локальный DNS:

```sh
ssh homelab-agent 'dig +short @<node1-ip> uptime.example.com A'
```

Ожидаемый ответ: `<node1-ip>`.

HTTP-маршруты можно проверять без зависимости от DNS клиента:

```sh
ssh homelab-agent 'curl -sk --resolve uptime.example.com:443:<node1-ip> \
  -o /dev/null -sS -w "%{http_code}\n" https://uptime.example.com/'
```

Ожидаемое внешнее поведение:

- Gatus (`uptime.…`) и Technitium (`dns.…`): `200`.
- Сервисы за `oauth2-proxy` (`grafana.…`, `vm.…`, `longhorn.…` и др.): `302`
  на форму Zitadel.
- `5xx`, transport error и отсутствие DNS-ответа считаются ошибкой.

Проверка свежих ошибок выполняется отдельно для затронутого сервиса:

```sh
ssh homelab-agent 'sudo -u artlab bash -lc "kubectl logs deploy/grafana --since=5m"'
```

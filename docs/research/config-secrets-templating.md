# Конфиги с секретами: шаблонизация и доставка вместо самописного init.sh + envsubst

Дата проверки: 2026-08-22.

## Короткий вывод

Для сервиса, которому нужен **конфиг-файл с секретами в открытом виде**, есть три
универсальных подхода, и все они лучше «bake-time» рендера через `envsubst` в том,
что касается секретов:

1. **Шифрование в git + расшифровка на месте (SOPS + age)** — отраслевой стандарт
   для конфигов-as-code вне Kubernetes. Секреты хранятся зашифрованными в git,
   расшифровываются только в момент запуска (`sops exec-env` / `exec-file` /
   `decrypt -i`), поддерживается частичное шифрование через `encrypted_regex`
   и читаемые диффы ([getsops.io/docs](https://getsops.io/docs/),
   [common operations](https://getsops.io/docs/usage/common-operations/)).
   Это совпадает с рекомендацией этапа 1 из
   [secret-management-providers.md](./secret-management-providers.md).

2. **Runtime-инъекция** — секрет вообще не попадает в файл: либо сервис читает
   переменные окружения напрямую (нативная интерполяция `${VAR}` внутри config.yaml,
   как у Gatus и Grafana provisioning), либо обёртка вроде `infisical run --`,
   `vals exec -f ... --`, `sops exec-env`, либо рендер живым демоном
   (Vault Agent Templates / consul-template). Это единственный класс решений,
   дающий ротацию без перегенерации файлов руками
   ([developer.hashicorp.com/vault](https://developer.hashicorp.com/vault/docs),
   [infisical.com/docs/cli](https://infisical.com/docs/cli/overview)).

3. **Шаблонизаторы с datasource'ами (gomplate, vals)** — зрелая замена envsubst,
   когда рендер всё же нужен: тянут значения прямо из Vault/SOPS/AWS SM/Consul и
   десятков других бэкендов, т.е. plaintext появляется только в момент рендера
   ([docs.gomplate.ca/datasources](https://docs.gomplate.ca/datasources/),
   [github.com/helmfile/vals](https://github.com/helmfile/vals)).

Docker Compose secrets (`secrets:` + `/run/secrets/<name>` + конвенция `_FILE`)
— не решение проблемы plaintext-on-disk: файл по-прежнему лежит открытым текстом
на хосте, compose просто бинд-маунтит его в контейнер
([docs.docker.com/compose/how-tos/use-secrets](https://docs.docker.com/compose/how-tos/use-secrets/)).

**Рекомендация для этого репозитория** (кратко, детали ниже): оставить текущий
`.env` + envsubst как рабочий baseline для несекретных значений, но (а) где можно —
перейти на нативную интерполяцию переменных окружения в конфигах (паттерн Gatus),
(б) закоммитить секреты в git через SOPS+age с `.sops.yaml` + git-diff textconv,
(в) при появлении самоописанных потребностей в UI/RBAC — использовать уже
развёрнутый Infisical (`infisical run`) как runtime-источник. Это ровно маршрут
«этап 1 → этап 3» из secret-management-providers.md; отдельный Vault Agent здесь
не нужен, пока нет dynamic secrets/PKI (см. ту же доку).

**Принятая схема хранения и рендера — SOPS + age + vals**: смешанные `.env`
раскладываются на публичный `config.env` и зашифрованный `secrets.enc.env`,
шаблоны `*.tpl.yaml` ссылаются на секреты через `ref+sops://`. Детали,
именование и операции — в разделе
[8](#8-принятая-схема-sops--age--vals).

---

## Текущий пайплайн репозитория (контекст)

Самописный механизм в `scripts/lib/common.sh`:

| Функция | Что делает | Ограничение |
| --- | --- | --- |
| `write_env_file` (common.sh:124) | создаёт `<svc>/.env` (0600) из heredoc, существующий не трогает | секреты лежат в `.env` plaintext; файл не в git |
| `ensure_secret` / `random_secret` (common.sh:183, :76) | генерирует секрет один раз, хранит в `.env` | нет ротации, нет истории |
| `upsert_env` / `read_env_key` (common.sh:165, :176) | точечная правка/чтение ключей, в т.ч. cross-service (netdata ← forgejo) | sed-парсинг, значение с `\|` не поддерживается |
| `render_template` (common.sh:70) | рендерит `*.tpl` в `$APPS_STORAGE_PATH/<svc>/…` через GNU gettext `envsubst` с явным белым списком `${VAR}` | отрендеренные конфиги содержат секреты plaintext на диске (netdata go.d prometheus.conf, traefik.yaml, cup.json) |

Плюс compose-интерполяция `${VAR:?set in svc/.env}` внутри compose.yaml.

Проблемы, которые решает индустрия стандартными средствами: (1) секреты есть
plaintext на диске дважды — в `.env` и в отрендеренном конфиге; (2) секреты не
в git — нет ни бэкапа, ни истории, восстановление только с сервера; (3) envsubst
умеет только подстановку, без дефолтов, условий и функций; белый список имён
приходится поддерживать руками в каждом вызове `render_template`.

---

## 1. Инструменты шаблонизации

### envsubst (GNU gettext)

Подставляет переменные окружения вида `$VAR`/`${VAR}`. Ограничения: без аргумента
заменяет **все** найденные последовательности (поэтому в репозитории передаётся
белый список); нет значений по умолчанию, условий, функций, экранирования `$`
(`$$` остаётся `$$`). Это чисто текстовая утилита, ничего не знает про секреты.
Источник: [GNU gettext manual, envsubst](https://www.gnu.org/software/gettext/manual/gettext.html#envsubst_002e1).

### gomplate

Официальный сайт — **gomplate.ca** (документация docs.gomplate.ca), проект
[hairyhenderson/gomplate](https://github.com/hairyhenderson/gomplate) (Go,
один бинарник; не progrium и не «hairyfotr»). Зрелый проект, активен в 2026.

Ключевое отличие от envsubst — **datasources**: шаблон ссылается на внешние
источники по URI-схемам. Поддерживаются, среди прочего:

- `vault://` — HashiCorp Vault KV v1/v2, динамические секреты, auth через
  approle/token/github/userpass/aws/kubernetes, опция `_FILE` для кредов;
- `consul://` — Consul KV (+ генерация ACL-токена через Vault);
- `aws+smp`, `aws+sm`, `gcp+sm`, `s3`, `gs` — облачные сторы;
- `file://`, `env:`, `http(s)://`, `git://`, `merge:`, `stdin:`;
- парсинг JSON/YAML/TOML/CSV/**.env** из коробки.

Источник: [Datasources — gomplate documentation](https://docs.gomplate.ca/datasources/).

```sh
# traefik.yaml.tpl: password = {{ (datasource "vault" "kv/traefik").htpasswd }}
gomplate -d vault=vault:///kv/traefik -f traefik.yaml.tpl -o traefik.yaml
```

Функции шаблонов Go + собственные sprig-подобные (`crypto.*`, `net.*`, `conv.*`),
что закрывает типовые нужды (bcrypt, base64, sha256) без shell-обвязки.

### consul-template

Демон HashiCorp
([hashicorp/consul-template](https://github.com/hashicorp/consul-template)):
шаблоны с функциями `secret "/kv/path"` (Vault) и `key "path"` (Consul KV),
рендерит файл **и следит за изменениями**, перерендеривая и выполняя команду
(`command = "docker kill -s HUP traefik"`). Это bake-time + непрерывный re-render:
единственный из «шаблонизаторов» способ, который даёт настоящую ротацию секрета
без перезапуска контейнера. Минус для homelab — это ещё один постоянно работающий
процесс рядом с каждым сервисом (или sidecar-контейнер), и он привязан к
экосистеме Consul/Vault.

### vals

[helmfile/vals](https://github.com/helmfile/vals) — «Helm-like values loader»:
сканирует YAML/JSON на выражения `ref+<backend>://path#/key` и подставляет
значения из ~30 бэкендов, включая **Vault, OpenBao, SOPS-файлы, AWS SM/SSM,
GCP SM, 1Password, Bitwarden, Doppler, Infisical, Terraform state, HTTP JSON**,
плюс generic-провайдер `ref+exec://` (любая CLI-команда как источник секрета).
Три режима:

```sh
vals eval -f refs.yaml          # заменить refs значениями, вывести документ
vals exec -f env.yaml -- cmd    # засунуть refs в env и выполнить команду
vals env -f env.yaml            # вывести env для direnv/eval
```

Источники: [README vals](https://github.com/helmfile/vals). Для этого репозитория
интересен тем, что умеет читать **SOPS-файлы** (`ref+sops://`) — т.е. связка
«секреты зашифрованы в git + vals рендерит конфиг» работает без Vault.

### Go templates + sprig; ytt; jsonnet

- Чистые Go templates + библиотека функций
  [Masterminds/sprig](https://masterminds.github.io/sprig/) (~140 функций) — база,
  на которой построены Helm и gomplate; сама по себе секреты не получает.
- [ytt](https://carvel-dev-ytt.readthedocs.io/en/stable/) (Carvel) — YAML-aware
  шаблонизатор со схемами и оверлеями; секреты сам не берёт, обычно комбинируют
  с SOPS/vals. Избыточен для одного сервера.
- [jsonnet](https://jsonnet.org/) — язык конфигураций (Tanka/ArgoCD); то же
  самое: генерирует структуру, секреты доставляет внешний механизм.

Все четыре — инструменты **структуры**, а не доставки секретов; упомянуты для
полноты, потому что часто фигурируют рядом в обсуждениях templating.

## 2. Runtime-инъекция вместо bake-time

Идея: секрет никогда не записывается в файл — процесс получает его в окружении
или через FIFO/tmpfs-файл в момент старта.

### HashiCorp Vault Agent Templates

Vault Agent (или Vault Proxy) аутентифицируется в Vault автоматически
(auto-auth), рендерит шаблоны consul-template-языком с `{{ secret }}` и держит их
актуальными; канонический паттерн — init-container/sidecar в Kubernetes, но
работает и просто как демон на хосте. Источник:
[Vault Agent docs](https://developer.hashicorp.com/vault/docs/agents-and-proxy/agent),
[tutorial: Templating Vault secrets](https://developer.hashicorp.com/vault/tutorials/vault-agent-auto-renewal).

Применимость сюда: в репозитории уже стоит Vault (`vault/`, BSL 1.1, Raft, unseal
вручную после рестарта). Пока нет auto-unseal, Agent как постоянный компонент
даёт мало: до `vault operator unseal` он бесполезен. В
[secret-management-providers.md](./secret-management-providers.md) Vault прямо
помечен как «избыточен для статических API keys»; этот вывод сохраняется.

### Infisical CLI `run` / Infisical Agent

CLI: `infisical run -- <cmd>` подтягивает секреты проекта/environment в окружение
процесса; установка brew/apt/npm
([infisical.com/docs/cli/overview](https://infisical.com/docs/cli/overview)).
Для compose: `infisical run -- docker compose up -d`. В репозитории уже развёрнут
self-hosted Infisical (`infisical/`, PostgreSQL + Redis + backend, MIT CE) и в
README описан именно этот workflow (`infisical login/init/run`). Это самый
дешёвый путь к runtime-инъекции, потому что инфраструктура уже есть — минус
только зависимость доступности Infisical при каждом `docker compose up`.

### sops exec-env / exec-file

SOPS имеет встроенные команды передачи секретов дочернему процессу
([Advanced usage — getsops.io](https://getsops.io/docs/usage/advanced/)):

- `sops exec-env file.env 'cmd'` — секреты в окружение процесса, **на диск не
  пишутся**;
- `sops exec-file file.yaml 'cmd {}'` — расшифрованное содержимое передаётся
  через **FIFO** (plaintext только в памяти; `--no-fifo` — временный файл,
  удаляемый после выхода), `{}` — плейсхолдер пути.

Это готовая замена «render_template + chmod 600»: конфиг хранится зашифрованным
в git, а сервис стартует как `sops exec-file config.yaml.tpl-rendered '...'`.
Плюс флаг `--user` для сброса привилегий.

### direnv-подобные подходы

[direnv](https://direnv.net/) подгружает `.envrc` в шелл; сам по себе не про
секреты и не для сервисов, но `vals env` и `sops exec-env` сознательно совместимы
с этим паттерном (см. README vals). В homelab-контексте (systemd/docker) прямой
пользы мало — упомянут как родственная техника.

## 3. Шифрование в git

### SOPS + age — основной вариант

Проверено по первоисточникам ([getsops.io](https://getsops.io/docs/), CNCF Sandbox):

- форматы YAML/JSON/ENV/INI/BINARY; шифрует только значения, ключи остаются
  читаемыми — структура конфига видна в diff'е;
- age-идентичность: `age-keygen`, `SOPS_AGE_KEY_FILE`
  ([Age integration](https://getsops.io/docs/usage/identities/age/));
- **частичное шифрование**: `--encrypted-regex`, `--unencrypted-regex`,
  суффиксы `*_unencrypted`/`--encrypted-suffix`, коммент-regex — шесть взаимно
  исключающих опций ([Common operations](https://getsops.io/docs/usage/common-operations/));
- **редактирование**: `sops edit file.yaml` открывает расшифрованный файл в
  $EDITOR и шифрует обратно при сохранении; `sops set/unset` — точечные правки
  без редактора;
- **git diff в cleartext**: `.gitattributes` c `*.yaml diff=sopsdiffer` +
  `git config diff.sopsdiffer.textconv "sops decrypt"`
  ([Common operations](https://getsops.io/docs/usage/common-operations/));
- правила создания файлов по путям — `.sops.yaml` в корне репозитория.

Минусы (совпадают с secret-management-providers.md): ротация ручная; потеря
age-ключа = потеря всех секретов (ключ надо хранить отдельно от сервера);
plaintext всё равно возникает на диске в момент использования — вопрос лишь где
(FIFO/память через `exec-file` против постоянного файла через `decrypt -i`).

### git-crypt

[AGWA/git-crypt](https://github.com/AGWA/git-crypt) — прозрачное шифрование
**целых файлов** в git. Отличия от SOPS: нет частичного шифрования (весь файл
шифруется целиком — диффы нечитаемы, структура скрыта), нет редактора/regex,
ключ экспортируется вручную (`git-crypt export-key`). Проект стабилен, но
развивается медленно; для конфигов, где хочется видеть структуру в git, SOPS
удобнее. Для бинарников (например, бэкапы ключей) git-crypt или
`sops encrypt -i` бинарного файла равнозначны
([SOPS binary support](https://getsops.io/docs/usage/common-operations/)).

### Sealed Secrets

Kubernetes-only (controller + CRD + kubeseal); к Docker Compose неприменим.
Подробно разобран в
[secret-management-providers.md](./secret-management-providers.md) («хорош для
K8s-only… рассматривать как альтернативу SOPS») — здесь не повторяется.

## 4. Docker-native механизмы

### Compose secrets (file-based)

По официальной документации
([Manage secrets securely in Docker Compose](https://docs.docker.com/compose/how-tos/use-secrets/)):

```yaml
services:
  myapp:
    secrets: [my_secret]
secrets:
  my_secret:
    file: ./my_secret.txt
```

- секрет монтируется как **bind-mount одиночного файла** в
  `/run/secrets/<name>` внутри контейнера (только Linux-контейнеры);
- доступ выдаётся per-service через атрибут `secrets`;
- source может быть `file:` или `environment:` (последнее — для build secrets).

**Что это даёт и чего не даёт:** гранулярность доступа (процессы без явного
доступа не видят файл, в отличие от env vars, которые видны всему дереву процессов
и утекают в логи) — это реальное улучшение. Но **plaintext-on-disk не исчезает**:
файл-источник лежит на хосте в открытом виде, compose его просто маунтит.
«Short-lived» это становится только в Swarm mode (секреты раздаются через Raft
и монтируются в in-memory tmpfs) — обычный `docker compose` этого не делает.

Практический вывод: Compose secrets полезны, чтобы убрать секрет из `environment:`
и из `docker inspect`, но источник файла всё равно надо защищать (0600, вне git)
или шифровать — сами по себе они проблему не решают.

### Конвенция `_FILE`

Многие образы принимают `POSTGRES_PASSWORD_FILE=/run/secrets/db_pass` и читают
первую строку файла — конвенция, используемая Docker Official Images (mysql,
postgres и др.) ([та же страница docs.docker.com](https://docs.docker.com/compose/how-tos/use-secrets/)).
Комбинируется с любым источником файла: Compose secret, tmpfs, FIFO от
`sops exec-file`. Для образов **без** поддержки `_FILE` универсального решения
нет — нужен entrypoint-wrapper.

## 5. App-native возможности (лучший вариант, если доступен)

Если сервис сам умеет читать окружение — рендер вообще не нужен, и секрет
остаётся только в `.env`/runtime:

- **Gatus**: нативная интерполяция `$VAR` / `${VAR}` в любом месте config.yaml
  (используется в репозитории); `$` в литералах экранируется как `$$`.
  Источник: [TwiN/gatus README, «Use environment variables in config files»](https://github.com/TwiN/gatus#use-environment-variables-in-config-files).
- **Grafana provisioning**: во всех provisioning-конфигах доступны
  `$ENV_VAR_NAME` / `${ENV_VAR_NAME}`; есть нюанс двойной подстановки при `$$`.
  Источник: [Provision Grafana](https://grafana.com/docs/grafana/latest/administration/provisioning/#use-environment-variables).
- **Telegraf**: подстановка `${ENV_VAR}` из окружения в telegraf.conf
  ([Telegraf configuration docs](https://github.com/influxdata/telegraf/blob/master/docs/CONFIGURATION.md#environment-variable-substitution)).
- **Traefik**: основной конфиг целиком задаётся env/labels/file-provider; для
  file provider сами файлы провайдера можно рендерить любым инструментом выше.
- **Netdata go.d**: модуль prometheus принимает заголовки авторизации; в
  репозитории сейчас creds запечены через envsubst в
  `netdata/config/go.d/prometheus.conf` — кандидат №1 на перевод в env-based
  конфигурацию или на SOPS.

Общий принцип: **чем меньше мест, куда секрет попадает в открытом виде, тем
проще**. Порядок предпочтения: env-native → `_FILE` → runtime-рендер (FIFO) →
bake-time рендер с последующим удалением исходника.

## 6. Сравнительная таблица

| Подход | Plaintext на диске? | Зашифровано в git? | Runtime-ротация | Сложность | Зависимости | Пригодность для этого homelab |
| --- | --- | --- | --- | --- | --- | --- |
| Текущий: `.env` + envsubst (init.sh) | Да (`.env` + отрендеренные tpl) | Нет | Нет (перегенерация руками) | Низкая (уже написано) | bash, openssl, gettext | ⭐⭐⭐⭐ работает, но секреты не в git и дублируются |
| env-native интерполяция (Gatus/Grafana/Telegraf) | Только `.env` | Нет (без SOPS) | После рестарта сервиса | Низкая | Нет новых | ⭐⭐⭐⭐⭐ там, где сервис поддерживает |
| SOPS+age: хранение `.env`/tpl в git + `exec-env`/`exec-file` | Минимально (FIFO/окружение) | **Да** | Нет (re-encrypt руками) | Средняя | sops (~5 МБ), age (~3 МБ) | ⭐⭐⭐⭐⭐ закрывает «секреты в git» без сервера |
| gomplate (+vault/consul ds) | Да, в момент рендера | Нет (сам) | Через демон — нет; разово — да | Средняя | один бинарник | ⭐⭐⭐⭐ замена render_template, если появится Vault/KV |
| vals | Да, в момент рендера/exec-env | Нет (сам), но читает SOPS | Нет | Низкая–средняя | один бинарник | ⭐⭐⭐⭐ мост SOPS→конфиги, без нового сервиса |
| consul-template | Да (рендерит файлы) | Нет | **Да** (watch + command) | Средняя | демон + Consul/Vault | ⭐⭐ лишний демон, пока нет Consul/Vault-стора |
| Vault Agent templates | Да (рендерит файлы) | Нет | **Да** (auto-auth + lease renewal) | Высокая | Vault unsealed, агент | ⭐⭐ см. вывод prior-доки про Vault |
| Infisical `run` / Agent | Нет (окружение) | Нет (стор — БД Infisical) | Частично (рестарт процесса; Agent — watch) | Средняя | уже развёрнутый Infisical | ⭐⭐⭐⭐ этап 3 из prior-доки, инфраструктура есть |
| Compose secrets (`file:`) | Да (host-файл) | Нет | Нет | Низкая | Docker ≥ compose v2 | ⭐⭐⭐ убирает env из inspect, не решает диск |
| git-crypt | Да (расшифрованный working tree) | Да (целые файлы) | Нет | Низкая | git-crypt | ⭐⭐ диффы нечитаемы vs SOPS |
| Sealed Secrets | — | Да | Нет | — | Kubernetes | ❌ не для Compose (см. prior-доку) |

## 7. Рекомендация для этого репозитория

> Итог выбора см. в разделе 8: принятая связка — **SOPS + age + vals**
> (`ref+sops://` вместо `render_template`), разделение на `config.env` /
> `secrets.enc.env` вместо `encrypted_regex`.

Согласовано с [secret-management-providers.md](./secret-management-providers.md):
маршрут «этап 1: SOPS+age → этап 3: Infisical», Vault/OBao — только при появлении
dynamic secrets/PKI. Учитывая, что `vault/` и `infisical/` уже стоят:

1. **Не переписывать работающий pipeline целиком.** `write_env_file` /
   `ensure_secret` / compose-интерполяция — нормальный baseline для несекретных
   и низкочувствительных значений. Самописным остаётся только `render_template`
   — и только его стоит постепенно вытеснять.

2. **Первый шаг — SOPS + age (этап 1 prior-доки).**
   - `age-keygen`, ключ хранить вне сервера; `SOPS_AGE_KEY_FILE` на сервере.
   - `.sops.yaml` в корне: правило для `*/secrets.enc.*` с age recipient.
   - Хранить в git **зашифрованные копии** per-service `.env`
     (формат ENV поддерживается) и критичных `*.tpl`; рабочие plaintext-копии
     остаются локально как сейчас — это миграция без остановки сервисов.
   - `.gitattributes`: `diff=sopsdiffer` + `textconv "sops decrypt"` — читаемые
     диффы секретов.
   - Для новых сервисов предпочитать `sops exec-env secrets.enc.env 'bash init.sh && docker compose up -d'`
     вместо постоянного plaintext `.env`, где это возможно.

3. **Второй шаг — давить количество bake-time рендеров.**
   - Перевести сервисы с нативной env-интерполяцией (Gatus уже так устроен;
     Grafana provisioning, Telegraf при появлении) на неё — паттерн «конфиг в git
     целиком, секрет через `${VAR}` из окружения». Это устраняет
     `render_template` для них полностью.
   - Для оставшихся (netdata go.d, cup.json, части traefik.yaml) — либо
     `_FILE`-конвенция + Compose secrets, где образ поддерживает, либо оставить
     envsubst, но рендерить из SOPS-источника: `sops exec-env` → envsubst, либо
     взять **vals** (`ref+sops://`) как drop-in замену envsubst с дефолтами и
     без ручного whitelist'а имён.

4. **gomplate/vals — по мере надобности, не как самоцель.** Если/когда Vault
   станет основным стором (auto-unseal, KV-наполнение), gomplate `vault://`
   datasource или vals `ref+vault://` дают чистую замену `render_template` без
   изменения архитектуры вызова. Пока основного stora нет — достаточно связки
   SOPS + (опционально) vals, оба без демонов.

5. **Infisical `run` — этап 3, когда понадобится UI/RBAC/центральный стор**
   (prior-дока: «по мере роста команды/сервисов»). Инфраструктура уже развёрнута;
   включение сводится к `infisical login --domain … && infisical run -- docker
   compose up -d` и переносу секретов из `.env` в проект Infisical. Ротация тогда
   станет «обновил в UI → перезапустил compose», без правки файлов.

6. **Чего не делать:** consul-template/Vault Agent как резидентные демоны рядом
   с каждым сервисом (лишние движущиеся части для single-server compose);
   git-crypt (теряется читаемость структуры в git); Sealed Secrets (нет K8s-части
   задачи в этом контуре).

## 8. Принятая схема: SOPS + age + vals

Зафиксировано по итогам обсуждения (2026-08-23). Выбран git-вариант хранения:
секреты коммитятся в репозиторий зашифрованными; рендер конфигов — через
**vals** (`ref+sops://`) вместо самописного `render_template`.

### 8.1. Модель

| Роль | Файл | Формат | В git |
| --- | --- | --- | --- |
| Публичные значения сервиса | `<svc>/config.env` | plaintext ENV | да |
| Секреты сервиса | `<svc>/secrets.enc.env` | SOPS ENV (шифруется **целиком**) | да, шифротекст |
| Шаблон конфига | `<svc>/<name>.tpl.yaml` | plaintext + `ref+sops://` ссылки | да |
| Отрендеренный конфиг | `$APPS_STORAGE_PATH/<svc>/…` | результат `vals eval` | нет (выводим) |

Главный принцип: **секрет хранится ровно один раз — у своего владельца**, в его
`secrets.enc.env`. Все места использования ссылаются на него по имени — ссылка
не является значением, поэтому шаблоны безопасно коммитятся plaintext:

```yaml
# forgejo/metrics.tpl.yaml — plaintext
token: ref+sops://forgejo/secrets.enc.env#FORGEJO_METRICS_TOKEN
```

Кросс-сервисный доступ работает так же — ссылка указывает на чужой
`secrets.enc.env`, значение нигде не дублируется:

```yaml
# netdata/scrape.tpl.yaml
password: ref+sops://dawarich/secrets.enc.env#DAWARICH_METRICS_PASSWORD
```

Рендер заменяет `render_template` полностью:

```sh
vals eval -f netdata/scrape.tpl.yaml \
  > "$APPS_STORAGE_PATH/netdata/config/go.d/prometheus.conf"
```

`.env.example` больше не нужен: его роль выполняет `config.env` (публичные
значения по факту, а не «пример»).

### 8.2. Почему разделение файлов, а не `encrypted_regex` в одном

`encrypted_regex` привязывает безопасность к именованию переменных:
переименовал `POSTGRES_PASSWORD` → `DB_PASS`, regex перестал совпадать — и
значение молча уехало в git открытым текстом. Физическое разделение исключает
этот класс ошибок: файл либо `*.enc.*` (шифруется целиком и заведомо не содержит
публичных полей), либо в нём нет значений секретов вовсе (`config.env`,
шаблоны с ссылками).

Regex остаётся fallback'ом для файлов, которые нельзя разложить на ссылки:
бинарники или разовая зашифрованная копия legacy-`.env` при миграции.

### 8.3. Соглашения об именах

Правило: **«полезное» расширение — всегда последним**.

| Тип | Имя | Зачем расширение в конце |
| --- | --- | --- |
| Шаблон | `scrape.tpl.yaml` | подсветка синтаксиса YAML в IDE |
| Шифротекст | `secrets.enc.env` | SOPS выбирает формат по расширению: `.env` в конце → ENV-формат; `secrets.enc.env.enc` был бы прочитан как binary |

Механические правила для git:

- коммитятся `*.tpl.*` и `*.enc.*`;
- `.gitignore`: голые `*.env` (runtime) и отрендеренные конфиги;
- `.gitattributes` + textconv — читаемые диффы шифротекста (см. 8.4).

SOPS определяет зашифрованность по наличию `sops:`-метаданных внутри файла,
а не по имени, — суффиксы нужны людям, скриптам и gitignore-правилам.

### 8.4. Разовая настройка

```sh
# Рабочая станция (ключ задублировать в менеджер паролей / офлайн-бэкап!)
age-keygen -o age.txt        # публичный recipient (age1...) идёт в .sops.yaml

# Сервер
install -m600 age.txt ~/.config/sops/age/keys.txt
```

`.sops.yaml` в корне:

```yaml
creation_rules:
  - path_regex: '(^|/)secrets\.enc\.env$'
    age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
  - path_regex: '\.enc\.(ya?ml|json|ini)$'
    encrypted_regex: '(?i)(secret|token|password|pass|key)'  # fallback-ветка
    age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

`.gitattributes`:

```text
*.enc.env diff=sops
*.enc.yaml diff=sops
```

```sh
git config diff.sops.textconv "sops decrypt"
```

### 8.5. Дерево сервиса после миграции

```
forgejo/
├── compose.yaml            # публичное, ${VAR:?} читает os env
├── config.env              # публичные значения, plaintext, в git
├── secrets.enc.env         # ВСЕ секреты, шифротекст, в git
└── *.tpl.yaml              # шаблоны с ref+sops://, plaintext, в git
```

### 8.6. Операции

```sh
sops encrypt -i forgejo/secrets.enc.env        # зашифровать новый файл
sops forgejo/secrets.enc.env                   # правка в $EDITOR (туда-обратно)
sops set forgejo/secrets.enc.env '["KEY"]' '"v"'   # точечная правка
sops updatekeys forgejo/secrets.enc.env        # после ротации age-ключа
vals eval -f x.tpl.yaml                        # проверить рендер без записи
```

### 8.7. Ограничения схемы

- Возрастной ключ (age) — единственная критичная вещь: потеря = потеря всех
  секретов; хранить вне сервера.
- Ротация секрета ручная: поменял в `secrets.enc.env` → перезапустил сервис
  и перерендерил зависимые конфиги.
- Отрендеренные конфиги в `$APPS_STORAGE_PATH` по-прежнему содержат секреты
  plaintext — неизбежно для сервисов без `_FILE`/env-поддержки, но они выводимы
  из git-источников и не требуют бэкапа.
- При появлении потребности в UI/RBAC/центральном сторе — миграция на уже
  развёрнутый Infisical (`infisical run`), refs заменяются на окружение
  (см. раздел 7, этап 3).

---

## Не подтверждённые утверждения

Проверено по первоисточникам: возможности SOPS (formats, regex-опции, exec-env/
exec-file/FIFO, git textconv, binary, set/unset), datasources и auth gomplate
(vault/consul/облака/.env, `_FILE` для кредов), режимы vals (eval/exec/env,
бэкенды включая sops/vault/openbao/infisical), Compose secrets (bind-mount,
Linux-only, `_FILE` у mysql/postgres, environment-source для build), нативная
интерполяция Gatus и Grafana. Следующее — **не** проверено напрямую в этой
сессии и помечено по памяти/вторичным источникам:

1. **Swarm-mode tmpfs для секретов** — общеизвестное отличие Swarm от Compose;
   в актуальной compose-spec документации в рамках этой проверки не перепроверялось.
2. **Telegraf env-подстановка** — по docs/CONFIGURATION.md в репозитории influxdata;
   точная версия/поведение с вложенными `${}` не сверялись постранично.
3. **Infisical Agent** (резидентный демон, рендер `.env`/шаблонов с watch) —
   существование страницы docs/agent не верифицировано в этой сессии; проверять
   https://infisical.com/docs/llms.txt перед использованием. CLI `run` — верифицирован.
4. **Актуальные версии инструментов на 2026-08** (gomplate vX, vals vX, consul-template
   vX) — не снимались; перед внедрением смотреть releases соответствующих репозиториев.
5. **Темп роста/поддержка git-crypt в 2026** — оценка «медленно развивается»
   субъективна, по release-активности в этой сессии не проверялась.
6. **Утверждение, что `sops decrypt -i` оставляет plaintext на диске** — следует
   из семантики `-i` (in-place), но поведение wipe/права доступа файла специально
   не тестировались.

## См. также

- [secret-management-providers.md](./secret-management-providers.md) — сравнение
  vault-провайдеров и обоснование маршрута SOPS→Infisical→Vault.
- `scripts/lib/common.sh` — текущие функции pipeline.
- `vault/README.md`, `infisical/README.md` — уже развёрнутые сторы.

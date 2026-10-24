# Argo CD: установка, бутстрап и разборы

Argo CD — GitOps-контроллер кластера: под ним `clusters/casa/argocd/`, а
`clusters/casa/argocd/bootstrap/` применяется руками. Документ описывает
установку, бутстрап и разборы подводных камней, накопленные по ходу.

Целевое решение — Flux (`docs/research/k8s/argo-cd-vs-flux-cd.md`), поэтому
`clusters/casa/argocd/bootstrap/` устроен так, чтобы его можно было снести целиком: root рендерит
`clusters/casa/argocd/`, а каталог `clusters/casa/argocd/bootstrap/` в kustomization не входит.

| | |
|---|---|
| Чарт | `argo/argo-cd` 10.9.1 (community-maintained) |
| Argo CD | v3.5.3 |
| Namespace | `argocd` |
| URL | https://argocd.example.com |
| Параметры | `platform/casa/argocd/values.yaml` — только отклонения от дефолтов чарта |
| Управление | `clusters/casa/argocd/platform/argocd.yaml` — Argo применяет свой чарт сам |
| Маршрут | `platform/casa/argocd/manifests/route.yaml` — в источнике приложения |

Команды выполняются с macOS из корня рабочей копии: на сервере чекаута нет
(`docs/agents/server-access.md`).

## Установка

```sh
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Сначала посмотреть, что получится, не трогая кластер:
helm template argocd argo/argo-cd --version 10.9.1 -f platform/casa/argocd/values.yaml | less

helm install argocd argo/argo-cd \
  --version 10.9.1 \
  --namespace argocd --create-namespace \
  -f platform/casa/argocd/values.yaml \
  --wait
```

Это единственный ручной шаг. После `argocd app sync root` чарт ставит уже сам Argo
(`clusters/casa/argocd/platform/argocd.yaml`), релиз забывается — см. «Обновление Argo».

Gateway, `ClusterIssuer` и wildcard-`Certificate` отдельным шагом не ставятся:
они объявлены в юнитах `gateway-api`, `traefik` и `cert-manager` и приезжают
первыми волнами root'а.

## Проверка

```sh
kubectl -n argocd get pods
```

Ожидаемо пять подов: `argocd-application-controller-0`,
`argocd-applicationset-controller`, `argocd-redis`, `argocd-repo-server`,
`argocd-server`. Отдельный под `dex` не появится — он отключён в values.

```sh
curl --resolve argocd.example.com:443:<node1-ip> \
  -o /dev/null -sS -w '%{http_code}\n' https://argocd.example.com
```

Ожидаемо `200` (страница логина). `5xx` и transport error — ошибка.

## Вход

Пароль admin генерируется один раз при установке:

```sh
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Дальше https://argocd.example.com, логин `admin`.

CLI — два способа, потому что gRPC через прокси капризен:

```sh
# 1) через ингресс, поверх HTTP/1.1 (grpc-web)
argocd login argocd.example.com --grpc-web

# 2) через port-forward, вообще минуя Traefik
kubectl -n argocd port-forward svc/argocd-server 8080:80 &
argocd login localhost:8080 --plaintext
```

`--plaintext` нужен именно потому, что стоит `server.insecure: true` — Argo
отдаёт чистый HTTP. Если `argocd` CLI ещё не установлен:

```sh
curl -sSL -o /tmp/argocd https://github.com/argoproj/argo-cd/releases/download/v3.5.3/argocd-linux-amd64
sudo install -m 0755 /tmp/argocd /usr/local/bin/argocd
```

Сразу после первого входа:

```sh
argocd account update-password
```

## Что проверять в рамках эксперимента

Задача стенда — сравнить механики, поэтому смотреть стоит именно на них:

1. **Self-heal (главное отличие от Terraform).** Создать приложение, потом
   вручную увести кластер в сторону — Argo вернёт сам:
   ```sh
   argocd app create guestbook \
     --repo https://github.com/argoproj/argocd-example-apps.git \
     --path guestbook --dest-server https://kubernetes.default.svc \
     --dest-namespace argocd-trial \
     --sync-policy automated --self-heal --auto-prune
   kubectl -n argocd-trial scale deploy guestbook-ui --replicas=5
   ```
2. **Отсутствие Helm-релиза.** `helm list -n argocd-trial` пуст: Argo сделал
   `helm template` и применил результат сам. Сравнить с тем, как повёл бы себя
   Flux `HelmRelease`.
3. **Порядок в Helm-чартах.** У Argo его задают sync-waves
   (`argocd.argoproj.io/sync-wave`), а не `dependsOn`, как во Flux.
4. **`lookup` не работает.** Чарты, читающие существующие объекты кластера при
   шаблонизации (генерация паролей), отрендерятся с пустыми значениями.
5. **ApplicationSet** — генератор приложений из git-директорий и списка
   кластеров вместо ручного создания каждого Application. Возможность рабочая,
   но у нас не используется: генератор собирает `Application` в рантайме, и
   спека не лежит в git. Свойства проверены на стенде, решение — в разделе
   «Приложения из `clusters/casa/argocd/apps/`».

## Бутстрап: спеки Application'ов живут в git

Application'ы применяет корневой `Application` —
`clusters/casa/argocd/bootstrap/root.yaml`. Он рендерит каталог
`clusters/casa/argocd/` через kustomize и получает `AppProject`'ы и все
`Application` юнитов. Спеки лежат в git, поэтому изменение состава приложений —
это правка в репозитории, а не объект в кластере.

Источник манифестов — публичное зеркало на GitHub
(`https://github.com/Artemiy111/homelab.git`). Репозиторий публичный, клон
анонимный по HTTPS, поэтому `argocd repo add` и deploy key не нужны. Это же
разрывает цикл бутстрапа: манифесты Forgejo лежат в Forgejo, которую разворачивает
сам Argo, и на пустом кластере `ssh://git@forgejo…` недостижим.

Плата за зеркало — задержка: Argo видит состояние зеркала, а не Forgejo. Если нужен
синк ровно с Forgejo, её регистрируют вторым репозиторием и переключают `repoURL`:

```sh
argocd repo add ssh://git@forgejo.biplane.casa:2222/artemiy/homelab.git \
  --type git --name homelab \
  --ssh-private-key-path ~/.ssh/id_homelab-argocd_homelab-repo
```

Deploy key для этого добавляется в Forgejo (Настройки репозитория → Deploy keys,
только чтение), без пароля: Argo тянет репозиторий без человека на месте, и
зашифрованный ключ не откроет. Личный ключ аккаунта шире нужного — deploy key
ограничен одним репозиторием. Дальше `repoURL` в `root.yaml` и во всех `app.yaml`
меняется на этот адрес.

Два подводных камня:

- **Без `--ssh-private-key-path` команда не создаст рабочее подключение.** Argo
  не получает ключа и пытается обратиться к SSH-агенту, которого в поде нет:
  `error creating SSH agent: "SSH agent requested but SSH_AUTH_SOCK not-specified"`.
- **URL должен совпасть с `repoURL` посимвольно** — секрет сопоставляется с
  адресом точным сравнением строки.

Хост-ключ Forgejo уже прописан в `configs.ssh.knownHosts` в `platform/casa/argocd/values.yaml`,
поэтому проверка хоста проходит. Ключ добавлен из `known_hosts` macOS, где
`origin` уже работает, — то есть проверен существующим соединением; `ssh-keyscan`
для этого не годится, он опрашивает сервер и ничего не проверяет. Тип только
`ssh-rsa`: ed25519-хостового ключа Forgejo в `known_hosts` нет.

### Обновление Argo

Настройки и версия чарта меняются правкой в git — приложение `argocd` ставит их
само:

```sh
$EDITOR platform/casa/argocd/values.yaml
git commit -m "..." && git push
argocd app sync argocd
argocd app diff argocd          # пусто
```

Первая адопция уже стоящего релиза делается по рецепту из раздела «Адопция
существующего Helm-релиза» ниже, и там обязателен `--force-conflicts`: по нему
адоптировали и сам Argo. Причина та же, по которой флаг обязателен и для
`helm upgrade`: ConfigMap `argocd-ssh-known-hosts-cm` когда-то правили руками, и
поле `data.ssh_known_hosts` осталось за менеджером `kubectl-patch`; server-side
apply без этого флага отказывается перехватывать чужое поле и валится:

```
Upgrade "argocd" failed: conflict occurred while applying object
argocd/argocd-ssh-known-hosts-cm /v1, Kind=ConfigMap: Apply failed with
1 conflict: conflict with "kubectl-patch" using v1: .data.ssh_known_hosts
```

После адопции Helm-релиз «забывается», иначе `helm upgrade` начнёт конкурировать
с Argo:

```sh
kubectl -n argocd delete secret -l owner=helm,name=argocd
helm list -n argocd             # пусто, ресурсы и поды на месте
```

Откат после этого — revert коммита в git: история Helm'а удаляется вместе с
release-секретами.

Если сломан сам контроллер и синкать некому — `helm install` чарта с values из
юнита (как при первой установке) и разбор через `kubectl`: маршрут на панель и
секрет с ключом живут в кластере, поэтому доступ обычно не теряется. У
приложения `Prune=false`, так что неудачный синк ничего своего не удалит.

`resource.customizations.*` — `ignoreDifferences` и `health` — контроллер
читает при старте, а не на лету. Поэтому после синка, меняющего `argocd-cm`,
нужен рестарт `application-controller`. Проверить, что правила доехали:

```sh
kubectl -n argocd get cm argocd-cm -o jsonpath='{.data}' \
  | python3 -c 'import json,sys; print([k for k in json.load(sys.stdin) if k.startswith("resource.customizations")])'
```

### Как увидеть расхождение настроек с репозиторием

Расхождение ищет сам Argo:

```sh
argocd app diff argocd
```

Раньше это приходилось делать вручную — `helm get values --all` против файла,
потому что настройки ехали Helm'ом мимо git и расхождение не ловил никто. Тот
способ, для истории, сравнивал только ключи, заданные файлом:

```sh
python3 - <<'EOF'
import json, subprocess, yaml
live = json.loads(subprocess.run(
    ["helm", "get", "values", "argocd", "-n", "argocd", "--all", "-o", "json"],
    capture_output=True, text=True).stdout)
want = yaml.safe_load(open("platform/casa/argocd/values.yaml"))

def flat(d, p=""):
    out = {}
    for k, v in (d.items() if isinstance(d, dict) else []):
        out.update(flat(v, f"{p}.{k}" if p else str(k)) or {f"{p}.{k}": v})
    return out

L, W = flat(live), flat(want)
for k in sorted(W):
    if str(L.get(k)).strip() != str(W[k]).strip():
        print(f"{k}\n   live: {str(L.get(k))[:90]}\n   file: {str(W[k])[:90]}")
EOF
```

Проверено 2026-10-11, когда `traefik` не сходился с репозиторием из-за
неприменённого правила для `Gateway`: файл содержал его с #921, а в `argocd-cm`
его не было, потому что `helm upgrade` после #921 не делался. Ничто это
расхождение не ловило — релиз Helm и репозиторий живут отдельно.

Сам root применяется руками — ровно как и сам Argo ставится `helm install`:
контроллер не может применить Application, который сам его и создаёт.

```sh
kubectl apply -f clusters/casa/argocd/bootstrap/root.yaml
argocd app sync root
```

Проверка, что переход состоялся и ничего не сломалось:

```sh
argocd proj get upstream              # проект создан
argocd app list --project upstream               # 18 компонентов
argocd app list --project homelab                # 8 сервисов
argocd app list --project homelab-cluster-readers # 5 сервисов, alloy-profiler OutOfSync
argocd app diff traefik               # пусто
```

Дальше спеки меняются только коммитом: правка в git доезжает сама, `kubectl apply`
по одному файлу не нужен.

Что root делает и чего не делает:

| | Зачем |
|---|---|
| `automated.prune: true` | удалённый из git `Application` исчезает из кластера |
| `FailOnSharedResource=true` | root не перехватывает ресурсы, принадлежащие другому `Application`, а падает |
| `PruneLast=true` | обновление раньше удаления: ресурс появляется до исчезновения старого |

`PruneLast` защищает только от удаления при замене. От prune сирот — когда
ресурс не входит в desired state вовсе — он не помогает: такой ресурс всё
равно удаляется, просто позже. Против него снимают prune точечно, аннотацией на
самом ресурсе (`docs/adr/0013`).
| `selfHeal` не включён | отладочные правки Application в кластере не откатываются |
| finalizer не задан | удаление root не сносит компоненты каскадом |
| `retry` с backoff | компенсирует «упавший sync не повторяется сам» для самого root |
| `ignoreDifferences` у `Application` | нет: политика синка (в том числе `prune`) принадлежит git, и правка в `app.yaml` доезжает |

Ограничения, которые надо знать до того, как что-то сломается:

- **`destinations` в `appprojects/upstream.yaml` — белый список из 16 namespace.**
  Компонент в новом namespace не задеплоится, пока его не впишут руками. Сделано
  намеренно: `clusterResourceWhitelist` у всех 18 компонентов одинаковый и
  включает `*`, ограничивать по kind бессмысленно — операторы законно создают
  CRD, ClusterRole, PriorityClass и webhook-конфигурации. Единственное, что
  осталось сузить, — куда им можно.
- **`namespaceResourceWhitelist` не задан намеренно.** Он не только разрешает,
  но и фильтрует resource tree в UI: не внесённые в него `Pod`/`ReplicaSet`
  перестают быть видны под `Deployment`. Плюс namespaced-ресурсы Argo
  ограничивает deny-list'ом, а не allow-list'ом, так что ограничивать их
  whitelist'ом — не то самое.
- **Root живёт в проекте `default`.** Если `default` когда-нибудь ужесточат
  (Argo документирует, как убрать из него все права), root откажется работать —
  тогда ему нужен собственный проект.
- **`prune: true` у root, а finalizer у `Application` в манифестах не задан.**
  Это осознанно: на одном узле ошибка в prune бьёт по одному сервису. Проверьте
  цену этой ошибки на инциденте 0009 ниже, прежде чем считать её небольшой.
  Но есть исключение,
  о котором надо знать: Argo добавляет `pre-delete-finalizer.argocd.argoproj.io`
  сам, когда в рендере чарта появляется `PreDelete`-хук. На 2026-10-04 это
  произошло с `longhorn` и `vault-secrets-operator`, и удаление спеки из git у
  этих двух снесёт ресурсы каскадом, а у остальных оставит сиротами.
  `resources-finalizer.argocd.argoproj.io` при этом есть не у всех: на 2026-10-05
  его носили три `Application`, созданных `ApplicationSet`, и ни один из 18
  написанных рукой в `applications/`, хотя `automated`-синк включён у обоих
  наборов. Проверять надо всегда, а не по списку:
  ```sh
  kubectl -n argocd get application -o \
    custom-columns='NAME:.metadata.name,FINALIZERS:.metadata.finalizers'
  ```
- **Ошибка в prune у root стоит дороже, чем кажется.** На 2026-10-10 в 18:37
  UTC за две секунды были пересозданы 22 объекта `Application` и 14 namespace'ов
  ([инцидент 0009](../incidents/0009-applications-and-namespaces-recreated.md)).
  Тринадцать namespace'ов вернулись сами — их содержимое лежит в `manifests/`.
  `uptime-kuma` не вернулся: его MariaDB применяется руками (#902), CR исчез
  вместе с namespace, PVC — вместе с ним, сервис стоял 15,5 часов, данные
  потеряны. **Всё, что не под Argo, не переживает пересоздание namespace.**
  Увидеть такое можно по датам создания:
  ```sh
  kubectl get ns --sort-by=.metadata.creationTimestamp \
    -o custom-columns='NS:.metadata.name,CREATED:.metadata.creationTimestamp'
  kubectl -n argocd get application \
    -o custom-columns='NAME:.metadata.name,CREATED:.metadata.creationTimestamp' \
    --sort-by=.metadata.creationTimestamp
  ```
  Массовое пересоздание в пределах минуты — признак того, что что-то удалило
  объекты, а не что-то их обновило.

### Внутренние значения (домен, externalIPs)

Часть values — environment-specific: адрес узла в `traefik` и `forgejo`, issuer и
redirect URL в `headlamp`, домен в `dns01-webhook`. Секретов среди них
нет: реальные credentials приходят из Vault через VSO, в Application лежат
ссылки `existingSecret` и `secretKeyRef`.

Значения лежат в публичном репозитории: у `traefik` — в
`platform/casa/traefik/values.yaml`, у остальных компонентов пока инлайн в
`valuesObject` Application. Отдельный приватный слой был отменён
(`docs/adr/0009`): домен и так публичен — wildcard-сертификат Let's Encrypt
попадает в Certificate Transparency, где виден базовый домен, — а приватный
репозиторий стоил второго источника в каждом Application, SSH-подключения Argo,
хост-ключа Forgejo и роли в Vault. Плата: `terraform plan` в этих модулях
больше нельзя прогонять из публичного репозитория, пока `terraform.tfvars`
не на месте, а CI их не проверяет.

Список `gitea.oauth` задаётся целиком: merge-patch заменяет массивы целиком, и
частично перекрыть список нельзя, поэтому в Application перечислены все поля
элемента, а не только `autoDiscoverUrl`.

- **Упавший sync не повторяется сам.** После ошибки контроллер логирует
  `failed previous sync attempt ... will not retry` и ждёт новый revision или ручной sync,
  даже при включённом `automated`. У `root` это компенсировано полем `retry`; у 18
  платформенных `Application` — пока нет, там выкручивается вручную. Форсировать
  из кластера (без CLI):
  ```sh
  kubectl -n argocd patch application local-path-provisioner --type merge \
    -p '{"operation":{"sync":{"prune":true}}}'
  ```
  (`operation` — поле верхнего уровня Application, не в `spec`.)
- **Immutable-поля Kubernetes не дают Argo починить дрейф** — типовая история: StorageClass
  (`reclaimPolicy`, `volumeBindingMode`, `provisioner`, `parameters`) или Service (`clusterIP`).
  Argo будет вечно `OutOfSync` с `field is immutable`; лечится удалением объекта, после чего
  Argo создаёт его заново.

## Приложения из `clusters/casa/argocd/apps/`

По одному `Application` на сервис, лежат в `clusters/casa/argocd/apps/<сервис>.yaml`
и применяются тем же корневым `Application`, что и платформенные компоненты.
Способ тот же, что у 18 компонентов в `applications/`, — в репозитории один
стандарт на все 31 приложение.

Цена — повтор `repoURL` и `targetRevision` в каждом файле. Экономия на нём не
стоит: генератор собирает `Application` в рантайме, спека не лежит в git, и
PR, добавляющий сервис, не показывает ни `prune`, ни `selfHeal`, ни
`syncOptions` — то есть ровно то, что Argo сделает с кластером.

Что было вместо этого: `ApplicationSet` с git-генератором файлов, который читал
реестр `app.yaml` из каталога сервиса — файл из четырёх полей (`name`, `dir`,
`namespace`, `project`). От него отказались, и вот почему:

| Проблема реестра | Что вместо |
|---|---|
| `Application` собирается в рантайме, в git не лежит | спека в файле, видна в диффе PR |
| реестр `app.yaml` не проверялся ни одним гейтом: `kubeconform` сканирует `apps/casa/*/manifests`,
`platform/casa` и `clusters/casa/argocd`, а `app.yaml` в каталоге сервиса не попадал ни в одну дорожку | спека лежит в `clusters/casa/argocd/apps/` и проверяется kubeconform как `Application` |
| `prune` задан литералом в `spec.template` и достаётся всем без исключения — сервисы с данными защищены только тем, что их не добавили | `prune` виден в файле сервиса |
| поля реестра — подмножество `spec.Application`: чарты (`3x-ui`, `element`) и multi-source values (`traefik`) не выражались | выражаются, отдельный `Application` на каждый случай |
| `path` в реестре перекрывается служебным параметром генератора — пришлось переименовать в `dir` | таких коллизий нет |
| добавление сервиса — одна строка в git, но сервис появляется в кластере сам и незаметно | добавление сервиса — новый файл плюс строка в `clusters/casa/argocd/kustomization.yaml`, и в ревью видно, что сервис добавлен под Argo |

Обходной путь для boolean-полей (`templatePatch`, где `prune: {{ .prune }}`
рендерится как YAML, а не как строка) существует и был бы пригоден — но он не
решает ни одну из проблем выше, только последнюю.

### Перевод сервиса на Argo

Один сервис — один файл `clusters/casa/argocd/apps/<сервис>.yaml` плюс строка в
`clusters/casa/argocd/kustomization.yaml`. Ниже — порядок для сервиса, который уже применён
руками; AGE подов при этом не должен сброситься.

```sh
# 1. Снять finalizer с Application, если он есть. Иначе удаление спеки
#    снесёт управляемые ресурсы каскадом, а вместе с ними Namespace.
#    Пока сервис обслуживает ApplicationSet — см. «Снятие ApplicationSet».
kubectl -n argocd get application <svc> -o \
  custom-columns='NAME:.metadata.name,FINALIZERS:.metadata.finalizers'
kubectl -n argocd patch application <svc> --type json \
  -p '[{"op":"remove","path":"/metadata/finalizers"}]'

# 2. Проверить рендер до синка: Argo покажет расхождение, если что-то не так.
argocd app diff <svc>

# 3. Синк и проверка, что поды те же.
argocd app sync <svc>
kubectl -n <ns> get pods
```

`server-side apply` обязателен (`ServerSideApply=true`): часть сервисов
применялась Helm'ом, и client-side apply полез бы чинить
`last-applied-configuration`, которого после Helm нет.

### Проект сервиса

`homelab` либо `homelab-cluster-readers`. Второй нужен шести сервисам, читающим
кластер целиком, — `alloy`, `alloy-profiler`, `beyla`, `homepage`,
`victoria-metrics`, `elk`. Список имён и причина — в разделе
«Проект `homelab-cluster-readers`».

### Отключённый сервис

Поле `suspend` у `Application` нет — это механизм Flux. В Argo эквивалент
отсутствие блока `syncPolicy.automated`: приложение существует, но никогда не
синкается само, поэтому Argo не создаст удалённые ресурсы обратно.

Так выключен `alloy-profiler`: `DaemonSet` удалён из кластера вручную
2026-10-06, входящих профилей в `pyroscope` нет. Файл Application оставлен с
манифестами, но без `automated`; включение — убрать блок из файла. Приложение
при этом постоянно `OutOfSync`, и это служит индикатором выключенного
состояния.

Список выключенного, чтобы не выводить его археологией:

Проверено 2026-10-10: `authentik` и `gitlab` снова синхронизируются
автоматически, `netdata` удалён из репозитория целиком. Актуальное состояние —
по `app.yaml` сервиса, а не по этой таблице.

С 2026-10-12 в списке `local-ai`: юнит лежал в git без `Application` вовсе
(#949), поэтому его не было видно ни в `argocd app list`, ни по `attachedRoutes`
Gateway.

| Сервис | Как выключен | Включение |
|---|---|---|
| `alloy-profiler` | Application без `syncPolicy.automated` | вернуть блок `automated` |
| `local-ai` | Application без `syncPolicy.automated` | вернуть блок `automated` |

Проверки выключенных сервисов удалены из `apps/casa/gatus/manifests/config/config.yaml`, а не
помечены `enabled: false`. `enabled: false` останавливает опрос, но Gatus хранит
последний результат в своей БД и продолжает показывать его красным — доска
остаётся вечно красной, а её перестаёшь открывать. По этому списку и таблице
выше восстанавливается, что отключено и почему.

### Про `prune`

`prune: true` означает: ресурс, удалённый из git, удаляется и из кластера. У
юнитов он включён: иначе удалённый из репозитория Deployment продолжит жить, а
сгенерированный ConfigMap останется в кластере сиротой и приложение будет вечно
`OutOfSync`, не отличая это от настоящего дрейфа.

То, что терять нельзя, снимает prune точечно — аннотацией
`argocd.argoproj.io/sync-options: Prune=false` на самом ресурсе. Так защищены PVC
(данных в git нет, и судьбу тома решает `reclaimPolicy` класса) и namespace
(prune унёс бы всё содержимое, включая применённое руками — инцидент 0009).
Правило и причины — `docs/adr/0013`, соответствие держит
`scripts/argocd-prune.sh --check`.

Платформенные компоненты живут по своему правилу: они ставят операторов, и
кластерные CRD из git не удаляются (app-level `Prune=false`).

Обратная сторона `prune: true` — удаление спеки сервиса из git удаляет и его
ресурсы, если у `Application` есть `resources-finalizer.argocd.argoproj.io`:
finalizer заставляет Argo снести управляемые ресурсы перед тем, как объект
исчезнет. Проверять надо всегда, а не по списку.

Три таких `Application` нашлись 2026-10-06 — их создал `ApplicationSet`, и
finalizer добавлял именно он, а не Argo при `automated`-синке: наши 25
`Application`, написанные рукой, ни одного не имеют, хотя `automated` включён
у всех. Отсюда и порядок ниже.

### Снятие `ApplicationSet`

Удаление `ApplicationSet` каскадом удаляет созданные им `Application` — у них
`ownerReferences` с `blockOwnerDeletion`. Если у них же есть
`resources-finalizer`, каскад продолжается в managed-ресурсы и `Namespace`.
На 2026-10-06 с этим столкнулись при снятии `ApplicationSet apps`:
`code-server` и `mermaid-live-editor` потеряли бы поды.

Просто снять finalizer руками нельзя: `applicationset-controller` в пределах
цикла реконсиляции возвращает его и логирует `updated Application`. Сначала
запрещаем контроллеру трогать эти `Application`, потом снимаем finalizer, потом
удаляем сет:

```sh
# 1. create-only запрещает и изменять, и удалять существующие Application.
kubectl -n argocd patch applicationset apps --type merge \
  -p '{"spec":{"syncPolicy":{"applicationsSync":"create-only"}}}'

# 2. Теперь finalizer держится снятым (проверять после реконсиляции, не сразу).
for a in code-server mermaid-live-editor node-exporter; do
  kubectl -n argocd patch application "$a" --type json \
    -p '[{"op":"remove","path":"/metadata/finalizers"}]'
done
kubectl -n argocd get application \
  -o custom-columns='NAME:.metadata.name,FINALIZERS:.metadata.finalizers' \
  | grep -v '<none>'

# 3. Удалить сет — теперь из git коммитом или руками.
```

Без шага 1 шаг 2 не имеет эффекта, а без шага 2 шаг 3 роняет сервисы. После
перехода финализаторов нет ни у одного `Application`, поэтому будущее удаление
спеки оставит ресурсы сиротами — сносить их руками.

### Проект `homelab`

Единственное кластерное право — свой `Namespace`. Приложение обязано уметь
создать свой, но не может трогать `CRD`, `ClusterRole`, `StorageClass` и прочее
на уровне кластера. Это структурная защита от эскалации: нельзя случайно
выдать сервису кластерные права, как это делал чарт headlamp
(`clusterRoleBinding.create: true`).

`namespaceResourceWhitelist` не задан намеренно. Он не только разрешает, но и
фильтрует resource tree в UI: не внесённые в него `Pod`/`ReplicaSet`
перестают быть видны под `Deployment`. Плюс namespaced-ресурсы Argo
ограничивает deny-list'ом, а не allow-list'ом — ограничивать их whitelist'ом
не то самое.

`destinations` — `namespace: '*'`, в отличие от проекта `upstream`: перечислять
40+ namespace'ов сервисов означало бы править проект при каждом новом
сервисе. Границы сервиса держат его манифесты.

### Проект `homelab-cluster-readers`

Шесть приложений читают кластер целиком — `alloy`, `alloy-profiler`, `beyla`,
`victoria-metrics`, `homepage`, `elk`. Первым пяти и `elk` нужен
`ClusterRole`, а проект `homelab` разрешает только `Namespace`, поэтому они
живут в отдельном проекте `homelab-cluster-readers`.

Отдельно про `Namespace`: сервис, который приносит `namespace.yaml` в своих
манифестах, требует и права создать `Namespace`. В этом проекте такой один —
`homepage`; остальные четыре живут в уже существующем `monitoring`. Поэтому
whitelist содержит `Namespace` с именем `homepage`, а не вид целиком. Без этой
записи синк падает с «`Namespace` is not permitted in project».

Почему отдельный, а не расширить `homelab`: добавление `ClusterRole` в его
whitelist дало бы право всем ~45 сервисам проекта, включая те, которые его не
запрашивали. Здесь право есть ровно у шести.

Whitelist перечисляет не вид целиком, а конкретные имена — двенадцать записей
по шесть пар `ClusterRole`/`ClusterRoleBinding`. Схема
`ClusterResourceRestrictionItem` допускает `name` с glob-паттернами, а без
`name` совпадает всё в группе и виде. Поэтому сервис не сможет создать
посторонний `ClusterRole`, даже если тот появится в манифесте по ошибке.

`clusterResourceWhitelist` — единственный рычаг на кластерные объекты:
namespaced-ресурсы Argo ограничивает deny-list'ом, cluster-scoped —
allow-list'ом. Нет записи → нельзя ни создать, ни удалить. Отсюда свойство,
которого нет у `upstream` с его `*`/`*`: `prune: true` у приложения в
`homelab` или `homelab-cluster-readers` физически не может задеть чужой
кластерный объект.

Почему ограничение нужно. Argo применяет манифесты от имени одной учётки
`system:serviceaccount:argocd:argocd-application-controller`, и у неё есть
права на `create`/`delete` любых кластерных объектов — иначе не поставились бы
операторы Longhorn, Gateway API и cert-manager. `AppProject` вторая линия
поверх этого. Без неё ошибка в манифесте (убрали `ClusterRole` из
`manifests/`)
привела бы не к отказу Argo, а к удалению `ClusterRole` из кластера: сборщик
логов или метрик молча теряет права и перестаёт работать.

### Про `kustomization.yaml`

Манифесты лежат в `apps/casa/<сервис>/manifests/`, и Argo в режиме
plain-каталога **не
рекурсирует в подкаталоги**: каталог без `kustomization.yaml` считается пустым
и приложение отвечает «app path does not exist». Проверено на стенде — в том
числе пробным `Application` с новым именем, у которого тот же путь работал.

Поэтому каждому сервису под Argo нужен `kustomization.yaml` в корне каталога.
Это заодно делает тип приложения детерминированным: не приходится полагаться
на то, как именно Argo определит каталог.

### Про HTTPRoute и дефолты CRD

Apiserver подставляет в `HTTPRoute` шесть полей, которых нет в манифесте:

| Поле | Значение |
|---|---|
| `spec.parentRefs[].group` | `gateway.networking.k8s.io` |
| `spec.parentRefs[].kind` | `Gateway` |
| `spec.rules[].backendRefs[].group` | `""` |
| `spec.rules[].backendRefs[].kind` | `Service` |
| `spec.rules[].backendRefs[].weight` | `1` |
| `spec.rules[].matches` | `[{path: {type: PathPrefix, value: /}}]` |

Отсюда росла старая беда: приложение оставалось `OutOfSync` навсегда, при этом
`argocd app diff` был пуст, а `argocd app sync` отрабатывал успешно. Правила
`ignoreDifferences` для `HTTPRoute` и `Gateway` больше не нужны и удалены:
расхождение считается server-side diff'ом (`controller.diff.server.side`), то
есть dry-run применением, и дефолты apiserver попадают в него так же, как в живой
объект. Проверено на стенде — удаление правил из `argocd-cm` и рестарт
контроллера не разошли ни одного приложения.

Второй источник той же беды — устаревший `last-applied-configuration` у объекта,
который когда-то применяли руками; он разобран в `platform/casa/argocd/README.md`.
Правкой всех `apps/casa/*/manifests/route.yaml` вопрос не решается в любом
случае: дефолты вернутся при обновлении CRD.

## Про таймауты выборки репозитория

Источник манифестов — внешний (зеркало на GitHub), и его fetch упирается в два
предела сразу. Контроллер ждёт ответа repo-server
`controller.repo.server.timeout.seconds` секунд (поднят до 300), а сам
repo-server бросает `git fetch` примерно через 90 секунд — клиентского таймаута
fetch в его флагах нет, поэтому вторым пределом управлять нечем. Симптом, когда
не укладывается первое: приложения уходят в `Unknown` с `DeadlineExceeded` на
стороне контроллера, а в логах repo-server видно
`git fetch origin --tags --force --prune failed timeout after 1m30s`.

## Про кэш ошибок рендера

`controller.default.cache.expiration` по умолчанию **24 часа**, и ошибка
рендера кэшируется на весь этот срок. Практическое следствие: если приложение
упало с ошибкой, то исправление манифестов в git не будет замечено до конца
срока. Не помогают ни `argocd app get --refresh`, ни
`argocd.argoproj.io/refresh=hard`, ни перезапуск `repo-server`.

Обходной путь, которым пришлось воспользоваться при переводе первых трёх
сервисов: изменить ключ кэша. Он складывается из namespace, имени приложения,
URL и пути — но **не** из ревизии, так что фиксация `targetRevision` не
помогает. Сработало удаление и пересоздание `Application` под другим именем.

Понижено до `10m` в `platform/casa/argocd/values.yaml`, в `configs.params` — отдельного
значения `controller.default.*` в чарте 10.9.1 нет, ключ попадает в
`argocd-cmd-params-cm` через эту свободную карту. Компонент читает cm при
старте, поэтому после синка, меняющего этот ключ, нужен рестарт
`application-controller`. Дефолт — сутки: если правило не доехало, об ошибке
рендера стоит думать как о «залипшей на сутки».

## Задержка применения

Webhook не настроить: источник манифестов — зеркало на GitHub, и Argo умеет
принимать его webhook'и, но сам Argo доступен только из локальной сети и
tailnet, то есть из интернета GitHub до него не дотянется. Поэтому root ждёт
следующей сверки ревизии (`timeout.reconciliation: 60s`), и спека `Application`
доезжает в кластер с задержкой — это нормально и специально не ускорено.

`kube-state-metrics.yaml` — Application, который ставит официальный чарт
`prometheus-community/kube-state-metrics` в namespace `monitoring`. Он отдаёт
метрики состояния объектов кластера (`kube_*`), которых нет у node-exporter.
Это уже не пробный стенд, а рабочий компонент, поэтому держать его нужно
**только** под Argo — не дублировать манифестами для будущего Flux.

```sh
kubectl apply -f clusters/casa/argocd/platform/kube-state-metrics.yaml
argocd app get kube-state-metrics
argocd app diff kube-state-metrics
```

`syncPolicy` автоматический (prune + selfHeal): Argo сам приводит кластер к
состоянию чарта. Проверка self-heal — увести ресурс в сторону и дождаться
возврата (сравнимо с ручным `helm upgrade`):

```sh
kubectl -n default scale deploy kube-state-metrics --replicas=3
argocd app get kube-state-metrics
```

Метрики скрейпит vmagent (job `kube-state-metrics` в
`apps/casa/victoria-metrics/manifests/config/vmagent/scrape.yml`) — после синка нужно
перезапустить vmagent.

## Адопция существующего Helm-релиза (на примере headlamp)

`headlamp.yaml` переводит уже работающий Helm-релиз под Argo **без
пересоздания** ресурсов. Порядок применим и к боевому Traefik.

```sh
kubectl apply -f clusters/casa/argocd/platform/headlamp.yaml

argocd app diff headlamp        # желаемое (чарт) vs живое: расхождений быть не должно
argocd app sync headlamp        # server-side apply берёт ownership, Pod не пересоздаётся

kubectl -n headlamp get pods    # AGE не должен сброситься
```

Так как релиз ставился Helm 4 (server-side apply), адопция идёт
`ServerSideApply=true` — иначе client-side apply полез бы чинить
`last-applied-configuration`, которого Helm не оставляет.

Дальше нужно «забыть» Helm-релиз, чтобы `helm upgrade` не конкурировал с Argo.
Опции «удалить релиз, но оставить ресурсы» у Helm нет: `--keep-resources` не
существует ни в 3, ни в 4, а `--cascade orphan` — это лишь propagation policy
при удалении самих объектов. Рабочий способ — удалить release-секреты; ресурсы
при этом не трогаются, а релиз пропадает из `helm list`:

```sh
kubectl -n headlamp delete secret -l owner=helm,name=headlamp
```

Проверка: `helm list -n headlamp` пуст, ресурсы и Pod на месте.

Границы владения: чарт по умолчанию создаёт `ClusterRoleBinding headlamp-admin`
на SA пода `headlamp` — то есть выдаёт cluster-admin самому поду. Здесь это
выключено (`clusterRoleBinding.create: false`): под остаётся бесправным и
бежит под SA `headlamp`. Права приходят из OIDC: Headlamp отдаёт apiserver'у
`id_token`, который тот проверяет по подписи Zitadel и читает из него claim
`role` как группу. `cluster-admin` выдаётся группе `oidc:admin`
(`platform/casa/headlamp/manifests/headlamp-admins.clusterrolebinding.yaml`), поэтому он есть
только у пользователей с ролью `admin` в Zitadel. `extraManifests` в этом
Application больше нет. Маршрут
(`platform/casa/headlamp/manifests/route.yaml`) — вне Application.

### Traefik

`traefik.yaml` — тот же приём для боевого ingress (единственный вход на
`<node1-ip>`, поэтому проверять `argocd app diff` особенно внимательно).
Отличия от headlamp:

- `skipCrds: true` — CRD `*.traefik.io` кластерные; под управлением Argo они
  при удалении приложения снесли бы все `IngressRoute`/`Middleware` кластера.
- values лежат в `platform/casa/traefik/values.yaml` и подключены через `$values` —
  второй источник в `spec.sources`, ссылающийся на тот же репозиторий (зеркало по
  HTTPS).
  Раньше те же 32 значения были продублированы инлайн в `valuesObject`, и правка
  файла молча расходилась с кластером. Теперь файл — единственный источник.
- `service.spec.externalIPs` — адрес узла, и это нагрузочное значение: без него
  Traefik не принимает трафик на адрес узла. Живёт в values-файле.
  Домен здесь не нужен — он в `Gateway` (`platform/casa/traefik/manifests/gateway-homelab.yaml`)
  и в маршрутах юнитов, а не в values Traefik.
- Значения из приватного репозитория сюда не возвращаются (`docs/adr/0009`):
  домен и адрес узла публичны по решению.
- Чарт сам создаёт `ClusterRole`/`ClusterRoleBinding`/`IngressClass` — они под
  управлением Argo (в отличие от RBAC headlamp, который вне чарта).

## Отклонения от дефолтов чарта

| Параметр | Дефолт | Здесь | Зачем |
|---|---|---|---|
| `global.domain` | `argocd.example.com` | реальный домен | попадает в генерируемые URL |
| `configs.params."server.insecure"` | `false` | `true` | TLS терминирует Traefik |
| `configs.cm."timeout.reconciliation"` | `120s` | `60s` | реактивнее на одном репо |
| `dex.enabled` | `true` | `false` | SSO будет внешний (authentik) |
| `notifications.enabled` | `true` | `false` | контроллер уведомлений пока не нужен |
| `*.resources` | `{}` | заданы | однозный кластер: без limits контроллер может вытеснить приложения |

## Удаление

```sh
# Сначала root: иначе он успеет восстановить то, что удаляется ниже
kubectl delete application root -n argocd

# Сначала приложения и их ресурсы, иначе финалайзеры подвесят удаление namespace
argocd app list -A
argocd app delete guestbook --cascade

helm uninstall argocd -n argocd
kubectl delete ns argocd

# CRD чарт намеренно не удаляет (crds.keep: true) — снимаем руками
kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io
```

## ⚠️ Argo CD и Flux одновременно

Два GitOps-контроллера, ведущие один и тот же объект к разным желаемым
состояниям, — это гарантированный «пинг-понг» и непонятные случайные откаты.

Пока стенд живёт вместе с будущим Flux:

- держать Argo на **отдельном** наборе ресурсов: тестовые приложения, а не
  боевые манифесты кластера из `platform/casa/`;
- не указывать обоим контроллерам один и тот же git-путь;
- помнить, что Argo ставится Helm'ом, а Flux будет управлять собой сам —
  их собственные манифесты в кластере тоже не должны пересекаться.

## Источники

- [argo-cd Helm chart](https://artifacthub.io/packages/helm/argo/argo-cd)
- [Argo CD Operator Manual](https://argo-cd.readthedocs.io/en/stable/operator-manual/)
- [argo-cd-vs-flux-cd.md](../../../docs/research/k8s/argo-cd-vs-flux-cd.md)
- [k0s-kubernetes-distribution.md](../../../docs/research/k8s/k0s-kubernetes-distribution.md)

---
status: accepted
---

# Раскладка v2: clusters/casa — корень истины, спека Argo живёт рядом с манифестами

Отменяет [0004](0004-repository-layout.md). Верхний уровень делится не на «control
plane / платформа / сервисы», а на **кластер и всё остальное**: под
`clusters/casa/` лежит ровно то, чем управляет Argo, остальное — инфраструктура
вне кластера, документация и скрипты. Слой `argocd/` исчезает: отдельный
каталог под спеки Argo и есть причина, по которой правка сервиса и правка его
`Application` оказались в разных половинах репозитория.

Решаем два инварианта, остальное — следствия.

1. **Всё, что Argo применяет, лежит под `clusters/casa/`.** Всё, что не лежит
   там, Argo не применяет и не должен. Инвариант нарушим — манифест,
   применяемый руками, окажется вперемешку с управляемыми (сегодня это
   `platform/traefik/route.yaml` и `platform/headlamp/route.yaml`, #858).
2. **Application и его манифесты лежат в одном каталоге.** Единица правки —
   issue, единица ревью — PR, и он должен показывать всё, что относится к
   сервису: спеку, значения и манифесты.

## Раскладка

```
homelab/
├── README.md, AGENTS.md, CONTEXT.md
│
├── bootstrap/                     # применяется руками, вне рендера root
│   ├── README.md
│   ├── argocd-values.yaml         # было argocd/install/values.yaml
│   ├── bootstrap.sh               # helm upgrade + kubectl apply + sync root
│   └── root.yaml                  # Application root, был root-application.yaml
│
├── clusters/
│   └── casa/                      # кластер; k0s — дистрибутив, не имя кластера
│       ├── kustomization.yaml     # глобы на spec'и, не список из 77 строк
│       ├── projects/              # AppProject'ы — часть рендера root
│       ├── values/
│       │   └── cluster.yaml       # домен, адрес узла, issuer, registry
│       ├── platform/
│       │   └── <компонент>/
│       └── apps/
│           └── <сервис>/
│
├── infra/                         # состояние мира вне кластера
│   ├── host/
│   │   ├── etc/                   # бывший etc/
│   │   └── k0s/                   # бывший platform/k0s/
│   ├── dotfiles/                  # бывший dotfiles/
│   ├── terraform/
│   └── ansible/
│
├── docs/{adr,agents,runbooks,incidents,troubleshot,research,status}/
├── scripts/
└── .forgejo/workflows/
```

Имя `casa` вместо `k0s` снимает путаницу: `platform/k0s/` был подготовкой узла,
а не Kubernetes-манифестами, и лежал в слое, который назывался `platform`. Теперь
подготовка узла — `infra/host/k0s/`, а `clusters/casa/` называется по стенду.

## Юнит

Два вкуса с одинаковыми именами файлов. Вкус выбирается тем, откуда берутся
манифесты, и ничем больше.

```
чарт — апстримный или локальный    плоские манифесты

clusters/casa/platform/traefik/    clusters/casa/apps/jellyfin/
├── app.yaml                       ├── app.yaml
├── values.yaml                    └── manifests/
├── manifests/                         ├── kustomization.yaml
│   ├── kustomization.yaml            └── *.yaml
│   └── route.yaml                   └── README.md
└── README.md
```

`manifests/` рядом с чартом нужен, когда у компонента есть объекты вне его
values: маршруты, middleware, TLS-хранилище. Сейчас они лежат в каталоге
компонента и применяются руками — в новой раскладке варианта «применить руками»
нет, всё, что перечислено в `manifests/kustomization.yaml`, живёт под Argo.

Локальный чарт (`apps/element/chart/`) — тот же вкус: Application ссылается на
каталог вместо апстримного `repoURL`. Обслуживающий код репозитория не касается:
исходники webhook'а DNS-01 и `kubiform` живут в `packages/`, который не
отслеживается git и в раскладку не входит.

**Инвариант: `app.yaml` никогда не лежит в source-path своего Application.**
Применение `Application` к самому себе ломает юнит, а неправильно написанный
`resources` подводит к нему одной строкой. Разделение на `manifests/` делает
ошибку невозможной, а не маловероятной.

Имя `Application` совпадает с именем каталога. Это не косметика: переезд
спеки в юнит при том же имени — это обновление существующего объекта через
server-side apply, а не удаление с последующим созданием. Вторая операция на
объектах с финализаторами уже едва не погасила два приложения (#784).

## Control plane

`bootstrap/root.yaml` применяется руками: контроллер не может применить
`Application`, который сам его создаёт. Он рендерит `clusters/casa` и
подхватывает спеки глобами:

```yaml
resources:
  - projects/*.yaml
  - platform/*/app.yaml
  - apps/*/app.yaml
```

Следствия:

- Добавление сервиса — это каталог и один файл. Центральный реестр, который
  сегодня приходится править руками при каждом новом сервисе, перестаёт
  существовать.
- Спека лежит в git и видна в диффе PR. Это ровно то, за что отказ от
  генератора записан в `argocd/README.md`.
- `kubeconform` продолжает проверять спеки — они просто лежат в другом каталоге.

## Значения

Общие значения окружения объявляются один раз в `clusters/casa/values/cluster.yaml`,
специфичные — в `values.yaml` юнита, и оба подключаются через `$values`:

```yaml
helm:
  valueFiles:
    - $values/values/cluster.yaml
    - $values/platform/traefik/values.yaml
```

Порядок важен: файл юнита перекрывает кластерный. Это снимает размножение
внутренних значений между `values.yaml` и `valuesObject` (ADR 0009) — там,
где `valuesObject` ещё остался, он удаляется в пользу файла.

## Что сознательно не меняется

- **CRD не выделяются в отдельный юнит.** `skipCrds: true` остаётся там, где
  стоит сейчас. Вопрос возникает снова при первом инциденте с порядком
  обновления операторов, и до него он не решается.
- **Namespace владеет сервис** ([0001](0001-namespace-ownership.md)), отдельный
  юнит `platform/namespaces/` не заводится. Побочно уходит дублирование: список
  namespace'ов в `platform/homelab/values.yaml` должен быть удалён, иначе
  владение определено дважды.
- **Структурных проверок раскладки в CI не будет.** Инварианты держатся
  соглашением и ревью. Автоматическая проверка окупается, когда раскладку
  пишут и читают чужие; здесь её читает и пишет один человек.
- **Сред по-прежнему нет.** Кластер один, `clusters/casa/` не имеет уровня
  окружения.

## Рассмотренные варианты

- **Оставить `argocd/` отдельным слоем** — дёшево, но именно он разрывает
  связку «сервис — его спека». Переезд с сохранением слоя означал бы, что
  `clusters/casa/apps/jellyfin/app.yaml` и `argocd/applications/apps/jellyfin.yaml`
  продолжают описывать одно и то же в двух местах.
- **Отдельный репозиторий под control plane** — пережил бы смену Argo на Flux,
  но это второй клон, второе SSH-подключение и вторая точка отказа. ADR 0009
  уже отменил приватный слой по близкой причине.
- **ApplicationSet с git-генератором** — генератор собирает `Application` в
  рантайме, спека не лежит в git, и PR, добавляющий сервис, не показывает ни
  `prune`, ни `selfHeal`. Обоснование в `argocd/README.md` верное и новой
  раскладкой не опровергается.
- **`base/` и `components/` над общими кусками** — общий знаменатель
  рукописных манифестов и апстримных чартов пуст, абстракция будет фиктивной.
  Вопрос вернётся, когда появится третий экземпляр.
- **`tools/` для собственного кода** — исходники и так вне репозитория
  (`packages/` не отслеживается), каталог был бы пустым.

## Следствия

| Было | Стало |
| --- | --- |
| `argocd/bootstrap/root-application.yaml` | `bootstrap/root.yaml` |
| `argocd/install/values.yaml` | `bootstrap/argocd-values.yaml` |
| `argocd/projects/*.yaml` | `clusters/casa/projects/*.yaml` |
| `argocd/applications/*.yaml` | `clusters/casa/platform/<компонент>/app.yaml` |
| `argocd/applications/apps/*.yaml` | `clusters/casa/apps/<сервис>/app.yaml` |
| `argocd/kustomization.yaml` | `clusters/casa/kustomization.yaml`, глобы вместо списка |
| `apps/<сервис>/k8s/` | `clusters/casa/apps/<сервис>/manifests/` |
| `platform/<компонент>/values.yaml` | `clusters/casa/platform/<компонент>/values.yaml` |
| `platform/k0s/` | `infra/host/k0s/` |
| `etc/`, `dotfiles/` | `infra/host/etc/`, `infra/dotfiles/` |
| `terraform/`, `ansible/` | `infra/terraform/`, `infra/ansible/` |
| `argocd/README.md` | `docs/runbooks/argocd.md` + указатель в `bootstrap/` |

- Имя `k8s/` внутри юнита уходит по тому же аргументу, по которому в 0004 ушёл
  корневой `k8s/`: внутри репозитория, который целиком про Kubernetes, имя не
  различает ничего.
- Путь зашит не только в файлы, но и в правила, которые на них смотрят, и
  часть правил после переезда ошибается молча:

  | Где | Как отпадает |
  | --- | --- |
  | `.gitignore`: `platform/k0s/*.private.yaml`, `terraform/*/terraform.tfvars` | приватный файл выходит из игнора и `git add -A` коммитит его |
  | `paths:` в workflow (`kubeconform`, `kube-linter`, `status`, `tflint`, `ansible`) | job не запускается: правка переехавшего манифеста не проверяется ничем, CI зелёный |
  | `.gitleaks.toml`, `.kube-linter.yaml` | allowlist и `ignorePaths` перестают совпадать, CI красный |
  | `scripts/kubeconform.sh`, `scripts/status-badges.sh`, `.githooks/pre-commit` | набор проверок не меняется, меняются цели |

  Полный инвентарь и порядок проверки — в issue чек-листе. `.sops.yaml`
  привязан к суффиксам, а не к каталогам, и переезда не касается.
- `argocd/README.md` — runbook на 691 строку, а не конфигурация. В каталоге
  конфигурации он неотличим от журнала разборов; переезд в `docs/runbooks/`
  отделяет одно от другого.
- Миграция выполняется перемещениями каталогов и правкой путей в одном коммите:
  Argo видит атомарную смену всех 71 `path`. Порядок шагов и риски — в issue
  миграции.
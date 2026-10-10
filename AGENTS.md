# Homelab

Этот Homelab на Kubernetes k0s, на котором я учусь production-grade навыкам DevOps.
Когда я тебя спрашиваю о чём то или ты выполняешь задачи, применяй лучшие практики DevOps и рассказывай мне о них.
Я много не знаю и могу заблуждаться, так что если заметил, что я прошу что-то странное, то скажи мне об этом.

Комментарии к коде/манифестах НЕ ПИШИ. Комментарии о прошлой реализации чего-либо НЕ ПИШИ.

## Стандартный flow разработки

Используй CLI `fj`. Заводится Issue под задачу, создается PR с Ref на Issue, merge (squash) и проверяется на кластере. Если на кластере всё заработало, то Issue закрывается. Если нет то создается PR на исправление.

## Инструмент IaC

Инструмент — `terraform`. Конфигурация, state и запуск живут на macOS

## Работа в worktree

Каждая задача агента живёт в своём рабочем дереве `.worktrees/`. Пути
относительные, работай через параметр `workdir`.

```sh
# Создать: issue 577, слагизированный текст задачи
git worktree add -b feat/577-readme .worktrees/577-readme main

# Путь для workdir
git worktree list                 # проверить, что появилось
pwd                              # внутри .worktrees/577-readme

# Коммиты и PR — обычные, из этого дерева
git add -A && git commit -m "..."
git push -u origin feat/577-readme

# Убрать после merge
git worktree remove .worktrees/577-readme
git branch -d feat/577-readme
```

Правила:

- Имя дерева — `<номер issue>-<слаг>`, имя ветки — `feat/<то же>`. Ветка
  не переиспользуется между деревьями: одна ветка — одно дерево.
- `git worktree list` — источник правды, кто где работает.
- `git stash`, `git rebase`, `git checkout` вне своей ветки не делать: refs
  и stash общие для всех деревьев.
- `git worktree remove` требует чистого дерева. Не залитая в main ветка
  удаляется только `git branch -D` и только осознанно.
- Локальные проверки перед коммитом: хуки из [`.githooks/`](.githooks/) (они
  отслеживаются в git и работают в дереве без настройки, путь
  `core.hooksPath` общий для всех деревьев) и `./scripts/check.sh` — те же
  шаги плюс shellcheck и actionlint. Если `core.hooksPath` не настроен, хуки
  молча не выполнятся, а `check.sh` об этом предупредит.

Приватные файлы в дерево **не переносятся** намеренно: `config.env`,
`infra/host/k0s/values.private.yaml`, `infra/terraform/*/terraform.tfvars`,
`.terraform/`, `*.tfstate`. В дереве агента их нет — не создавай симлинки и
не запускай операции с приватным слоем. `terraform plan`/`apply` и проверка
Argo выполняются только в основном дереве.

Внутренние значения (домен, адрес узла, issuer, clientID) лежат в репозитории
рядом с остальными: `platform/homelab/values.yaml` и `valuesObject` в
`argocd/applications/`. Отдельный приватный репозиторий отменён — решение
`docs/adr/0009`. Credentials в values не кладутся никогда, для них Vault и
`VaultStaticSecret`. Правила обращения с обоими уровнями —
`docs/agents/information-handling.md`.

## Инциденты

Происшествия, повлиявшие на сервисы (простой, потеря данных, деградация), обязательно разбираются и записываются как blameless-постмортем в `docs/incidents/`. Формат, обязательные разделы и правила именования в `docs/incidents/README.md`. Диагностические разборы без влияния на работу идут в `docs/troubleshot/`. Действия по итогам инцидента заводятся как issues.

## Agent skills

### Issue tracker

Issues and specs are tracked in Forgejo Issues. See `docs/agents/issue-tracker.md`.

### Commit conventions

Commit messages follow Conventional Commits, are written in English, and are checked by commitlint. See `docs/agents/commit-conventions.md`.

Лимит длины считай **заранее**, до создания PR. Заголовок PR при squash-merge
становится сообщением коммита вместе с дописанным Forgejo ` (#<n>)`, и именно
эта итоговая строка линтится в CI. Поэтому:

```sh
# 72 - len(" (#<n>)") = 65 для номеров #100-#999
printf '%s' "fix(element): json web logs, coturn metrics (#537)" | wc -c
```

Если строка длиннее — сокращай subject сразу, а не после падения CI: сначала
красный `commitlint`, затем невозможность merge (405). Заголовок коммита и PR
должны совпадать.

### Triage labels

The repository uses the five standard triage labels. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository. See `docs/agents/domain.md`.

### Доступ к серверу

Способ подключения к серверу в `docs/agents/server-access.md`. 

### Обработка информации

Репозиторий зеркалится в публичный GitHub. Любые утечки недопустимы. 
Если произошло чтение расшифрованного секрета, то сразу докладывай какого именно и как сделать ротацию. 
Правила обращения с секретами, внутренними адресами и выводом инструментов в `docs/agents/information-handling.md`.
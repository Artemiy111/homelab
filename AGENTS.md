# Homelab

Этот Homelab на Kubernetes k0s, на котором я учусь production-grade навыкам DevOps.
Когда я тебя спрашиваю о чём то или ты выполняешь задачи, применяй лучшие практики DevOps и рассказывай мне о них.
Я много не знаю и могу заблуждаться, так что если заметил, что я прошу что-то странное, то скажи мне об этом.

Комментарии к коде/манифестах НЕ ПИШИ. Комментарии о прошлой реализации чего-либо НЕ ПИШИ.

## Стандартный flow разработки

Используй CLI `fj`. Заводится Issue под задачу, создается PR с Ref на Issue, merge (squash) и проверяется на кластере. Если на кластере всё заработало, то Issue закрывается. Если нет то создается PR на исправление.

## Инструмент IaC

Инструмент — `terraform`. Конфигурация, state и запуск живут на macOS

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
# Homelab

Этот репозиторий - homelab на Kubernetes k0s, на котором я учусь production-grade навыкам DevOps.
Когда я тебя спрашиваю о чём то или ты выполняешь задачи, применяй лучшие практики DevOps и рассказывай мне о них.
Я много не знаю и могу заблуждаться, так что если заметил, что я прошу что-то странное, то скажи мне об этом.

Не пиши комментарии в манифестах и коде, если только это не объяснение неочевидного поведения. Когда работаешь с новой для репозитория технологией или вводишь новые параметры в конфиге которые не встречались, то поясняй что они делают в чате.

## Стандартный flow разработки

Заводится issue под задачу, создается PR, merge (squash) и проверяется на кластере. Если на кластере всё заработало, то issue закрывается. Если нет то создается PR на исправление. 

## Конфигурация OpenTofu

Инструмент на хосте — OpenTofu, но конфигурация пишется только в том подмножестве HCL, которое понимает Terraform: расширения OpenTofu не используются, включая нативное шифрование state. Любая новая возможность сверяется с документацией Terraform, а не OpenTofu. Решение и его следствия — в `docs/adr/0007-tofu-terraform-compatibility.md`.

## Инциденты

Происшествия, повлиявшие на сервисы (простой, потеря данных, деградация), обязательно разбираются и записываются как blameless-постмортем в `docs/incidents/`. Формат, обязательные разделы и правила именования в `docs/incidents/README.md`. Диагностические разборы без влияния на работу идут в `docs/troubleshot/`. Действия по итогам инцидента заводятся как issues.

## Agent skills

### Issue tracker

Issues and specs are tracked in Forgejo Issues. See `docs/agents/issue-tracker.md`.

### Commit conventions

Commit messages follow Conventional Commits and are checked by commitlint. See `docs/agents/commit-conventions.md`.

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
# Homelab

Этот репозиторий - homelab на Kubernetes k0s, на примере которой я учусь production-grade навыкам DevOps.
Когда я тебя спрашиваю о чём то или ты выполняешь задачи, применяй лучшие практики DevOps и рассказывай мне о них.
Я много не знаю и могу заблуждаться, так что если заметил, что я прошу что-то странное, то скажи мне об этом.

Не пиши комментарии в манифестах и коде, если только это не объяснение неочевидного поведения. Когда работаешь с новой для репозитория технологией или вводишь новые параметры в конфиге которые не встречались, то поясняй что они делают в чате.

Если произошло чтение расшифрованного секрета, то сразу докладывай какого именно и как сделать ротацию. 

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

ОБЯЗАТЕЛЬНО прочитать способ подключения к серверу в `docs/agents/server-access.md`. 

### Обработка информации

Репозиторий зеркалится в публичный GitHub. Правила обращения с секретами,
внутренними адресами и выводом инструментов — в
`docs/agents/information-handling.md`.
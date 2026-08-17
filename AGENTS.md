## Agent skills

### Issue tracker

Issues and specs are tracked in GitHub Issues. See `docs/agents/issue-tracker.md`.

### Triage labels

The repository uses the five standard triage labels. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository. See `docs/agents/domain.md`.

### Доступ к серверу

Подключение, развёртывание и диагностика homelab описаны в
`docs/agents/server-access.md`. Отслеживаемые файлы на сервере не редактировать:
изменения проходят через локальный commit, push и `git pull --ff-only`.

Краткая шпаргалка:

- Подключение: `ssh homelab-agent`
- Read-only проверки: `ssh homelab-agent '...'`
- Запись/запуск скриптов: `ssh homelab-agent 'sudo -u artlab bash -lc "..."'`
- Репозиторий на сервере: `/home/artlab/projects/homelab`

### Настройка Element/Matrix

Для настройки Element/Matrix на homelab сервере используйте скилл `configure-element`.
Он описывает полный стек: Synapse, Element Web, LiveKit (для видеозвонков) и push-уведомления.

Краткая шпаргалка:

- Директория: `/home/artlab/projects/homelab/element/`
- Требования: ~4.5 GB RAM, ~7 ядер, ~70 GB диска
- Качество видео: 1080p+ через LiveKit
- Push-уведомления: через Sygnal + Firebase/FCM

# Доступ к сессиям ИИ-агентов и локальным LLM с телефона

Дата проверки: 2026-08-16.

## Вывод

- Самый удобный первый-party путь «телефон → агент на маке» — **[T3 Code](https://github.com/pingdotgg/t3code)**: официальные iOS/Android-приложения, веб-приложение `app.t3.codes` и desktop-приложение. Он управляет CLI-агентами (Claude Code, Codex, Cursor, Grok Build, opencode), а не сам раздаёт LLM ([README](https://github.com/pingdotgg/t3code#readme)). Подключение с телефона — через одноразовый pairing-токен с QR: `npx t3 pair`, а флаг `--tailscale` публикует сервер через Tailscale Serve HTTPS ([remote-access.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md)).
- **opencode** (репозиторий переехал в [anomalyco/opencode](https://github.com/anomalyco/opencode)) — своего мобильного приложения нет, но есть браузерный интерфейс `opencode web` и headless HTTP-сервер `opencode serve` (порт `4096`, basic auth через `OPENCODE_SERVER_PASSWORD`, OpenAPI-спека на `/doc`). TUI можно подключить к запущенному серверу через `opencode attach` ([server](https://opencode.ai/docs/server/), [web](https://opencode.ai/docs/web/)). Функция Share создаёт только **публичные** ссылки-вьюверы на разговор (`opncd.ai/s/<id>`), это не управление сессией ([share](https://opencode.ai/docs/share/)).
- **Codex CLI** — первый-party веб/мобильного интерфейса нет. Удалённо работает через SSH + неинтерактивный `codex exec`; новые механизмы (`app-server`, `remote-control`, desktop `app`, `exec-server`) помечены experimental. Для локальных моделей используется флаг `--oss` с выбором провайдера `--local-provider` (Ollama или LM Studio); `wire_api` в конфиге теперь **только** `responses` — старый `wire_api = "chat"` и провайдер `ollama-chat` удалены ([lib.rs](https://github.com/openai/codex/blob/main/codex-rs/model-provider-info/src/lib.rs), [discussion 7782](https://github.com/openai/codex/discussions/7782), [integration](https://docs.ollama.com/integrations/codex)).
- Локальные LLM-эндпоинты на маке (Apple Silicon):
  - **[mlx-lm](https://github.com/ml-explore/mlx-lm)** — `mlx_lm.server` поднимает OpenAI-совместимый HTTP-сервер (по умолчанию `127.0.0.1:8080`, флаги `--host`/`--port`), реализует `/v1/chat/completions` и `/v1/models` ([SERVER.md](https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/SERVER.md), [server.py](https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/server.py)). Подходит для opencode, но **не** для Codex — там нет `/v1/responses`.
  - **[Ollama](https://github.com/ollama/ollama)** — OpenAI-совместимый `/v1/chat/completions`, а `/v1/responses` добавлен в v0.13.3 ([docs](https://docs.ollama.com/openai)); по умолчанию слушает `127.0.0.1:11434`, сетевой доступ — через переменную `OLLAMA_HOST` ([faq](https://docs.ollama.com/faq)). Это единственный из локальных эндпоинтов, который напрямую покрывает Codex (плюс LM Studio).
- В homelab уже есть готовая связка для телефона: [code-server](https://code.example.com/) (VS Code в браузере через Traefik, `code-server/README.md`), [LocalAI](https://localai.example.com/) (OpenAI-совместимый API на сервере, `local-ai/README.md`) и Tailscale с tailnet-ом и MagicDNS на Fedora-хосте (`tailscale/README.md`).

## opencode: веб-интерфейс и headless-сервер

Репозиторий проекта переехал из `sst/opencode` в [anomalyco/opencode](https://github.com/anomalyco/opencode) (старые ссылки на `sst/` не работают). Клиент по умолчанию — TUI, но архитектура сервер/клиент позволяет подключать другие клиенты.

### Headless-сервер: `opencode serve`

`opencode serve` запускает сервер без TUI; флаги и значения по умолчанию ([документация Server](https://opencode.ai/docs/server/)):

- `--port` — порт, по умолчанию `4096`;
- `--hostname` — адрес, по умолчанию `127.0.0.1`;
- `--mdns` / `--mdns-domain` — mDNS-публикация (по умолчанию отключена, домен `opencode.local`);
- `--cors` — дополнительные origins для браузера.

Аутентификация: переменная окружения `OPENCODE_SERVER_PASSWORD` включает HTTP basic auth (логин по умолчанию `opencode`, меняется через `OPENCODE_SERVER_USERNAME`). Та же переменная работает и для `opencode web`.

Сервер публикует OpenAPI 3.1-спеку на `http://<hostname>:<port>/doc` и полный REST API для сессий и сообщений: `GET /session`, `POST /session/:id/message`, `POST /session/:id/prompt_async`, файловые и поисковые эндпоинты (`/file`, `/find`), SSE-эвенты (`/event`) и др. То есть с телефона можно управлять сессией даже голым HTTP-клиентом.

`opencode attach <url>` подключает TUI к уже запущенному серверу — например, `opencode attach http://localhost:4096` (пример в [документации Web](https://opencode.ai/docs/web/)).

### Браузерный UI: `opencode web`

`opencode web` открывает в браузере полноценный интерфейс: список сессий, новые сессии, статус серверов ([web](https://opencode.ai/docs/web/)):

- по умолчанию слушает `127.0.0.1` на случайном свободном порту;
- `--hostname 0.0.0.0` делает сервер доступным по сети и выводит LAN-адрес (например `http://<device-ip>:4096`);
- `--mdns` автоматически переключает hostname на `0.0.0.0` и рекламирует `opencode.local`;
- настройки можно положить в `opencode.json` в блок `"server": { "port", "hostname", "mdns", "cors" }` (CLI-флаги имеют приоритет).

Документация прямо предупреждает: если `OPENCODE_SERVER_PASSWORD` не задан, сервер не защищён — для сетевого доступа пароль обязателен.

### Share: только публичные ссылки

`/share` в TUI создаёт публичную ссылку `opncd.ai/s/<share-id>` и синхронизирует историю на серверы opencode ([share](https://opencode.ai/docs/share/)). Режимы: `manual` (по умолчанию), `auto`, `disabled` — настраиваются в `opencode.json` через поле `share`. Разговор доступен **любому, у кого есть ссылка**; управление сессией через эту ссылку не предусмотрено. Для «отдать ссылку, чтобы посмотреть со стороны» — годится, для работы с телефона — нет.

### Локальные провайдеры

opencode использует AI SDK и Models.dev и поддерживает 75+ провайдеров; любой OpenAI-совместимый сервер подключается как кастомный провайдер с `npm: "@ai-sdk/openai-compatible"`, `options.baseURL` и картой `models` ([providers](https://opencode.ai/docs/providers/)). В документации есть готовые блоки для:

- Ollama — `baseURL: http://localhost:11434/v1` ([пример](https://opencode.ai/docs/providers/) + [интеграция Ollama](https://docs.ollama.com/integrations/opencode));
- LM Studio — `baseURL: http://127.0.0.1:1234/v1`;
- llama.cpp `llama-server` — `baseURL: http://127.0.0.1:8080/v1`.

Тот же механизм подойдёт для LocalAI на сервере (`https://localai.example.com/v1`).

## T3 Code: мобильные приложения и pairing

[T3 Code](https://github.com/pingdotgg/t3code) позиционируется как «agent harness control surface»: он управляет CLI-агентами (Claude Code, Codex, Cursor, Grok Build, opencode), установленными и залогиненными на компьютере ([README](https://github.com/pingdotgg/t3code#readme)). Интерфейсы:

- официальные мобильные приложения: [iOS](https://apps.apple.com/us/app/t3-code-remote-claude-more/id6787819824), [Android](https://play.google.com/store/apps/details?id=com.t3tools.t3code);
- веб-приложение [app.t3.codes](https://app.t3.codes);
- desktop-приложение (macOS: `brew install --cask t3-code`; Windows: `winget install T3Tools.T3Code`).

Запуск без установки — `npx t3@latest` (требуется Node `^22.16 || ^23.11 || >=24.10`, см. [install.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/install.md)). Это самый подходящий для телефона вариант из трёх рассмотренных агентов.

### Pairing с телефона

Поток подключения описан в [remote-access.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md):

1. На маке уже запущен сервер T3 (`npx t3@latest` или desktop-приложение).
2. `npx t3 pair` выпускает одноразовый pairing-токен и печатает QR для сканирования — без перезапуска сервера.
3. `npx t3 pair --tailscale` публикует сервер через Tailscale Serve HTTPS (по `https://machine.tailnet.ts.net/`) и печатает уже доступный с телефона URL. Маппинг Tailscale Serve живёт до `tailscale serve --https=443 off`. Дополнительные флаги: `--tailscale-serve-port`, `--ttl`, `--base-dir`.
4. Если сервер не запущен — `npx t3 pair` подскажет `npx t3 serve` или `npx t3 connect`.

Headless-вариант для сервера: `npx t3 serve --host "$(tailscale ip -4)"` (без GUI, печатает connection string, токен, URL и QR), либо `npx t3 serve --tailscale-serve` (по умолчанию HTTPS 443, порт меняется флагом `--tailscale-serve-port`). После pairing доступ сессионный; управление токенами и отзыв — через `npx t3 auth`.

Рекомендация самой документации — подключаться по доверенной приватной сети (tailnet): стабильный адрес, транспортная безопасность, без публичного интернета.

### Ограничения

- T3 — это управляющая поверхность над CLI-агентами, а не LLM-эндпоинт: подключить произвольный OpenAI-совместимый локальный сервер «в лоб» нельзя, конфигурация модели уходит в конфиг соответствующего CLI (например, `codex` или `opencode`).
- Для браузерной пары с `https://app.t3.codes` нужен HTTPS-бэкенд: обычные `http://192.168.x.y:3773` ссылки из защищённой страницы не работают (mixed content). HTTPS-эндпоинт Tailscale Serve — решение под это.
- Сервер T3 сам по себе не создаёт сетевого доступа: desktop-приложение требует вручную включить **Settings → Connections → Network access** (перезапуск бэкенда на всех интерфейсах).

## Codex CLI: удалённые режимы и локальные модели

Проверено по исходникам репозитория [openai/codex](https://github.com/openai/codex) (официальный сайт docs `developers.openai.com/codex/*` при проверке отдавал 403).

### Удалённый доступ

Первый-party мобильного/веб-интерфейса у Codex CLI нет. Подкоманды из [main.rs](https://github.com/openai/codex/blob/main/codex-rs/cli/src/main.rs): `exec`, `review`, `login`, `logout`, `mcp`, `plugin`, `mcp-server`, `app-server` [experimental], `remote-control` [experimental], `app` (desktop), `exec-server` [EXPERIMENTAL] и др. Классической `codex serve` (JSON-RPC) в текущем main нет — её место заняли `app-server`/`remote-control`/desktop-приложение ([remote_control_cmd.rs](https://github.com/openai/codex/blob/main/codex-rs/cli/src/remote_control_cmd.rs): `remote-control start|stop|pair`, WebSocket-аутентификация).

Практический сценарий с телефона — SSH в хост и неинтерактивный режим `codex exec` (см. [docs/exec.md](https://github.com/openai/codex/blob/main/docs/exec.md)). Для homelab это `ssh homelab` поверх tailnet (OpenSSH, а не Tailscale SSH — см. `tailscale/README.md`).

### Локальные модели

- Флаг `--oss` включает локальный режим; провайдер выбирается через `--local-provider`: `ollama` или `lmstudio` ([exec/src/lib.rs](https://github.com/openai/codex/blob/main/codex-rs/exec/src/lib.rs)). Перед работой Codex проверяет, что сервер Ollama поддерживает Responses API (`ensure_responses_supported`) ([utils/oss](https://github.com/openai/codex/blob/main/codex-rs/utils/oss/src/lib.rs)).
- `WireApi` теперь поддерживает **только** `responses`; `wire_api = "chat"` удалён (ошибка со ссылкой на [discussion 7782](https://github.com/openai/codex/discussions/7782)), удалён и легаси-провайдер `ollama-chat` ([model-provider-info lib.rs](https://github.com/openai/codex/blob/main/codex-rs/model-provider-info/src/lib.rs)). Это значит, что для локальной модели в Codex нужен сервер с эндпоинтом `/v1/responses` — у Ollama он появился в v0.13.3, у `mlx_lm.server` его нет.
- Произвольные провайдеры задаются в `config.toml` через `model_providers` (карта `base_url`/`env_key`/`wire_api`, мержится поверх встроенных `openai`, `amazon-bedrock`, `ollama`, `lmstudio`) ([core/src/config/mod.rs](https://github.com/openai/codex/blob/main/codex-rs/core/src/config/mod.rs)).

Официальная интеграция с Ollama ([docs.ollama.com/integrations/codex](https://docs.ollama.com/integrations/codex)):

```shell
ollama launch codex          # быстрый запуск (создаёт профиль и каталог моделей)
codex --oss                  # вручную: локальные модели
codex --oss -m gpt-oss:120b  # конкретная модель
```

Профильный вариант конфига: `~/.codex/ollama-launch.config.toml` с `wire_api = "responses"` и `base_url = "http://localhost:11434/v1/"`, затем `codex --profile ollama-launch`. Документация рекомендует контекст не меньше 64k токенов.

## Локальные LLM-эндпоинты на маке (Apple Silicon)

### mlx-lm / `mlx_lm.server`

Пакет `mlx-lm` выделен в отдельный репозиторий [ml-explore/mlx-lm](https://github.com/ml-explore/mlx-lm) (в mlx-examples оставлено уведомление о переносе: [llms/README.md](https://github.com/ml-explore/mlx-examples/blob/main/llms/README.md)). Установка: `pip install mlx-lm`.

HTTP-сервер описан в [SERVER.md](https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/SERVER.md):

- запуск: `mlx_lm.server --model <path_or_hf_repo>`;
- API «похож на OpenAI chat API»: `POST /v1/chat/completions` (включая стриминг, `logprobs`, vision-поля) и `GET /v1/models`;
- по умолчанию слушает `127.0.0.1:8080`; флаги `--host` и `--port` из [server.py](https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/server.py) (default `--host 127.0.0.1`, `--port 8080`), также `--allowed-origins`, `--draft-model` и др.;
- прямая оговорка: «не рекомендуется для production — только базовые проверки безопасности».

Для доступа с телефона: `mlx_lm.server --host 0.0.0.0 --port 8080`. Подходит для opencode через кастомный OpenAI-совместимый провайдер; для Codex — нет (нет `/v1/responses`).

### Ollama

- Установка на macOS — приложение или `curl -fsSL https://ollama.com/install.sh | sh` ([README](https://github.com/ollama/ollama#readme)). REST API по умолчанию на `127.0.0.1:11434`; собственный API (`/api/chat`, `/api/generate`) + OpenAI-совместимый.
- OpenAI-совместимый слой: `http://localhost:11434/v1/` — `/v1/chat/completions`, `/v1/completions`, `/v1/embeddings`, `/v1/models`, а `/v1/responses` добавлен в v0.13.3 ([docs.ollama.com/openai](https://docs.ollama.com/openai)). Для клиентов-агентов открыт: провайдеры для opencode и Codex (см. выше).
- Сетевой доступ: по умолчанию bind `127.0.0.1:11434`; изменение через `OLLAMA_HOST` (на macOS-приложении — `launchctl setenv OLLAMA_HOST "0.0.0.0:11434"` и перезапуск, [faq](https://docs.ollama.com/faq)). Docker-вариант: `ollama/ollama` с публикацией порта 11434.

### LM Studio и llama.cpp (упоминание)

Для Codex LM Studio — второй встроенный локальный провайдер (порт по умолчанию 1234, crates `codex-rs/lmstudio` и `codex-rs/ollama` в дереве репозитория). Для opencode есть готовые блоки конфигурации под LM Studio (`127.0.0.1:1234/v1`) и llama.cpp `llama-server` (`127.0.0.1:8080/v1`) ([providers](https://opencode.ai/docs/providers/)).

## Транспорт: Tailscale

Tailscale уже развёрнут на Fedora-хосте homelab (машина в tailnet, subnet router `<node1-lan-cidr>`, MagicDNS-имя homelab; Tailscale SSH намеренно не включён — используется OpenSSH поверх tailnet, см. `tailscale/README.md`). Релевантные официальные возможности:

- `tailscale serve` ограничивает публикацию рамками tailnet (в отличие от `tailscale funnel`, который выставляет сервис в интернет на портах 443/8443/10000) ([funnel/serve](https://tailscale.com/kb/1311/ts-serve)). Именно `tailscale serve` использует `npx t3 pair --tailscale`.
- Tailscale SSH: `tailscale set --ssh`, аутентификация ключами WireGuard, только порт 22, серверная часть — Linux и macOS (open source `tailscaled`); удобно для телефона как SSH-клиента: `ssh homelab` по MagicDNS-имени без управления ключами ([Tailscale SSH](https://tailscale.com/kb/1193/tailscale-ssh)).

Для доступа с телефона на мак нужен Tailscale-клиент и на маке (или прямое попадание в LAN). В tailnet работают MagicDNS-имена и стабильные `100.x.y.z` адреса.

## Рекомендации для этой связки

1. **opencode на маке, управление с телефона.** Запуск: `OPENCODE_SERVER_PASSWORD=... opencode web --hostname 0.0.0.0 --port 4096` (в LAN) или через tailnet на адрес мака. Пароль обязателен: без него сервер не защищён (см. [web](https://opencode.ai/docs/web/)). Альтернатива для «железного» использования — `opencode serve` + TUI через `opencode attach` с другого устройства.
2. **T3 Code на маке, управление с телефона.** `npx t3 pair --tailscale` → QR → официальное iOS/Android-приложение. Это единственный из трёх сценариев с настоящим мобильным UX.
3. **Локальные модели на маке.**
   - Для opencode: Ollama (`http://localhost:11434/v1`, кастомный провайдер с `@ai-sdk/openai-compatible`) или `mlx_lm.server --host 0.0.0.0`.
   - Для Codex: только сервер с `/v1/responses` — Ollama (≥0.13.3, `codex --oss` / профиль с `wire_api="responses"`) или LM Studio.
   - `mlx_lm.server` не подходит для Codex, но это самый лёгкий вариант чисто для инференса на Apple Silicon.
4. **Через сервер homelab.** Телефон уже умеет:
   - code-server — VS Code в браузере: `https://code.example.com/` (пароль в менеджере паролей, `code-server/README.md`);
   - LocalAI — OpenAI-совместимый API: `https://localai.example.com` (`LOCALAI_API_KEY`, только через Traefik, `local-ai/README.md`) — годится как провайдер для opencode;
   - SSH-агенту на сервере — `ssh homelab` (tailnet) и headless-режимы (например `codex exec`, `npx t3 serve --host "$(tailscale ip -4)"`).
5. **Границы безопасности.** Pairing-токены и URL — как пароли (см. [security notes](https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md)); веб-интерфейсы не открывать наружу без пароля; всё внешнее — через Traefik + TLS/ключ (LocalAI уже так); share-ссылки opencode публичны — ничего секретного.

# Доступ AI-агентов к удалённому серверу: обзор подходов

Дата проверки: 2026-08-17.

## Короткий вывод

Для данного homelab (Fedora, Docker, SSH-alias `homelab`) оптимальный паттерн —
**SSH + ssh-agent delegation** в связке с **Tailscale** для сетевого доступа. Это
минимально инвазивно, не требует новых компонентов и соответствует модели, которую
уже используют все основные AI-агенты (OpenCode, Claude Code, Cursor, Aider).

Для повышения безопасности — выделить отдельного SSH-пользователя для агента
с ограничениями через `command=` в authorized_keys или `Match`-блоки в sshd_config,
использовать временные ключи и вести аудит-лог.

Если потребуется полная изоляция — рассмотреть **DevContainer** на сервере или
**Daytona/E2B** как облачные песочницы, но это избыточно для текущего use-case.

## Содержание

1. [SSH-подходы](#1-ssh-подходы)
2. [VPN + SSH](#2-vpn--ssh)
3. [Контейнерная изоляция](#3-контейнерная-изоляция)
4. [Агентные подходы (native)](#4-агентные-подходы-native)
5. [Агент на сервере vs удалённое подключение](#5-агент-на-сервере-vs-удалённое-подключение)
6. [Безопасность](#6-безопасность)
7. [Рекомендация для данного homelab](#7-рекомендация)

---

## 1. SSH-подходы

### 1.1 Прямой SSH + выделенный пользователь

**Суть:** Создать отдельного Linux-пользователя для AI-агента, дать ему
ограниченные права (read-only файловая система, доступ только к Docker-сокету
или конкретным скриптам), сгенерировать временный SSH-ключ.

**Практический паттерн (из blog.hgnlab.org, 2026-06):**
```
# На сервере:
sudo useradd -m -s /bin/bash ai-agent
sudo passwd -l ai-agent
# Ограничение через command= в authorized_keys:
command="/home/ai-agent/allowed-scripts/deploy.sh",no-port-forwarding,no-X11-forwarding ssh-ed25519 ...
```

**Плюсы:**
- Простейший подход, нулевая инфраструктура
- Временные ключи = минимальный blast radius
- Работает с любым AI-агентом из коробки

**Минусы:**
- Каждый tool-call создаёт новое SSH-соединение (stateless)
- Ключи нужно ротировать вручную
- Нет встроенного аудита команд

**Рекомендации:**
- Использовать Ed25519 вместо RSA
- Отдельный ключ = отдельный инструмент
- Никогда не передавать приватный ключ в промпт агента
- Использовать `--ssh-key /path/to/key` (файловый путь)

**Источники:**
- https://blog.hgnlab.org/ssh-access-for-ai-agents/
- https://patrickmccanna.net/giving-coding-agents-ssh-access-to-other-systems-without-giving-disclosing-secrets/

### 1.2 ssh-agent delegation (capability-based security)

**Суть:** Вместо передачи приватного ключа агенту — использовать `ssh-agent` как
signing oracle. Агент получает `$SSH_AUTH_SOCK` (путь к Unix-сокету), но никогда
не видит сам ключ.

```
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
# Агент наследует SSH_AUTH_SOCK, ключ не покидает процесс ssh-agent
# По окончании:
ssh-agent -k  # мгновенная отмена доступа
```

**Плюсы:**
- Ключ никогда не покидает trusted boundary
- Работает с OpenCode, Claude Code, Cursor — все наследуют env
- Мгновенная ревокация (kill ssh-agent)
- Capability-based модель: временная, ограниченная протоколом

**Минусы:**
- Требует ssh-agent запущенным на хосте запуска агента
- Forwarded agent (ssh -A) расширяет attack surface
- Агент с доступом к файловой системе может прочитать сокет-файл (но сам по себе бесполезен без процесса)

**Источники:**
- https://patrickmccanna.net/giving-coding-agents-ssh-access-to-other-systems-without-giving-disclosing-secrets/
- https://github.com/always-further/nono/pull/80 (Secure Enclave-backed ssh-agent)

### 1.3 SSH-сертификаты (Certificate Authority)

**Суть:** Вместо статических ключей — SSH CA выдаёт короткоживущие сертификаты
(например, на 1 час) с ограничениями (principals, extensions).

**Плюсы:**
- Нет проблемы «authorized_keys растёт бесконечно»
- Сертификаты автоматически протухают
- Централизованное управление через CA

**Минусы:**
- Требует настройки SSH CA (n ssh-keygen -t ed25519 -f ca_key)
- Сложнее, чем простые ключи, для homelab избыточно
- Не все AI-агенты поддерживают сертификаты из коробки

**Применимость:** Хорош для команд/организаций. Для homelab — overkill.

### 1.4 ProxyJump / bastion host

**Суть:** Если homelab не имеет публичного IP, используется VPS как jump-host:

```
Host homelab
    HostName <node1-ip>
    ProxyJump user@vps.example.com
```

**Плюсы:**
- Работает за NAT, не требует VPN
- Стандартная SSH-фича

**Минусы:**
- Требует VPS
- Промежуточный хост — дополнительная точка компрометации

**Применимость:** Актуально только если homelab недоступен по прямому
VPN-маршруту. При наличии Tailscale — избыточно.

### 1.5 Mosh (Mobile Shell)

**Суть:** UDP-протокол поверх SSH, обеспечивает устойчивость к смене IP и
потере сети.

**Плюсы:**
- Сессия не рвётся при смене Wi-Fi → cellular
- Локальный echo = мгновенный ввод
- Идеален для мобильного доступа к Claude Code/OpenCode

**Минусы:**
- Не заменяет SSH для автоматизации (только для интерактивных сессий)
- Нативной поддержки в AI-агентах нет (агенты используют SSH, не mosh)

**Источники:**
- https://www.zbuild.io/resources/news/claude-code-remote-control-mobile-terminal-handoff-guide-2026

---

## 2. VPN + SSH

### 2.1 Tailscale

**Суть:** WireGuard-based mesh VPN. Каждое устройство получает стабильный IP
(100.x.x.x), работает через NAT без проброса портов.

**Tailscale SSH:** Опциональный режим, где Tailscale заменяет traditional SSH
key management — аутентификация через ACL-политику tailnet, без distributed
key files.

```
# На сервере:
sudo tailscale up --ssh
```

**Плюсы для homelab:**
- Установка: `curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up`
- MagicDNS: `ssh homelab` работает из anywhere
- ACL: laptops → servers:22,443; servers → servers:*
- Subnet router: доступ к устройствам без Tailscale-клиента
- Free tier для personal use (до 3 пользователей, 100 устройств)
- Tailscale SSH: нет распределённых ключей, мгновенная ревокация через ACL
- Работает с OpenCode, Claude Code, Cursor через стандартный SSH

**Минусы:**
- Зависимость от Tailscale coordination server (free tier)
- Tailscale SSH не работает с multi-user machines (каждый OS-user = разные ACL)
- Нет full control plane (для этого — Headscale)

**Headscale (self-hosted):**
- Полный контроль над control plane
- Tradeoff: сложнее setup, нет MagicDNS, нет мобильного приложения
- Рекомендация: для homelab free tier Tailscale достаточен

**Популярность 2025-2026:** Tailscale — де-факто стандарт для homelab
remote access. Упоминается в каждом втором гайде по AI homelab.

**Источники:**
- https://tailscale.com/docs/features/tailscale-ssh
- https://tailscale.com/use-cases/homelab
- https://bmosan.com/blog/ai-agent-homelab-guide-2026
- https://homelabstarter.com/tailscale-homelab-access/
- https://komluk.github.io/posts/tailscale-setup-homelab/

### 2.2 ZeroTier

**Суть:** Аналог Tailscale — L2 overlay VPN с central control plane.

**Плюсы:**
- Free tier: до 25 устройств, 3 сети
- L2-режим = можно использовать ARP, mDNS

**Минусы:**
- Меньше community adoption для AI/agent use-case
- Нет аналога Tailscale SSH (нужен traditional SSH)
- Нативных интеграций с AI-агентами нет

**Популярность:** Используется в homelab, но значительно уступает Tailscale.

### 2.3 WireGuard (raw)

**Суть:** Низкоуровневый VPN-протокол. Tailscale и ZeroTier — обёртки над ним.

**Плюсы:**
- Максимальный контроль, minimal overhead
- Встроен в Linux kernel

**Минусы:**
- Ручное управление ключами и маршрутизацией
- Нет ACL-системы (нужно делать через iptables/nftables)
- Нет zero-config discovery

**Применимость:** Для homelab избыточно, если есть Tailscale.

---

## 3. Контейнерная изоляция

### 3.1 DevContainer (для AI-агентов)

**Суть:** Запускать AI-агента внутри Docker-контейнера с ограниченной
файловой системой, изолированным сетевым стеком и minimal tools.

**Реализации:**
- `dirien/devcontainer-coding-agents` — DevContainer с Claude Code, Copilot,
  OpenCode, Codex и 29 agent skills
- `develmusa/agent-devbox` — DevContainer под AI coding agents
- VS Code Remote + Dev Container: агент работает в контейнере, IDE — локально

**Плюсы:**
- Blast radius ограничен контейнером
- Воспроизводимая среда
- Нет риска повредить хостовую систему
- Агент может делать `rm -rf /` без последствий

**Минусы:**
- Дополнительная сложность (Docker-in-Docker, volume mounts)
- Агент не видит хостовые ресурсы (Docker-сокет, systemd) без проброса
- Для работы с Docker Compose на хосте — нужен проброс docker.sock
- Производительность: overlay filesystem может тормозить на больших кодовых базах

**Популярность:** Активно обсуждается в 2025-2026. VS Code Remote + Dev Container
— рекомендованный подход для «sandboxing» AI-агентов.

**Источники:**
- https://github.com/dirien/devcontainer-coding-agents
- https://github.com/develmusa/agent-devbox
- https://codewithandrea.com/articles/run-ai-agents-inside-devcontainer
- https://markphelps.me/posts/running-ai-agents-in-devcontainers/
- https://code.visualstudio.com/blogs/2025/05/27/ai-and-remote

### 3.2 ContainerSSH

**Суть:** SSH-сервис, который при подключении запускает Docker/Kubernetes
контейнер на лету. Пользователь попадает в ephemeral container.

**Плюсы:**
- Каждое подключение = изолированная среда
- Встроенная интеграция с Docker и Kubernetes
- Аутентификация через внешний auth server (webhook)
- Open source (Go)

**Минусы:**
- Сложная настройка (auth server + container engine + ContainerSSH proxy)
- Для homelab — избыточная сложность
- Последний релиз v0.5.2 (март 2026), развитие медленное
- Нет нативной интеграции с AI-агентами

**Популярность:** Нишевый проект, используется в образовательных и
research-средах. Не получил массового adoption.

**Источники:**
- https://github.com/ContainerSSH/ContainerSSH
- https://github.com/ContainerSSH/agent

### 3.3 Teleport

**Суть:** Единая платформа доступа к инфраструктуре (SSH, Kubernetes,
дatabases, MCP servers) с identity-first моделью.

**Agentic Identity Framework (февраль 2026):**
- Каждый AI-агент = first-class identity с криптографически подтверждённым
  identity (SPIFFE/SPIRE)
- Ephemeral privileges: доступ выдаётся на время задачи
- MCP proxying: Teleport проксирует MCP-соединения с RBAC и аудитом
- Tool filtering: агент видит только разрешённые инструменты
- Anomaly detection: 50+ типов identity vulnerability

**Плюсы:**
- Enterprise-grade security
- Единый control plane для SSH + K8s + DB + MCP
- Полный аудит всех действий
- RBAC с tool-level granularity

**Минусы:**
- Community Edition: ограничения (до 10 пользователей, 5 ресурсов)
- Enterprise: дорого
- Сложная настройка (proxy + auth server + agents)
- CVE-2025-49825 (CVSS 9.8, июнь 2025) — критический auth bypass
- Для homelab — серьёзное overkill

**Популярность:** Активно развивается, позиционируется как «AI Infrastructure
Identity Company». Используется enterprise-компаниями.

**Источники:**
- https://goteleport.com/use-cases/agentic-ai/
- https://goteleport.com/platform/ai-infrastructure/
- https://www.infoq.com/news/2026/02/teleport-secure-ai-agents/
- https://github.com/gravitational/teleport/blob/master/rfd/0238-delegating-access-to-ai-workloads.md
- https://siliconangle.com/2026/01/27/teleport-launches-agentic-identity-framework-secure-ai-agents-production

### 3.4 Cloud Dev Environments (GitHub Codespaces, Gitpod/Ona, Daytona, Coder)

**Суть:** Облачные песочницы для кодирования, которые можно использовать
как runtime для AI-агентов.

**Daytona (особенно интересна):**
- Open-source dev environment manager, pivoted в 2025 на AI agent runtimes
- Sub-90ms cold start (27ms в оптимальных конфигурациях)
- Sandboxes: isolated kernel, filesystem, network, vCPU/RAM/disk
- SDK: Python, TypeScript, Ruby, Go
- AGPL-3.0 self-hostable
- $24M Series A (февраль 2026), клиенты: LangChain, Writer

**Coder:**
- Self-hosted cloud dev environments
- Codex CLI Module для запуска OpenAI Codex в workspace
- AI Governance GA в версии 2.30

**GitHub Codespaces:**
- DevContainer-спецификация (портативная)
- Поддержка AI-агентов через VS Code Copilot

**Плюсы:**
- Полная изоляция (отдельный VM/kernel)
- Ephemeral: создал → использовал → удалил
- Enterprise-аудит и governance
- Идеально для parallel agent runs

**Минусы:**
- Стоимость (облачные ресурсы)
- Задержка network (не локальная файловая система)
- Для homelab с работающим сервером — избыточно
- Self-hosted варианты (Daytona, Coder) требуют significant infrastructure

**Популярность:** CDE — mainstream для enterprise в 2026. Daytona — fast-growing.

**Источники:**
- https://www.daytona.io/dotfiles/from-dev-environments-to-ai-runtimes
- https://codex.danielvaughan.com/2026/04/21/cloud-development-environments-codex-cli-coder-daytona-infrastructure/
- https://github.com/DigitalVertise/Ai-Agent-Infrastructure

---

## 4. Агентные подходы (native)

### 4.1 SSH MCP Server (Model Context Protocol)

**Суть:** MCP-сервер, который предоставляет AI-агенту инструменты для
выполнения SSH-команд через standard MCP-протокол.

**Реализации:**
- `vilasone455/ssh-mcp-server` — multi-machine SSH management
  (TypeScript, machines.json для credentials)
- `Maxim11111/mcp-ssh` — Remote SSH Management for LLM Agents
  (Python, поддержка Cursor, Claude Desktop, Codex)
- `ssh-11` (MCP Market) — AI Agent Remote DevOps Automation

**Плюсы:**
- Credentials не попадают в контекст окна агента
- Multi-machine: один сервер управляет множеством хостов
- Command blocklist / pattern-based exclusion
- Аудит через MCP-protocol logging

**Минусы:**
- MCP-сервер — дополнительный компонент для поддержания
- Зависимость от MCP-экосистемы (ещё молодая)
- Не все агенты стабильно работают с remote MCP

**Популярность:** MCP-серверы для SSH активно создаются в 2025-2026,
но ещё не стабилизировались.

**Источники:**
- https://skywork.ai/skypage/en/unlocking-ai-agent-ssh-remote-execution/1981237413092970496
- https://mcpmarket.com/server/ssh-11
- https://github.com/Maxim11111/mcp-ssh

### 4.2 agent-ssh (brokered SSH)

**Суть:** CLI-broker, который держит реальные credentials и предоставляет
агенту named targets и approved command surfaces.

```
agent-ssh exec --server staging-api --profile logs --arg service=api
```

**Плюсы:**
- Agent never sees credentials
- Named profiles = approved command surfaces
- Works with any CLI-based agent

**Минусы:**
- Молодой проект (aibunny/agent-ssh)
- Требует настройки broker + server profiles

**Источники:**
- https://aibunny.github.io/agent-ssh/
- https://github.com/aibunny/agent-ssh

### 4.3 agent-ssh-access (plan/go protocol)

**Суть:** SSH-skill для Claude Code и OpenCode с mandatory human approval.
Каждое действие требует плана → подтверждения → исполнения.

**Особенности:**
- SAFE_PATHS: агент работает только в разрешённых каталогах
- Audit log: каждое действие логируется
- Plan → Go протокол: human-in-the-loop для каждого шага
- Skills-based: устанавливается как Claude Code skill или OpenCode skill

**Плюсы:**
- Максимальная безопасность для homelab
- Human approval для каждого действия
- Работает с существующей SSH-infraструктурой

**Минусы:**
- Медленнее: каждый шаг требует подтверждения
- Для быстрой диагностики — неудобно

**Источники:**
- https://github.com/tomekness/agent-ssh-access

### 4.4 sshDCommander (persistent SSH daemon)

**Суть:** Persistent daemon, который держит SSH-соединения живыми между
всеми tool-call'ами агента. Клиент-серверная модель.

**Особенности:**
- Persistent sessions: соединения не рвутся между tool calls
- SHA-256 streaming checksums на каждом upload
- Deploy manifests: криптографический record каждого deploy
- Certificate auth: Ed25519 CA
- CLI: `sshdcmd --client-id claude "uptime" --server prod --connect`
- MCP Server: announced for June 2026

**Плюсы:**
- Решает основную проблему SSH + AI agents (stateless connections)
- Zero credential exposure (OS keyring)
- Audit trail для каждого запроса
- Работает с Claude Code, Cursor, Copilot, Windsurf, Aider, Codex CLI

**Минусы:**
- Commercial product (€99/year base)
- Дополнительный daemon на хосте
- MCP Server integration ещё не вышел

**Популярность:** Новый продукт, но решает реальную pain point.

**Источники:**
- https://www.sshdcommander.com/for/ai-agents/
- https://www.sshdcommander.com/use-cases/ai-agent-infrastructure

### 4.5 AgentShell (мобильный SSH-клиент)

**Суть:** macOS/iOS приложение для SSH с поддержкой AI coding agents.
Позволяет запускать Claude Code или Cursor на сервере и
контролировать с телефона.

**Источники:**
- https://agentshell.dev/

### 4.6 Server Compass AI Access (MCP)

**Суть:** Desktop app с встроенным SSH, предоставляет coding agents
scoped access через local MCP endpoint. Каждый AI-инструмент получает
token с permission tiers (Read, Operate, Deploy, Danger).

**Плюсы:**
- Credentials хранятся в desktop app, не в контексте агента
- Scoped tokens: staging vs production
- Activity log для каждого MCP-call
- Setup snippets для Claude Code, Codex CLI, OpenCode, Cursor

**Источники:**
- https://servercompass.app/blog/ai-access-coding-agents

### 4.7 opencode-remote-ssh (OpenCode plugin)

**Суть:** Plugin для OpenCode, который позволяет работать против удалённых
Linux-машин по SSH. Состоит из local plugin + Go stub на удалённом хосте.

**Особенности:**
- Provider-based host management
- SSH bootstrap для удалённого stub
- Permission-first path access
- Persistent approvals per workspace

**Плюсы:**
- Native для OpenCode
- Работает с Linux-машинами без установки OpenCode на них
- Permission model: доступ к файлам по одобрению

**Минусы:**
- Требует Go 1.21+ на local machine для сборки stub
- Молодой проект (11 stars, май 2026)
- Требует SSH-доступа и bootstrap

**Источники:**
- https://github.com/TyRoden/opencode-remote-ssh

### 4.8 opencode-mcp (multi-instance)

**Суть:** MCP-сервер для discovery и управления множественными
экземплярами OpenCode на разных машинах через SSH reverse tunnels.

**Источники:**
- https://github.com/klutometis/opencode-mcp

---

## 5. Агент на сервере vs удалённое подключение

### 5.1 Запуск агента на сервере (рекомендуемый для homelab)

**Суть:** Установить OpenCode/Claude Code CLI непосредственно на Fedora-сервер
и запускать через SSH-сессию (tmux/screen).

```
ssh homelab
cd /home/artlab/projects/homelab
opencode   # или claude
```

**Плюсы:**
- Agent работает локально с файлами на сервере
- Нет latency для файловых операций
- Полный доступ к Docker-сокету, systemd, логам
- Текущая модель работы в данном homelab (по server-access.md)
- OpenCode — standalone CLI, installable как single binary
- Поддерживает cloud providers (Anthropic, OpenAI) и local (Ollama)

**Минусы:**
- Требует SSH-подключения (Tailscale решает)
- Терминал-зависимость (нужен tmux для persistent sessions)
- Large output truncation (нужно фильтровать через grep/tail)

**Популярность:** Это стандартный подход для homelab. OpenCode, Claude Code,
Aider — все работают через SSH + tmux.

**Источники:**
- https://www.noze.it/en/insights/opencode-remote-ops-ssh
- https://computingforgeeks.com/claude-code-ssh-server-management/

### 5.2 Claude Code Remote Control

**Суть:** Anthropic's official feature (февраль 2026). Claude Code запущенный
локально может быть контролируем с телефона/планшета через веб-интерфейс.

```
# В Claude Code:
/rc
```

**Архитектура:**
- Агент работает на local machine
- Remote device = view-and-interact layer (не execution environment)
- Outbound HTTPS only (no inbound ports)
- Text-only relay (код не передаётся через relay)
- Сессия-scoped authentication

**Плюсы:**
- Minimal setup (1 команда)
- Не открывает inbound ports
- Source code never leaves your machine
- Поддержка mobile: iPhone, Android

**Минусы:**
- Работает только с Claude (не OpenCode, не Cursor)
- Требует Claude app (не generic browser)
- Зависимость от Anthropic's relay servers
- Агент выполняется на local machine, не на сервере

**Популярность:** Доступно для Pro/Max/Team/Enterprise планов.

**Источники:**
- https://blog.laozhang.ai/en/posts/remote-control-claude-code
- https://www.zbuild.io/resources/news/claude-code-remote-control-mobile-terminal-handoff-guide-2026
- https://www.digitalapplied.com/blog/claude-code-remote-control-feature-guide

### 5.3 Cursor Background Agents

**Суть:** Cursor может запускать background agents в cloud-provisioned
environments, которые работают автономно. Контролируются через веб-интерфейс.

**Архитектура:**
- Remote environment: containerized workspace с доступом к репозиторию
- Agent runtime: Cursor agent, работающий автономно
- Web UI: доступен с любого устройства, включая телефон

**Плюсы:**
- Автономная работа: start agent → close laptop → agent keeps working
- Parallel runs: несколько agents на разных репозиториях
- Mobile monitoring и steering

**Минусы:**
- Требует paid subscription
- Cloud environment (не self-hosted по умолчанию)
- Зависимость от Cursor infrastructure

**Источники:**
- https://www.mindstudio.ai/blog/cursor-remote-access-phone-control

### 5.4 VS Code Remote SSH + AI Agent

**Суть:** VS Code (или Cursor) подключается к серверу через Remote SSH extension.
AI-agent (Copilot, Cursor Agent) работает в контексте удалённой файловой системы.

**Плюсы:**
- Agent индексирует удалённую файловую систему
- Полный доступ к файлам, логам, конфигурациям
- Стабильнее, чем «terminal wrap» подход
- Нативная поддержка в VS Code/Cursor

**Минусы:**
- Требует VS Code Server на удалённом хосте (устанавливается автоматически)
- GUI-dependent: нужен дисплей или VNC на сервере (или headless через SSH)
- Cursor's Agent AI может нестабильно работать через Remote SSH (bug reports)

**Источники:**
- https://orendra.com/blog/vs-code-remote-ssh-ai-agents-the-ultimate-server-debugging-stack/
- https://dixiyao.github.io/topics/remote-coding-ssh-cursor/

---

## 6. Безопасность

### 6.1 Принцип наименьших привилегий для AI-агентов

**Ключевые принципы (2025-2026 consensus):**

1. **Отдельная identity для каждого агента** — не использовать пользовательский
   токен/ключ
2. **Scoped permissions** — read vs operate vs deploy vs admin
3. **Short-lived credentials** — ephemeral tokens (5-15 минут)
4. **External authorization** — policy enforcement вне промпта
5. **Human-in-the-loop** для irreversible actions
6. **Audit logging** каждого tool-call

**Источники:**
- https://learn.microsoft.com/en-us/security/zero-trust/sfi/least-privilege-for-ai-agents
- https://www.microsoft.com/en-us/security/blog/2026/07/16/least-privilege-for-ai-agents-identity-access-and-tool-binding
- https://baeseokjae.github.io/posts/secure-ai-agents-least-privilege-2026/
- https://www.okta.com/identity-101/how-to-implement-least-privilege-for-ai-agents

### 6.2 Ephemeral access patterns

**SSH-агент для ephemeral access:**
```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
# ... запуск AI-агента ...
ssh-agent -k  # мгновенная ревокация
```

**Dedicated user + temporary key:**
```bash
# На сервере:
sudo useradd -m -s /bin/bash ai-agent
sudo passwd -l ai-agent
# На local:
ssh-keygen -t ed25519 -f ~/temp-keys/ai-agent-key -C "ai-agent-$(date +%Y%m%d)"
```

**SSH certificates (enterprise):**
- Short-lived certificates (1 hour) с scoped principals
- CA выдаёт и отзывает автоматически

### 6.3 Аудит и мониторинг

**Что логировать для каждого tool-call:**
- Timestamp
- Agent identity
- Target host
- Command executed
- Exit code
- Output size
- Duration

**Инструменты:**
- SSH audit: `/var/log/secure` (Fedora), `sshd` logging
- agent-ssh-access: `client/session.log`
- Teleport: полный аудит через identity platform
- sshDCommander: `--client-id` для multi-agent traceability

### 6.4 Конкретные рекомендации для homelab

1. **Создать пользователя `ai-agent`** на сервере
2. **Ограничить права:** read-only для файловой системы, доступ к Docker
   через group membership (не sudo)
3. **Использовать отдельный ключ** для каждого агента/инструмента
4. **Tailscale ACL:** laptops → homelab:22 (SSH only)
5. **SSH-ограничения:** `no-port-forwarding,no-X11-forwarding` в authorized_keys
6. **Не передавать приватный ключ** в промпт агента — использовать ssh-agent
   или file path (`--ssh-key`)
7. **Вести аудит-лог** через session.log или systemd-journald
8. **Ротировать ключи** после каждого significant session

---

## 7. Рекомендация для данного homelab

### Текущее состояние

- SSH alias: `homelab` (<node1-ip>, user `artlab`)
- zsh (POSIX) shell, SELinux enforcing, Docker без sudo
- Git-based deployment: local commit → push → `git pull --ff-only` on server
- OpenCode доступен (terminal agent)

### Рекомендуемый паттерн

**Уровень 1 (baseline, уже работает):**
- SSH через Tailscale (если настроен) или LAN
- OpenCode/Claude Code запускаются через `ssh homelab`
- tmux для persistent sessions
- ssh-agent для delegation ключей

**Уровень 2 (повышение безопасности):**
- Отдельный пользователь `ai-agent` с limited permissions
- Временные ключи с `command=` restrictions
- Tailscale ACL для least privilege
- Session logging

**Уровень 3 (максимальная изоляция, если потребуется):**
- DevContainer на сервере для sandboxed execution
- Docker-in-Docker для workspace isolation
- MCP-сервер для controlled tool access

### Минимальные действия

```bash
# 1. На сервере: создать пользователя
sudo useradd -m -s /bin/bash ai-agent
sudo passwd -l ai-agent
sudo usermod -aG docker ai-agent  # доступ к Docker

# 2. На local machine: сгенерировать временный ключ
ssh-keygen -t ed25519 -f ~/.ssh/ai-agent-key -C "ai-agent-homelab"

# 3. Скопировать публичный ключ
ssh-copy-id -i ~/.ssh/ai-agent-key.pub ai-agent@homelab

# 4. Ограничить в authorized_keys (на сервере)
# Добавить в ~/.ssh/authorized_keys пользователя ai-agent:
command="cd /home/artlab/projects/homelab && bash -lc \"$SSH_ORIGINAL_COMMAND\"",no-port-forwarding,no-X11-forwarding ssh-ed25519 ...
```

### OpenCode remote setup (для удалённого доступа к OpenCode с phone/laptop)

```bash
# На сервере:
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# OpenCode serve:
OPENCODE_SERVER_PASSWORD=yourpassword opencode serve --hostname 0.0.0.0 --port 4096

# С телефона (через Tailscale):
# http://100.x.x.x:4096
```

Источник: https://dzianisv.github.io/opencode-mobile/remote-access

---

## Дополнительные источники

- https://ssh.bot/ — Controlled SSH Access for AI Agents (beta, commercial)
- https://www.innvesti.com/reports/best-tools-give-claude-code-remote-server-access-2026/
- https://beyondscale.tech/blog/ai-agent-authorization-security-least-privilege
- https://www.hashicorp.com/en/blog/advancing-ai-agent-security-in-vault
- https://www.cequence.ai/blog/ai/ai-agent-least-privilege-access

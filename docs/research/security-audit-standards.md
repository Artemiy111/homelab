# Аудит безопасности перед публикацией репозитория: стандарты, инструменты и раскрытие секретов

Дата исследования: 2026-09-20. Все факты сверены с первоисточниками (официальные
документации, спецификации, исходные репозитории). Этот документ — о том, как
подготовить инфраструктурный репозиторий к публичному зеркалу: каким стандартам
аудита следовать, чем искать секреты в рабочем дереве и в полной истории git, что
именно считается чувствительным для homelab, и как должны вести себя AI-агенты,
которым дали доступ к серверу.

**См. также: [docs/research/secret-management-providers.md](secret-management-providers.md)**
(что такое секреты, static/dynamic, провайдеры vault) и
**[docs/research/ai-agent-remote-server-access.md](ai-agent-remote-server-access.md)**
(как давать агенту доступ к серверу).

## Вывод

Публикация зеркала — это **необратимое** действие: как только коммит ушёл на
публичный GitHub, его нельзя «забрать назад» — он осядет в клонах и форках, а
SHA-коммита попадёт в кешированные представления
([GitHub: removing sensitive data](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)).
Поэтому порядок действий такой:

1. **Сначала ротация, потом чистка.** Если секрет попал в историю, «удалить из
   git» — недостаточно: копии уже могли разойтись. Официальная позиция GitHub:
   первым шагом отозвать/ротировать секрет, и только потом (если вообще нужно)
   переписывать историю. GitHub Support удаляет данные только там, где риск
   нельзя закрыть ротацией
   ([removing sensitive data](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)).
   То же и у Sealed Secrets: если sealing-ключ утёк, все запечатанные им
   `SealedSecret` считаются скомпрометированными, и «перевыпуск ключа» это не
   лечит — надо менять сами значения секретов
   ([Sealed Secrets: Secret Rotation](https://github.com/bitnami-labs/sealed-secrets#secret-rotation)).
2. **Сканировать НУЖНО и рабочее дерево, и всю историю.** Секрет, удалённый в
   следующем коммите, всё равно живёт в истории и в объектах git. GitHub secret
   scanning сканирует «your entire Git history on all branches»
   ([GitHub: about secret scanning](https://docs.github.com/en/code-security/secret-scanning/introduction/about-secret-scanning)),
   а `git-secrets --scan-history`, `gitleaks git` и `trufflehog git` умеют ходить
   по ревизиям ([git-secrets README](https://github.com/awslabs/git-secrets),
   [gitleaks README](https://github.com/gitleaks/gitleaks),
   [trufflehog README](https://github.com/trufflesecurity/trufflehog)).
3. **Заблокировать на входе.** GitHub **push protection** (`github`-уровень)
   включён по умолчанию и не даёт пушить секреты в публичные репозитории
   ([push protection](https://docs.github.com/en/code-security/concepts/secret-security/push-protection)).
   Локально — `pre-commit` + gitleaks hook
   ([gitleaks: Pre-Commit](https://github.com/gitleaks/gitleaks#pre-commit)).
4. **Отдельно решить, что считается чувствительным.** Для homelab это не только
   пароли: имена устройств и tailnet-DNS в Tailscale, ACL-policy, kubeconfig,
   service account tokens, sealed-secrets sealing keys, имена нод и внутренние
   DNS-имена. Публичный TLS-сертификат выкладывает хосты в Certificate
   Transparency log, который читают все
   ([How CT works](https://certificate.transparency.dev/howctworks/)).
5. **Агентам — least privilege и редактирование логов.** Не класть секреты в
   system prompt, считать вывод инструментов и трейсы каналом утечки, работать в
   песочнице и с подтверждением опасных операций
   ([OWASP LLM02:2026](https://github.com/GenAI-Security-Project/GenAI-LLM-Top10/blob/main/2026/final/LLM02_SensitiveInformationDisclosure.md),
   [Anthropic Claude Code security](https://docs.claude.com/en/docs/claude-code/security)).

Короткий чек-лист «перед тем как нажать public»:

| Шаг | Действие | Инструмент / первоисточник |
|---|---|---|
| 1 | Просканировать историю всех веток и рабочее дерево | `gitleaks git`, `trufflehog git`, `git-secrets --scan-history` |
| 2 | Каждый найденный секрет — ротировать/отозвать | GitHub removing-sensitive-data; Sealed Secrets rotation |
| 3 | Убедиться, что нет `.env`, `kubeconfig`, ключей, `*.pem` | `.gitignore` + ASVS 13.3.1 |
| 4 | Переписать историю, если секрет нельзя ротировать | `git filter-repo --sensitive-data-removal` |
| 5 | Включить push protection и secret scanning | GitHub docs |
| 6 | Включить pre-commit-хук и CI-проверку как required check | gitleaks/trufflehog + branch protection |
| 7 | Проверить, что `.git` не публикуется как контент | ASVS 13.4.1 |

---

## 1. Стандарты и фреймворки аудита

### 1.1 OWASP ASVS (Application Security Verification Standard)

Текущая стабильная версия — **ASVS 5.0.0**; проект публикует также
«bleeding edge»-сборку из master, которую сам ASVS не рекомендует для
production ([OWASP/ASVS releases](https://github.com/OWASP/ASVS/releases)).
В версии 5.0 стандарт переработан: из 286 требований 4.0.3 только 11 остались
неизменными, главы переразбиты, появились новые — OAuth/OIDC, WebRTC,
Self-contained Tokens, Web Frontend Security, Secure Coding and Architecture;
глава V1 Architecture удалена
([For Users of 4.0](https://github.com/OWASP/ASVS/blob/master/5.0/en/0x05-For-Users-Of-4.0.md)).

Актуальные главы ASVS 5.0 (именно они, а не нумерация 4.x):

| Глава | Тема | Что важно для публичного репозитория |
|---|---|---|
| V1 | Encoding and Sanitization | — |
| V2 | Validation and Business Logic | — |
| V3 | Web Frontend Security | — |
| V4 | API and Web Service | — |
| V5 | File Handling | — |
| V6 | Authentication | — |
| V7 | Session Management | — |
| V8 | Authorization | — |
| V9 | Self-contained Tokens | отзыв токенов, срок жизни |
| V10 | OAuth and OIDC | — |
| V11 | Cryptography | — |
| V12 | Secure Communication | — |
| **V13** | **Configuration** | **13.3 Secret Management; 13.4 Unintended Information Leakage** |
| **V14** | **Data Protection** | защита данных в покое/при передаче |
| V15 | Secure Coding and Architecture | — |
| V16 | Security Logging and Error Handling | — |
| V17 | WebRTC | — |

Ключевые для нас требования V13 (цитаты по
[0x22-V13-Configuration.md](https://github.com/OWASP/ASVS/blob/master/5.0/en/0x22-V13-Configuration.md)):

- **13.3.1** (L2): использовать secrets management solution (key vault) для
  создания, хранения, контроля доступа и уничтожения бэкенд-секретов; «Secrets
  must not be included in application source code or included in build
  artifacts». Для L3 — hardware-backed (HSM).
- **13.3.2** (L2): доступ к секретам по принципу наименьших привилегий.
- **13.3.4** (L3): секреты должны истекать и ротироваться по документированному
  расписанию.
- **13.4.1** (L1): приложение разворачивается **без** метаданных контроля версий
  (`.git`, `.svn`) или так, чтобы они были недоступны извне и самому приложению.
- **13.1.4** (L3): документация должна перечислять критичные секреты и расписание
  их ротации.

V14 (Data Protection) дополняет это требованиями к защите данных, но именно
раздел 13.3/13.4 — рабочий ориентир для репозитория.

### 1.2 OWASP Top 10 и OWASP для LLM/агентов

- **OWASP Top 10:2025** — текущая версия; категории: A01 Broken Access Control,
  A02 Security Misconfiguration, A03 Software Supply Chain Failures, A04
  Cryptographic Failures, A05 Injection, A06 Insecure Design, A07 Authentication
  Failures, A08 Software or Data Integrity Failures, A09 Security Logging and
  Alerting Failures, A10 Mishandling of Exceptional Conditions
  ([OWASP Top 10:2025](https://owasp.org/Top10/2025/)). Для публичного зеркала
  прямо релевантны A02 (misconfiguration / лишние эндпоинты и метаданные) и A04
  (криптография, в т.ч. утёкшие ключи).
- **OWASP GenAI LLM Top 10 2026** — опубликован 4 августа 2026; список:
  LLM01 Prompt Injection, **LLM02 Sensitive Information Disclosure**, LLM03
  Excessive Agency, LLM04 Supply Chain, LLM05 Data and Model Poisoning, LLM06
  Unbounded Consumption, LLM07 Misinformation, LLM08 Hidden Context Exposure,
  LLM09 Vector and Embedding Weaknesses, LLM10 Improper Output Handling
  ([GenAI-LLM-Top10 2026/final](https://github.com/GenAI-Security-Project/GenAI-LLM-Top10/tree/main/2026/final),
  [LLM02](https://github.com/GenAI-Security-Project/GenAI-LLM-Top10/blob/main/2026/final/LLM02_SensitiveInformationDisclosure.md)).
  LLM02 прямо говорит: канал утечки — не только финальный ответ, но и аргументы
  tool-call, reasoning traces, retrieved chunks, логи, телеметрия, embeddings;
  system prompt не должен содержать секреты; логи и трейсы надо чистить перед
  отправкой в APM.
- **OWASP Agentic Security Initiative**: «Agentic AI – Threats and Mitigations»
  (17 февраля 2025) и **OWASP Top 10 for Agentic Applications 2026** —
  peer-reviewed фреймворк рисков автономных агентов
  ([Agentic Security Initiative](https://genai.owasp.org/initiatives/agentic-security-initiative/),
  [Agentic AI – Threats and Mitigations](https://genai.owasp.org/resource/agentic-ai-threats-and-mitigations/)).
  См. §5.

### 1.3 NIST SSDF и SP 800-53

- **NIST SP 800-218 (SSDF) v1.1**, февраль 2022 — «Secure Software Development
  Framework»: набор высокоуровневых практик, встраиваемых в любой SDLC, дающих
  общий словарь для производителей и потребителей ПО
  ([NIST SP 800-218](https://csrc.nist.gov/pubs/sp/800/218/final)). Есть
  профиль для AI — SP 800-218A.
- **NIST SP 800-53 Rev. 5** — каталог контролов. Контрольные семейства, значимые
  для секретов и конфигурации: Access Control (AC), Audit and Accountability (AU),
  Configuration Management (CM), Identification and Authentication (IA),
  System and Communications Protection (SC), Supply Chain Risk Management (SR)
  ([NIST SP 800-53 Rev. 5](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final)).
  NIST выпустил минорный релиз 5.2.0 (27 августа 2025)
  ([там же](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final)). Конкретные
  номера контролов (например SC-28 Protection of Information at Rest, IA-5
  Authenticator Management) — общеизвестны, но их формулировки в этой заметке
  не сверялись построчно с текстом публикации (см. раздел «Не удалось
  проверить»).
- Отдельно полезен **NIST SP 800-63B** (Digital Identity Guidelines) — про
  управление аутентификаторами; ASVS 5.0 сознательно уменьшил жёсткую привязку
  к нему, но он остаётся reference
  ([For Users of 4.0](https://github.com/OWASP/ASVS/blob/master/5.0/en/0x05-For-Users-Of-4.0.md)).

### 1.4 CIS Benchmarks и CIS Critical Security Controls

- **CIS Critical Security Controls v8.1** — 18 приоритизированных контролов;
  для контейнеров/хостов особенно релевантны: **CIS Control 3 Data Protection**
  (классификация, безопасное обращение, хранение и удаление данных),
  **Control 4 Secure Configuration of Enterprise Assets and Software**,
  **Control 5 Account Management**, **Control 6 Access Control Management**,
  **Control 8 Audit Log Management**, **Control 16 Application Software
  Security**, **Control 12/13 Network Infrastructure Management / Monitoring**
  ([The 18 CIS Critical Security Controls](https://www.cisecurity.org/controls/cis-controls-list)).
- **CIS Benchmarks** — «100+ vendor-neutral configuration guides» под конкретные
  платформы (Linux, Docker, Kubernetes и др.)
  ([CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks)). Именно из CIS
  Benchmark for Kubernetes/Docker берутся практические «secure configuration»
  проверки для self-hosted кластера.

### 1.5 SLSA и OpenSSF Scorecard

- **SLSA** — спецификация уровней supply-chain безопасности; текущая версия
  **v1.2** (Approved). Треки: **Build** (уровни L1–L3) и **Source**; важны
  provenance (происхождение артефакта), attestation-форматы и verified
  properties. SLSA описывает, *как* и что именно проверяется, и даёт модель
  доверия к цепочке сборки
  ([SLSA v1.2 specification](https://slsa.dev/spec/v1.2/)). Прямо к утечке
  секретов не относится, но относится к целостности источника и сборки: SLSA
  Source Track оценивает, как защищена система контроля версий.
- **OpenSSF Scorecard** — автоматизированный чекер эвристик безопасности
  OSS-проекта, по 0–10 на проверку; агрегат — взвешенное среднее. Проверки
  включают Binary-Artifacts, Branch-Protection, CI-Tests, Code-Review,
  Dangerous-Workflow, Dependency-Update-Tool, Pinned-Dependencies, SAST,
  Security-Policy, Signed-Releases, **Token-Permissions**, **Vulnerabilities**
  ([ossf/scorecard README](https://github.com/ossf/scorecard)). Важно понимать,
  что это именно эвристики с false positive/negative, а не «certification»
  (README: «The checks themselves are heuristics»).

### 1.6 ISO/IEC 27001:2022 Annex A

ISO/IEC 27001:2022 — международный стандарт системы менеджмента информационной
безопасности; его нормативное Приложение A содержит набор контролов, сгруппированных
по темам (организационные, людские, физические, технологические)
([ISO/IEC 27001:2022](https://www.iso.org/standard/27001)). Текст стандарта
платный, поэтому конкретные номера и названия контролов Annex A в этой заметке
**не сверялись построчно с первоисточником** (см. «Не удалось проверить»). Для
практического маппинга NIST публикует crosswalk между SP 800-53 Rev. 5 и
ISO/IEC 27001:2022
([NIST OLIR crosswalk](https://csrc.nist.gov/projects/olir/informative-reference-catalog/details?referenceId=155)).

---

## 2. Поиск секретов: рабочее дерево и полная история git

Главный риск при зеркалировании — не файлы в текущем дереве, а **история**.
Инструменты делятся на те, что сканируют историю репозитория, и те, что
предотвращают попадание нового секрета.

| Инструмент | Что делает | История git | Верификация | Особенность |
|---|---|---|---|---|
| **gitleaks** | regex + entropy детект секретов в git/файлах/stdin | да (`git log -p` по патчам) | нет | baseline, `.gitleaksignore` по fingerprint, `gitleaks:allow`, декодирование base64/hex, архивы |
| **trufflehog** | discovery + classification (800+ типов) + **active verification** | да, включая скрытые/удалённые коммиты GitHub | да (`verified`/`unverified`/`unknown`) | умеет проверять, живой ли credential, и анализировать его права |
| **Yelp detect-secrets** | плагины (regex/entropy/keyword) + baseline | нет (по умолчанию сканирует только добавленный diff) | опционально | baseline как «долг», фокус на «не допускать новые» |
| **git-secrets** | запрещённые regex-паттерны AWS и свои | да (`--scan-history`) | нет | нативные git-хуки pre-commit/commit-msg/prepare-commit-msg |
| **GitHub secret scanning** | сканирование на стороне GitHub | да, все ветки | партнёрская валидация + validity checks | бесплатно для публичных репозиториев |

### 2.1 gitleaks

Сканирует репозитории, файлы и stdin; под капотом `git`-режима — `git log -p`,
поэтому видит историю и умеет ограничивать диапазон через `--log-opts`
(`gitleaks git -v --log-opts="--all commitA..commitB"`). Конфиг — regex-правила
с `entropy`, `keywords`, allowlist'ами; поддержаны baseline-файлы (игнор старых
находок) и `.gitleaksignore` по полю `Fingerprint`. Есть `gitleaks:allow` для
осознанно тестовых секретов, `--redact` для редактирования вывода, рекурсивное
декодирование (`--max-decode-depth`) и сканирование архивов
(`--max-archive-depth`) ([gitleaks README](https://github.com/gitleaks/gitleaks)).
Важно: gitleaks теперь в режиме «feature complete» — новые фичи не принимаются,
только security-патчи.

### 2.2 trufflehog

Позиционируется как discovery + classification + validation + analysis: 800+
детекторов, для каждого классифицируемого секрета может «залогиниться», чтобы
подтвердить, что он живой (статусы `verified`, `unverified`, `unknown`). Умеет
сканировать git, GitHub, GitLab, Docker-образы, S3/GCS, файловые системы, Postman,
Jenkins, Elasticsearch и stdin; есть GitHub Action и pre-commit hook. Для CI:
`--fail` возвращает код 183, если найдены результаты. Отдельно (`github-experimental
--object-discovery`) перечисляет удалённые/скрытые коммиты GitHub и сканирует их
([trufflehog README](https://github.com/trufflesecurity/trufflehog)). Верификация
— сильная сторона: она резко снижает число false positive и показывает реальную
опасность.

### 2.3 Yelp detect-secrets

Философия отличается: «accepting that there may *currently* be secrets hiding in
your large repository (baseline), but preventing this issue from getting any
larger». Три инструмента: `scan` (создать/обновить baseline), `hook` (блокировать
новые секреты, обычно как pre-commit), `audit` (разметить baseline). Плагины:
regex (AWS, GitHub, GitLab, OpenAI, Stripe, JWT, PrivateKey и др.), энтропийные
Base64/Hex и KeywordDetector; фильтры отсекают ложные срабатывания.
Официальные caveats: **не предотвращает** многострочные секреты и дефолтные
пароли, не похожие на секрет («login = "hunter2"»), и вообще «This is not meant
to be a sure-fire solution»
([detect-secrets README](https://github.com/Yelp/detect-secrets)).

### 2.4 git-secrets

Ставит git-хуки (`pre-commit`, `commit-msg`, `prepare-commit-msg`) и блокирует
коммиты/мержи/сообщения, совпавшие с запрещёнными regex. `--register-aws`
добавляет AWS-паттерны и проверяет, что ключи из `~/.aws/credentials` не попадут
в коммит. Для «перед публикацией» есть `git secrets --scan-history` — скан
репозитория по всем ревизиям. Обход — `--no-verify`; ложные срабатывания
разрешаются через `--allowed`/`.gitallowed`
([git-secrets README](https://github.com/awslabs/git-secrets)).

### 2.5 GitHub secret scanning и push protection

- **Secret scanning** автоматически ищет hardcoded credentials во **всей истории
  git на всех ветках**, а также в issues/PR/Discussions/Wikis/Gists. Для
  **публичных репозиториев работает бесплатно**; для владельцев — с GitHub
  Secret Protection. GitHub периодически пересканирует репозитории при
  добавлении новых типов секретов; партнёрские секреты репортуются провайдеру
  для отзыва. Рекомендация при алерте: немедленно ротировать credential
  ([about secret scanning](https://docs.github.com/en/code-security/secret-scanning/introduction/about-secret-scanning)).
- **Push protection** блокирует push с секретом **до** попадания в репозиторий:
  из CLI, GitHub UI, загрузки файлов, REST API и GitHub MCP server (public repos).
  Для **users** включён по умолчанию и не даёт пушить секреты в публичные
  репозитории; для **repositories** требует GitHub Secret Protection и по
  умолчанию выключен. Bypass возможен, но создаёт alert и audit-запись
  ([push protection](https://docs.github.com/en/code-security/concepts/secret-security/push-protection)).

Вывод: GitHub-сканер ловит уже случившееся, push protection предотвращает новое.
Это два разных уровня, нужны оба.

---

## 3. Очистка истории git и обязательная ротация

### 3.1 Чем чистить

- **git filter-repo** — официально рекомендованный GitHub инструмент; для
  удаления чувствительных данных нужен флаг `--sensitive-data-removal`
  (версия ≥ 2.47):
  `git-filter-repo --sensitive-data-removal --invert-paths --path PATH` или
  `--replace-text passwords.txt`
  ([removing sensitive data](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)).
- **BFG Repo-Cleaner** — быстрый альтернативный чистильщик для больших файлов и
  паролей; `bfg --replace-text passwords.txt` заменяет секреты на
  `***REMOVED***`, после чего нужен `git reflog expire --expire=now --all &&
  git gc --prune=now --aggressive`. Важная деталь: по умолчанию BFG **не
  трогает последний коммит** protected-ветки, поэтому текущий коммит должен быть
  уже чистым
  ([BFG Repo-Cleaner](https://rtyley.github.io/bfg-repo-cleaner/)).

### 3.2 Что удаление НЕ исправляет

GitHub прямо перечисляет побочные эффекты и пределы перезаписи истории
([removing sensitive data](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)):

- **Ротация обязательна.** Если удаляемый фрагмент — это секрет, сначала
  отозвать/ротировать его; удаление истории может быть уже не нужным.
- **Реконтаминация.** У коллеги со старым клоном после `git pull` + `git push`
  секрет вернётся. Нужно переклонировать/переписать и свои клоны.
- **Смена хешей.** Меняются хеши коммита-источника и всех последующих; это ломает
  подписи коммитов и тегов и инструменты, завязанные на хеши.
- **Форки и клоны.** Из форков и чужих клонов данные не удалить; GitHub не даст
  контактов владельцев форков. В кешированных представлениях GitHub и в PR
  данные тоже остаются, пока не обратиться в GitHub Support (и только если риск
  не закрывается ротацией).
- **Ветки/pull requests.** Перезапись ломает diff у закрытых PR и инвалидирует
  комментарии; перед чисткой лучше закрыть/смержить открытые PR.
- Прямая рекомендация: сначала ротировать секрет, а историю переписывать только
  при реальной необходимости.

Отсюда практическое правило для homelab: **относиться к каждому секрету так, что
он уже опубликован**, и планировать ротацию, а чистку истории рассматривать как
понижение шума, а не как средство защиты.

---

## 4. Что именно считается чувствительным для homelab

### 4.1 Tailscale

С точки зрения утечки чувствительны несколько разных сущностей:

- **Auth keys** (`tskey-...`). Одноразовые безопаснее, но даже их нельзя
  публиковать. Про **reusable** keys документация говорит прямо: «Be very
  careful with reusable keys! These can be very dangerous if stolen. They're best
  kept in a key vault». Auth key аутентифицирует устройство как пользователя,
  который его создал (или как его теги). Срок жизни — 1–90 дней; node keys по
  умолчанию истекают через 180 дней; у **tagged** устройств истечение ключей по
  умолчанию **отключено**
  ([Use auth keys](https://tailscale.com/kb/1085/auth-keys)).
- **ACL / tailnet policy file**. Описывает, кто к чему имеет доступ, по
  deny-by-default; правила **распространяются на все устройства** и
  enforce'ятся локально на каждом узле. Публикация policy — это карта внутренней
  сети и модель доступа атакующему
  ([Manage ACLs](https://tailscale.com/kb/1018/acls)).
- **Имена устройств (machine names) и MagicDNS-имена.** MagicDNS автоматически
  регистрирует DNS-имя для каждого устройства; FQDN = machine name +
  tailnet DNS name, например `monitoring.<tailnet-name>.ts.net`. Имена машин
  видны в FQDN и часто раскрывают назначение узлов (`nas`, `db`, `monitoring`).
  Для доступа к **shared** устройствам обязательно используется полный FQDN, а
  не короткое имя
  ([MagicDNS](https://tailscale.com/kb/1081/magicdns)).
- **Tailscale IP 100.x.y.z.** Это адреса из CGNAT-диапазона `100.64.0.0/10`
  (RFC 6598), стабильные для устройства. Документация подчёркивает, что они не
  выставляются в публичный интернет и «aren't exposed to the public internet»
  ([What are these 100.x.y.z addresses?](https://tailscale.com/kb/1015/100.x-addresses)).
  То есть сам 100.x-адрес — не публичный маршрутизируемый адрес; но в связке с
  именами устройств, FQDN и ACL он выдаёт топологию tailnet. Есть также
  служебный Quad100 `100.100.100.100` ([там же](https://tailscale.com/kb/1015/100.x-addresses)).
  Практический вывод: не считать «100.x-адреса безопасны» — вместе с именами и
  policy это готовый план internal-сети.
- **Карта tailnet (netmap).** Узлы получают распределённые правила доступа и
  информацию о tailnet; термин «netmap» используется в документации Tailscale.
  В рамках этого исследования страницу с определением netmap напрямую
  получить не удалось (см. «Не удалось проверить»), поэтому утверждения о его
  составе здесь не делаются.

Правило: auth keys и OAuth-клиенты — в vault; tailnet policy, device names и
FQDN — считать чувствительной внутренней информацией; примеры в заметках
обезличивать (`node-a`, `<tailnet>.ts.net`).

### 4.2 Kubernetes

- **kubeconfig.** Файл хранит кластеры, пользователей и контексты; credential
  пользователя может быть встроенным клиентским сертификатом/ключом или токеном.
  Это фактически админский доступ к кластеру, и он не должен попадать в git
  ([Organizing Cluster Access Using kubeconfig Files](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)).
- **Service account tokens.** Это учётные данные для pod'ов; их нельзя
  публиковать. Kubernetes документирует и good practices для Secrets, и
  управление Service Accounts/токенами
  ([Service Accounts](https://kubernetes.io/docs/concepts/security/service-accounts/),
  [Good practices for Kubernetes Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/),
  [Distribute Credentials Securely Using Secrets](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/)).
- **SealedSecrets — что безопасно публиковать.** Официальная позиция: `SealedSecret`
  — «write only»-устройство, и его **безопасно хранить даже в публичном
  репозитории**, потому что расшифровать может только controller в целевом
  кластере, и никто другой, включая автора, не получит исходный `Secret`. В
  шифротекст включаются namespace и имя секрета (scope `strict` по умолчанию),
  поэтому перенести sealed secret в другой namespace нельзя; есть также
  `namespace-wide` и `cluster-wide` scope
  ([Sealed Secrets: Scopes](https://github.com/bitnami-labs/sealed-secrets#scopes)).
  Но есть жёсткие оговорки про ротацию
  ([Secret Rotation](https://github.com/bitnami-labs/sealed-secrets#secret-rotation)):
  - sealing keys автоматически возобновляются каждые 30 дней, старые ключи
    **сохраняются** (старые SealedSecret остаются расшифровываемыми);
  - если sealing private key скомпрометирован — **все** SealedSecret, запечатанные
    этим ключом, считаются скомпрометированными; перевыпуск ключа или
    re-encryption это не исправляет;
  - нужно и возобновить sealing key, и **сменить сами значения секретов**
    (например, пароль БД), и заново запечатать;
  - re-encryption (`kubeseal --re-encrypt`) — не замена ротации секретов.
  То есть **публиковать SealedSecret можно и нужно**, но при этом нельзя
  публиковать sealing keys (они лежат в `kube-system` как обычные Secret) и
  нельзя считать, что «sealed = не секрет навсегда».
- **Имена нод и внутренние DNS.** Имена нод (Node objects) и внутренние
  service-DNS (`<service>.<namespace>.svc.cluster.local`) раскрывают топологию и
  назначение сервисов
  ([DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/),
  [Service ClusterIP allocation](https://kubernetes.io/docs/concepts/services-networking/cluster-ip-allocation/)).
  В публичном репозитории их лучше обезличивать или выносить в приватные
  overlay-значения.

### 4.3 Certificate Transparency и публичный DNS как канал утечки

Certificate Transparency — механизм, где сертификаты попадают в **публичные
append-only логи**; CA отправляет precertificate в логи, получает SCT и выдаёт
сертификат, а browsers (Chrome, Safari) требуют наличия SCT. Logs публично
проверяемы и мониторятся всеми желающими, включая сам владелец домена
([How CT works](https://certificate.transparency.dev/howctworks/)). Практическое
следствие: **любое имя хоста, на которое выписан публичный TLS-сертификат,
становится публичным**, даже если DNS-record приватный. Плюс сами публичные
DNS-зоны по определению раскрывают имена. Для homelab это значит: не заводить
публичные сертификаты на имена, которые вы не готовы раскрыть; внутренние имена
не должны утекать через CT.

---

## 5. Правила для AI-агентов: секреты и информация о сервере

### 5.1 Фреймворки

- **NIST AI RMF** (AI 100-1, январь 2023) — добровольный фреймворк управления
  рисками ИИ, ядро — функции Govern/Map/Measure/Manage; дополнен **Generative AI
  Profile (NIST AI 600-1, июль 2024)**
  ([NIST AI RMF](https://www.nist.gov/itl/ai-risk-management-framework)).
  Применительно к агенту это означает: определить границы (что агенту видно),
  измерять (аудит и логи), управлять (права, подтверждения, откат).
- **OWASP GenAI LLM Top 10 2026 / LLM02** — практические требования: never store
  secrets/credentials/regulated data in system prompts; минимизировать контекст;
  санитизировать логи и трейсы до отправки в observability; считать
  tool-call аргументы и reasoning traces полноценными output-каналами
  ([LLM02:2026](https://github.com/GenAI-Security-Project/GenAI-LLM-Top10/blob/main/2026/final/LLM02_SensitiveInformationDisclosure.md)).
- **OWASP Agentic AI** — threat-model-based референс emerging угроз и митигаций
  для агентных систем (excessive agency, least privilege и т.д.)
  ([Agentic AI – Threats and Mitigations](https://genai.owasp.org/resource/agentic-ai-threats-and-mitigations/)).

### 5.2 Первосторонние гайды производителей агентов

- **Anthropic Claude Code**. Безопасность построена на permission-based
  architecture: в Manual mode агент стартует с read-only, спрашивает разрешение
  на редактирование/команды; есть sandbox для bash с изоляцией файловой системы
  и сети; сетевые команды (`curl`, `wget`) по умолчанию не авто-одобряются;
  секреты (API keys, tokens) хранятся в macOS Keychain, а на Windows/Linux — под
  защитой прав файлов; рекомендуют не пайпить недоверенный контент в агента и
  использовать VM для запуска скриптов
  ([Claude Code security](https://docs.claude.com/en/docs/claude-code/security)).
- **OpenAI Agents SDK** предоставляет guardrails (input/output validation),
  human-in-the-loop, sandbox agents (работа в контейнере) и инструменты-примитивы
  — то есть встраивание подтверждений и ограничений в сам агентный workflow
  ([openai-agents-python](https://github.com/openai/openai-agents-python)).
  Публичная страница platform.openai.com/docs/guides/safety-best-practices в этой
  среде оказалась недоступна (403), поэтому ссылка только на репозиторий SDK.

### 5.3 Рабочие правила для этого репозитория

1. **Least privilege.** Агенту выдаётся минимально нужный доступ (отдельный
   SSH-пользователь, ограниченные права); см.
   [ai-agent-remote-server-access.md](ai-agent-remote-server-access.md).
2. **Не передавать секреты в промпт.** Значения загружаются из vault/переменных
   окружения, а не из текста задачи. Никогда не логировать и не печатать
   расшифрованные значения.
3. **Считать вывод инструментов каналом утечки.** `env`, `kubectl get secret -o
   yaml`, вывод `docker inspect`, логи приложений — всё это может содержать
   секреты; результат нельзя автоматически пересказывать или коммитить.
4. **Редактирование логов и трейсов.** Перед записью в репозиторий или внешнюю
   observability-систему маскировать токены, IP, домены.
5. **Обязательное сообщение при чтении расшифрованного секрета.** Правило
   репозитория (см. `AGENTS.md`): если агент прочитал расшифрованный секрет —
   сразу доложить, какой именно, и предложить ротацию.
6. **Подтверждение опасных операций.** Удаление, push, изменение прав, сетевые
   команды — только после явного подтверждения; для продакшн-доступа — sandbox
   или отдельная изолированная среда.

---

## 6. Принуждение в pre-commit и CI

Локальные хуки и CI ловят разные классы ошибок: pre-commit останавливает
случайный секрет до коммита, CI — до merge, а push protection — до попадания на
сервер.

### 6.1 pre-commit

`pre-commit` — фреймворк git-хуков; в `.pre-commit-config.yaml` подключаются
конкретные хуки ([pre-commit.com](https://pre-commit.com/)). Официальные
примеры:

```yaml
# gitleaks
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.24.2
    hooks:
      - id: gitleaks
```

([gitleaks: Pre-Commit](https://github.com/gitleaks/gitleaks#pre-commit);
обход — `SKIP=gitleaks git commit ...`). Для detect-secrets официальный пример —
хук `detect-secrets` с `args: ['--baseline', '.secrets.baseline']`
([detect-secrets README](https://github.com/Yelp/detect-secrets)). У trufflehog
есть свой `pre-commit` hook и GitHub Action
([trufflehog README](https://github.com/trufflesecurity/trufflehog)).

### 6.2 GitHub Actions

Правила из официального «Secure use reference»
([Security hardening for GitHub Actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions)):

- **GITHUB_TOKEN — наименьшие права**, по умолчанию выставлять read-only и
  повышать только конкретным job'ам.
- Секреты **никогда не хранить плейнтекстом в workflow**; маскировать значения
  через `::add-mask::`; не использовать структурированные данные (JSON/XML/YAML)
  как один секрет — редактирование логов ломается.
- **Пинить сторонние actions на полный commit SHA** — единственный способ
  использовать их как immutable release; тег можно переместить.
- **Self-hosted runners практически нельзя использовать для публичных
  репозиториев** — любой может открыть PR и компрометировать окружение.
- Для доступа в облако — **OIDC** вместо долгоживущих секретов; для чувствительных
  окружений — required reviewers (environment secrets не доступны без апрува).
- `CODEOWNERS` на `.github/workflows`, Dependabot для actions, code scanning для
  workflow-паттернов.

### 6.3 Branch protection / required status checks

Чтобы проверка была обязательной, а не «советом», её включают как **required
status check** в branch protection, а push в защищённую ветку — только через PR
([GitHub: about protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)).
OpenSSF Scorecard проверяет именно это (Branch-Protection, Code-Review,
Token-Permissions) и потому хорош как внешний аудит настройки репозитория
([scorecard checks](https://github.com/ossf/scorecard#scorecard-checks)).

Рекомендуемая конфигурация для публичного homelab-зеркала:

| Слой | Что проверяет | Где |
|---|---|---|
| pre-commit | секреты в staged-файлах | локально, `.pre-commit-config.yaml` |
| CI job | секреты в diff PR / истории | GitHub Actions (gitleaks/trufflehog) |
| push protection | секрет вообще не попадёт в репозиторий | настройки repo/user в GitHub |
| branch protection | CI-проверка обязательна, PR + review | настройки репозитория |
| secret scanning | вся история всех веток, бесплатно для public | GitHub |
| OpenSSF Scorecard | гигиена supply chain репозитория | GitHub Action |

---

## 7. Источники

**Стандарты и фреймворки**

- [OWASP/ASVS releases](https://github.com/OWASP/ASVS/releases) · [ASVS 5.0
  For Users of 4.0](https://github.com/OWASP/ASVS/blob/master/5.0/en/0x05-For-Users-Of-4.0.md)
  · [ASVS 5.0 V13 Configuration](https://github.com/OWASP/ASVS/blob/master/5.0/en/0x22-V13-Configuration.md)
- [OWASP Top 10:2025](https://owasp.org/Top10/2025/)
- [OWASP GenAI LLM Top 10 2026](https://github.com/GenAI-Security-Project/GenAI-LLM-Top10/tree/main/2026/final)
  · [LLM02:2026 Sensitive Information Disclosure](https://github.com/GenAI-Security-Project/GenAI-LLM-Top10/blob/main/2026/final/LLM02_SensitiveInformationDisclosure.md)
- [OWASP Agentic Security Initiative](https://genai.owasp.org/initiatives/agentic-security-initiative/)
  · [Agentic AI – Threats and Mitigations](https://genai.owasp.org/resource/agentic-ai-threats-and-mitigations/)
- [NIST SP 800-218 SSDF v1.1](https://csrc.nist.gov/pubs/sp/800/218/final)
- [NIST SP 800-53 Rev. 5](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final)
- [CIS Critical Security Controls v8.1](https://www.cisecurity.org/controls/cis-controls-list)
  · [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks)
- [SLSA v1.2 specification](https://slsa.dev/spec/v1.2/)
- [OpenSSF Scorecard](https://github.com/ossf/scorecard)
- [ISO/IEC 27001:2022](https://www.iso.org/standard/27001) · [NIST OLIR crosswalk
  800-53 ↔ ISO 27001:2022](https://csrc.nist.gov/projects/olir/informative-reference-catalog/details?referenceId=155)

**Поиск секретов**

- [gitleaks](https://github.com/gitleaks/gitleaks)
- [trufflehog](https://github.com/trufflesecurity/trufflehog)
- [Yelp detect-secrets](https://github.com/Yelp/detect-secrets)
- [aws/git-secrets](https://github.com/awslabs/git-secrets)
- [GitHub: about secret scanning](https://docs.github.com/en/code-security/secret-scanning/introduction/about-secret-scanning)
  · [GitHub: push protection](https://docs.github.com/en/code-security/concepts/secret-security/push-protection)

**Очистка истории и ротация**

- [GitHub: removing sensitive data from a repository](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)
- [newren/git-filter-repo](https://github.com/newren/git-filter-repo)
- [BFG Repo-Cleaner](https://rtyley.github.io/bfg-repo-cleaner/)
- [Sealed Secrets: Secret Rotation / Scopes](https://github.com/bitnami-labs/sealed-secrets#secret-rotation)

**Tailscale**

- [Use auth keys](https://tailscale.com/kb/1085/auth-keys)
- [Manage ACLs](https://tailscale.com/kb/1018/acls)
- [MagicDNS](https://tailscale.com/kb/1081/magicdns)
- [What are these 100.x.y.z addresses?](https://tailscale.com/kb/1015/100.x-addresses)

**Kubernetes**

- [Organizing Cluster Access Using kubeconfig Files](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)
- [Service Accounts](https://kubernetes.io/docs/concepts/security/service-accounts/)
- [Good practices for Kubernetes Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)
- [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)

**Сертификаты / DNS**

- [How Certificate Transparency works](https://certificate.transparency.dev/howctworks/)

**AI-агенты**

- [NIST AI RMF](https://www.nist.gov/itl/ai-risk-management-framework)
- [Anthropic Claude Code security](https://docs.claude.com/en/docs/claude-code/security)
- [OpenAI Agents SDK](https://github.com/openai/openai-agents-python)

**CI / pre-commit**

- [pre-commit.com](https://pre-commit.com/)
- [GitHub Actions security hardening](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions)
- [GitHub: about protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)

### Не удалось проверить из первоисточника

Следующие пункты сознательно не утверждаются в тексте либо помечены как
непроверенные:

- **Tailscale netmap** — страница с определением получить не удалось (сайт
  tailscale.com недоступен из среды исследования; использованы архивированные
  копии официальных страниц). Термин упомянут, но состав netmap не описывается.
- **ISO/IEC 27001:2022 Annex A** — текст стандарта платный, iso.org отдал 403;
  конкретные номера/названия контролов Annex A не сверялись.
- **NIST SP 800-53** — названия контролов (SC-28, IA-5 и т.д.) приведены как
  общеизвестные, но их формулировки не сверялись построчно с PDF публикации.
- **CIS Benchmarks** — конкретные названия и содержимое бенчмарков для
  Kubernetes/Docker/Linux не проверялись; подтверждено только существование
  каталога бенчмарков и 18 контролов CIS Controls v8.1.
- **OpenAI platform safety best practices** — страница вернула 403; ссылка только
  на репозиторий Agents SDK.
- **MCP security best practices** — спецификация Model Context Protocol не
  открылась из этой среды, поэтому её требования не включены.
- **OWASP Top 10 for Agentic Applications 2026** — подтверждено существование и
  дата, но содержимое списка не сверялось.
- **GitHub branch protection / required status checks** — поведение описано по
  официальной странице GitHub, но конкретные поля настройки не проверялись
  пошагово.

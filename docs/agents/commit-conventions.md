# Commit conventions

Сообщения коммитов следуют **Conventional Commits**, пишутся на **английском** и
проверяются `gitlint` 0.19.1: локально — хуком `.githooks/commit-msg`, в CI —
workflow `.forgejo/workflows/gitlint.yml`. Правила заданы `.gitlint` и
`scripts/gitlint_rules.py`; локально линтер ставится как `brew install gitlint`,
в CI — теми же файлами из зеркала RustFS.

Из встроенных правил `gitlint` включено одно — `title-max-length`; остальные
выключены в `.gitlint`, чтобы гейт проверял ровно то, что описано ниже:

| Правило | Где | Что проверяет |
| --- | --- | --- |
| `title-max-length` | `.gitlint` | заголовок ≤ 70 символов |
| `contrib-title-conventional-commits` | `.gitlint` | тип из списка и форма `type(scope): subject` |
| `subject-conventional` (`UC1`) | `scripts/gitlint_rules.py` | непустой subject, без точки в конце, не upper/pascal/start-case |
| `body-forbidden` (`UC2`) | `scripts/gitlint_rules.py` | тело коммита запрещено, разрешены только footer'ы вида `Refs #12` |

Правила — часть гейта, а не настройка инструмента, поэтому в них можно
ошибиться в обе стороны: пропустить мусор в историю или заблокировать корректный
коммит. Ожидаемый вердикт для каждого случая зафиксирован таблицей в
`scripts/gitlint-selftest.sh`; он же гоняется в `scripts/check.sh` и в CI.

## Формат

```
type(scope): subject
```

| Часть | Правило |
| --- | --- |
| `type` | один из `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert` |
| `scope` | необязательно; если указан — непустой и в нижнем регистре (`argocd`, `traefik`, `forgejo`, `vault`, `dotfiles`, имя приложения из `clusters/casa/apps/`) |
| `subject` | императив на английском, нижний регистр (имена собственные допустимы: `Zitadel`, `DoH`, `GLITCHTIP`), без точки в конце |
| header | ≤ 70 символов, включая `type(scope): ` (для заголовка PR — с учётом ` (#<n>)`, см. ниже) |
| body | **запрещено** (правило `body-forbidden`) |
| footer | разрешён: `Refs #12`; строка-продолжение футера запрещена, `Reviewed-on` намеренно не добавляем — мержим с `-m ""` (см. ниже) |
| флаги merge | `-t` не передаём: он перекрывает заголовок PR и убирает ` (#<n>)` (см. ниже) |

Заголовок PR становится сообщением squash-коммита не сам по себе, а вместе с
дописанным Forgejo ` (#<n>)`. CI линтит именно итоговую строку
`<заголовок PR> (#<n>)`, поэтому бюджет под её subject — `70 − len(" (#<n>)")`
(7 символов для номеров #100–#999), а не 70.

## Примеры

```
feat(forgejo): add actions runner with docker-in-docker
fix(seafile): fix container health endpoint
chore: drop dead Cup and Arcane references
```

Так нельзя:

```
added runner                    # нет type
feature(x): y                   # неверный type
Feat(x): add y                  # type с заглавной буквы
feat(): add y                   # пустой scope
feat(x): add y.                 # точка в конце subject
feat(x): add y                  # + тело ниже — тело запрещено
```

## Issue-first flow

Каждая задача начинается с issue. Порядок:

1. Создай issue: `fj issue create "Title" --body "..."` (см. `issue-tracker.md`).
2. Ветка: `<type>/<issue>-<slug>` — например, `ci/12-cache-bun`, `docs/4-issue-first-flow`.
3. Коммиты — по формату выше (тело запрещено).
4. PR: заголовок тоже в формате `type(scope): subject`, а в описании — ссылка на
   issue через `Refs #<issue>` (не `Closes`: merge не значит «проверено»):

   ```sh
   fj pr create --base main --head <branch> \
     "docs(agents): ..." --body "Refs #12"
   ```

5. `fj pr merge <n> --method squash --delete -m ""`. Темой коммита станет
   заголовок PR (плюс ` (#<n>)`) — эта итоговая строка проверяется в CI на
   заголовке PR (см. «Локальная проверка»).
6. Проверить результат на стенде и закрыть issue вручную:
   `fj issue close <n> -w "проверено: ..."`.

Ссылка на issue живёт в описании PR и в `(#<n>)` заголовка squash-коммита.

Тема коммита берётся из заголовка PR сама, поэтому `-t` не нужен и вреден: флаг
перекрывает её целиком. Например, PR с заголовком
`fix(argocd): name vault keys as argocd reads them (#641)` смерженный с
`-t "fix(argocd): register values repo as repository secret"` даёт коммит
`fix(argocd): register values repo as repository secret` — без `(#<n>)` и с текстом,
который в PR не встречался. Правильный вызов:

```sh
fj pr merge <n> --method squash --delete -m ""
```

`-m ""` обязателен: без него `fj` дописывает тело `Reviewed-on: <url>`, а это
внутренний домен, которого не должно быть в публичной истории (см. #25).
Серверный шаблон merge-сообщения (`clusters/casa/apps/forgejo`) задаёт пустое тело для
веб-мержей, но `fj` использует своё тело и шаблон не учитывает.

**Гейт это расхождение не ловит.** На `pull_request` CI линтит заголовок PR, а не
тему получившегося squash-коммита, поэтому подмена через `-t` проходит
бесшумно: проверка на merge-commit не настроена. Проверить руками:

```sh
git log -1 --format='%s' origin/main     # тема последнего merge-коммита
git log -1 --format='%b' origin/main     # тело должно быть пустым
```

Требуемое соответствие: тема последнего merge-коммита равна заголовку PR плюс
` (#<n>)` того PR, которым он смержен.

## Почему так

- `main` защищён: прямой push запрещён, изменения идут через PR и squash-merge.
  Поэтому заголовок PR становится сообщением коммита в истории — он должен
  соответствовать тем же правилам.
- Тело коммита не нужно: пояснения живут в описании PR/issue, а история
  остаётся однострочной и машинно-разбираемой.
- `Reviewed-on` не просто не нужен, а вреден: это внутренний домен, а история
  `main` зеркалируется в публичный GitHub. Трейлер добавляет `fj`, а не Forge, и
  серверный шаблон его не отключает.
- Тема коммита не перекрывается: `-t` отключает механизм, который и держит
  заголовок PR и историю коммитов в одном формате, а расхождение между ними
  никем не проверяется.

## Хуки

Хуки лежат в `.githooks/` и **отслеживаются в git**: ни генератора, ни установки
зависимостей для них не нужно, поэтому они работают и в основном дереве, и в
любом worktree. Включаются один раз на клон:

```sh
git config core.hooksPath .githooks
```

Путь записывается в общий `.git/config`, а сами файлы берутся из корня **того**
дерева, в котором идёт коммит, — поэтому добавление `git worktree add` не
требует ничего, чтобы заработали хуки. Проверить:

```sh
git config --get core.hooksPath          # .githooks
./scripts/check.sh                       # те же проверки, что и в хуке
```

`gitlint` нужен локально (CI ставит ту же версию из зеркала):

```sh
brew install gitlint
gitlint --version                        # 0.19.1
```

Версия пинится одинаково с двух сторон: локально — формулой brew, в CI —
файлами `gitlint/0.19.1/*` из `clusters/casa/apps/rustfs/manifests/artifacts.tsv`
(скачиваются со сверкой sha256, `pip install --no-index`). Правила
(`.gitlint` и `scripts/gitlint_rules.py`) — единственный источник правды для
хука и CI, а расхождение версий ловит самотест `scripts/gitlint-selftest.sh`:
он входит в `scripts/check.sh` и выполняется первым шагом гейта.

| Хук | Что проверяет |
| --- | --- |
| `.githooks/pre-commit` | gitleaks по staged, соответствие `docs/status/` состоянию репозитория, схемы API манифестов из индекса (`kubeconform`) |
| `.githooks/commit-msg` | сообщение коммита по `.gitlint` и `scripts/gitlint_rules.py` |

`./scripts/check.sh` — те же проверки плюс самотест правил, shellcheck и
actionlint; хуки, в отличие от скрипта, выполняются всегда, когда
`core.hooksPath` настроен, а скрипт можно позвать руками.

`kubeconform` нужен локально и для хука, и для скрипта:

```sh
brew install kubeconform
```

Хук смотрит на манифесты из индекса, `check.sh` и гейт в
`.forgejo/workflows/kubeconform.yml` — на все каталоги. Набор путей, схем и
фильтров лежит в `scripts/kubeconform.sh` и общий для всех трёх: расхождение
локальной проверки с гейтом хуже, чем её отсутствие, потому что приучает не
смотреть на результат.

Тот же набор инструментов, что у гейтов, есть в образе
[`.devcontainer/`](../.devcontainer/README.md): версии в нём совпадают с
`artifacts.tsv` и workflow, поэтому проверка в контейнере значит то же, что
проверка на хосте, а Homebrew и Rancher Desktop для неё не нужны.

## Локальная проверка

```sh
gitlint --commit HEAD                    # последний коммит
gitlint --commits origin/main..HEAD      # диапазон
./scripts/gitlint-selftest.sh            # правила соответствуют ожиданиям
```

`gitlint` читает `.gitlint` (а через него — `scripts/gitlint_rules.py`)
относительно текущего каталога и вверх по дереву не ищет: запускать из корня
репозитория, иначе он молча применит встроенные правила по умолчанию.

CI делает то же: на `push` — последний коммит, на `pull_request` — диапазон
`base.sha..head.sha`. Отдельно на `pull_request` линтится заголовок PR как
`<заголовок> (#<n>)` — проверить локально можно так:

```sh
printf '%s' "<заголовок PR> (#<n>)" | gitlint
```

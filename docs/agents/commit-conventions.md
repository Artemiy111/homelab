# Commit conventions

Сообщения коммитов следуют **Conventional Commits**, пишутся на **английском** и
проверяются `commitlint`: локально — хуком `.githooks/commit-msg`, в CI —
workflow `.forgejo/workflows/commitlint.yml`. Правила заданы в
`commitlint.config.mjs`.

## Формат

```
type(scope): subject
```

| Часть | Правило |
| --- | --- |
| `type` | один из `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert` |
| `scope` | необязательно; подсистема или сервис в нижнем регистре (`argocd`, `traefik`, `forgejo`, `sealed-secrets`, `dotfiles`, имя приложения из `apps/`) |
| `subject` | императив на английском, нижний регистр (имена собственные допустимы: `Zitadel`, `DoH`, `GLITCHTIP`), без точки в конце |
| header | ≤ 72 символов, включая `type(scope): ` (для заголовка PR — с учётом ` (#<n>)`, см. ниже) |
| body | **запрещено** (правило `body-empty`) |
| footer | разрешён: `Refs #12`; `Reviewed-on` намеренно не добавляем — мержим с `-m ""` (см. ниже) |

Заголовок PR становится сообщением squash-коммита не сам по себе, а вместе с
дописанным Forgejo ` (#<n>)`. CI линтит именно итоговую строку
`<заголовок PR> (#<n>)`, поэтому бюджет под её subject — `72 − len(" (#<n>)")`
(7 символов для номеров #100–#999), а не 72.

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
`-m ""` обязателен: без него `fj` дописывает тело `Reviewed-on: <url>`, а это
внутренний домен, которого не должно быть в публичной истории (см. #25).
Серверный шаблон merge-сообщения (`apps/forgejo`) задаёт пустое тело для
веб-мержей, но `fj` использует своё тело и шаблон не учитывает.

## Почему так

- `main` защищён: прямой push запрещён, изменения идут через PR и squash-merge.
  Поэтому заголовок PR становится сообщением коммита в истории — он должен
  соответствовать тем же правилам.
- Тело коммита не нужно: пояснения живут в описании PR/issue, а история
  остаётся однострочной и машинно-разбираемой.

## Хуки

Хуки лежат в `.githooks/` и **отслеживаются в git**: ни генератора, ни
`bun install` для них не нужно, поэтому они работают и в основном дереве, и в
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

`commitlint` нужен глобально:

```sh
npm i -g @commitlint/cli @commitlint/config-conventional
```

Глобальная, а не локальная — потому что `bun x` в worktree без `node_modules`
скачивает пакет из публичного npm в момент коммита, то есть непрокиненную
версию из сети, и обходит Verdaccio с lockfile, на которых построен CI.
Побочный эффект: глобальная версия плавает, поэтому **локальный хук — быстрая
подсказка, а гейт — CI**. Правила в `commitlint.config.mjs` — единственный
источник правды для обоих.

| Хук | Что проверяет |
| --- | --- |
| `.githooks/pre-commit` | gitleaks по staged, соответствие `docs/status/` состоянию репозитория |
| `.githooks/commit-msg` | сообщение коммита по `commitlint.config.mjs` |

`./scripts/check.sh` (или `bun run check`) — те же проверки плюс shellcheck и
actionlint; хуки, в отличие от скрипта, выполняются всегда, когда
`core.hooksPath` настроен, а скрипт можно позвать руками.

## Локальная проверка

```sh
commitlint --last                        # последний коммит
commitlint --from origin/main --to HEAD  # диапазон
```

CI делает то же: на `push` — последний коммит, на `pull_request` — диапазон
`base.sha..head.sha`. Отдельно на `pull_request` линтится заголовок PR как
`<заголовок> (#<n>)` — проверить локально можно так:

```sh
printf '%s' "<заголовок PR> (#<n>)" | commitlint
```

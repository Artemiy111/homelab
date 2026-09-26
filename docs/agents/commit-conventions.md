# Commit conventions

Сообщения коммитов следуют **Conventional Commits** и проверяются `commitlint`:
локально — git-хуком husky (`.husky/commit-msg`), в CI — workflow
`.forgejo/workflows/commitlint.yml`. Правила заданы в `commitlint.config.mjs`.

## Формат

```
type(scope): subject
```

| Часть | Правило |
| --- | --- |
| `type` | один из `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert` |
| `scope` | необязательно; подсистема или сервис в нижнем регистре (`argocd`, `traefik`, `forgejo`, `sealed-secrets`, `dotfiles`, имя приложения из `apps/`) |
| `subject` | императив, нижний регистр (имена собственные допустимы: `Zitadel`, `DoH`, `GLITCHTIP`), без точки в конце |
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

## Локальная проверка

```sh
bun x commitlint --last --verbose          # последний коммит
bun x commitlint --from main --to HEAD     # диапазон
```

CI делает то же: на `push` — последний коммит, на `pull_request` — диапазон
`base.sha..head.sha`. Отдельно на `pull_request` линтится заголовок PR как
`<заголовок> (#<n>)` — проверить локально можно так:

```sh
printf '%s' "<заголовок PR> (#<n>)" | bun x commitlint --verbose
```

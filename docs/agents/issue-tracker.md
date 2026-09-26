# Issue tracker: Forgejo

Issues and specs for this repo live as Forgejo issues at
`forgejo.example.com`. Use the `fj` CLI (forgejo-cli) for all operations.

Auth: `fj auth login` or `fj auth add-token`; check the current login with
`fj auth list`. Run inside a clone — `fj` infers the repository from the git
remote (`-R origin` to override), and the host from `fj auth`.

`fj` prints human-readable tables and has **no `--json`**. For machine-readable
data use the Forgejo REST API (`/api/v1`).

Forgejo shares one index across issues and pull requests — a bare `#42` may be
either. Resolve with `fj pr view 42`, falling back to `fj issue view 42`.

## Issue-first flow

Every change starts with an issue:

1. Create it: `fj issue create "Title" --template task --body-file <file>` (the
   template, with a Definition of Done, lives in `.forgejo/issue_template/task.md`
   and applies `status/needs-triage`).
2. Triage it: set **one** state label (see `triage-labels.md`) —
   `status/ready-for-agent`, `status/ready-for-human`, `status/needs-info` or
   `status/wontfix`.
3. Branch as `<type>/<issue>-<slug>` (e.g. `ci/12-cache-bun`) and set
   `status/in-progress`; its scope removes `status/ready-*` automatically.
4. Open the PR with a description referencing the issue: `Refs #<issue>`. Do
   **not** use `Closes`: merge does not mean the outcome is verified.
5. Merge with `fj pr merge <n> --method squash --delete -m ""` (the empty `-m`
   stops `fj` from appending a `Reviewed-on:` URL — see `commit-conventions.md`).
6. Verify on the live stand (steps from the issue/README), then remove the state
   label and close manually:
   `fj issue close <n> -w "проверено: ..."`.

State labels describe the issue's **current** state. They are **scoped** labels
(`status/...`, exclusive), so Forgejo itself keeps at most one and swaps it on
transition; `status/wontfix` is the exception and stays on close. See
`triage-labels.md` for the lifecycle.

## Definition of Done

An issue is **done when its Definition of Done is met**, not when the PR is
merged. The issue stays open through merge, deploy and verification; the DoD
checklist is part of the issue body. Because the PR only references the issue
(`Refs`), Forgejo does not close it on merge — closing is a deliberate step
after verification.

If the change turns out broken after merge and it is the **same** defect, fix it
with another PR referencing the same issue (`Refs #<n>`) or reopen it. Open a
**new** issue only for a genuinely new problem; the original issue's context and
history are worth keeping.

See `docs/agents/commit-conventions.md` for the branch, commit and PR-title
format.

## Conventions

- **Create an issue**: `fj issue create "Title" --template task --body-file <file>` (the template is required while `.forgejo/issue_template/` exists; `--no-template` for a blank issue).
- **Read an issue**: `fj issue view <n>` for title and body; `fj issue view <n> comments` for comments; `fj issue view <n> assignees` for assignees.
- **List / search issues**: `fj issue search [QUERY] -s open -l "<label>"`. There is no `list`; `search` is the lister. Default state is `open`, use `-s all` for everything.
- **Comment on an issue**: `fj issue comment <n> "..."` (or `--body-file <file>`).
- **Apply / remove labels**: `fj issue edit <n> labels -a "<label>"` / `-r "<label>"`. Careful: here `-r` means *remove*, not *repo*.
- **Assign / unassign**: `fj issue assign <n> <username>` / `fj issue unassign <n> <username>`.
- **Close**: remove the state label first unless it is `status/wontfix` (`fj issue edit <n> labels -r "<label>"`), then `fj issue close <n> -w "comment"` (or `--with-msg`).

## Pull requests as a triage surface

**PRs as a request surface: no.**

But PRs are the only way into `main` (the branch is protected), so PR operations
matter day to day:

- **Create**: `fj pr create --base main --head <branch> "<title>" --body "<Refs #N>"`.
  Заголовок — позиционный аргумент, флагов `--title`/`-t` нет; `--autofill`
  берёт заголовок и тело из коммитов. Флаги сверены с `forgejo-cli` 0.6.0.
- **Status**: `fj pr status <n>` (add `--wait` to block until checks finish).
- **View**: `fj pr view <n>`; diff with `fj pr view <n> diff`, files with `fj pr view <n> files`.
- **Merge**: `fj pr merge <n> --method squash --delete -m ""` (empty `-m` avoids the `Reviewed-on:` body).
- **Comment / close**: `fj pr comment <n> "..."` / `fj pr close <n> -w "..."`.

## When a skill says "publish to the issue tracker"

Create a Forgejo issue with `fj issue create`.

## When a skill says "fetch the relevant ticket"

Run `fj issue view <number> comments` (and `fj issue view <number>` for the title
and body).

## Wayfinding operations

Used by `/wayfinder`. The map is a single issue with child issues as tickets.

- Map label: `wayfinder:map`.
- Child labels: `wayfinder:research`, `wayfinder:prototype`, `wayfinder:grilling`, or `wayfinder:task`.
- Use Forgejo sub-issues and native issue dependencies if the instance supports
  them; otherwise fall back to a task list in the map body plus `Part of #<map>`
  and `Blocked by: #<n>` lines.
- Claim work with `fj issue assign <n> <username>`.
- Resolve by commenting with the result and closing the issue.

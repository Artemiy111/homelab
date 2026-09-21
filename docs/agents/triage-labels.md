# Triage Labels

Лейбл описывает **текущее состояние** issue, а не историю.

## Оси

Три независимые оси; лейблы разных осей стоят вместе и друг друга не заменяют:

- **status** — состояние; ровно один.
- **kind** — тип; максимум один.
- **area** — область; сколько угодно (issue может затрагивать несколько сервисов).

## Состояние (status)

| Canonical role    | Label in our tracker   | Meaning                                 |
| ----------------- | ---------------------- | --------------------------------------- |
| `needs-triage`    | `status/needs-triage`  | Maintainer needs to evaluate this issue |
| `needs-info`      | `status/needs-info`    | Waiting for more information            |
| `ready-for-agent` | `status/ready-for-agent` | Fully specified and ready for an agent |
| `ready-for-human` | `status/ready-for-human` | Requires human implementation         |
| `in-progress`     | `status/in-progress`   | Work has started (branch/PR open)       |
| `wontfix`         | `status/wontfix`       | Will not be actioned (terminal)         |

Канонические имена ролей (`needs-triage` и т. д.) — это словарь скиллов; в
трекере им соответствуют строки с префиксом `status/`. Скилл, оперирующий ролью,
применяет лейбл из второй колонки.

`status/wontfix` — терминальный: остаётся на закрытой issue как причина.
Остальные лейблы состояния при закрытии снимаются: само «закрыто» уже состояние,
вешать на него `status/ready-*` или `status/in-progress` бессмысленно.

## Тип (kind)

`kind/bug`, `kind/feature`, `kind/chore`, `kind/docs` — не обязателен, максимум
один. `kind/feature` соответствует канонической категории `enhancement`.

## Область (area)

`area/<service>` (например `area/traefik`), не обязателен, может быть несколько.
Заводится по мере надобности, заранее весь список сервисов не создаём.

## Как Forgejo обеспечивает эксклюзивность

Лейблы `status/*` и `kind/*` — **scoped (exclusive)**: имя вида `scope/value` и
включённый флаг Exclusive. При добавлении второго лейбла того же scope платформа
снимает первый в той же транзакции. Это работает и в веб-интерфейсе, и через
API/`fj` — эксклюзивность принуждается в слое моделей, а не только в UI.

Scope определяется по **последнему** `/`, поэтому `scope/subscope/item` даёт scope
`scope/subscope`. Без `/` (или с пустым scope/именем) флаг exclusive не
срабатывает — поэтому всегда пишем `scope/value`.

## Жизненный цикл

1. Создана → `status/needs-triage` (ставит шаблон issue).
2. Разобрана → `status/needs-info` | `status/ready-for-agent` |
   `status/ready-for-human` | `status/wontfix`.
3. Ответ получен → назад в `status/needs-triage`.
4. Начата работа (есть ветка/PR) → `status/in-progress`. Переход сам снимает
   `status/ready-*` (exclusive), отдельно снимать не нужно.
5. PR смержен, но проверка на стенде не пройдена → остаётся `status/in-progress`
   (Definition of Done ещё не выполнен).
6. Проверено и закрыто → снять лейбл status; `status/wontfix` остаётся, если issue
   закрыт как «не будем делать».

## Инструменты

- Создать: `fj repo labels create "<scope>/<value>" <цвет> -e -d "..."`.
- Переименовать / сделать exclusive: `fj repo labels edit <id|name> -n "<scope>/<value>" -e true`.
  Флаг `-e` (exclusive) действует только вместе с `/`.
- Список лейблов: `fj repo labels view`.
- Применить / снять на issue: `fj issue edit <n> labels -a "<label>"` / `-r "<label>"`
  (здесь `-r` — это *remove*, не repo). Эксклюзивность срабатывает при `-a`.

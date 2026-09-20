# Triage Labels

Лейбл описывает **текущее состояние** issue, а не историю. Лейблы состояния
взаимоисключающие: на issue не больше одного, при переходе старый снимается, а
не копится рядом с новым.

## Состояние

| Canonical role    | Label in our tracker | Meaning                                 |
| ----------------- | -------------------- | --------------------------------------- |
| `needs-triage`    | `needs-triage`       | Maintainer needs to evaluate this issue |
| `needs-info`      | `needs-info`         | Waiting for more information            |
| `ready-for-agent` | `ready-for-agent`    | Fully specified and ready for an agent  |
| `ready-for-human` | `ready-for-human`    | Requires human implementation           |
| `in-progress`     | `in-progress`        | Work has started (branch/PR open)       |
| `wontfix`         | `wontfix`            | Will not be actioned (terminal)         |

`wontfix` — терминальный: остаётся на закрытой issue как причина. Остальные
лейблы состояния при закрытии снимаются: само «закрыто» уже состояние, вешать на
него `ready-for-*` или `in-progress` бессмысленно.

## Оси

- **Состояние** — одна строка из таблицы выше; максимум один лейбл.
- **Тип** (опционально) — `bug` / `feature` / `chore` / `docs`; максимум один.
- **Область** (опционально) — имя сервиса (`gitlab`, `forgejo`, `traefik`).

Оси независимы: состояние не заменяет тип и наоборот.

## Жизненный цикл

1. Создана → `needs-triage` (ставит шаблон issue).
2. Разобрана → `needs-info` | `ready-for-agent` | `ready-for-human` | `wontfix`.
3. Ответ получен → назад в `needs-triage`.
4. Начата работа (есть ветка/PR) → `in-progress`, снять `ready-for-*`.
5. PR смержен, но проверка на стенде не пройдена → остаётся `in-progress`
   (Definition of Done ещё не выполнен).
6. Проверено и закрыто → снять лейбл состояния; `wontfix` остаётся, если issue
   закрыт как «не будем делать».

Переход делать в порядке «добавить новый → снять старый», чтобы не было окна без
лейбла состояния.

## Инструменты

- Применить / снять: `fj issue edit <n> labels -a "<label>"` / `-r "<label>"`
  (здесь `-r` — это *remove*, не repo).
- Ограничения «ровно один лейбл из оси» в Forgejo нет — это конвенция. Следить
  за ней должны и человек, и агент, закрывающий issue.

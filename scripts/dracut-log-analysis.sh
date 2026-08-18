#!/bin/bash

# Английские названия дней и месяцев нужны команде date для строк dracut.log.
export LC_ALL=C

# $1 — первый аргумент скрипта. Если он не задан, используется системный журнал.
log_file=${1:-/var/log/dracut.log}

# -r проверяет, существует ли файл и доступен ли он для чтения.
if [ ! -r "$log_file" ]; then
    printf 'Ошибка: журнал %s недоступен для чтения.\n' "$log_file" >&2
    exit 1
fi

# Создаём безопасный временный каталог и удаляем его при завершении скрипта.
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/dracut-analysis.XXXXXX") || exit 1
trap 'rm -rf -- "$work_dir"' EXIT HUP INT TERM

filtered_file="$work_dir/filtered"
paths_file="$work_dir/paths"
counts_file="$work_dir/counts"
names_file="$work_dir/names"
block_file="$work_dir/first-block"

printf '%s\n' '=== Задание 1 ==='

# awk оставляет строки, в которых сообщение не начинается с Installing или
# Stripping. Строка "Not stripping" остаётся, так как регистр имеет значение.
awk '
index($0, " Info: Installing ") == 0 &&
index($0, " Info: Stripping ") == 0 {
    print
}
' "$log_file" > "$filtered_file"

# tac печатает строки с конца файла к началу.
tac "$filtered_file"

# wc -l считает строки, а tr удаляет пробелы из результата wc.
filtered_count=$(wc -l < "$filtered_file" | tr -d '[:space:]')
printf 'Количество строк: %d\n\n' "$filtered_count"

printf '%s\n' '=== Задание 2 ==='

# Извлекаем полные имена файлов из трёх типов сообщений:
# Installing, Stripping и Not stripping.
awk '
function strip_quotes(s, quote, first, last) {
    quote = sprintf("%c", 39)

    first = substr(s, 1, 1)
    if (first == quote || first == "\"")
        s = substr(s, 2)

    last = substr(s, length(s), 1)
    if (last == quote || last == "\"")
        s = substr(s, 1, length(s) - 1)

    return s
}
{
    marker = " Info: "
    marker_pos = index($0, marker)
    if (marker_pos == 0)
        next

    message = substr($0, marker_pos + length(marker))
    path = ""

    if (message ~ /^Installing[[:space:]]+/) {
        path = message
        sub(/^Installing[[:space:]]+/, "", path)
    } else if (message ~ /^Stripping[[:space:]]+/) {
        path = message
        sub(/^Stripping[[:space:]]+/, "", path)
    } else if (message ~ /^Not stripping[[:space:]]+/) {
        path = message
        sub(/^Not stripping[[:space:]]+/, "", path)
        sub(/,[[:space:]]*because it has hmac checksum file\.[[:space:]]*$/, "", path)
    }

    if (path != "") {
        sub(/^[[:space:]]+/, "", path)
        sub(/[[:space:]]+$/, "", path)
        path = strip_quotes(path)
        if (path != "")
            print path
    }
}
' "$log_file" > "$paths_file"

if [ ! -s "$paths_file" ]; then
    printf '%s\n\n' 'Полные имена файлов не найдены.'
else
    # sort группирует одинаковые имена, uniq -c считает их повторения.
    sort "$paths_file" | uniq -c > "$counts_file"

    # Находим самое большое значение в первом столбце файла counts.
    max_count=$(awk '
    BEGIN { max = 0 }
    $1 > max { max = $1 }
    END { print max }
    ' "$counts_file")

    # Оставляем все имена с максимальной частотой, включая случаи равенства.
    awk -v max="$max_count" '
    $1 == max {
        sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "")
        print
    }
    ' "$counts_file" > "$names_file"

    printf 'Максимальная частота: %d\n' "$max_count"
    printf '%s\n' 'Файл(ы):'
    sed 's/^/  /' "$names_file"

    # -F означает буквальный поиск, -f читает искомые имена из names_file.
    printf '%s\n' 'Строки журнала с найденными именами:'
    grep -F -f "$names_file" "$log_file" || :
    printf '\n'
fi

printf '%s\n' '=== Задание 3 ==='

# Запоминаем первое событие Executing и берём первое событие Wrote после него.
awk '
!executing_found && $0 ~ / Info: Executing([[:space:]:]|$)/ {
    executing_line = $0
    executing_found = 1
    next
}
executing_found && $0 ~ / Info: Wrote([[:space:]:]|$)/ {
    print executing_line
    print
    exit
}
' "$log_file" > "$block_file"

block_line_count=$(wc -l < "$block_file" | tr -d '[:space:]')
if [ "$block_line_count" -lt 2 ]; then
    printf '%s\n' 'Первый блок с событиями Executing и Wrote не найден.' >&2
    exit 2
fi

# sed извлекает первую и вторую строки найденной пары событий.
executing_line=$(sed -n '1p' "$block_file")
wrote_line=$(sed -n '2p' "$block_file")

# Удаляем из строк часть, начинающуюся с " Info:", и оставляем дату/время.
executing_time=${executing_line%% Info:*}
wrote_time=${wrote_line%% Info:*}

# date +%s преобразует дату в количество секунд с начала эпохи Unix.
if ! executing_epoch=$(date -d "$executing_time" +%s 2>/dev/null); then
    printf 'Не удалось преобразовать дату: %s\n' "$executing_time" >&2
    exit 3
fi

if ! wrote_epoch=$(date -d "$wrote_time" +%s 2>/dev/null); then
    printf 'Не удалось преобразовать дату: %s\n' "$wrote_time" >&2
    exit 3
fi

# Арифметическое выражение Bash: время Wrote минус время Executing.
elapsed_seconds=$((wrote_epoch - executing_epoch))

printf 'Executing: %s\n' "$executing_time"
printf 'Wrote:     %s\n' "$wrote_time"
printf 'Прошло секунд: %d\n' "$elapsed_seconds"

#!/bin/sh

# Скрипт для замера скорости записи/чтения на диск
# Использует dd, awk и встроенные средства shell
# Совместим с Entware (роутеры), WSL, Linux, macOS
# chmod +x iospeed.sh
# ./iospeed.sh -h
# ./iospeed.sh -s 1024
# sudo ./iospeed.sh - для правильной очистки кэша

# --- Параметры по умолчанию ---
# Размер блока по умолчанию 1M. Можно указать в K, M. Без указания юнита будет в байтах
BS="1M"
# Количество блоков
COUNT="256"
# Путь к каталогу для временного файла
OUTPUT_DIR="."
# Имя временного файла
FILENAME="tempfile.io"
# Собираем полный путь к файлу
OUTPUT_FILE="$OUTPUT_DIR/$FILENAME"

# --- Цвета для вывода ---
# Используем printf для максимальной совместимости
C_RED=$(printf "\033[0;31m")
C_GREEN=$(printf "\033[0;32m")
C_YELLOW=$(printf "\033[0;33m")
C_CYAN=$(printf "\033[0;36m")
C_RESET=$(printf "\033[0m")

# Функция для универсального замера времени
get_current_time() {
    if date +%s.%N >/dev/null 2>&1; then
        # Поддерживаются наносекунды
        date +%s.%N
    else
        # Fallback на секунды
        date +%s
    fi
}

# Функция для расчета разности времени
calc_time_diff() {
    START_TIME_VAR="$1"
    END_TIME_VAR="$2"
    
    if date +%s.%N >/dev/null 2>&1; then
        # Наносекунды поддерживаются, точный расчет
        echo "$END_TIME_VAR $START_TIME_VAR" | awk '{printf "%.3f", $1 - $2}'
    else
        # Только секунды, менее точный расчет
        echo "$END_TIME_VAR $START_TIME_VAR" | awk '{printf "%.0f", $1 - $2}'
    fi
}

# Функция для проверки условий
calc_condition() {
    awk "BEGIN { exit !($1) }"
}

# Функция для проверки поддержки oflag=dsync
supports_dsync() {
    dd if=/dev/zero of=/dev/null bs=1 count=1 oflag=dsync 2>/dev/null
}

# Функция для разбиения текста на строки с учетом максимальной длины
split_text() {
    text="$1"
    max_width="$2"
    
    # Если текст короткий, просто выводим его
    if [ ${#text} -le "$max_width" ]; then
        echo "$text"
        return
    fi
    
    # Разбиваем длинный текст на строки
    while [ ${#text} -gt "$max_width" ]; do
        # Ищем последний пробел в пределах max_width
        cut_pos="$max_width"
        while [ "$cut_pos" -gt 0 ]; do
            char=$(echo "$text" | cut -c"$cut_pos")
            if [ "$char" = " " ]; then
                break
            fi
            cut_pos=$((cut_pos - 1))
        done
        
        # Если не нашли пробел, режем по max_width
        if [ "$cut_pos" -eq 0 ]; then
            cut_pos="$max_width"
        fi
        
        # Выводим часть строки
        echo "$text" | cut -c1-"$cut_pos"
        
        # Убираем обработанную часть
        text=$(echo "$text" | cut -c$((cut_pos + 1))-)
        # Убираем ведущие пробелы
        text=$(echo "$text" | sed 's/^[[:space:]]*//')
    done
    
    # Выводим остаток, если есть
    if [ -n "$text" ]; then
        echo "$text"
    fi
}

# Универсальная функция для вывода многострочных сообщений
print_message() {
    icon="$1"
    title="$2"
    color="$3"
    shift 3
    
    # Максимальная ширина текста (без учета символов форматирования)
    max_width=150
    
    # Рассчитываем длину префикса: "│ 🔄 ЗАГОЛОВОК: "
    # 2 (│ ) + длина иконки (обычно 2) + 1 пробел + длина заголовка + 2 (: )
    prefix_length=$((2 + 2 + 1 + ${#title} + 2))
    available_width=$((max_width - prefix_length))
    
    # Если передан только один аргумент и он помещается рядом с заголовком
    if [ $# -eq 1 ] && [ ${#1} -le "$available_width" ]; then
        printf "%s│ %s %s: %s%s\n" "$color" "$icon" "$title" "$1" "$C_RESET"
        printf "\n"
        return
    fi
    
    # Выводим заголовок для многострочных или длинных сообщений
    printf "%s│ %s %s:%s\n" "$color" "$icon" "$title" "$C_RESET"
    
    # Обрабатываем каждый аргумент как отдельную логическую строку
    for text in "$@"; do
        # Разбиваем текст на физические строки если он длинный
        split_text "$text" "$max_width" | while IFS= read -r line; do
            if [ -n "$line" ]; then
                printf "%s│ %s%s\n" "$color" "$line" "$C_RESET"
            fi
        done
    done
    
    # Добавляем пустую строку после сообщения
    printf "\n"
}

# Функция для вывода предупреждений
print_warning() {
    print_message "⚠ " "ВНИМАНИЕ" "$C_YELLOW" "$@"
}

# Функция для вывода ошибок
print_error() {
    print_message "⛔" "ОШИБКА" "$C_RED" "$@"
}

# Функция для вывода успеха
print_success() {
    print_message "✅" "УСПЕХ" "$C_GREEN" "$@"
}

# --- Гарантированная очистка ---

# --- Функция вывода справки ---
usage() {
    echo "Использование: ${C_CYAN}$0 [-s мегабайты] [-p путь_к_папке]${C_RESET}"
    echo "  -s: Общий размер файла для теста в МБ (по умолч. $COUNT)"
    echo "  -p: Путь к каталогу для временного файла (по умолч. $OUTPUT_DIR)"
    echo "Пример: ${C_CYAN}$0 -s 512 -p /mnt/data${C_RESET}"
    exit 1
}

printf "\n"

# --- Парсинг аргументов командной строки ---
while [ "$#" -gt 0 ]; do
    case "$1" in
        -s)
            COUNT="$2"
            shift 2
            ;;
        -p)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            print_error "Неизвестный параметр: $1"
            usage
            ;;
    esac
done

# Пересобираем путь к файлу после парсинга аргументов
OUTPUT_FILE="$OUTPUT_DIR/$FILENAME"

# Устанавливаем ловушку для удаления временного файла при выходе из скрипта
# EXIT: нормальное завершение, INT: прерывание (Ctrl+C), TERM: команда kill
trap 'printf "\n%s\n" "${C_YELLOW}Прерывание. Очистка...${C_RESET}"; rm -f "$OUTPUT_FILE"' EXIT INT TERM

# --- Основная логика ---

# Проверка зависимостей
if ! command -v awk >/dev/null 2>&1; then
    print_error "Необходимая утилита 'awk' не найдена. Скрипт не может продолжить."
    exit 1
fi

# Проверка наличия внешней утилиты time (не встроенной)
USE_BUILTIN_TIME=0
# Проверяем наличие внешней time в типичных путях Entware и Linux
TIME_FOUND=0
for time_path in /opt/bin/time /usr/bin/time /bin/time; do
    if [ -x "$time_path" ] && "$time_path" -p true >/dev/null 2>&1; then
        TIME_FOUND=1
        break
    fi
done

if [ "$TIME_FOUND" -eq 0 ]; then
    print_warning "Внешняя утилита 'time' не найдена. Будет использован встроенный механизм замера времени."
    USE_BUILTIN_TIME=1
    
    # Проверяем поддержку наносекунд в date
    if ! date +%s.%N >/dev/null 2>&1; then
        print_warning "Поддержка наносекунд в 'date' недоступна. Точность замера времени может быть снижена."
    fi
fi

# Проверка прав суперпользователя для корректной очистки кэша
if [ "$(id -u)" -ne 0 ]; then
    print_warning "Скрипт запущен без прав суперпользователя (sudo). Тест скорости чтения может показать завышенные результаты из-за кэширования. Для точного замера запустите скрипт через 'sudo'."
fi

# Извлекаем числовое значение из размера блока (например, "1M" -> "1")
# и множитель (M=1024*1024, K=1024)
SIZE_VAL=$(echo $BS | sed 's/[^0-9]*//g')
SIZE_UNIT=$(echo $BS | sed 's/[0-9]*//g' | tr '[:lower:]' '[:upper:]')

MULTIPLIER=1
if [ "$SIZE_UNIT" = "M" ] || [ "$SIZE_UNIT" = "MB" ]; then
    MULTIPLIER=$((1024*1024))
elif [ "$SIZE_UNIT" = "K" ] || [ "$SIZE_UNIT" = "KB" ]; then
    MULTIPLIER=1024
fi

# Общий размер данных для записи в байтах
TOTAL_BYTES=$((SIZE_VAL * COUNT * MULTIPLIER))
# Общий размер в Мегабайтах для вывода
TOTAL_MB=$(echo "$TOTAL_BYTES" | awk '{printf "%.1f", $1 / 1048576}')

# Определяем тип файловой системы для диагностики
FS_TYPE="неизвестно"
if command -v df >/dev/null 2>&1; then
    FS_INFO=$(df -T "$OUTPUT_DIR" 2>/dev/null | tail -1)
    if [ -n "$FS_INFO" ]; then
        FS_TYPE=$(echo "$FS_INFO" | awk '{print $2}')
    fi
fi

# Проверяем поддержку синхронной записи
DSYNC_SUPPORT="нет"
if supports_dsync; then
    DSYNC_SUPPORT="да"
fi

echo "=== Тест скорости записи ==="
echo "Файл:             $OUTPUT_FILE"
echo "Файловая система: $FS_TYPE"
echo "Sync запись:      $DSYNC_SUPPORT"
echo "Размер блока:     $BS"
echo "Кол-во блоков:    $COUNT"
echo "Общий размер:     ${TOTAL_MB} MB"

echo "---------------------------"
echo "Выполняется запись... пожалуйста, подождите."

# Выполняем команду записи и замеряем время.
if [ "$USE_BUILTIN_TIME" -eq 1 ]; then
    # Используем встроенный механизм замера времени
    START_TIME=$(get_current_time)
    
    # Используем oflag=dsync для принудительной синхронной записи (если поддерживается)
    if supports_dsync; then
        WRITE_DD_OUTPUT=$(dd if=/dev/zero of=$OUTPUT_FILE bs=$BS count="$COUNT" oflag=dsync 2>&1)
    else
        WRITE_DD_OUTPUT=$(dd if=/dev/zero of=$OUTPUT_FILE bs=$BS count="$COUNT" 2>&1)
    fi
    
    # Принудительная синхронизация для точного замера
    sync
    # Дополнительная задержка для exFAT и других файловых систем с отложенной записью
    if [ "$FS_TYPE" = "exfat" ] || [ "$FS_TYPE" = "vfat" ] || [ "$FS_TYPE" = "ntfs" ]; then
        sleep 0.1  # 100ms задержка для Windows-файловых систем
    fi
    
    END_TIME=$(get_current_time)
    WRITE_REAL_TIME=$(calc_time_diff "$START_TIME" "$END_TIME")
    WRITE_TIME_OUTPUT="$WRITE_DD_OUTPUT"
else
    # Используем внешнюю утилиту time
    for time_path in /opt/bin/time /usr/bin/time /bin/time; do
        if [ -x "$time_path" ]; then
            # Проверяем поддержку oflag=dsync и используем его если возможно
            if supports_dsync; then
                WRITE_TIME_OUTPUT=$( ("$time_path" -p sh -c "dd if=/dev/zero of=$OUTPUT_FILE bs=$BS count=$COUNT oflag=dsync && sync") 2>&1 )
            else
                WRITE_TIME_OUTPUT=$( ("$time_path" -p sh -c "dd if=/dev/zero of=$OUTPUT_FILE bs=$BS count=$COUNT && sync") 2>&1 )
            fi
            break
        fi
    done
fi

# Извлекаем реальное время выполнения из вывода 'time'
if [ "$USE_BUILTIN_TIME" -eq 1 ]; then
    # Время уже рассчитано выше
    true
else
    WRITE_REAL_TIME=$(echo "$WRITE_TIME_OUTPUT" | grep '^real' | awk '{print $2}')
fi
# Извлекаем сообщения об ошибках (если есть)
if [ "$USE_BUILTIN_TIME" -eq 1 ]; then
    WRITE_ERROR=$(echo "$WRITE_TIME_OUTPUT" | grep -v '^[0-9].*records.*\|^[0-9].*bytes.*copied')
else
    WRITE_ERROR=$(echo "$WRITE_TIME_OUTPUT" | grep -v '^real\|^user\|^sys\|^[0-9].*records.*\|^[0-9].*bytes.*copied')
fi

# --- Тест чтения ---
echo "Выполняется чтение... пожалуйста, подождите."

# Очищаем дисковый кэш для более точного замера скорости чтения.
# Может требовать прав суперпользователя, поэтому ошибки перенаправляются в /dev/null
sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null

# Выполняем команду чтения и замеряем время.
if [ "$USE_BUILTIN_TIME" -eq 1 ]; then
    # Используем встроенный механизм замера времени
    START_TIME=$(get_current_time)
    READ_DD_OUTPUT=$(dd if=$OUTPUT_FILE of=/dev/null bs=$BS count="$COUNT" 2>&1)
    END_TIME=$(get_current_time)
    READ_REAL_TIME=$(calc_time_diff "$START_TIME" "$END_TIME")
    READ_TIME_OUTPUT="$READ_DD_OUTPUT"
else
    # Используем внешнюю утилиту time
    for time_path in /opt/bin/time /usr/bin/time /bin/time; do
        if [ -x "$time_path" ]; then
            READ_TIME_OUTPUT=$( ("$time_path" -p sh -c "dd if=$OUTPUT_FILE of=/dev/null bs=$BS count=$COUNT") 2>&1 )
            break
        fi
    done
fi
if [ "$USE_BUILTIN_TIME" -eq 1 ]; then
    # Время уже рассчитано выше
    true
else
    READ_REAL_TIME=$(echo "$READ_TIME_OUTPUT" | grep '^real' | awk '{print $2}')
fi
# Извлекаем сообщения об ошибках (если есть)
if [ "$USE_BUILTIN_TIME" -eq 1 ]; then
    READ_ERROR=$(echo "$READ_TIME_OUTPUT" | grep -v '^[0-9].*records.*\|^[0-9].*bytes.*copied')
else
    READ_ERROR=$(echo "$READ_TIME_OUTPUT" | grep -v '^real\|^user\|^sys\|^[0-9].*records.*\|^[0-9].*bytes.*copied')
fi

# Удаляем временный файл
rm -f "$OUTPUT_FILE"
# Снимаем ловушку, так как файл уже удален штатно
trap - EXIT INT TERM

# --- Расчет и вывод результата ---
echo "---------------------------"
echo ""

# Инициализируем флаг ошибки
HAS_WRITE_ERRORS=0
HAS_READ_ERRORS=0

# Расчет и форматирование результатов
if [ -n "$WRITE_REAL_TIME" ] && calc_condition "$WRITE_REAL_TIME > 0"; then
    # Проверяем, что время больше 0.001 секунды для адекватного расчета
    if calc_condition "$WRITE_REAL_TIME >= 0.001"; then
        WRITE_SPEED_MBPS=$(echo "$TOTAL_BYTES $WRITE_REAL_TIME" | awk '{printf "%.2f", $1 / $2 / 1048576}')
        WRITE_TIME_FORMATTED=$(printf "%.3f" "$WRITE_REAL_TIME")
    else
        # Слишком быстрая операция для точного замера
        WRITE_SPEED_MBPS="Слишком быстро"
        WRITE_TIME_FORMATTED=$(printf "%.6f" "$WRITE_REAL_TIME")
    fi
    # Для таблицы используем обычный текст
    WRITE_SPEED_TABLE="$WRITE_SPEED_MBPS"
    WRITE_TIME_TABLE="$WRITE_TIME_FORMATTED"
else
    HAS_WRITE_ERRORS=1
    # Цветные версии для сообщений об ошибках
    WRITE_SPEED_MBPS=$(printf "%sОшибка%s" "$C_RED" "$C_RESET")
    WRITE_TIME_FORMATTED=$(printf "%sОшибка%s" "$C_RED" "$C_RESET")
    # Для таблицы тоже используем цветные версии
    WRITE_SPEED_TABLE="$(printf "%sОшибка%s" "$C_RED" "$C_RESET")"
    WRITE_TIME_TABLE="$(printf "%sОшибка%s" "$C_RED" "$C_RESET")"
fi

if [ -n "$READ_REAL_TIME" ] && calc_condition "$READ_REAL_TIME > 0"; then
    # Проверяем, что время больше 0.001 секунды для адекватного расчета
    if calc_condition "$READ_REAL_TIME >= 0.001"; then
        READ_SPEED_MBPS=$(echo "$TOTAL_BYTES $READ_REAL_TIME" | awk '{printf "%.2f", $1 / $2 / 1048576}')
        READ_TIME_FORMATTED=$(printf "%.3f" "$READ_REAL_TIME")
    else
        # Слишком быстрая операция для точного замера
        READ_SPEED_MBPS="Слишком быстро"
        READ_TIME_FORMATTED=$(printf "%.6f" "$READ_REAL_TIME")
    fi
    # Для таблицы используем обычный текст
    READ_SPEED_TABLE="$READ_SPEED_MBPS"
    READ_TIME_TABLE="$READ_TIME_FORMATTED"
else
    HAS_READ_ERRORS=1
    # Цветные версии для сообщений об ошибках
    READ_SPEED_MBPS=$(printf "%sОшибка%s" "$C_RED" "$C_RESET")
    READ_TIME_FORMATTED=$(printf "%sОшибка%s" "$C_RED" "$C_RESET")
    # Для таблицы тоже используем цветные версии
    READ_SPEED_TABLE="$(printf "%sОшибка%s" "$C_RED" "$C_RESET")"
    READ_TIME_TABLE="$(printf "%sОшибка%s" "$C_RED" "$C_RESET")"
fi

# Выводим итоговый статус в зависимости от наличия ошибок
if [ "$HAS_WRITE_ERRORS" -eq 1 ] || [ "$HAS_READ_ERRORS" -eq 1 ] ; then
    # Собираем все ошибки в отдельные аргументы
    if [ -n "$WRITE_ERROR" ] && [ -n "$READ_ERROR" ]; then
        print_error "Тест завершён с ошибками." "Ошибка записи: $WRITE_ERROR" "Ошибка чтения: $READ_ERROR"
    elif [ -n "$WRITE_ERROR" ]; then
        print_error "Тест завершён с ошибками." "Ошибка записи: $WRITE_ERROR"
    elif [ -n "$READ_ERROR" ]; then
        print_error "Тест завершён с ошибками." "Ошибка чтения: $READ_ERROR"
    else
        print_error "Тест завершён с ошибками."
    fi
else
    print_success "Тест завершен."
fi

WRITE_TIME_WIDTH="%10s"
READ_TIME_WIDTH="%10s"

if [ "$HAS_WRITE_ERRORS" -eq 1 ]; then
    WRITE_TIME_WIDTH="%-27s"
fi

if [ "$HAS_READ_ERRORS" -eq 1 ]; then
    READ_TIME_WIDTH="%-27s"
fi

echo "=== Результаты ==="
printf "%-8s | %10s | %15s\n" "Операция" "Время (с) " "Скорость (МБ/с)"
printf "%-8s | %-10s | %-15s\n" "--------" "----------" "---------------"
printf "%-14s | $READ_TIME_WIDTH | %15s\n" "Чтение" "$READ_TIME_TABLE" "$READ_SPEED_TABLE"
printf "%-14s | $WRITE_TIME_WIDTH | %15s\n" "Запись" "$WRITE_TIME_TABLE" "$WRITE_SPEED_TABLE"
printf "\n"
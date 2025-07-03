#!/bin/sh

# Установщик iospeed.sh для Entware
# Автор: [Ваше имя]
# Версия: 1.0

# --- Настройки ---
GITHUB_REPO="constgen/iospeed"  # Замените на ваш GitHub репозиторий
SCRIPT_NAME="iospeed.sh"
INSTALL_DIR="/opt/bin"
CONFIG_DIR="/opt/etc/iospeed"
VERSION_FILE="$CONFIG_DIR/version"
GITHUB_API="https://api.github.com/repos/$GITHUB_REPO"
GITHUB_RAW="https://raw.githubusercontent.com/$GITHUB_REPO/main"

# --- Цвета для вывода ---
C_RED=$(printf "\033[0;31m")
C_GREEN=$(printf "\033[0;32m")
C_YELLOW=$(printf "\033[0;33m")
C_CYAN=$(printf "\033[0;36m")
C_RESET=$(printf "\033[0m")

# Функция для вывода сообщений
print_info() {
    printf "%s[INFO]%s %s\n" "$C_CYAN" "$C_RESET" "$1"
}

print_success() {
    printf "%s[SUCCESS]%s %s\n" "$C_GREEN" "$C_RESET" "$1"
}

print_error() {
    printf "%s[ERROR]%s %s\n" "$C_RED" "$C_RESET" "$1"
}

print_warning() {
    printf "%s[WARNING]%s %s\n" "$C_YELLOW" "$C_RESET" "$1"
}

# Проверка Entware
check_entware() {
    if [ ! -d "/opt" ] || [ ! -x "/opt/bin/opkg" ]; then
        print_error "Entware не найден. Установите Entware перед запуском этого скрипта."
        exit 1
    fi
    print_info "Entware найден: $(opkg --version | head -1)"
}

# Проверка зависимостей
check_dependencies() {
    print_info "Проверка зависимостей..."
    
    # Проверяем wget или curl
    if command -v wget >/dev/null 2>&1; then
        DOWNLOADER="wget"
        DOWNLOAD_CMD="wget -q -O"
    elif command -v curl >/dev/null 2>&1; then
        DOWNLOADER="curl"
        DOWNLOAD_CMD="curl -s -L -o"
    else
        print_error "Не найден wget или curl. Установите один из них, например: ${C_CYAN}opkg install wget${C_RESET}"
        exit 1
    fi
    print_info "Найден загрузчик: $DOWNLOADER"
    
    # Устанавливаем ca-certificates если нужно
    if ! opkg list-installed | grep -q ca-certificates; then
        print_info "Устанавливаем ca-certificates..."
        opkg update
        opkg install ca-certificates
    fi
}

# Получение последней версии из GitHub
get_latest_version() {
    print_info "Получение информации о последней версии..."
    
    # Пытаемся получить информацию через API
    if [ "$DOWNLOADER" = "wget" ]; then
        LATEST_INFO=$(wget -q -O - "$GITHUB_API/releases/latest" 2>/dev/null)
    else
        LATEST_INFO=$(curl -s "$GITHUB_API/releases/latest" 2>/dev/null)
    fi
    
    if [ -n "$LATEST_INFO" ]; then
        # Извлекаем версию из JSON (простой способ без jq)
        LATEST_VERSION=$(echo "$LATEST_INFO" | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
    fi
    
    # Если не удалось получить через API, используем коммиты
    if [ -z "$LATEST_VERSION" ]; then
        print_warning "Не удалось получить версию через API, используем timestamp"
        LATEST_VERSION="$(date +%Y%m%d_%H%M%S)"
    fi
    
    echo "$LATEST_VERSION"
}

# Загрузка скрипта
download_script() {
    version="$1"
    temp_file="/tmp/${SCRIPT_NAME}.tmp"
    
    print_info "Загрузка $SCRIPT_NAME версии $version..."
    
    # Загружаем основной скрипт
    if [ "$DOWNLOADER" = "wget" ]; then
        wget -q -O "$temp_file" "$GITHUB_RAW/$SCRIPT_NAME"
    else
        curl -s -L -o "$temp_file" "$GITHUB_RAW/$SCRIPT_NAME"
    fi
    
    if [ ! -f "$temp_file" ] || [ ! -s "$temp_file" ]; then
        print_error "Не удалось загрузить $SCRIPT_NAME"
        rm -f "$temp_file"
        return 1
    fi
    
    # Проверяем что это shell скрипт
    if ! head -1 "$temp_file" | grep -q "^#!/"; then
        print_error "Загруженный файл не является shell скриптом"
        rm -f "$temp_file"
        return 1
    fi
    
    echo "$temp_file"
}

# Установка скрипта
install_script() {
    temp_file="$1"
    version="$2"
    
    print_info "Установка скрипта..."
    
    # Создаем директории
    mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"
    
    # Копируем скрипт
    cp "$temp_file" "$INSTALL_DIR/$SCRIPT_NAME"
    chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
    
    # Сохраняем версию
    echo "$version" > "$VERSION_FILE"
    echo "$(date)" >> "$VERSION_FILE"
    
    # Очищаем временный файл
    rm -f "$temp_file"
    
    print_success "Скрипт установлен в $INSTALL_DIR/$SCRIPT_NAME"
}

# Проверка обновлений
check_updates() {
    if [ ! -f "$VERSION_FILE" ]; then
        print_info "Информация о версии не найдена"
        return 0
    fi
    
    current_version=$(head -1 "$VERSION_FILE")
    latest_version=$(get_latest_version)
    
    print_info "Текущая версия: $current_version"
    print_info "Последняя версия: $latest_version"
    
    if [ "$current_version" != "$latest_version" ]; then
        print_info "Доступно обновление!"
        return 0
    else
        print_success "У вас установлена последняя версия"
        return 1
    fi
}

# Функция обновления
update_script() {
    latest_version=$(get_latest_version)
    temp_file=$(download_script "$latest_version")
    
    if [ -n "$temp_file" ]; then
        install_script "$temp_file" "$latest_version"
        print_success "Обновление завершено!"
    else
        print_error "Обновление не удалось"
        return 1
    fi
}

# Создание скрипта автообновления
create_updater() {
    updater_script="/opt/bin/iospeed-update"
    
    cat > "$updater_script" << EOF
#!/bin/sh
# Автообновление iospeed.sh

INSTALLER_URL="https://raw.githubusercontent.com/$GITHUB_REPO/main/install-iospeed.sh"

# Загружаем и запускаем установщик с флагом обновления
wget -q -O - "\$INSTALLER_URL" | sh -s -- --update
EOF
    
    chmod +x "$updater_script"
    print_success "Создан скрипт автообновления: $updater_script"
}

# Добавление в cron (опционально)
setup_auto_update() {
    print_info "Настройка автоматических обновлений..."
    
    # Проверяем наличие cron
    if [ ! -x "/opt/sbin/cron" ]; then
        print_warning "Cron не найден. Установите: opkg install cron"
        return 1
    fi
    
    # Добавляем задачу в crontab (проверка обновлений раз в неделю)
    cron_line="0 2 * * 0 /opt/bin/iospeed-update >/dev/null 2>&1"
    
    # Проверяем, есть ли уже такая задача
    if ! crontab -l 2>/dev/null | grep -q "iospeed-update"; then
        (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
        print_success "Автообновление настроено (каждое воскресенье в 2:00)"
    else
        print_info "Автообновление уже настроено"
    fi
}

# Главная функция
main() {
    command="$1"
    
    case "$command" in
        --update)
            print_info "Режим обновления"
            check_entware
            check_dependencies
            if check_updates; then
                update_script
            fi
            ;;
        --check)
            print_info "Проверка обновлений"
            check_entware
            check_dependencies
            check_updates
            ;;
        --uninstall)
            print_info "Удаление iospeed.sh"
            rm -f "$INSTALL_DIR/$SCRIPT_NAME"
            rm -rf "$CONFIG_DIR"
            rm -f "/opt/bin/iospeed-update"
            # Удаляем из crontab
            crontab -l 2>/dev/null | grep -v "iospeed-update" | crontab -
            print_success "iospeed.sh удален"
            ;;
        *)
            print_info "Установка iospeed.sh"
            check_entware
            check_dependencies
            
            latest_version=$(get_latest_version)
            temp_file=$(download_script "$latest_version")
            
            if [ -n "$temp_file" ]; then
                install_script "$temp_file" "$latest_version"
                create_updater
                
                echo ""
                print_success "Установка завершена!"
                print_info "Использование: iospeed.sh -h"
                print_info "Обновление: iospeed-update"
                print_info "Проверка обновлений: $0 --check"
                
                # Предлагаем настроить автообновление
                printf "\nНастроить автоматические обновления? [y/N]: "
                read -r answer
                case "$answer" in
                    [Yy]|[Yy][Ee][Ss])
                        setup_auto_update
                        ;;
                esac
            else
                print_error "Установка не удалась"
                exit 1
            fi
            ;;
    esac
}

# Запуск
main "$@"

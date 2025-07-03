# Makefile для проекта IOSpeed

.PHONY: test install uninstall check lint release help

# Переменные
SCRIPT_NAME = iospeed.sh
INSTALLER = install-iospeed.sh
INSTALL_DIR = /opt/bin
VERSION = $(shell date +%Y%m%d_%H%M%S)

help: ## Показать эту справку
	@echo "IOSpeed - Утилита тестирования скорости дисков"
	@echo ""
	@echo "Доступные команды:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

test: ## Запустить тесты
	@echo "Проверка синтаксиса..."
	@sh -n $(SCRIPT_NAME)
	@sh -n $(INSTALLER)
	@echo "Тестирование базовой функциональности..."
	@chmod +x $(SCRIPT_NAME)
	@./$(SCRIPT_NAME) -s 1 -p /tmp
	@echo "✅ Все тесты пройдены"

lint: ## Проверить код с помощью shellcheck
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "Проверка $(SCRIPT_NAME)..."; \
		shellcheck $(SCRIPT_NAME); \
		echo "Проверка $(INSTALLER)..."; \
		shellcheck $(INSTALLER); \
		echo "✅ Проверка кода завершена"; \
	else \
		echo "⚠️  shellcheck не найден. Установите: apt install shellcheck"; \
	fi

install: ## Установить скрипт локально
	@echo "Установка $(SCRIPT_NAME)..."
	@chmod +x $(SCRIPT_NAME) $(INSTALLER)
	@sudo cp $(SCRIPT_NAME) $(INSTALL_DIR)/
	@echo "✅ Установка завершена: $(INSTALL_DIR)/$(SCRIPT_NAME)"

uninstall: ## Удалить установленный скрипт
	@echo "Удаление $(SCRIPT_NAME)..."
	@sudo rm -f $(INSTALL_DIR)/$(SCRIPT_NAME)
	@echo "✅ Удаление завершено"

check: ## Проверить установленную версию
	@if [ -f "$(INSTALL_DIR)/$(SCRIPT_NAME)" ]; then \
		echo "Установленная версия:"; \
		$(INSTALL_DIR)/$(SCRIPT_NAME) -h | head -3; \
	else \
		echo "❌ Скрипт не установлен"; \
	fi

release: ## Подготовить релиз
	@echo "Подготовка релиза $(VERSION)..."
	@git add .
	@git commit -m "Release $(VERSION)" || true
	@git tag -a "v$(VERSION)" -m "Release version $(VERSION)"
	@echo "✅ Релиз подготовлен. Выполните: git push origin main --tags"

clean: ## Очистить временные файлы
	@echo "Очистка временных файлов..."
	@rm -f tempfile.io
	@rm -f /tmp/tempfile.io
	@echo "✅ Очистка завершена"

benchmark: ## Запустить бенчмарк на разных ФС
	@echo "Бенчмарк файловых систем..."
	@echo "\n=== Тест tmpfs (RAM) ==="
	@./$(SCRIPT_NAME) -s 50 -p /dev/shm 2>/dev/null || echo "tmpfs недоступен"
	@echo "\n=== Тест /tmp ==="
	@./$(SCRIPT_NAME) -s 50 -p /tmp
	@echo "\n=== Тест текущей директории ==="
	@./$(SCRIPT_NAME) -s 50

demo: ## Показать демонстрацию возможностей
	@echo "🚀 Демонстрация IOSpeed"
	@echo ""
	@chmod +x $(SCRIPT_NAME)
	@echo "1️⃣  Быстрый тест 10MB..."
	@./$(SCRIPT_NAME) -s 10
	@echo ""
	@echo "2️⃣  Справка по использованию:"
	@./$(SCRIPT_NAME) -h

# Дополнительные цели для разработки
dev-setup: ## Настроить среду разработки
	@echo "Настройка среды разработки..."
	@chmod +x $(SCRIPT_NAME) $(INSTALLER)
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "Рекомендуется установить shellcheck для проверки кода"; \
		echo "Ubuntu/Debian: sudo apt install shellcheck"; \
		echo "macOS: brew install shellcheck"; \
	fi
	@echo "✅ Среда разработки готова"

package: ## Создать архив для распространения
	@echo "Создание пакета..."
	@tar -czf iospeed-$(VERSION).tar.gz $(SCRIPT_NAME) $(INSTALLER) README.md
	@echo "✅ Создан пакет: iospeed-$(VERSION).tar.gz"

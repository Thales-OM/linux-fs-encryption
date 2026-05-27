CC      = gcc
CFLAGS  = -Wall -O2 -D_FILE_OFFSET_BITS=64 `pkg-config --cflags fuse3`
LDFLAGS = `pkg-config --libs fuse3` -lsodium -lpthread

.PHONY: all clean install-deps run help

all: encfs

install-deps:
	@chmod +x install_deps.sh
	@./install_deps.sh

encfs: encfs.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

run: encfs
	@echo "📌 Использование: ./encfs <backend_dir> <mount_point>"
	@echo "🔹 Пример: mkdir -p ~/enc_backend ~/enc_mount && ./encfs ~/enc_backend ~/enc_mount"

clean:
	rm -f encfs

help:
	@echo "📖 Доступные цели:"
	@echo "  make install-deps  - Автоматически установить зависимости"
	@echo "  make               - Собрать проект"
	@echo "  make run           - Показать инструкцию по запуску"
	@echo "  make clean         - Удалить бинарный файл"

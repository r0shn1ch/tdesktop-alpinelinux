# Сборка Telegram Desktop 7.2.8 для Alpine Linux 3.20

Эта инструкция описывает сборку, которая была проверена на Alpine 3.20.6
x86_64. Цель — получить обычный APK для установки в изолированной системе,
где во время установки нет доступа в интернет.

## Почему потребовалась отдельная сборка

Предыдущий APK был собран смесью Alpine edge и Alpine 3.20. В результате
бинарник требовал ABI, которых нет в 3.20: `libavcodec.so.62`,
`libabsl_*.so.2608.0.0`, `libada.so.3` и другие edge-версии. Наличие файлов
с похожими именами не исправляет несовместимость ABI; именно это приводило к
ошибкам загрузчика и падению в FFmpeg/WebRTC.

Здесь все C/C++ библиотеки берутся из одного набора Alpine 3.20:

- FFmpeg 6.1.1 (`libavcodec.so.60`, `libavfilter.so.9` и т. д.);
- Abseil 20230802.1 (`libabsl_*.so.2308.0.0`);
- OpenH264 2.4.1 (`libopenh264.so.7`);
- libvpx 1.14.1;
- Qt 6.6.3 и остальные библиотеки из репозиториев v3.20.

## Исходники

Версии зафиксированы в `versions.env`. Официальный Telegram Desktop берётся
с тега `v7.2.8`; TDLib, tlottie и tg_owt также фиксируются конкретными
коммитами. Подмодули Telegram нужно получить рекурсивно.

```sh
git clone --branch v7.2.8 --recurse-submodules \
  https://github.com/telegramdesktop/tdesktop.git tdesktop
git -C tdesktop checkout 272f6f5c2d29d8cdb3aec15907d616b87451a3ca

git clone https://github.com/tdlib/td.git tdlib
git -C tdlib checkout 51743dfd01dff6179e2d8f7095729caa4e2222e9

git clone https://github.com/dkaraush/tlottie.git tlottie
git -C tlottie checkout 4b940c7942fbde8ee56f10f39a5224a4153bd91e

git clone --recurse-submodules https://github.com/desktop-app/tg_owt.git tg_owt
git -C tg_owt checkout 26068e29bfa8d74a9dc9c8f7f94172fafbc262b8
git -C tg_owt submodule update --init --recursive
```

На машине без интернета эти исходники и APK-пакеты Alpine нужно заранее
перенести обычным архивом. Целевая система для установки исходники не нужны.

## Подготовка Alpine build-root

Собирать нужно внутри Alpine 3.20.6 или в таком же build-root. Репозитории
должны указывать только на v3.20:

```text
https://dl-cdn.alpinelinux.org/alpine/v3.20/main
https://dl-cdn.alpinelinux.org/alpine/v3.20/community
https://dl-cdn.alpinelinux.org/alpine/v3.20/testing
```

Минимальный набор инструментов и development-пакетов:

```sh
apk add alpine-sdk build-base cmake ninja meson python3 pkgconf \
  qt6-qtbase-dev qt6-qtdeclarative-dev qt6-qtwayland-dev qt6-qtsvg-dev \
  ffmpeg-dev libvpx-dev openh264-dev abseil-cpp-dev \
  glib-dev pango-dev cairo-dev fontconfig-dev hunspell-dev \
  libx11-dev libxcomposite-dev libxdamage-dev libxext-dev \
  libxfixes-dev libxrandr-dev libxtst-dev libxkbcommon-dev libxcb-dev \
  libavif-dev libheif-dev libjxl-dev libdispatch-dev xxhash-dev \
  ada-dev lz4-dev minizip-dev openal-soft-dev opus-dev rnnoise-dev
```

Не устанавливайте в этот build-root пакеты из edge. Наличие одновременно
`ffmpeg-libs`/`tg_owt-dev` из разных веток делает результат непредсказуемым.

## Патчи

Сначала применяются патчи из `patches/`. Для внешних исходников можно указать
пути переменными окружения:

```sh
TDLIB_SOURCE_DIR=/path/to/tdlib \
TLOTTIE_SOURCE_DIR=/path/to/tlottie \
TG_OWT_SOURCE_DIR=/path/to/tg_owt \
  ./packaging/alpine/apply-patches.sh
```

Назначение патчей:

1. `telegram-alpine-qt.patch` добавляет недостающий `QGuiApplication` include.
2. `qt-6.6-accessibility.patch` отключает API accessibility attributes,
   появившийся только в Qt 6.8.
3. `qt-6.6-webkitgtk.patch` корректно преобразует `std::string` в `QByteArray`.
4. `tg-owt-musl.patch` добавляет явный `<cstdint>` для сборки на musl.
5. `tlottie-native.patch` убирает wasm-only зависимости Cargo из native-сборки.

## Порядок сборки библиотек

Пусть `DESTDIR` — staging-root, например `/tmp/telegram-root`. Все install
команды должны использовать `DESTDIR`, чтобы случайно не изменить хостовую
систему.

```sh
cmake -S "$TDLIB_SOURCE_DIR" -B build/tdlib -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build/tdlib --parallel
DESTDIR="$DESTDIR" cmake --install build/tdlib

cargo build --release --manifest-path "$TLOTTIE_SOURCE_DIR/Cargo.toml"
install -Dm644 "$TLOTTIE_SOURCE_DIR/target/release/libtlottie.a" \
  "$DESTDIR/usr/lib/libtlottie.a"
install -Dm644 "$TLOTTIE_SOURCE_DIR/include/tlottie.h" \
  "$DESTDIR/usr/include/tlottie/tlottie.h"

cmake -S "$TG_OWT_SOURCE_DIR" -B build/tg_owt -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
  -DCMAKE_INSTALL_LIBDIR=lib
cmake --build build/tg_owt --parallel
DESTDIR="$DESTDIR" cmake --install build/tg_owt
```

Для tlottie используется тот же Rust, которым собрана проверенная версия
`1.96.1`. Если cargo пытается обратиться к crates.io, заранее перенесите
Cargo cache на build-машину или подготовьте локальный vendor-каталог.

## Сборка Telegram

```sh
cmake -S . -B build/telegram -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DCMAKE_PREFIX_PATH="$DESTDIR/usr" \
  -DDESKTOP_APP_USE_PACKAGED=ON \
  -DDESKTOP_APP_USE_PACKAGED_FONTS=OFF \
  -DDESKTOP_APP_USE_PANGO=ON \
  -DTDESKTOP_API_ID=<your-api-id> \
  -DTDESKTOP_API_HASH=<your-api-hash>
cmake --build build/telegram --parallel
DESTDIR="$DESTDIR" cmake --install build/telegram --config Release
```

API ID и API hash не должны записываться в документацию или коммиты. Их нужно
передавать параметрами своей build-системы.

## Упаковка и запуск

В APK должны попасть `/usr/bin/Telegram` и launchers
`/usr/bin/telegram-desktop`, `/usr/local/bin/telegram-desktop`. Для целевой
системы используй RPATH `/usr/lib/telegram:/usr/lib`; это позволяет положить
совместимый `libxxhash.so.0` рядом с приложением и не зависеть от того,
установлен ли пакет `xxhash` в локальном репозитории.

Перед передачей APK проверь:

```sh
apk verify telegram-desktop-7.2.8-r1.apk
readelf -d "$DESTDIR/usr/bin/Telegram" | grep -E 'NEEDED|RUNPATH'
```

Подпиши APK своим локальным ключом Alpine и передай публичный ключ вместе с
пакетом. На целевой машине установка выглядит так:

```sh
install -m 0644 telegram-desktop-local.rsa.pub /etc/apk/keys/
apk add ./telegram-desktop-7.2.8-r1.apk
telegram-desktop
```

Профиль Telegram хранится в домашнем каталоге и не является частью APK.

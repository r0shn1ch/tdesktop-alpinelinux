# Сборка Telegram Desktop 7.2.8 для Alpine Linux 3.20

Эта ветка проверена на Alpine Linux 3.20.6 x86_64. Цель — собрать обычный
подписанный APK для установки в изолированной системе, где во время
установки нет доступа в интернет.

## Откуда брались падения

Предыдущий APK собирался смесью Alpine edge и Alpine 3.20. В его метаданных
оказались зависимости edge: `libavcodec.so.62`, `libabsl_*.so.2608.0.0`,
`libada.so.3` и другие. В Alpine 3.20 используются другие ABI: FFmpeg 6.1
с `libavcodec.so.60`, Abseil 20230802 и ada 2.x. Одинаковое имя библиотеки
не делает несовместимые ABI безопасными, поэтому приложение падало внутри
FFmpeg/WebRTC.

Для сборки нужно использовать только один набор Alpine 3.20:

- FFmpeg 6.1.1;
- Abseil 20230802.1;
- OpenH264 2.4.1;
- libvpx 1.14.1;
- Qt 6.6.3.

Точные ревизии исходников находятся в `versions.env`.

## Что изменено

В основном дереве Telegram Desktop добавлен явный include для
`QGuiApplication`.

Файлы `lib_ui` и `lib_webview` остаются upstream submodule. После
`git clone --recursive` скрипт `prepare-sources.sh` проверяет их ревизии и
вносит исправления непосредственно в checkout:

- Qt accessibility API обёрнут проверкой Qt 6.8, поскольку в Qt 6.6
  `QAccessibleAttributesInterface` ещё отсутствует;
- WebKitGTK использует явное преобразование `std::string` в `QByteArray`.

Тот же скрипт подготавливает внешние исходники `tlottie` и `tg_owt`:
убирает wasm-only зависимости из native tlottie, пересоздаёт Cargo.lock и
добавляет отсутствующий `<cstdint>` в tg_owt. Все операции идемпотентны.
В репозитории больше нет patch-файлов и запускать `git apply` не нужно.

## Исходники

Клонирование выполняется на машине с сетью. В offline-окружение переносятся
готовые каталоги исходников и локальный Cargo cache.

```sh
git clone --branch alpine-3.20-v7.2.8 --recursive \
  https://github.com/r0shn1ch/tdesktop-alpinelinux.git tdesktop
cd tdesktop

git clone https://github.com/tdlib/td.git ../tdlib
git -C ../tdlib checkout 51743dfd01dff6179e2d8f7095729caa4e2222e9

git clone https://github.com/dkaraush/tlottie.git ../tlottie
git -C ../tlottie checkout 4b940c7942fbde8ee56f10f39a5224a4153bd91e

git clone --recursive https://github.com/desktop-app/tg_owt.git ../tg_owt
git -C ../tg_owt checkout 26068e29bfa8d74a9dc9c8f7f94172fafbc262b8
git -C ../tg_owt submodule update --init --recursive
```

На offline-машине вместо clone используются уже перенесённые каталоги.
Перед сборкой проверьте их ревизии по `versions.env`. Затем выполните:

```sh
./packaging/alpine/prepare-sources.sh ../tlottie ../tg_owt
```

Скрипт завершится с ошибкой, если checkout не соответствует зафиксированной
ревизии. Это защищает от тихой подмены ABI или исходников.

## Build root

Репозитории build root должны указывать только на Alpine v3.20:

```text
/localRepositories/003/main
/localRepositories/003/community
/localRepositories/003/testing
```

Проверьте, что в build root нет пакетов edge:

```sh
apk policy ffmpeg-libs abseil-cpp libvpx openh264
ffmpeg -version
```

Для сборки нужен следующий набор development-пакетов:

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

Не добавляйте edge-репозитории поверх этого набора.

## Сборка зависимостей

Все install-команды направляются в staging-root, например `/tmp/telegram-root`:

```sh
export DESTDIR=/tmp/telegram-root
rm -rf "$DESTDIR"
mkdir -p "$DESTDIR"

cmake -S ../tdlib -B build/tdlib -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build/tdlib --parallel
DESTDIR="$DESTDIR" cmake --install build/tdlib

cargo build --manifest-path ../tlottie/Cargo.toml --release --offline
install -Dm644 ../tlottie/target/release/libtlottie.a \
  "$DESTDIR/usr/lib/libtlottie.a"
install -Dm644 ../tlottie/include/tlottie.h \
  "$DESTDIR/usr/include/tlottie/tlottie.h"

cmake -S ../tg_owt -B build/tg_owt -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DCMAKE_INSTALL_LIBDIR=lib
cmake --build build/tg_owt --parallel
DESTDIR="$DESTDIR" cmake --install build/tg_owt
```

Для native tlottie нужен Rust/Cargo версии 1.96.1. В offline-режиме зависимости
должны находиться в локальном Cargo cache.

## Сборка Telegram Desktop

API ID и API hash возьмите на `https://my.telegram.org`. Не записывайте их
в Git и не добавляйте в README:

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

## Упаковка APK

В APK должны попасть:

- Telegram Desktop и оба launcher-имени: `/usr/bin/Telegram` и
  `/usr/bin/telegram-desktop`;
- библиотеки приложения в `/usr/lib/telegram`;
- bundled `libxxhash.so.0`;
- RPATH или launcher с
  `LD_LIBRARY_PATH=/usr/lib/telegram:/usr/lib`.

Bundled xxHash нужен для устранения ошибки загрузчика
`Error loading shared library libxxhash.so.0` на минимальном Alpine.

Проверьте пакет до переноса на offline-машину:

```sh
apk verify telegram-desktop-7.2.8-r1.apk
readelf -d "$DESTDIR/usr/bin/Telegram" | grep -E 'NEEDED|RPATH|RUNPATH'
```

Установка подписанного пакета:

```sh
install -m 0644 telegram-desktop-local.rsa.pub /etc/apk/keys/
apk add ./telegram-desktop-7.2.8-r1.apk
telegram-desktop
```

Публичный ключ должен соответствовать приватному ключу, которым подписан
APK.

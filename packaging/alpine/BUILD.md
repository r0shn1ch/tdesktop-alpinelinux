# Сборка Telegram Desktop 7.2.8 для Alpine Linux 3.20

Эта инструкция описывает source-fork, проверенный на Alpine 3.20.6
x86_64. Все правки, необходимые для Qt 6.6 и musl, уже закоммичены
в исходниках Telegram и его зависимостей; во время сборки патчи применять
не нужно.

## Почему потребовалась отдельная сборка

Предыдущий APK был собран смесью Alpine edge и Alpine 3.20. В результате
бинарник требовал ABI, которых нет в 3.20: libavcodec.so.62,
libabsl_*.so.2608.0.0, libada.so.3 и другие edge-версии. Наличие файлов
с похожими именами не исправляет несовместимость ABI; именно это приводило к
ошибкам загрузчика и падению в FFmpeg/WebRTC.

Здесь все C/C++ библиотеки берутся из одного набора Alpine 3.20:

- FFmpeg 6.1.1 (libavcodec.so.60, libavfilter.so.9 и т. д.);
- Abseil 20230802.1 (libabsl_*.so.2308.0.0);
- OpenH264 2.4.1 (libopenh264.so.7);
- libvpx 1.14.1;
- Qt 6.6.3 и остальные библиотеки из репозиториев v3.20.

## Исходники

Версии и SHA зафиксированы в versions.env. Основной репозиторий уже
содержит изменённые gitlink-ы для lib_ui и lib_webview; tlottie
и tg_owt также берутся из подготовленных форков.

```sh
git clone --branch alpine-3.20-v7.2.8 --recurse-submodules \
  https://github.com/r0shn1ch/tdesktop-alpinelinux.git tdesktop
git -C tdesktop submodule update --init --recursive

git clone https://github.com/tdlib/td.git tdlib
git -C tdlib checkout 51743dfd01dff6179e2d8f7095729caa4e2222e9

git clone --branch alpine-3.20.6 https://github.com/r0shn1ch/tlottie.git tlottie
git -C tlottie checkout 6f13037238b04a1764b2d76babdebfed433b738f

git clone --branch alpine-3.20.6 --recurse-submodules \
  https://github.com/r0shn1ch/tg_owt.git tg_owt
git -C tg_owt checkout 1d5e9adb5301e50fff6943cf2e9f2b84bb183bac
git -C tg_owt submodule update --init --recursive
```

Затем установи переменные путей:

```sh
export TDESKTOP_SOURCE_DIR="$PWD/tdesktop"
export TDLIB_SOURCE_DIR="$PWD/tdlib"
export TLOTTIE_SOURCE_DIR="$PWD/tlottie"
export TG_OWT_SOURCE_DIR="$PWD/tg_owt"
export DESTDIR="$PWD/telegram-root"
```

На машине без интернета эти исходники, Cargo vendor-каталог и APK-пакеты
Alpine нужно заранее перенести обычным архивом. Целевая система для установки
исходники не нужны.

## Подготовка Alpine build-root

Собирать нужно внутри Alpine 3.20.6 или в таком же build-root. Репозитории
должны указывать только на v3.20:

```
https://dl-cdn.alpinelinux.org/alpine/v3.20/main
https://dl-cdn.alpinelinux.org/alpine/v3.20/community
```

Минимальный набор инструментов и development-пакетов:

```sh
apk add alpine-sdk build-base cmake ninja meson python3 pkgconf gperf boost-dev \
  qt6-qtbase-dev qt6-qtdeclarative-dev qt6-qtwayland-dev qt6-qtsvg-dev \
  ffmpeg-dev libvpx-dev openh264-dev abseil-cpp-dev zlib-dev \
  glib-dev gobject-introspection-dev pango-dev cairo-dev fontconfig-dev hunspell-dev pipewire-dev \
  libx11-dev libxcomposite-dev libxdamage-dev libxext-dev \
  libxfixes-dev libxrandr-dev libxtst-dev libxkbcommon-dev libxcb-dev \
  libavif-dev libheif-dev libjxl-dev libdispatch-dev xxhash-dev \
  ada-dev lz4-dev minizip-dev openal-soft-dev opus-dev rnnoise-dev
```

Не устанавливайте в этот build-root пакеты из edge. Наличие одновременно
ffmpeg-libs/tg_owt-dev из разных веток делает результат непредсказуемым.
Для native tlottie нужен Rust 1.96.1; его toolchain и Cargo cache должны быть
подготовлены заранее, если сборка выполняется без интернета.

## Порядок сборки библиотек

Все install-команды используют DESTDIR, чтобы не менять хостовую систему.

```sh
cmake -S "$TDLIB_SOURCE_DIR" -B build/tdlib -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build/tdlib --parallel
DESTDIR="$DESTDIR" cmake --install build/tdlib

# Telegram's Linux build consumes tde2e as a separate CMake package.
cmake -S "$TDLIB_SOURCE_DIR" -B build/tdlib_e2e -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build/tdlib_e2e --parallel
DESTDIR="$DESTDIR" cmake --install build/tdlib_e2e

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

## Сборка Telegram

```sh
cmake -S "$TDESKTOP_SOURCE_DIR" -B build/telegram -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DCMAKE_PREFIX_PATH="$DESTDIR/usr" \
  -DDESKTOP_APP_USE_PACKAGED=ON \
  -DDESKTOP_APP_USE_PACKAGED_FONTS=OFF \
  -DDESKTOP_APP_USE_PANGO=ON \
  -DTDESKTOP_API_ID="$TDESKTOP_API_ID" \
  -DTDESKTOP_API_HASH="$TDESKTOP_API_HASH"
cmake --build build/telegram --parallel
DESTDIR="$DESTDIR" cmake --install build/telegram --config Release
```

API ID и API hash передавай переменными окружения своей build-системы; в
репозиторий их записывать нельзя.

## Проверка и упаковка

Команды выше собирают бинарник и staging-root в `$DESTDIR`; сами по себе они
не создают APK. Для APK нужен отдельный `APKBUILD` и запуск `abuild`.

Проверь зависимости собранного бинарника:

```sh
readelf -d "$DESTDIR/usr/bin/Telegram" | grep -E 'NEEDED|RUNPATH'
```

После упаковки проверь APK и установи его своим локальным ключом Alpine:

```sh
apk verify telegram-desktop-7.2.8-r1.apk
install -m 0644 telegram-desktop-local.rsa.pub /etc/apk/keys/
apk add ./telegram-desktop-7.2.8-r1.apk
Telegram
```

В установленной системе запускается `/usr/bin/Telegram` (именно это имя
использует desktop-файл). Профиль Telegram хранится в домашнем каталоге и не
является частью APK.

#!/bin/sh
set -eu

. /usr/local/share/tdesktop/versions.env

: "${TDESKTOP_API_ID:?TDESKTOP_API_ID is required}"
: "${TDESKTOP_API_HASH:?TDESKTOP_API_HASH is required}"

BUILD_ROOT=/build
SOURCE_ROOT="${BUILD_ROOT}/sources"
DESTDIR="${BUILD_ROOT}/telegram-root"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 2)}"
export HOME="${BUILD_ROOT}/home"
export CARGO_HOME="${BUILD_ROOT}/cargo"
export RUSTUP_HOME="${RUSTUP_HOME:-/opt/rustup}"
export PATH="/opt/cargo/bin:${PATH}"
export LDFLAGS="${LDFLAGS:--lmount -lblkid}"

mkdir -p "${SOURCE_ROOT}" "${DESTDIR}" "${OUTPUT_DIR}" "${HOME}" "${CARGO_HOME}"

clone_exact() {
    url=$1
    commit=$2
    destination=$3

    echo "==> cloning ${url} at ${commit}"
    git clone --filter=blob:none --no-checkout --no-tags "${url}" "${destination}"
    git -C "${destination}" fetch --depth 1 origin "${commit}"
    git -C "${destination}" checkout --detach "${commit}"

    actual=$(git -C "${destination}" rev-parse HEAD)
    test "${actual}" = "${commit}" || {
        echo "ERROR: expected ${commit}, got ${actual}" >&2
        exit 1
    }
}

TDESKTOP_SOURCE_DIR="${SOURCE_ROOT}/tdesktop"
TDLIB_SOURCE_DIR="${SOURCE_ROOT}/tdlib"
TLOTTIE_SOURCE_DIR="${SOURCE_ROOT}/tlottie"
TG_OWT_SOURCE_DIR="${SOURCE_ROOT}/tg_owt"

clone_exact "${TDESKTOP_REPOSITORY}" "${TDESKTOP_COMMIT}" "${TDESKTOP_SOURCE_DIR}"
git -C "${TDESKTOP_SOURCE_DIR}" submodule sync --recursive
git -C "${TDESKTOP_SOURCE_DIR}" submodule update --init --recursive

clone_exact "${TDLIB_REPOSITORY}" "${TDLIB_COMMIT}" "${TDLIB_SOURCE_DIR}"
clone_exact "${TLOTTIE_REPOSITORY}" "${TLOTTIE_COMMIT}" "${TLOTTIE_SOURCE_DIR}"
clone_exact "${TG_OWT_REPOSITORY}" "${TG_OWT_COMMIT}" "${TG_OWT_SOURCE_DIR}"
git -C "${TG_OWT_SOURCE_DIR}" submodule sync --recursive
git -C "${TG_OWT_SOURCE_DIR}" submodule update --init --recursive

mkdir -p "${BUILD_ROOT}/build"

echo "==> building TDLib"
cmake -S "${TDLIB_SOURCE_DIR}" -B "${BUILD_ROOT}/build/tdlib" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr
cmake --build "${BUILD_ROOT}/build/tdlib" --parallel "${JOBS}"
DESTDIR="${DESTDIR}" cmake --install "${BUILD_ROOT}/build/tdlib"

echo "==> building TDLib E2E"
cmake -S "${TDLIB_SOURCE_DIR}" -B "${BUILD_ROOT}/build/tdlib_e2e" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DTD_E2E_ONLY=ON \
    -DTD_INSTALL_STATIC_LIBRARIES=ON
cmake --build "${BUILD_ROOT}/build/tdlib_e2e" --parallel "${JOBS}"
DESTDIR="${DESTDIR}" cmake --install "${BUILD_ROOT}/build/tdlib_e2e"

echo "==> building tlottie"
cargo build --release --features c-api \
    --manifest-path "${TLOTTIE_SOURCE_DIR}/Cargo.toml"
install -Dm644 "${TLOTTIE_SOURCE_DIR}/target/release/libtlottie.a" \
    "${DESTDIR}/usr/lib/libtlottie.a"
install -Dm644 "${TLOTTIE_SOURCE_DIR}/include/tlottie.h" \
    "${DESTDIR}/usr/include/tlottie/tlottie.h"

echo "==> building tg_owt"
cmake -S "${TG_OWT_SOURCE_DIR}" -B "${BUILD_ROOT}/build/tg_owt" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR=lib
cmake --build "${BUILD_ROOT}/build/tg_owt" --parallel "${JOBS}"
DESTDIR="${DESTDIR}" cmake --install "${BUILD_ROOT}/build/tg_owt"

echo "==> building Telegram Desktop"
cmake -S "${TDESKTOP_SOURCE_DIR}" -B "${BUILD_ROOT}/build/telegram" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_PREFIX_PATH="${DESTDIR}/usr" \
    -DDESKTOP_APP_USE_PACKAGED=ON \
    -DDESKTOP_APP_USE_PACKAGED_FONTS=OFF \
    -DDESKTOP_APP_USE_PANGO=ON \
    -DTDESKTOP_API_ID="${TDESKTOP_API_ID}" \
    -DTDESKTOP_API_HASH="${TDESKTOP_API_HASH}"
cmake --build "${BUILD_ROOT}/build/telegram" --parallel "${JOBS}"
DESTDIR="${DESTDIR}" cmake --install "${BUILD_ROOT}/build/telegram" --config Release

test -x "${DESTDIR}/usr/bin/Telegram"

echo "==> exporting build to ${OUTPUT_DIR}"
install -Dm755 "${DESTDIR}/usr/bin/Telegram" "${OUTPUT_DIR}/Telegram"
mkdir -p "${OUTPUT_DIR}/usr/share"
if [ -d "${DESTDIR}/usr/share" ]; then
    cp -a "${DESTDIR}/usr/share/." "${OUTPUT_DIR}/usr/share/"
fi

cat > "${OUTPUT_DIR}/build-info.txt" <<EOF
target=${ALPINE_RELEASE}-${ALPINE_ARCH}
tdesktop_commit=${TDESKTOP_COMMIT}
lib_ui_commit=${LIB_UI_COMMIT}
lib_webview_commit=${LIB_WEBVIEW_COMMIT}
tdlib_commit=${TDLIB_COMMIT}
tlottie_commit=${TLOTTIE_COMMIT}
tg_owt_commit=${TG_OWT_COMMIT}
rust_version=${RUST_VERSION}
EOF

if [ "${EXPORT_STAGING:-0}" = 1 ]; then
    echo "==> exporting staging archive"
    tar -C "${DESTDIR}" -czf "${OUTPUT_DIR}/telegram-root.tar.gz" .
fi

echo "DONE: ${OUTPUT_DIR}/Telegram"


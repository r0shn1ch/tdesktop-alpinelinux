# syntax=docker/dockerfile:1.7

FROM alpine:3.20.6

ARG RUST_VERSION=1.96.1

ENV RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    PATH=/opt/cargo/bin:$PATH \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apk add --no-cache \
        alpine-sdk \
        bash \
        ca-certificates \
        cmake \
        curl \
        ffmpeg-dev \
        gperf \
        git \
        libavif-dev \
        libdispatch-dev \
        libheif-dev \
        libjxl-dev \
        libvpx-dev \
        linux-headers \
        lz4-dev \
        meson \
        minizip-dev \
        ninja \
        openal-soft-dev \
        openh264-dev \
        openssl-dev \
        opus-dev \
        pipewire-dev \
        pkgconf \
        python3 \
        qt6-qtbase-dev \
        qt6-qtdeclarative-dev \
        qt6-qtwayland-dev \
        qt6-qtsvg-dev \
        rnnoise-dev \
        rust \
        boost-dev \
        abseil-cpp-dev \
        ada-dev \
        cairo-dev \
        eudev-dev \
        fontconfig-dev \
        glib-dev \
        gobject-introspection-dev \
        hunspell-dev \
        pango-dev \
        util-linux-dev \
        xxhash-dev \
        zlib-dev \
        libx11-dev \
        libxcomposite-dev \
        libxdamage-dev \
        libxext-dev \
        libxfixes-dev \
        libxkbcommon-dev \
        libxrandr-dev \
        libxtst-dev \
        libxcb-dev

RUN curl --fail --location --show-error --silent \
        https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-musl/rustup-init \
        --output /tmp/rustup-init \
    && chmod 0755 /tmp/rustup-init \
    && /tmp/rustup-init -y --profile minimal \
        --default-toolchain "${RUST_VERSION}" \
        --target x86_64-unknown-linux-musl \
    && rustup component add rustfmt \
    && rm -f /tmp/rustup-init

RUN mkdir -p /build /output /usr/local/share/tdesktop \
    && chmod 1777 /build /output

COPY versions.env /usr/local/share/tdesktop/versions.env
COPY container-build.sh /usr/local/bin/tdesktop-alpine-build

RUN chmod 0755 /usr/local/bin/tdesktop-alpine-build

WORKDIR /build
ENTRYPOINT ["/usr/local/bin/tdesktop-alpine-build"]


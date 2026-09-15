#!/bin/sh
set -eu

base=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
patches="$base/packaging/alpine/patches"

tdlib_source=${TDLIB_SOURCE_DIR:-"$base/../tdlib"}
tlottie_source=${TLOTTIE_SOURCE_DIR:-"$base/../tlottie"}
tg_owt_source=${TG_OWT_SOURCE_DIR:-"$base/../tg_owt"}

apply_patch() {
	repo=$1
	patch_file=$2

	if git -C "$repo" apply --check "$patch_file"; then
		git -C "$repo" apply "$patch_file"
		return
	fi
	if git -C "$repo" apply --reverse --check "$patch_file"; then
		printf '%s\n' "already applied: $patch_file"
		return
	fi
	printf '%s\n' "cannot apply: $patch_file" >&2
	exit 1
}

apply_patch "$base" "$patches/telegram-alpine-qt.patch"
apply_patch "$base/Telegram/lib_ui" "$patches/qt-6.6-accessibility.patch"
apply_patch "$base/Telegram/lib_webview" "$patches/qt-6.6-webkitgtk.patch"
apply_patch "$tlottie_source" "$patches/tlottie-native.patch"
apply_patch "$tg_owt_source" "$patches/tg-owt-musl.patch"

printf '%s\n' 'Alpine patches applied.'

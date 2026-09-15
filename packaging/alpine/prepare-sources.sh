#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
. "$root/packaging/alpine/versions.env"

ui_source=${LIB_UI_SOURCE_DIR:-"$root/Telegram/lib_ui"}
webview_source=${LIB_WEBVIEW_SOURCE_DIR:-"$root/Telegram/lib_webview"}
tlottie_source=${1:-${TLOTTIE_SOURCE_DIR:-"$root/../tlottie"}}
tg_owt_source=${2:-${TG_OWT_SOURCE_DIR:-"$root/../tg_owt"}}

require_revision() {
	repository=$1
	expected=$2
	actual=$(git -C "$repository" rev-parse HEAD)
	if [ "$actual" != "$expected" ]; then
		printf '%s\n' "unexpected revision in $repository: $actual (expected $expected)" >&2
		exit 1
	fi
}

require_revision "$ui_source" "09f35036fd4f2d2f67422d294740f9a92c38827f"
require_revision "$webview_source" "d1e3c3d705806324bc68da66765860ff7f0b3bd6"
require_revision "$tlottie_source" "$TLOTTIE_COMMIT"
require_revision "$tg_owt_source" "$TG_OWT_COMMIT"

ui_header="$ui_source/ui/accessible/ui_accessible_widget.h"
ui_source_file="$ui_source/ui/accessible/ui_accessible_widget.cpp"
if ! grep -Fq '#if QT_VERSION >= QT_VERSION_CHECK(6, 8, 0)' "$ui_header"; then
	sed -i '/^[[:space:]]*, public QAccessibleAttributesInterface {/c\
#if QT_VERSION >= QT_VERSION_CHECK(6, 8, 0)\
	, public QAccessibleAttributesInterface\
#endif\
{' "$ui_header"
	sed -i '/QList<QAccessible::Attribute> attributeKeys() const override;/i\
#if QT_VERSION >= QT_VERSION_CHECK(6, 8, 0)' "$ui_header"
	sed -i '/QVariant attributeValue(QAccessible::Attribute key) const override;/a\
#endif' "$ui_header"
fi
if ! grep -Fq '#if QT_VERSION >= QT_VERSION_CHECK(6, 8, 0)' "$ui_source_file"; then
	sed -i '/^[[:space:]]*if (type == QAccessible::AttributesInterface$/i\
#if QT_VERSION >= QT_VERSION_CHECK(6, 8, 0)' "$ui_source_file"
	sed -i '/return static_cast<QAccessibleAttributesInterface/ a\
#endif' "$ui_source_file"
	sed -i '/^QList<QAccessible::Attribute> Widget::attributeKeys()/i\
#if QT_VERSION >= QT_VERSION_CHECK(6, 8, 0)' "$ui_source_file"
	sed -i '/^} \\/\\/ namespace Ui::Accessible$/i\
#endif' "$ui_source_file"
fi

webview_file="$webview_source/webview/platform/linux/webview_linux_webkitgtk.cpp"
sed -i 's/const auto mime = QByteArray(stream->mime());/const auto mime = QByteArray::fromStdString(stream->mime());/' "$webview_file"

tlottie_toml="$tlottie_source/Cargo.toml"
sed -i 's/^no-std = .*/no-std = []/' "$tlottie_toml"
sed -i '/^hashbrown = /d' "$tlottie_toml"
sed -i '/target_arch = "wasm32"/,+2d' "$tlottie_toml"
(cd "$tlottie_source" && cargo generate-lockfile --offline)

reorder_optimizer="$tg_owt_source/src/modules/audio_coding/neteq/reorder_optimizer.cc"
if ! grep -Fxq '#include <cstdint>' "$reorder_optimizer"; then
	sed -i '/^#include <algorithm>$/a\
#include <cstdint>' "$reorder_optimizer"
fi

printf '%s\n' 'Alpine source fixes applied.'

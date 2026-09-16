#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
ENGINE=${CONTAINER_ENGINE:-docker}
IMAGE=${TDESKTOP_DOCKER_IMAGE:-tdesktop-alpine:3.20.6-v7.2.8}
PLATFORM=${DOCKER_PLATFORM:-linux/amd64}
OUTPUT_DIR=${OUTPUT_DIR:-${REPO_ROOT}/out/alpine}

: "${TDESKTOP_API_ID:?Set TDESKTOP_API_ID before running this script}"
: "${TDESKTOP_API_HASH:?Set TDESKTOP_API_HASH before running this script}"

command -v "${ENGINE}" >/dev/null 2>&1 || {
    echo "ERROR: container engine '${ENGINE}' was not found" >&2
    echo "Install Docker Engine (or set CONTAINER_ENGINE=podman)." >&2
    exit 1
}

mkdir -p "${OUTPUT_DIR}"
OUTPUT_DIR=$(CDPATH= cd -- "${OUTPUT_DIR}" && pwd)

echo "==> building image ${IMAGE}"
"${ENGINE}" build \
    --pull \
    --platform "${PLATFORM}" \
    --build-arg "RUST_VERSION=1.96.1" \
    --tag "${IMAGE}" \
    --file "${SCRIPT_DIR}/Dockerfile" \
    "${SCRIPT_DIR}"

echo "==> running build container"
"${ENGINE}" run --rm --init \
    --platform "${PLATFORM}" \
    --user "$(id -u):$(id -g)" \
    --mount "type=bind,source=${OUTPUT_DIR},target=/output" \
    --env "TDESKTOP_API_ID=${TDESKTOP_API_ID}" \
    --env "TDESKTOP_API_HASH=${TDESKTOP_API_HASH}" \
    --env "JOBS=${JOBS:-}" \
    --env "EXPORT_STAGING=${EXPORT_STAGING:-0}" \
    "${IMAGE}"

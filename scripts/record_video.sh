#!/bin/bash

# ======================================
# Record webcam video into input_videos
# ======================================

set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

CONFIG_FILE="$BASE_DIR/config/settings.conf"
VENV_PYTHON="$BASE_DIR/.venv/bin/python"
RECORD_PY="$BASE_DIR/python/record_video.py"
INPUT_DIR="$BASE_DIR/input_videos"

mkdir -p "$INPUT_DIR"

if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

PREVIEW_MIRROR_ENABLED="${PREVIEW_MIRROR_ENABLED:-true}"
VIDEO_MIRROR_ENABLED="${VIDEO_MIRROR_ENABLED:-false}"

is_true() {
    case "${1,,}" in
        1|true|yes|y|on) return 0 ;;
        *) return 1 ;;
    esac
}

if [ ! -f "$VENV_PYTHON" ]; then
    echo "[ERROR] 가상환경 Python이 없습니다: $VENV_PYTHON"
    exit 1
fi

if [ ! -f "$RECORD_PY" ]; then
    echo "[ERROR] 녹화 Python 파일이 없습니다: $RECORD_PY"
    exit 1
fi

read -p "녹화 파일 이름을 입력하세요. 예: hello_test : " VIDEO_NAME
read -p "녹화 시간(초)을 입력하세요. 예: 5 : " DURATION

SAFE_VIDEO_NAME=$(echo "$VIDEO_NAME" | tr ' /' '__')
DATE_TAG=$(date +"%Y%m%d_%H%M%S")

OUTPUT_VIDEO="$INPUT_DIR/${SAFE_VIDEO_NAME}_${DATE_TAG}.mp4"

echo "[INFO] 저장 경로: $OUTPUT_VIDEO"

record_args=(
    --output "$OUTPUT_VIDEO" \
    --camera 0 \
    --duration "$DURATION"
)
if is_true "$PREVIEW_MIRROR_ENABLED"; then
    record_args+=(--mirror-preview)
else
    record_args+=(--no-mirror-preview)
fi
if is_true "$VIDEO_MIRROR_ENABLED"; then
    record_args+=(--mirror-video)
fi

"$VENV_PYTHON" "$RECORD_PY" "${record_args[@]}"

echo "[DONE] input_videos 폴더에 mp4 영상이 생성되었습니다."
ls -lh "$OUTPUT_VIDEO"

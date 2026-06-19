#!/bin/bash

# ======================================
# Record webcam video into input_videos
# ======================================

set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

VENV_PYTHON="$BASE_DIR/.venv/bin/python"
RECORD_PY="$BASE_DIR/python/record_video.py"
INPUT_DIR="$BASE_DIR/input_videos"

mkdir -p "$INPUT_DIR"

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

"$VENV_PYTHON" "$RECORD_PY" \
    --output "$OUTPUT_VIDEO" \
    --camera 0 \
    --duration "$DURATION"

echo "[DONE] input_videos 폴더에 mp4 영상이 생성되었습니다."
ls -lh "$OUTPUT_VIDEO"

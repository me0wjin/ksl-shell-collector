#!/bin/bash

# ======================================
# KSL Shell-based Data Collection System
# Main Pipeline Script
# ======================================

set -euo pipefail

# 현재 프로젝트의 최상위 폴더 경로 계산
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# 주요 파일 및 폴더 경로 설정
INPUT_DIR="$BASE_DIR/input_videos"

VENV_PYTHON="$BASE_DIR/.venv/bin/python"
PYTHON_FILE="$BASE_DIR/python/extract_landmarks_tsv.py"

SPLIT_SCRIPT="$BASE_DIR/scripts/split_by_part.sh"
VALIDATE_SCRIPT="$BASE_DIR/scripts/validate_result.sh"
REPORT_SCRIPT="$BASE_DIR/scripts/make_report.sh"

ALL_DIR="$BASE_DIR/data/landmarks/all"
PART_DIR="$BASE_DIR/data/landmarks/parts"
REPORT_DIR="$BASE_DIR/data/reports"
LOG_DIR="$BASE_DIR/logs"

# 필요한 결과 폴더 생성
mkdir -p "$INPUT_DIR"
mkdir -p "$ALL_DIR"
mkdir -p "$PART_DIR"
mkdir -p "$REPORT_DIR"
mkdir -p "$LOG_DIR"

echo "======================================"
echo " KSL Shell-based Data Collection System"
echo "======================================"
echo ""

# 사용자 입력 받기
read -p "수어 단어를 입력하세요: " WORD
read -p "촬영자 ID를 입력하세요: " USER_ID

# 파일명에 위험할 수 있는 공백과 슬래시 처리
SAFE_WORD=$(echo "$WORD" | tr ' /' '__')
SAFE_USER_ID=$(echo "$USER_ID" | tr ' /' '__')

# 세션 ID 생성
DATE_TAG=$(date +"%Y%m%d_%H%M%S")
SESSION_ID="${SAFE_WORD}_${SAFE_USER_ID}_${DATE_TAG}"

# 로그 파일 경로
LOG_FILE="$LOG_DIR/${SESSION_ID}.log"

echo ""
echo "[INFO] Session ID: $SESSION_ID" | tee -a "$LOG_FILE"
echo "[INFO] Project Directory: $BASE_DIR" | tee -a "$LOG_FILE"
echo "[INFO] Input Video Directory: $INPUT_DIR" | tee -a "$LOG_FILE"
echo "[INFO] Virtualenv Python: $VENV_PYTHON" | tee -a "$LOG_FILE"
echo "[INFO] Python Extractor: $PYTHON_FILE" | tee -a "$LOG_FILE"
echo "[INFO] Split Script: $SPLIT_SCRIPT" | tee -a "$LOG_FILE"
echo "[INFO] Validate Script: $VALIDATE_SCRIPT" | tee -a "$LOG_FILE"
echo "[INFO] Report Script: $REPORT_SCRIPT" | tee -a "$LOG_FILE"
echo ""

# 가상환경 Python 확인
if [ ! -f "$VENV_PYTHON" ]; then
    echo "[ERROR] 가상환경 Python이 없습니다: $VENV_PYTHON" | tee -a "$LOG_FILE"
    echo "[GUIDE] 아래 명령어로 가상환경을 먼저 만들어주세요." | tee -a "$LOG_FILE"
    echo "        python3 -m venv .venv" | tee -a "$LOG_FILE"
    echo "        source .venv/bin/activate" | tee -a "$LOG_FILE"
    echo "        python -m pip install --upgrade pip" | tee -a "$LOG_FILE"
    echo "        python -m pip install opencv-python mediapipe" | tee -a "$LOG_FILE"
    exit 1
fi

# 필수 파일 존재 확인
if [ ! -f "$PYTHON_FILE" ]; then
    echo "[ERROR] Python 추출 파일이 없습니다: $PYTHON_FILE" | tee -a "$LOG_FILE"
    exit 1
fi

if [ ! -f "$SPLIT_SCRIPT" ]; then
    echo "[ERROR] 부위별 분리 스크립트가 없습니다: $SPLIT_SCRIPT" | tee -a "$LOG_FILE"
    exit 1
fi

if [ ! -f "$VALIDATE_SCRIPT" ]; then
    echo "[ERROR] 검증 스크립트가 없습니다: $VALIDATE_SCRIPT" | tee -a "$LOG_FILE"
    exit 1
fi

if [ ! -f "$REPORT_SCRIPT" ]; then
    echo "[ERROR] 리포트 생성 스크립트가 없습니다: $REPORT_SCRIPT" | tee -a "$LOG_FILE"
    exit 1
fi

# input_videos 폴더에 mp4 파일이 있는지 확인
shopt -s nullglob
VIDEOS=("$INPUT_DIR"/*.mp4)

if [ ${#VIDEOS[@]} -eq 0 ]; then
    echo "[ERROR] input_videos 폴더에 mp4 파일이 없습니다." | tee -a "$LOG_FILE"
    echo "[GUIDE] input_videos 폴더에 실제 mp4 영상을 넣어주세요." | tee -a "$LOG_FILE"
    exit 1
fi

echo "[INFO] 발견된 mp4 파일 수: ${#VIDEOS[@]}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# 영상별 처리 반복
for VIDEO in "${VIDEOS[@]}"
do
    FILE_NAME=$(basename "$VIDEO" .mp4)

    OUTPUT_TSV="$ALL_DIR/${SESSION_ID}_${FILE_NAME}_all.tsv"
    OUTPUT_PART_DIR="$PART_DIR/${SESSION_ID}_${FILE_NAME}"

    mkdir -p "$OUTPUT_PART_DIR"

    echo "--------------------------------------" | tee -a "$LOG_FILE"
    echo "[INFO] 처리 대상 영상: $(basename "$VIDEO")" | tee -a "$LOG_FILE"
    echo "[INFO] 출력 TSV: $OUTPUT_TSV" | tee -a "$LOG_FILE"
    echo "[INFO] 부위별 출력 폴더: $OUTPUT_PART_DIR" | tee -a "$LOG_FILE"

    # 1. Python MediaPipe 추출 파일 실행
    "$VENV_PYTHON" "$PYTHON_FILE" "$VIDEO" "$OUTPUT_TSV" | tee -a "$LOG_FILE"

    # 2. TSV 생성 여부 확인
    if [ -f "$OUTPUT_TSV" ]; then
        LINE_COUNT=$(wc -l < "$OUTPUT_TSV")
        echo "[SUCCESS] TSV 생성 완료: $OUTPUT_TSV" | tee -a "$LOG_FILE"
        echo "[INFO] TSV 라인 수: $LINE_COUNT" | tee -a "$LOG_FILE"
    else
        echo "[ERROR] TSV 생성 실패: $OUTPUT_TSV" | tee -a "$LOG_FILE"
        exit 1
    fi

    # 3. 부위별 TSV 분리
    bash "$SPLIT_SCRIPT" "$OUTPUT_TSV" "$OUTPUT_PART_DIR" | tee -a "$LOG_FILE"

    # 4. 결과 검증
    bash "$VALIDATE_SCRIPT" "$OUTPUT_TSV" "$OUTPUT_PART_DIR" | tee -a "$LOG_FILE"

    # 5. 리포트 생성
    bash "$REPORT_SCRIPT" "$SESSION_ID" "$VIDEO" "$OUTPUT_TSV" "$OUTPUT_PART_DIR" "$REPORT_DIR" | tee -a "$LOG_FILE"

    # 6. 부위별 파일 목록 출력
    echo "[INFO] 부위별 파일 목록:" | tee -a "$LOG_FILE"
    ls "$OUTPUT_PART_DIR" | tee -a "$LOG_FILE"

done

echo "" | tee -a "$LOG_FILE"
echo "======================================" | tee -a "$LOG_FILE"
echo "[DONE] TSV 생성, 부위별 분리, 결과 검증, 리포트 생성 자동화 완료" | tee -a "$LOG_FILE"
echo "[LOG] $LOG_FILE" | tee -a "$LOG_FILE"
echo "======================================" | tee -a "$LOG_FILE"

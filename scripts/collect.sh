#!/bin/bash

# ======================================
# User-friendly KSL Data Collection Script
# Dataset structure:
# data/dataset/<sign_word>/trial_<number>_<user>_<timestamp>/
# ======================================

set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="$BASE_DIR/config/settings.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "[ERROR] 설정 파일이 없습니다: $CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

VENV_PYTHON="$BASE_DIR/.venv/bin/python"
RECORD_PY="$BASE_DIR/python/record_video.py"
RUN_PIPELINE="$BASE_DIR/scripts/run_pipeline.sh"
CHECK_RESOURCES="$BASE_DIR/scripts/check_resources.sh"
CHECK_QUOTA="$BASE_DIR/scripts/check_quota.sh"

INPUT_DIR="$BASE_DIR/input_videos"
ARCHIVE_DIR="$INPUT_DIR/archive"
DATASET_ROOT="$BASE_DIR/$SESSION_ROOT"

mkdir -p "$INPUT_DIR"
mkdir -p "$ARCHIVE_DIR"
mkdir -p "$DATASET_ROOT"

clear
echo "======================================"
echo " KSL Data Collector"
echo "======================================"
echo ""
echo "수어 종류와 촬영자 ID만 입력하면,"
echo "영상 녹화부터 랜드마크 추출, 부위별 분리,"
echo "검증 및 리포트 생성까지 자동으로 수행합니다."
echo ""

read -p "수어 종류를 입력하세요. 예: 1, hello : " WORD
read -p "촬영자 ID를 입력하세요. 예: user01 : " USER_ID

SAFE_WORD=$(echo "$WORD" | tr ' /' '__')
SAFE_USER_ID=$(echo "$USER_ID" | tr ' /' '__')
DATE_TAG=$(date +"%Y%m%d_%H%M%S")

WORD_DIR="$DATASET_ROOT/$SAFE_WORD"
mkdir -p "$WORD_DIR"

CURRENT_COUNT=$(find "$WORD_DIR" -mindepth 1 -maxdepth 1 -type d -name "trial_*" | wc -l)
NEXT_TRIAL=$((CURRENT_COUNT + 1))
TRIAL_NO=$(printf "%03d" "$NEXT_TRIAL")

TRIAL_NAME="trial_${TRIAL_NO}_${SAFE_USER_ID}_${DATE_TAG}"
TRIAL_DIR="$WORD_DIR/$TRIAL_NAME"

RAW_DIR="$TRIAL_DIR/raw"
FULL_DIR="$TRIAL_DIR/landmarks/full"
POSE_DIR="$TRIAL_DIR/landmarks/parts/pose"
FACE_DIR="$TRIAL_DIR/landmarks/parts/face"
LEFT_DIR="$TRIAL_DIR/landmarks/parts/left_hand"
RIGHT_DIR="$TRIAL_DIR/landmarks/parts/right_hand"
REPORT_DIR="$TRIAL_DIR/report"
LOG_DIR="$TRIAL_DIR/logs"

mkdir -p "$RAW_DIR" "$FULL_DIR" "$POSE_DIR" "$FACE_DIR" "$LEFT_DIR" "$RIGHT_DIR" "$REPORT_DIR" "$LOG_DIR"

VIDEO_PATH="$INPUT_DIR/${SAFE_WORD}_${SAFE_USER_ID}_${DATE_TAG}.mp4"
COLLECT_LOG="$LOG_DIR/collect_detail.log"

echo ""
echo "======================================"
echo " 수집 세션 정보"
echo "======================================"
echo "수어 종류 : $WORD"
echo "촬영자 ID : $USER_ID"
echo "촬영 회차 : trial_$TRIAL_NO"
echo "녹화 시간 : ${DEFAULT_RECORD_SECONDS}초"
echo "저장 위치 : $TRIAL_DIR"
echo "======================================"
echo ""

echo "[1/6] 시스템 자원 점검"
bash "$CHECK_RESOURCES"
echo ""

echo "[2/6] 단어별 수집 상한선 점검"
bash "$CHECK_QUOTA" "$WORD"
echo ""

echo "[3/6] 기존 입력 영상 정리"
shopt -s nullglob
for OLD_VIDEO in "$INPUT_DIR"/*.mp4
do
    mv "$OLD_VIDEO" "$ARCHIVE_DIR/"
done
echo "[OK] input_videos 폴더를 새 수집 영상 기준으로 정리했습니다."
echo ""

echo "[4/6] 웹캠 영상 녹화"
echo "[GUIDE] 얼굴, 상체, 양손이 화면 안에 잘 보이도록 촬영하세요."

"$VENV_PYTHON" "$RECORD_PY" \
    --output "$VIDEO_PATH" \
    --camera 0 \
    --duration "$DEFAULT_RECORD_SECONDS" \
    --countdown "$RECORD_COUNTDOWN_SECONDS" \
    --warmup "$CAMERA_WARMUP_SECONDS" | tee "$COLLECT_LOG"

echo ""

echo "[5/6] 랜드마크 추출 및 부위별 데이터 생성"
printf "%s\n%s\n" "$WORD" "$USER_ID" | bash "$RUN_PIPELINE" >> "$COLLECT_LOG" 2>&1
echo "[OK] MediaPipe 추출, 부위별 분리, 검증, 리포트 생성 완료"
echo ""

echo "[6/6] 데이터셋 구조로 결과 정리"

LATEST_TSV=$(ls -t "$BASE_DIR"/data/landmarks/all/*.tsv | head -n 1)
LATEST_PART_DIR=$(ls -td "$BASE_DIR"/data/landmarks/parts/*/ | head -n 1)
LATEST_REPORT=$(ls -t "$BASE_DIR"/data/reports/*.txt | head -n 1)
LATEST_LOG=$(ls -t "$BASE_DIR"/logs/*.log | head -n 1)

cp "$VIDEO_PATH" "$RAW_DIR/video.mp4"
cp "$LATEST_TSV" "$FULL_DIR/all_landmarks.tsv"

cp "$LATEST_PART_DIR"/pose.tsv "$POSE_DIR/pose.tsv"
cp "$LATEST_PART_DIR"/face.tsv "$FACE_DIR/face.tsv"
cp "$LATEST_PART_DIR"/left_hand.tsv "$LEFT_DIR/left_hand.tsv"
cp "$LATEST_PART_DIR"/right_hand.tsv "$RIGHT_DIR/right_hand.tsv"

cp "$LATEST_REPORT" "$REPORT_DIR/report.txt"
cp "$LATEST_LOG" "$LOG_DIR/pipeline.log"

cat > "$TRIAL_DIR/metadata.txt" <<META
sign_word=$WORD
user_id=$USER_ID
trial_number=$TRIAL_NO
created_at=$DATE_TAG
record_seconds=$DEFAULT_RECORD_SECONDS
countdown_seconds=$RECORD_COUNTDOWN_SECONDS
camera_warmup_seconds=$CAMERA_WARMUP_SECONDS
META

echo "[OK] 결과를 수어 종류/촬영 회차 기준으로 정리했습니다."
echo ""

POSE_LINES=$(wc -l < "$POSE_DIR/pose.tsv")
FACE_LINES=$(wc -l < "$FACE_DIR/face.tsv")
LEFT_LINES=$(wc -l < "$LEFT_DIR/left_hand.tsv")
RIGHT_LINES=$(wc -l < "$RIGHT_DIR/right_hand.tsv")
TOTAL_LINES=$(wc -l < "$FULL_DIR/all_landmarks.tsv")
FRAME_COUNT=$(awk -F'\t' 'NR > 1 { print $2 }' "$FULL_DIR/all_landmarks.tsv" | sort -n | uniq | wc -l)

echo "======================================"
echo " 수집 결과 요약"
echo "======================================"
echo "수어 종류        : $WORD"
echo "촬영자 ID        : $USER_ID"
echo "촬영 회차        : trial_$TRIAL_NO"
echo "처리 프레임 수   : $FRAME_COUNT"
echo "전체 TSV 라인 수 : $TOTAL_LINES"
echo ""
echo "pose       : $POSE_LINES lines"
echo "face       : $FACE_LINES lines"
echo "left_hand  : $LEFT_LINES lines"
echo "right_hand : $RIGHT_LINES lines"
echo ""
echo "결과 저장 폴더:"
echo "$TRIAL_DIR"
echo ""
echo "촬영 영상:"
echo "$RAW_DIR/video.mp4"
echo ""
echo "전체 랜드마크:"
echo "$FULL_DIR/all_landmarks.tsv"
echo ""
echo "부위별 랜드마크:"
echo "$TRIAL_DIR/landmarks/parts/"
echo "======================================"
echo "[DONE] 데이터 수집이 완료되었습니다."

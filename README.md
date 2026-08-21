# Sync:Us Collector

`data/landmarks`, `data/reports`, `logs`, `input_videos`는 파이프라인 실행 중에만 사용하는 중간 작업 공간입니다. 최종 결과는 `data/dataset/{동작명}/trial_.../`에 저장됩니다.

Shell Script 중심의 한국 수어 데이터 수집 프로그램입니다. `scripts/collect.sh`가 메뉴, 입력 검증, 촬영 승인, 파이프라인 실행, 결과 정리를 제어합니다. Python은 OpenCV 영상 녹화와 MediaPipe 랜드마크 추출 helper로만 사용합니다.

## 실행

Ubuntu에서 가상환경과 의존성을 준비한 뒤 실행합니다.

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install opencv-python mediapipe
bash scripts/collect.sh
```

메인 메뉴는 다음 기능을 제공합니다.

1. 동작 리스트 보기
2. 촬영 시작
3. 저장 현황 보기
4. 도움말
0. 종료

동작 목록과 권장 촬영 시간은 UTF-8 TSV 파일인 `config/sign_catalog.tsv`에서 관리합니다. 동작별 저장 한도는 `config/settings.conf`의 `MAX_SAMPLES_PER_WORD`이며 기본값은 60입니다.

## 촬영 흐름

촬영할 때 catalog에 등록된 동작명과 촬영자 ID를 입력합니다. 촬영 시간 입력을 비우면 catalog 권장 시간을 사용하며, 1~60초 정수를 입력하면 임의 촬영 시간을 사용합니다. 모든 촬영의 countdown은 3초입니다.

촬영 후 선택지는 다음과 같습니다.

- `Y`: 영상을 확정하고 기존 `scripts/run_pipeline.sh`를 실행합니다.
- `N`: 후보 영상과 빈 trial 폴더를 삭제합니다.
- `R`: 기존 입력값을 유지하고 다시 촬영합니다.

파이프라인은 Y를 선택한 뒤에만 실행됩니다.

## 최종 데이터 구조

```text
data/dataset/{sign_word}/trial_001_{user_id}_{timestamp}/
├── raw/video.mp4
├── landmarks/full/all_landmarks.tsv
├── landmarks/parts/pose/pose.tsv
├── landmarks/parts/face/face.tsv
├── landmarks/parts/left_hand/left_hand.tsv
├── landmarks/parts/right_hand/right_hand.tsv
├── report/report.txt
├── logs/collection.log
├── logs/collect_detail.log
├── logs/pipeline.log
└── metadata.txt
```

저장 횟수와 진행률은 trial 폴더 수가 아니라 실제 `raw/video.mp4` 파일 수를 기준으로 계산합니다.

## 구성 요소

- `scripts/collect.sh`: 전체 메뉴와 수집 흐름 제어
- `scripts/run_pipeline.sh`: 추출, 분리, 검증, 리포트 파이프라인
- `scripts/check_resources.sh`: 메모리, 디스크, CPU 점검
- `python/record_video.py`: 카메라 영상 녹화 helper
- `python/extract_landmarks_tsv.py`: MediaPipe 추출 helper
- `config/sign_catalog.tsv`: 수어 동작과 권장 촬영 시간

생성되는 `data/`, `logs/`, `input_videos/`, `.venv/`, `__pycache__/`는 Git에 포함하지 않습니다.

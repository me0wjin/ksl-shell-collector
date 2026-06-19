# KSL Shell-based Data Collection System

## 1. 프로젝트 개요

이 프로젝트는 한국 수어 학습 시스템 개발을 위한 수어 동작 데이터 수집 자동화 프로그램이다.

기존에는 Python이 영상 처리, 랜드마크 추출, 부위별 분리, 파일 저장을 대부분 담당하는 구조였지만, 시스템프로그래밍 수업의 목적에 맞추기 위해 Shell Script가 전체 파이프라인을 관장하도록 재구성하였다.

Python은 MediaPipe 기반 랜드마크 추출만 담당하고, Shell Script는 사용자 입력, 파일 탐색, 반복 실행, 부위별 데이터 분리, 결과 검증, 로그 기록, 리포트 생성을 담당한다.

---

## 2. 주요 기능

- 웹캠을 이용한 mp4 영상 녹화
- input_videos 폴더 내 mp4 파일 자동 탐색
- MediaPipe Holistic 기반 랜드마크 추출
- 전체 랜드마크 TSV 파일 생성
- pose, face, left_hand, right_hand 부위별 TSV 분리
- 결과 파일 존재 여부 및 라인 수 검증
- 실행 로그 자동 저장
- 최종 처리 리포트 자동 생성

---

## 3. 폴더 구조

```text
ksl-shell-collector/
├── input_videos/
│   └── 녹화 또는 분석할 mp4 영상
│
├── python/
│   ├── record_video.py
│   └── extract_landmarks_tsv.py
│
├── scripts/
│   ├── record_video.sh
│   ├── run_pipeline.sh
│   ├── split_by_part.sh
│   ├── validate_result.sh
│   └── make_report.sh
│
├── data/
│   ├── landmarks/
│   │   ├── all/
│   │   └── parts/
│   └── reports/
│
└── logs/
```

---

## 4. 실행 방법

### 4-1. 프로젝트 폴더 이동

```bash
cd ~/ksl-shell-collector
```

### 4-2. 가상환경 활성화

```bash
source .venv/bin/activate
```

터미널 앞에 `(.venv)`가 표시되면 가상환경이 정상적으로 활성화된 상태이다.

### 4-3. 웹캠으로 mp4 영상 녹화

```bash
bash scripts/record_video.sh
```

입력 예시:

```text
녹화 파일 이름을 입력하세요. 예: hello_test : hello
녹화 시간(초)을 입력하세요. 예: 5 : 5
```

녹화된 영상은 `input_videos/` 폴더에 저장된다.

### 4-4. 전체 데이터 수집 파이프라인 실행

```bash
bash scripts/run_pipeline.sh
```

입력 예시:

```text
수어 단어를 입력하세요: hello
촬영자 ID를 입력하세요: user01
```

---

## 5. 처리 흐름

```text
record_video.sh 실행
↓
웹캠으로 mp4 영상 녹화
↓
input_videos 폴더에 영상 저장
↓
run_pipeline.sh 실행
↓
input_videos 폴더에서 mp4 파일 탐색
↓
Python MediaPipe 추출 모듈 실행
↓
전체 랜드마크 TSV 생성
↓
split_by_part.sh로 부위별 TSV 분리
↓
validate_result.sh로 결과 검증
↓
make_report.sh로 리포트 생성
↓
logs 폴더에 실행 로그 저장
```

---

## 6. Shell Script의 역할

이 프로젝트에서 Shell Script는 단순히 Python 파일을 실행하는 역할에 머무르지 않는다.

Shell Script는 다음 과정을 직접 담당한다.

- 사용자 입력 처리
- 날짜와 시간을 활용한 세션 ID 생성
- mp4 파일 자동 탐색
- 영상별 반복 처리
- Python 추출 모듈 실행
- `awk`를 이용한 부위별 TSV 분리
- `wc`, 조건문을 이용한 결과 검증
- `tee`를 이용한 화면 출력 및 로그 저장
- 최종 리포트 생성 자동화

이를 통해 제한된 Shell Script 환경 안에서 데이터 수집 파이프라인을 자동화하였다.

---

## 7. Python의 역할

Python은 MediaPipe와 OpenCV를 사용하는 부분만 담당한다.

### record_video.py

웹캠을 실행하여 mp4 영상을 녹화한다.

입력:

```text
저장할 mp4 파일 경로
녹화 시간
카메라 번호
```

출력:

```text
input_videos/ 폴더 안의 mp4 파일
```

### extract_landmarks_tsv.py

mp4 영상 1개를 입력받아 MediaPipe Holistic 랜드마크를 추출한다.

입력:

```text
input video path
output TSV path
```

출력:

```text
전체 랜드마크 TSV 파일
```

Python은 폴더 반복 처리, 부위별 분리, 검증, 리포트 생성을 담당하지 않는다.  
이러한 작업은 Shell Script가 담당하도록 역할을 분리하였다.

---

## 8. 출력 결과

### 8-1. 전체 TSV 파일

저장 위치:

```text
data/landmarks/all/
```

예시 컬럼:

```text
video    frame    part    landmark_id    x    y    z    visibility    timestamp
```

각 컬럼의 의미는 다음과 같다.

```text
video        : 입력 영상 파일 이름
frame        : 프레임 번호
part         : pose, face, left_hand, right_hand 중 하나
landmark_id  : 랜드마크 번호
x            : x 좌표
y            : y 좌표
z            : z 좌표
visibility   : pose 랜드마크의 가시성 값
timestamp    : 영상 내 시간 정보
```

### 8-2. 부위별 TSV 파일

저장 위치:

```text
data/landmarks/parts/
```

생성 파일:

```text
pose.tsv
face.tsv
left_hand.tsv
right_hand.tsv
```

전체 TSV 파일에서 `part` 컬럼을 기준으로 데이터를 분리한다.

### 8-3. 리포트 파일

저장 위치:

```text
data/reports/
```

리포트에는 다음 정보가 포함된다.

- Session ID
- 입력 영상 이름
- 전체 TSV 라인 수
- 프레임 수
- 부위별 파일 라인 수
- 최종 처리 상태

### 8-4. 로그 파일

저장 위치:

```text
logs/
```

로그에는 전체 실행 과정이 기록된다.

---

## 9. 실행 결과 예시

실제 실행 결과 예시는 다음과 같다.

```text
[PYTHON] MediaPipe 랜드마크 추출 완료
[PYTHON] 총 처리 프레임 수: 54
[SUCCESS] TSV 생성 완료
[INFO] TSV 라인 수: 27055
[SPLIT] pose 라인 수: 1783
[SPLIT] face 라인 수: 25273
[WARNING] left_hand 파일에 데이터가 없습니다. 헤더만 존재합니다.
[WARNING] right_hand 파일에 데이터가 없습니다. 헤더만 존재합니다.
[VALIDATE] 결과 검증 완료
[REPORT] 리포트 생성 완료
[DONE] TSV 생성, 부위별 분리, 결과 검증, 리포트 생성 자동화 완료
```

---

## 10. 실행 결과 리포트 예시

```text
======================================
 KSL Data Collection Report
======================================
Session ID      : dd_03_20260525_023511
Video Name      : hh_20260525_022221.mp4
Generated Time  : 2026. 05. 25. (월) 02:35:17 KST

[Input / Output]
Input Video     : /home/meowjin/ksl-shell-collector/input_videos/hh_20260525_022221.mp4
All TSV File    : dd_03_20260525_023511_hh_20260525_022221_all.tsv
Part Directory  : /home/meowjin/ksl-shell-collector/data/landmarks/parts/dd_03_20260525_023511_hh_20260525_022221

[Summary]
Total TSV Lines : 27055
Frame Count     : 54

[Part Files]
pose : 1783 lines
face : 25273 lines
left_hand : 1 lines
right_hand : 1 lines

[Status]
Result : SUCCESS
======================================
```

---

## 11. 주요 Shell Script 설명

### 11-1. record_video.sh

웹캠 녹화용 Shell Script이다.

담당 기능:

- 녹화 파일 이름 입력
- 녹화 시간 입력
- 날짜/시간 기반 mp4 파일명 생성
- Python 녹화 파일 실행
- 생성된 mp4 파일 확인

### 11-2. run_pipeline.sh

전체 파이프라인을 실행하는 메인 Shell Script이다.

담당 기능:

- 사용자 입력 처리
- 세션 ID 생성
- mp4 파일 자동 탐색
- Python MediaPipe 추출 모듈 실행
- 부위별 분리 스크립트 호출
- 검증 스크립트 호출
- 리포트 생성 스크립트 호출
- 로그 저장

### 11-3. split_by_part.sh

전체 TSV 파일을 부위별 TSV 파일로 분리한다.

사용한 핵심 명령어:

```bash
awk
wc
for
mkdir
```

### 11-4. validate_result.sh

결과 파일이 정상적으로 생성되었는지 검증한다.

검증 항목:

- 전체 TSV 파일 존재 여부
- 전체 TSV 라인 수
- 부위별 폴더 존재 여부
- pose.tsv 존재 여부
- face.tsv 존재 여부
- left_hand.tsv 존재 여부
- right_hand.tsv 존재 여부
- 프레임 수 확인

### 11-5. make_report.sh

실행 결과를 텍스트 리포트로 생성한다.

리포트에는 입력 영상, 출력 파일, 전체 라인 수, 프레임 수, 부위별 라인 수, 최종 상태가 기록된다.

---

## 12. 주의 사항

### 12-1. 손 랜드마크 검출 문제

손이 화면에서 작게 보이거나, 조명이 부족하거나, 손이 얼굴 및 상체에서 멀리 떨어져 있으면 `left_hand`, `right_hand` 랜드마크가 검출되지 않을 수 있다.

이 경우 `left_hand.tsv`, `right_hand.tsv`에는 헤더만 존재할 수 있다.

예시:

```text
left_hand : 1 lines
right_hand : 1 lines
```

이는 프로그램 오류가 아니라 MediaPipe가 해당 영상에서 손 랜드마크를 검출하지 못한 결과이다.

### 12-2. 녹화 시 권장 조건

- 손이 화면 안에 크게 보이도록 촬영한다.
- 상체와 얼굴이 함께 보이도록 촬영한다.
- 조명이 밝은 환경에서 촬영한다.
- 손이 화면 밖으로 나가지 않도록 한다.
- 너무 빠른 동작은 피한다.

---

## 13. 한계 및 개선 방향

현재 프로그램은 MediaPipe Holistic을 이용해 pose, face, hand 랜드마크를 추출한다. 다만 손이 화면에서 작게 보이거나 조명이 부족한 경우 hand 랜드마크가 검출되지 않을 수 있다.

향후 개선 방향은 다음과 같다.

- 손이 잘 보이도록 녹화 가이드 추가
- 손 검출 실패 프레임 비율 계산
- 부위별 검출률 리포트 추가
- 기준 동작과 사용자 동작을 비교하는 DTW 기능 연결
- 사용자에게 점수와 피드백을 제공하는 기능 확장
- 웹 인터페이스와 연동하여 사용성을 개선

---

## 14. 시스템프로그래밍 관점의 의의

이 프로젝트는 단순히 Python 프로그램을 실행하는 데 그치지 않고, Shell Script가 전체 데이터 수집 파이프라인을 제어하도록 설계하였다.

특히 시스템프로그래밍 수업의 목적에 맞추어 다음 요소를 구현하였다.

- 파일과 디렉터리 자동 생성
- 사용자 입력 처리
- 조건문 기반 예외 처리
- 반복문 기반 파일 일괄 처리
- `awk`를 활용한 텍스트 데이터 처리
- `wc`를 활용한 결과 통계 확인
- `tee`를 활용한 로그 기록
- 여러 스크립트 간 모듈화된 실행 구조

이를 통해 제한된 Shell Script 환경 안에서도 실제 데이터 수집 프로그램의 흐름을 구성할 수 있음을 보여준다.

---

## 15. 프로젝트 의의

본 프로젝트는 한국 수어 학습 시스템 개발을 위한 데이터 수집 과정을 자동화하는 것을 목표로 한다.

기존에는 Python이 대부분의 파일 처리와 데이터 정리를 담당할 수 있었지만, 본 프로젝트에서는 Python의 역할을 MediaPipe 기반 랜드마크 추출로 제한하고 Shell Script가 전체 실행 흐름과 파일 처리, 검증, 리포트 생성을 담당하도록 재구성하였다.

이를 통해 Ubuntu Shell 환경에서 실제 데이터 수집 파이프라인을 구성하고 자동화하는 경험을 구현하였다.

또한 향후 DTW 기반 동작 비교, 부위별 피드백, 수어 학습 웹 서비스와 연결될 수 있는 기초 데이터 수집 구조를 마련했다는 점에서 의미가 있다.

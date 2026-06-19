#!/usr/bin/env python3

import cv2
import mediapipe as mp

mp_holistic = mp.solutions.holistic
import csv
import sys
import os
from datetime import datetime



def write_pose_landmarks(writer, video_name, frame_index, timestamp, landmarks):
    """
    pose 랜드마크 저장
    pose는 x, y, z, visibility를 모두 저장한다.
    """
    if landmarks is None:
        return

    for landmark_id, lm in enumerate(landmarks.landmark):
        writer.writerow([
            video_name,
            frame_index,
            "pose",
            landmark_id,
            lm.x,
            lm.y,
            lm.z,
            lm.visibility,
            timestamp
        ])


def write_landmarks(writer, video_name, frame_index, timestamp, part_name, landmarks):
    """
    face / left_hand / right_hand 랜드마크 저장
    face와 hand는 x, y, z를 저장하고 visibility는 비워둔다.
    """
    if landmarks is None:
        return

    for landmark_id, lm in enumerate(landmarks.landmark):
        writer.writerow([
            video_name,
            frame_index,
            part_name,
            landmark_id,
            lm.x,
            lm.y,
            lm.z,
            "",
            timestamp
        ])


def process_video(input_path, output_path):
    """
    동영상 파일 1개를 처리하여 전체 랜드마크 데이터를 TSV 파일로 저장한다.
    폴더 반복 처리, 부위별 분리, 검증, 리포트 생성은 Shell Script가 담당한다.
    """
    cap = cv2.VideoCapture(input_path)

    if not cap.isOpened():
        print(f"[ERROR] 영상을 열 수 없습니다: {input_path}")
        sys.exit(1)

    output_dir = os.path.dirname(output_path)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    video_name = os.path.basename(input_path)
    frame_index = 0

    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, delimiter="\t")

        writer.writerow([
            "video",
            "frame",
            "part",
            "landmark_id",
            "x",
            "y",
            "z",
            "visibility",
            "timestamp"
        ])

        with mp_holistic.Holistic(
            static_image_mode=False,
            model_complexity=1,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5
        ) as holistic:

            while cap.isOpened():
                success, image = cap.read()

                if not success:
                    break

                timestamp_sec = round(cap.get(cv2.CAP_PROP_POS_MSEC) / 1000.0, 4)

                image.flags.writeable = False
                image_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
                results = holistic.process(image_rgb)

                write_pose_landmarks(
                    writer,
                    video_name,
                    frame_index,
                    timestamp_sec,
                    results.pose_landmarks
                )

                write_landmarks(
                    writer,
                    video_name,
                    frame_index,
                    timestamp_sec,
                    "face",
                    results.face_landmarks
                )

                write_landmarks(
                    writer,
                    video_name,
                    frame_index,
                    timestamp_sec,
                    "left_hand",
                    results.left_hand_landmarks
                )

                write_landmarks(
                    writer,
                    video_name,
                    frame_index,
                    timestamp_sec,
                    "right_hand",
                    results.right_hand_landmarks
                )

                frame_index += 1

    cap.release()

    print(f"[PYTHON] MediaPipe 랜드마크 추출 완료: {output_path}")
    print(f"[PYTHON] 총 처리 프레임 수: {frame_index}")
    print(f"[PYTHON] 처리 시간: {datetime.now()}")


def main():
    if len(sys.argv) != 3:
        print("[ERROR] 사용법: python3 extract_landmarks_tsv.py <input_video> <output_tsv>")
        sys.exit(1)

    input_video = sys.argv[1]
    output_tsv = sys.argv[2]

    if not os.path.isfile(input_video):
        print(f"[ERROR] 입력 영상 파일이 존재하지 않습니다: {input_video}")
        sys.exit(1)

    process_video(input_video, output_tsv)


if __name__ == "__main__":
    main()

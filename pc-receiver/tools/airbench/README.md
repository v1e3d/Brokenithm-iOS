# airbench: 카메라 AIR 정확도 벤치마크

정답(손 위치)을 아는 60fps 합성 영상으로 `camera/camera-core.js`의 판정 정확도를 측정합니다.
페이지와 같은 코드를 쓰므로, 여기서 측정한 수치가 실제 페이지 동작과 같습니다.

## 만드는 영상
- **손:** MediaPipe 예제 사진에서 손을 오려 내서 사용합니다.
- **장면:** 방 배경, 아래쪽에 iPad 슬라이더
- **움직임:**
  - `slow`: 천천히 위아래
  - `flick6/4/3/2`: 빔 6개를 6/4/3/2프레임 만에 통과
  - `two_hands`: 두 손
  - `idle_mid`: 가만히 있는 손
  - `empty`: 손 없음
- **조명:**
  - `bright`: 노출 30%, 노이즈 2
  - `dim`: 밝기 1/3, 노출 70%, 노이즈 5
  - `dark`: 밝기 1/7, 노출 100%, 노이즈 8
  - 모든 조명에서 서브프레임 8장으로 모션 블러를 만들고, 웹캠 JPEG 압축을 넣습니다.
- **정답:** 그 프레임 시간(1/60초) 동안 손이 지나간 빔입니다(스윕 기준).
  - AI 모드: 손 랜드마크 범위를 정답으로 씁니다.
  - 빠른 모드: 손 마스크를 정답으로 씁니다.

## 실행
```bash
python -m venv venv && venv/bin/pip install mediapipe opencv-python-headless numpy
curl -LO https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task
mkdir assets && for n in thumb_up pointing_up right_hands victory; do curl -L -o assets/$n.jpg https://storage.googleapis.com/mediapipe-assets/$n.jpg; done
venv/bin/python tools/airbench/generate.py hand_landmarker.task assets data
node tools/airbench/eval.mjs data
```

## 지표
- **eventRecall:** 빔이 막히는 사건(연속 구간)을 1프레임 지연 이내에 한 번이라도 잡은 비율입니다. 게임 판정에 가장 중요합니다.
- **frameRecall:** 정답이 "막힘"인 프레임을 잡은 비율입니다(1프레임 지연 허용).
- **latency:** 사건이 시작된 뒤 처음 잡을 때까지 걸린 프레임 수입니다.
- **FPrate:** 막히지 않았는데 막혔다고 한 프레임의 비율입니다(빈 화면과 정지 손 포함).

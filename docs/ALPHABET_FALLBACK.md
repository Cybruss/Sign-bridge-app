# Sign-to-text fingerspelling fallback

## What it does

The **Alphabet fallback** is a separate camera mode for spelling unfamiliar words. MediaPipe detects a hand and returns 21 landmarks. Sign Bridge subtracts the wrist position, scales by the wrist-to-middle-finger-base distance, and passes the resulting 63 values to a compact TFLite MLP. The UI waits for a high top score, a top-two separation, and five agreeing predictions before appending a letter. The signer lowers their hand between letters; Space, Delete, Clear, and an editable text field build and correct the phrase.

It auto-recognizes static **A–I and K–Y**. **J and Z use movement**, so this static classifier does not attempt to recognize their motion; the keyboard includes both. This spells English letters and is a fallback for isolated-word recognition. It is not continuous sign-language translation, ASL grammar, or a replacement for a fluent interpreter.

## Model and evaluation

- Data source: [ASL Alphabet dataset by ameythakur20 on Kaggle](https://www.kaggle.com/datasets/ameythakur20/asl-alphabet-train), released under **CC BY 4.0**. Cite the dataset author and provide the license link when presenting or redistributing this model.
- The source has 30 images per class. MediaPipe produced valid landmarks for 684 images across 24 static-letter classes. Training uses a stratified image-level 70/15/15 split (478 train, 103 validation, 103 test), deterministic landmark jitter and horizontal-reflection augmentation, and early stopping.
- Held-out image-level results: **90.29% top-1 accuracy**, **90.28% macro-F1**. With the runtime gate (top score ≥ 0.93 and top-1 minus top-2 ≥ 0.18), test coverage is **68.93%** and accuracy among accepted test examples is **100% (71 of 103)**.
- These are small, same-source image splits. They are not signer-independent and do not establish generalization to a new person, phone, lighting, camera, or signing style. The runtime score is not a calibrated probability. Validate with multiple fluent signers and a signer-disjoint set before making an accuracy claim.
- The model is a standalone 17 KB TFLite file. The training images and the larger Kaggle archive are not in Git.

The generated metrics and per-class report are in [`model/fingerspelling_baseline.json`](model/fingerspelling_baseline.json).

## Rebuild the model

Python requirements used for this training run are TensorFlow, MediaPipe Tasks, Pillow, NumPy, and scikit-learn. In this machine, the ASL dataset was downloaded to `/media/maan/New Volume/asl-alphabet-small/asl-alphabet-train` and the MediaPipe `hand_landmarker.task` model is at `/home/maan/Desktop/Final Year Project/hand_landmarker.task`.

```bash
source ~/Desktop/pyvenv/bin/activate
python scripts/train_fingerspelling_model.py \
  --dataset "/path/to/asl-alphabet-train" \
  --hand-model "/path/to/hand_landmarker.task" \
  --epochs 60
```

The script exports `assets/ml/fingerspelling.tflite`, its label list, and the metrics report. Flutter packages both model files as app assets.

## Evaluator explanation

> We have two separate sign-to-text paths. Our primary model recognizes a constrained vocabulary of isolated words. The fingerspelling fallback recognizes static handshapes and composes letters into editable text. It is useful when the word model has no suitable vocabulary item, but it is deliberately scoped: J/Z motion and full ASL sentence translation are out of scope. We report the image-level benchmark separately from real-world performance because we do not yet have signer-disjoint mobile evaluation.

If asked to demonstrate, select **Alphabet fallback**, hold one static letter clearly inside the camera frame until it is added, lower the hand briefly before the next letter, and use Space between words. Use the letter keys to correct uncertain output. Avoid presenting a predicted word as verified ground truth without a fluent signer.

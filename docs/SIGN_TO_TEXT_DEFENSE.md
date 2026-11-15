# Sign-to-Text: honest evaluation defense

## The accurate claim

SignBridge is a mobile research prototype with two separate recognition modes:

1. **Isolated word recognition:** Android camera → MediaPipe Holistic landmarks → temporal window of 64 frames and 180 selected landmarks per frame → bidirectional GRU embedding → cosine ranking against 351 word vectors → user reviews and accepts a suggested word.
2. **Static fingerspelling:** Android camera → 21 hand landmarks normalized relative to the wrist and palm scale → small TFLite classifier → a conservative score, margin, and repeated-frame gate → user edits the composed text.

The modes address different inputs. The word route attempts a constrained vocabulary of moving signs; the alphabet route spells with still handshapes. Neither performs continuous, grammar-aware sign-language translation. Do not describe the app as a production-ready interpreter.

## Results to state precisely

- The integrated word model was fine-tuned from a supplied checkpoint, not trained from scratch. On a paired 560-example held-out WLASL-derived feature split over 351 labels, its TFLite top-1 was **26.79%**, top-5 **40.89%**, and macro-F1 **20.03%**. The previous app model scored 23.93%, 37.50%, and 16.20% on the same split. This is a modest improvement on that split, not strong recognition performance. The split's signer independence is not established.
- A separate WLASL-video classifier baseline used 973 labels and scored **3.63% top-1** and **13.66% top-5** on 1,157 test examples. It was intentionally not connected to the mobile app because the result and model interface were not suitable.
- The static-letter model scored **90.29% top-1** and **90.28% macro-F1** on a small image-level split. The operating gate accepted 71/103 test examples (68.93% coverage), all 71 correct. This benchmark is not signer-disjoint or real-camera performance; repeated acquisition conditions can make an image split optimistic. J and Z movement are entered with the keyboard.
- Pixel testing confirms camera/model startup, landmarks, the letter model and correction workflow. It did **not** establish labeled real-signer accuracy or on-device latency.

Full methods and evidence: [MODEL_EVALUATION.md](MODEL_EVALUATION.md), [model/wlasl_video_baseline.md](model/wlasl_video_baseline.md), and [ALPHABET_FALLBACK.md](ALPHABET_FALLBACK.md).

## Suggested 30-second explanation

> “We built and evaluated two constrained recognition paths. One ranks isolated word-sign sequences from temporal body and hand landmarks; the other recognizes static fingerspelled letters and composes editable text. The app asks the user to confirm word suggestions and supports correction, because recognition errors are expected. Our current word-model score is modest, so we present this as an evaluated prototype rather than an interpreter. The important engineering result is the complete camera-to-landmark-to-model-to-editable-output path and the evidence showing where it currently fails.”

## Likely evaluator questions

### Why is recognition weak?

> “The task has 351 visually similar classes and the training intersection is limited: 2,770 train, 748 validation, and 560 test examples. The test has only 560 examples across 351 labels, with class imbalance and unverified signer separation. The local video pipeline had only 6,578 available clips over 973 labels; 9,115 annotation entries had no local video. More labels did not mean more examples per label. We should reduce the vocabulary to classes with adequate signer-diverse examples, improve capture consistency, and report per-class results.”

Do not claim those counts alone prove why a particular error happened. See the data audit in [MODEL_EVALUATION.md](MODEL_EVALUATION.md) and [the video baseline report](model/wlasl_video_baseline.md).

### Why landmarks instead of raw video?

> “Landmarks reduce input size and focus the prototype on hand/body motion, which is easier to run on-device than a large video model. The tradeoff is loss of appearance and fine visual detail, plus dependency on landmark quality. Occlusion, camera framing, speed, and signer variation can therefore hurt recognition.”

### How do you avoid adding every wrong prediction?

> “Word predictions are suggestions: the user explicitly taps Add word. Fingerspelling uses a high score threshold, a top-two margin, and agreement across frames; uncertain poses are rejected. The user can edit or delete the text. These controls reduce accidental insertion but do not make the classifier reliable.”

### What does the score mean?

> “For the word path it is cosine similarity between an output embedding and a label vector, not a calibrated probability. The letter path's score is a classifier output and is also not calibrated. We avoid presenting either as ‘90% sure’.”

### Why not join signs into sentences?

> “Recognizing an isolated gloss is not the same as translating continuous signing. Sentence translation needs temporal segmentation, non-manual signals, discourse and language-specific grammar. This app builds editable word/letter text; it does not claim to infer those structures.”

### What would make the next result credible?

> “A smaller vocabulary chosen from per-class support; consented recordings from multiple signers; signer-disjoint training, validation, and test sets; a frozen test set; per-class precision/recall and confusion analysis; and on-device latency and usability measurements. Deaf and fluent signing participants should help define the task and review errors.”

## How to present the live demo

1. Show **Spell by hand** and explain that the user can correct the result. Demonstrate the manual keyboard if no fluent signer is available. Do not use a handshape you cannot identify as ground truth.
2. Show **Recognize words** as the broader but weakly performing route. Explain the camera sequence and ask the evaluator to treat any output as a candidate. Do not promise that an arbitrary sign will be recognized.
3. Show the evidence table and identify the word-model number as the current measured result. Acknowledge that the app needs a signer-diverse evaluation before its accuracy can be generalized.

If asked whether it is “100% working,” answer: **“The app path runs end to end on the tested Pixel, but recognition quality is not 100%, and the evidence does not support claiming robust general sign translation.”**

# Test and verification report

Updated: 2026-11-14 (Asia/Karachi)

## Public presentation cleanup and website-aligned theme (2026-11-15)

- Matched the app palette to [sign-bridge.app](https://www.sign-bridge.app/): warm paper `#F6F1E7`, ink `#2A2620`, cream surfaces, and clay accents.
- Removed the project-demo badge, developer diagnostics entry point, raw model similarity/score details, and unused inference test screen from the user-facing app. Sign recognition now uses plain language and presents word outputs as suggestions; users can review and edit the message.
- Renamed internal routes and controls in the public flow, removed the HamNoSys/SiGML debug trace panels from the sign example screen, and retained plain-language notices about limited sign coverage, language examples, and online text sharing.
- Added [SIGN_TO_TEXT_DEFENSE.md](SIGN_TO_TEXT_DEFENSE.md), which documents the exact pipeline, measured results, failure limitations, demo approach, and evaluator Q&A.
- `flutter analyze`: PASS, no issues. `flutter test`: PASS, all tests passed.
- Arm64 release build: PASS, version code 2004, 103.5 MB at `build/app/outputs/flutter-apk/app-release.apk`. Installed on the Pixel 6 Pro (Android 16) and launched successfully.
- Visual device checks: website-aligned home screen, plain-language sign-recognition screen with hidden raw scores, still-letter mode with a friendly low-match state, and local sign examples page with a signing avatar. The build is fully usable as an evaluation prototype; recognition accuracy remains limited as described in [SIGN_TO_TEXT_DEFENSE.md](SIGN_TO_TEXT_DEFENSE.md).

## Alphabet fallback, theme, and current Pixel build (2026-11-14)

- Added a separate static fingerspelling fallback, editable text composition, and a correction keyboard. The classifier covers A–I and K–Y; J/Z are entered manually because their ASL forms require movement.
- Trained a compact MediaPipe-landmark MLP on the small Kaggle ASL Alphabet image dataset. Its held-out image-level score is 90.29% top-1 and 90.28% macro-F1. With the conservative runtime gate, 71/103 test examples are accepted (68.93% coverage) and all 71 accepted examples are correct. This is not signer-independent or real-phone accuracy evidence; see [ALPHABET_FALLBACK.md](ALPHABET_FALLBACK.md).
- Updated the app palette and home navigation, and included `blenderStory.sigml` in the bundled SiGML lexicon. The Text-to-Sign screen now shows supported glosses and clearly describes its NGT example scope.
- `dart format` and Python `py_compile`: PASS. `flutter analyze`: PASS, no issues. `flutter test`: PASS, all tests passed. `flutter build apk --debug --split-per-abi`: PASS; arm64 APK at `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk` (about 147 MB).
- Release package: `flutter build apk --release --target-platform android-arm64 --build-number 2002`: PASS; 103.5 MB at `build/app/outputs/flutter-apk/app-release.apk`. Installed as version code 2002 over the existing Pixel build and launched successfully.
- Pixel 6 Pro, Android 16, wireless ADB: latest arm64 APK installed and launched. Home and Text-to-Sign pages rendered. The live camera/Holistic and word-model status were ready. Alphabet model loaded; a low-match live pose displayed “Low match” and was not inserted. Manual A/B/C input appeared in the editable text field. The `orange blender explode` phrase loaded and played through the SiGML avatar.
- This device check confirms loading and interaction only. No fluent signer provided ground-truth letters; real-world alphabet accuracy, latency, and robustness remain unmeasured.
- Standalone `.hamnosys`/`.hns` files beyond the repository's bundled samples were not located in the searched Desktop or mounted data folders. The additional lexicon source is bundled SiGML `hamgestural_sign` content, not a claim of newly authored HamNoSys signs.

## Presentation UI and handoff update (2026-11-12)

- Refreshed the app's home screen with a branded header, a primary camera-recognition action, clearly grouped local avatar/SiGML demos, an online-service label, and a short scope note.
- Added `scripts/build_wlasl_reference_index.py`. It indexed 702 available reference clips across all 351 app labels from the mounted local WLASL folder; the CSV was written to that external dataset volume, and no video files were copied into this repository.
- `flutter analyze --no-pub`: PASS, no issues found after the UI update.
- `flutter build apk --release --no-pub`: PASS; release package is 136.0 MB at `build/app/outputs/flutter-apk/app-release.apk`.
- Attempted to install the new package on the Pixel 6 Pro, but its wireless ADB connection went offline during the build. The updated package was not installed or visually inspected on-device in this update.
- No unit tests were run in this continuation. No WLASL retraining or labeled real-signer accuracy evaluation was performed.
- GitHub push remains pending because this environment has no GitHub credential configured. The target remote has been configured as `origin` and the repo was confirmed empty.

## Continuation validation (2026-11-05)

- `flutter analyze`: PASS after adding the SiGML route and bundled-asset server.
- ARM64 release build: PASS at 103.2 MB; the build is at `build/app/outputs/flutter-apk/app-release.apk`.
- Pixel 6 Pro (Android 16): SiGML page rendered the bundled Anna avatar. Entering `I take mug` loaded the SiGML sequence and the player reported `Playing complete`.
- Pixel live camera screen: camera, Holistic processor, 351-label model, and hand landmarks were visible. An unlabelled hand pose had produced a candidate and the earlier app auto-added it; that was not labeled accuracy evidence. The latest installed release requires the user to tap **Add** before a candidate enters the sentence. This was exercised on the phone: the sentence stayed empty before tapping and accepted the selected candidate afterward.
- The lower prediction/editor panel scrolls on the Pixel so the sentence field and Undo/Clear controls are reachable. The installed app opens to the live camera screen; pause it or go Home before handing over the phone.
- The local WLASL video volume was not mounted during this continuation; no new model training or labeled user evaluation was performed.
- No Flutter unit tests were rerun during this continuation; the latest unit-test result remains the 6 passing tests recorded below for the October 18 source.

## Commands and results

| Command / check | Exit/result | Notes |
|---|---|---|
| `dart format lib test` | PASS, exit 0 | Final Dart formatting check ran after app changes. |
| `flutter analyze` | PASS, exit 0 | Latest rerun after fixing the bundled avatar asset key: `No issues found!` |
| `flutter test` | PASS, exit 0 | Latest rerun: all 6 tests passed, including preprocessing shapes/empty input, label-vector shape/uniqueness, prediction formatting, and home-screen smoke check. |
| `source ~/Desktop/pyvenv/bin/activate && python3 scripts/verify_tflite_model.py` | PASS, exit 0 | Three deterministic synthetic inputs; output `[1,300]`, 351 labels, finite unit-normalized embeddings. CPU XNNPACK. |
| Fine-tuned Kaggle TFLite smoke test | PASS | Downloaded export passed separate local TFLite invocation and metadata checks; 351 labels and finite unit-norm embeddings. Max validation parity error 0.001083. |
| Paired held-out evaluation | PASS | Existing app TFLite vs new TFLite on identical 560 cached examples: top-1 23.93% → 26.79%, top-5 37.50% → 40.89%, macro-F1 16.20% → 20.03%. Raw metrics and confusion/per-class files are under ignored local `artifacts/kaggle_run_2026-10-18/`; summary in [MODEL_EVALUATION.md](MODEL_EVALUATION.md). |
| `python3 -m py_compile scripts/train_sign_bridge.py` | PASS, exit 0 | Trainer syntax validation. |
| `python3 scripts/build_kaggle_training_notebook.py` plus notebook cell parsing | PASS | Generated a self-contained four-cell notebook; embedded trainer and run cell parse as Python. |
| Synthetic trainer fixture (`--epochs 1 --batch-size 1`) | PASS, exit 0 | Three synthetic samples (one each train/validation/test), 1 class. Produced checkpoint, held-out artifacts and `[1,64,180,3] → [1,300]` TFLite export. Export parity max error 0.002952; CPU XNNPACK latency median 21.71 ms. Its 100% toy metrics are **not accuracy evidence**. |
| `source ~/Desktop/pyvenv/bin/activate && python3 scripts/verify_tflite_model.py --checkpoint <exact Kaggle v2 checkpoint>` | PASS for synthetic runtime/parity, exit 0 | Input `[1,64,180,3]`, output `[1,300]`, 351 labels; three deterministic inputs were finite and unit-normalized. Maximum absolute parity error 0.028741; mean absolute error 0.002775; top-1 retrieval agreement 3/3 and mean top-5 overlap 4.67/5. Synthetic-only. Checkpoint file was deleted after comparison. |
| `flutter build apk --debug --target-platform android-arm64` | PASS, exit 0 | Built current ARM64 debug APK at `build/app/outputs/flutter-apk/app-debug.apk` (485,360,233 bytes). Gradle took approximately 13 minutes to complete dependency transforms and compilation. |
| `flutter build apk --release --target-platform android-arm64` | PASS, exit 0 | Final build after avatar asset path fix produced `build/app/outputs/flutter-apk/app-release.apk` (100.2 MB). |
| Final release install and launch on Pixel 6 Pro (Android 16, wireless ADB) | PASS | Final 100.2 MB APK installed; home screen launches and all four menu labels fit. Updated TFLite interpreter starts without error. |
| Sign-to-Text live camera screen on Pixel 6 Pro | PASS for camera/Holistic/model readiness | Existing camera permission was already granted. Updated release preview opened; UI reported Holistic processor ready and model ready (351 labels), with TFLite interpreter initialized. The phone was not held in a controlled signing position and no ground-truth word prediction is claimed. |
| Rylo in-app WebView on Pixel 6 Pro | PASS for route/page load; generation unavailable | Page loaded after a transient DNS retry and displayed the official English→American interface, cookie-consent panel, and “models ... in research preview” notice. No cookie choice was made and no text was submitted. A prior transient load error was surfaced with Retry. |
| Kaggle private training run | PASS | Version 1 completed 80 epochs on a GPU runtime where two Tesla T4s were visible (the code did not enable mirrored multi-GPU training). Eligible official split: 2,770 train / 748 validation / 560 test, 351 labels. Held-out Keras top-1 26.25%, top-5 40.89%, macro-F1 19.41%; exported TFLite max parity error 0.001083. Artifacts downloaded and independently smoke-tested. Original public notebook was not modified. |

## Baseline and changes

- Baseline tests passed before edits, but baseline `flutter analyze` had four existing lint findings. Those were fixed; final analysis is clean.
- Added TFLite input/output and label metadata validation in the Dart inference loader.
- Added sentence editing, undo-last-word, clear, visible low-similarity guidance, and camera start/pause/error feedback to Sign-to-Text.
- Restricted the avatar demo to clip names confirmed present in the GLB and made unsupported input visible. This does not verify sign semantics or sentence grammar.
- Fixed the avatar viewer's asset key to match the path bundled from `pubspec.yaml`; the previous phone build had stalled with an asset-not-found exception.
- Fine-tuned the app's 351-label model from the available checkpoint and replaced the mobile TFLite after paired held-out comparison showed modest gains on top-1/top-5 and macro-F1. The initialization checkpoint license is unknown; redistribution rights remain unresolved.
- Added `scripts/verify_tflite_model.py` for a local model smoke check and optional checkpoint parity comparison.

## Device and runtime evidence

- Host: Linux x86_64; supplied environment Python 3.12.3, TensorFlow 2.21.0. TensorFlow did not find a CUDA driver; no local GPU training was performed.
- The TFLite model ran with TensorFlow Lite's XNNPACK CPU delegate in the Python runtime. This is not Android runtime evidence.
- The Pixel 6 Pro camera path and Holistic landmark overlay work. A labeled sign attempt, expected top-k result, sentence auto-append/correction through a real prediction, camera permission-denial recovery, and on-device latency measurement remain outstanding.
- The final release loads the 3D avatar and successfully plays the supported `ME`, `WANT`, and `PIZZA` clips for the input “I want pizza.” This confirms clip playback only; the screen correctly disclaims sentence grammar/translation.
- The installed release APK is 100.2 MB; about 9.3 GB remains free on the host volume after the build.

## Remaining defects and blocked work

1. Capture a controlled, labeled sign attempt on the Pixel and verify expected top-k, sentence add/undo/clear and on-device latency.
2. The WLASL official split is not demonstrated signer-disjoint; run signer-disjoint evaluation if reliable signer metadata becomes available.
3. The public Rylo page says its latest models are in research preview and unavailable to the public. Text-to-sign remains an online service route plus a limited avatar word-demo; generated Rylo signs cannot currently be verified.
4. Confirm distribution rights for the private/unknown-license model checkpoints and mixed-license JAS assets before external sharing.

## Current quality status

Flutter analysis/tests and ARM64 debug/release builds: **PASS**. Final release install, camera/Holistic/model readiness, avatar load and supported word-clip playback on Pixel: **PASS**. Real WLASL-split training/export and paired model comparison: **PASS**, with modest results and signer leakage unverified. Rylo route/page load: **PASS**, but public model generation is unavailable. Real-user labeled sign accuracy and unrestricted text-to-sign: **NOT COMPLETE**.

# Evaluator demo runbook

Updated 2026-11-14 (Asia/Karachi).

## One-minute project description

Sign Bridge is a mobile prototype with two separate sign-to-text routes: an isolated-word recognizer and a static fingerspelling fallback that spells editable text. Text-to-sign has a small local GLB clip lookup, an experimental SiGML avatar player using a few NGT lexicon examples, and a hosted Rylo page when online. These are constrained prototypes, not a complete bidirectional sentence translator.

## Suggested live walkthrough

1. **Recognize words:** wait for the camera, then demonstrate the review-before-accept flow. Use a local WLASL reference clip for the exact word and ask a fluent signer to perform it if available. Treat the result as a suggestion; do not promise a correct recognition. The paired held-out top-1 result is 26.79%; real-camera user accuracy has not been measured.
2. **Spell by hand:** hold a static handshape in frame until a letter is accepted, briefly lower the hand between letters, and use **Space** between words. Use the letter keys to correct text. Explain that the 90.29% result is from a small image-level split, not signer-independent evaluation. Use this route to compose editable text, not to claim continuous sign translation. If no fluent signer is available, demonstrate the manual correction controls instead of inventing ground truth.
3. **Local word animation:** enter `I want pizza` and play the available GLB clips. This demonstrates clip lookup/playback; it is not sentence translation.
4. **Local SiGML examples:** try `welcome`, `I take mug`, `Scotland`, or `orange blender explode`. Show the generated SiGML and avatar. This concatenates a few NGT examples and does not translate English grammar or ASL.
5. **Online fallback:** open Rylo Translate with internet access. The in-app page is Rylo's hosted service; treat it as an external service route, not a bundled model.

## Device preparation

The connected demo phone is a Pixel 6 Pro (Android 16). The arm64 release APK is at `build/app/outputs/flutter-apk/app-release.apk`. With wireless debugging connected, install/update it using:

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Before evaluators arrive, open the app once, grant camera permission, check that the camera is ready, and confirm the signing avatar has loaded. The latest Pixel install was checked for launch, camera readiness, low-match rejection in the hand-spelling mode, manual A/B/C message composition, and `orange blender explode` example playback. Keep the phone online for the Rylo route. If time is short, prioritize the local word animations, then show the local sign examples.

## Rehearse with labeled signs

If the presenter does not know ASL, use the locally downloaded WLASL videos as visual references rather than guessing how to perform a word:

```bash
python3 scripts/build_wlasl_reference_index.py \
  --dataset "/media/maan/New Volume/wlasl-processed" \
  --output "$HOME/wlasl_rehearsal.csv"
```

Open the CSV and play the referenced `videos/<id>.mp4` clip with VLC (or another player) from the WLASL folder. The index contains up to one available example for each of the app's labels. Replay the clip on a second device while the Sign Bridge phone observes the signer; the app cannot evaluate the prerecorded video file directly. A person familiar with ASL should verify the sign and the intended label. Do not treat the dataset clip as proof of real-user accuracy or present the model's similarity score as a calibrated confidence.

## Evidence and limits to disclose

- The classifier predicts isolated WLASL-derived word classes; it is not continuous sign-language translation.
- The reported model result is modest and was measured on a held-out feature split. Signer-disjoint and real-camera accuracy are not established.
- The local GLB and SiGML output are demonstrations with limited coverage, not linguistically validated translation.
- Rylo's current web route is a hosted fallback, not a bundled model. The official page currently reports that its latest sign models are unavailable to the public.
- The local WLASL video volume is mounted, and a reference-index script is provided for rehearsal. The existing model was not retrained from these raw videos during this continuation; training requires a separate, validated video-to-landmark preprocessing and evaluation run.

See [MODEL_EVALUATION.md](MODEL_EVALUATION.md), [TEXT_TO_SIGN.md](TEXT_TO_SIGN.md), and [DATASET_AND_LICENSES.md](DATASET_AND_LICENSES.md) for methodology and provenance limits.

The fingerspelling methodology and sign-to-text evaluator answers are in [ALPHABET_FALLBACK.md](ALPHABET_FALLBACK.md) and [SIGN_TO_TEXT_DEFENSE.md](SIGN_TO_TEXT_DEFENSE.md). The project workspace contains bundled SiGML examples, but no additional standalone `.hamnosys`/`.hns` files were found under the searched Desktop or mounted data directories.

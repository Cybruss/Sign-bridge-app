# Evaluator demo runbook

Updated 2026-11-14 (Asia/Karachi).

## One-minute project description

Sign Bridge is a mobile prototype with two separate sign-to-text routes: an isolated-word recognizer and a static fingerspelling fallback that spells editable text. Text-to-sign has a small local GLB clip lookup, an experimental SiGML avatar player using a few NGT lexicon examples, and a hosted Rylo page when online. These are constrained prototypes, not a complete bidirectional sentence translator.

## Suggested live walkthrough

1. **Sign-to-Text word model:** wait for camera, Holistic, and model readiness. Show landmarks, the candidate, the cosine similarity, and editable text. For a known label, use a local WLASL reference clip and imitate one isolated word at a time. Tap **Add** only after reviewing the candidate. The paired app-model held-out top-1 result is 26.79%; real-camera user accuracy has not been measured.
2. **Alphabet fallback:** select **Alphabet fallback**. Hold a static handshape in frame until it is accepted, briefly lower the hand between letters, and tap **Space** between words. The model auto-detects static A–I and K–Y; use the letter keys to correct text and to enter J/Z. Explain that its 90.29% result is from a small image-level split, not signer-independent evaluation. Use this route to spell a short word, not to claim continuous ASL translation.
3. **Local word animation:** enter `I want pizza` and play the available GLB clips. This demonstrates clip lookup/playback; it is not sentence translation.
4. **Local SiGML examples:** try `welcome`, `I take mug`, `Scotland`, or `orange blender explode`. Show the generated SiGML and avatar. This concatenates a few NGT examples and does not translate English grammar or ASL.
5. **Online fallback:** open Rylo Translate with internet access. The in-app page is Rylo's hosted service; treat it as an external service route, not a bundled model.

## Device preparation

The connected demo phone is a Pixel 6 Pro (Android 16). The device-specific arm64 debug APK is built at `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk` (the universal debug APK is `build/app/outputs/flutter-apk/app-debug.apk`). With wireless debugging connected, install/update it using:

```bash
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk
```

Before evaluators arrive, open the app once, grant camera permission, check the on-device model/Holistic status, and confirm the avatar player has loaded. The latest Pixel install was checked for launch, camera/Holistic readiness, alphabet fallback loading and rejection of a low-match pose, manual A/B/C sentence composition, and `orange blender explode` SiGML loading/playback. Keep the phone online for the Rylo route. If time is short, prioritize the local GLB demo, then show the SiGML player as the local text-to-sign research prototype.

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

The new fingerspelling model's training protocol, metrics, and defense explanation are in [ALPHABET_FALLBACK.md](ALPHABET_FALLBACK.md). The project workspace contains several bundled `.sigml` examples, but no additional standalone `.hamnosys`/`.hns` files were found under the Desktop or mounted data volume during this audit. New HamNoSys/SiGML signs can only be integrated after the files and their license/provenance are supplied; see [TEXT_TO_SIGN.md](TEXT_TO_SIGN.md) for the current lexicon workflow.

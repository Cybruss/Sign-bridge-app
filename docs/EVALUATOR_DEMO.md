# Evaluator demo runbook

Updated 2026-11-12 (Asia/Karachi).

## One-minute project description

Sign Bridge is a mobile prototype with an on-device, isolated-word ASL recognition pipeline (camera → MediaPipe Holistic landmarks → TFLite classifier) and two text-to-sign demonstrations: a small local GLB clip lookup and an experimental SiGML avatar player using a few NGT lexicon examples. A separate Rylo Translate WebView provides access to its hosted interface when online. These are separate prototypes, not a complete bidirectional sentence translator.

## Suggested live walkthrough

1. **Sign-to-Text:** open the camera screen and wait for camera, Holistic, and model readiness. Show the top prediction, similarity score, hand landmarks, and editable sentence controls. For a known label, use the WLASL rehearsal index described below and play its local example clip on a second screen. Pause the clip and ask the signer to imitate one isolated word at a time. Tap **Add** to place a candidate in the sentence; candidates are not silently appended. Describe the result as a prototype prediction; the reported held-out top-1 score is 26.79% for the paired app TFLite comparison, and live user accuracy has not been measured.
2. **Local word animation:** enter `I want pizza` and play the available GLB clips. Say explicitly that this demonstrates clip lookup/playback; the animation glosses have not been validated by a fluent signer and this is not sentence translation.
3. **Local SiGML examples:** try `welcome`, `I take mug`, or `Scotland`. Show the generated SiGML and avatar. Explain that this concatenates a small set of NGT examples and does not translate English grammar or ASL.
4. **Online fallback:** open Rylo Translate with internet access. The in-app page is Rylo's hosted service. As of this runbook date, the official page says the latest Sign models are in research preview and unavailable to the public, so do not promise generated output.

## Device preparation

The connected demo phone is a Pixel 6 Pro (Android 16). The release APK is built at `build/app/outputs/flutter-apk/app-release.apk` and was installed on the connected Pixel on 2026-11-05. With wireless debugging connected, install/update it using:

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Before evaluators arrive, open the app once, grant camera permission, check the on-device model/Holistic status, and confirm the avatar player has loaded. The Pixel successfully played `I take mug` in the SiGML screen. Keep the phone online for the Rylo route. If time is short, prioritize the local GLB demo, then show the SiGML player as the local text-to-sign research prototype.

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

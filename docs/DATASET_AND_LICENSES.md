# Dataset provenance and licenses

Audit date: 2026-10-17.

## WLASL

The project targets word-level American Sign Language (ASL). The official [WLASL repository](https://github.com/dxli94/WLASL) states that WLASL is licensed under the Computational Use of Data Agreement (C-UDA-1.0) and asks users to read the agreement. Cite Li et al., *Word-level Deep Sign Language Recognition from Video: A New Large-scale Dataset and Methods Comparison*, WACV 2020, and consult the agreement itself before sharing or using data beyond the agreement's scope. Do not redistribute source videos or derived datasets without confirming the terms.

The user-provided local folder `/media/maan/New Volume/wlasl-processed/` contains:

- `WLASL_v0.3.json`, `nslt_100.json`, `nslt_300.json`, `nslt_1000.json`, `nslt_2000.json`, `wlasl_class_list.txt`, `missing.txt`;
- 11,980 files ending in `.mp4` under `videos/`.
- NSLT annotation counts/splits observed on 2026-10-17:

| Annotation | Entries | Train | Validation | Test | Distinct class IDs |
|---|---:|---:|---:|---:|---:|
| `nslt_100.json` | 2,038 | 1,442 | 338 | 258 | 100 |
| `nslt_300.json` | 5,118 | 3,549 | 901 | 668 | 300 |
| `nslt_1000.json` | 13,174 | 8,978 | 2,320 | 1,876 | 1,000 |
| `nslt_2000.json` | 21,095 | 14,296 | 3,920 | 2,879 | 2,000 |

These are annotation records, not unique usable videos or verified feature sequences. The installed file set does not establish complete accessibility or signer-disjoint splits. No videos were copied into this repository.

## Model-training provenance

The checked-in app model has 351 labels. The pulled Kaggle notebook `abdurrehmanzubair/sign-bridge` describes using the separate `abd0kamel/mutemotion-output` feature dataset (`landmarks_V3.npz`, `labels.npz`, `WLASL_parsed_data.json`, `filtered_labels.txt`) and separate `abdurrehmanzubair/poutput` or checkpoint datasets. These inputs are not in the app repository or the supplied local processed-video folder as named. This audit does not equate the NSLT files/videos to those preprocessed Kaggle features and does not claim that local videos trained the 351-label model.

The app's currently documented feature contract is 180 selected landmarks × XYZ, 64 temporal samples, hand wrist-centering/span scaling, and zero-filled missing landmarks. Training-time extraction and augmentation are described in the existing model report, but the raw pipeline/checkpoint are not versioned here. Face-mesh mismatch at indices 468 and 473 is explicitly noted in the model report.

## Other assets and software

- The checked-in Holistic task model is `android/app/src/main/assets/holistic_landmarker.task`; record its upstream license/provenance before redistributing the app outside the current project.
- JAS/CWASA files under `jas/loc2025/` have mixed licensing. Some visible pages carry CC BY-NC-ND 4.0 notices; included source also carries GPL-2.0 and other embedded notices. The included SiGML examples contain NGT glosses. Treat the bundle as non-commercial until each relevant asset's provenance/terms are verified; do not infer a single license for the whole folder.
- Sign.mt/Rylo Translate source states free use for individuals, non-profits and educational institutions under CC BY-NC-SA 4.0, with attribution and share-alike obligations; commercial organizations need a separate license. See [TEXT_TO_SIGN.md](TEXT_TO_SIGN.md) and the project's [license](https://github.com/sign/translate/blob/master/LICENSE.md). Its models/assets may carry separate terms.
- `assets/sign_bridge_export/` is untracked pre-existing work. Its 100-word H5/model provenance was not verified in this audit; preserve it and do not redistribute as a validated artifact.

## Attribution and safe use

For WLASL research, cite the WLASL paper and follow C-UDA-1.0. Store any signed agreement and source URLs with the research record. Keep source video out of Git. For each derived feature set, preserve annotation IDs, source split, signer ID where available, preprocessing version, and failed/missing sample records. Report held-out results only for actually evaluated partitions and explain any signer overlap.

The local video count is a filesystem observation only; it does not establish legality, completeness, corruption rate, or training eligibility. Those checks are outstanding before training.

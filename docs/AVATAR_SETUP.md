# Amy avatar replacement and vocabulary

`assets/avatars/AmyAvatarnew.glb.gz` is the replacement supplied for this project. It is the gzip-compressed GLB `AmyAvatarlatest.glb` (141,894,668 bytes before compression), with 2,034 embedded animation clips and about 2,007 normalized clip names. The compressed source is 90,976,704 bytes, below GitHub's 100 MB per-file limit.

The Text-to-Sign screen expands the compressed asset to a temporary `amy_avatar_v2.glb` file the first time it opens, then points the 3D viewer at that file. It reuses the extracted file on later opens. If a model update changes its decompressed byte size, update `expectedBytes` and the temporary filename in `lib/screens/avatar_pipeline_screen.dart`.

## What the larger clip dictionary does

- Text is split into words; the lookup prefers the longest phrase clip, then individual word clips.
- Supported clips play in input order, and unmatched words are reported.
- This is clip retrieval, not text-to-sign translation. Word order, inflection, nonmanual grammar, transitions, and sentence structure are not generated.
- The 2,007 count is based on normalized animation names, not a linguist-validated count of distinct ASL lemmas. Have a fluent signer review the gloss-to-motion mapping before presenting a word as verified.

The avatar file was supplied by the project owner. Its upstream author and redistribution license have not been established in this repository. Confirm those details before publishing a public APK or reusing the asset outside this educational project.

## SiGML/HamNoSys vocabulary sources reviewed

SiGML is a notation for describing signs, not a language-neutral word-to-motion dictionary. A sign entry must match the target sign language and be authored or reviewed by fluent signers. This app's bundled CWASA examples are NGT, while the new Amy avatar's animation names appear to be an ASL-oriented word list. Their vocabularies should remain labelled separately.

- [Dicta-Sign Lexicon](https://www.sign-lang.uni-hamburg.de/dicta-sign/portal/) provides approximately 1,000 concepts in BSL, GSL, DGS, and LSF with glosses and HamNoSys descriptions. The [Sign Language Dataset Compendium](https://www.sign-lang.uni-hamburg.de/lr/compendium/lex/dictasignlex.html) says access is public for browsing but reuse is by individual researcher license. It is a good route to request, not a dataset to bulk-copy without the agreement.
- [SiS-Builder](https://sign.ilsp.gr/sisbuilder/) can author/convert HamNoSys strings into SiGML. It is a notation/authoring tool, not a ready-made open lexicon; it does not supply validated ASL entries for this app.
- The [LSE motion-generation dataset paper](https://www.mdpi.com/2313-433x/9/12/262) describes 754 Spanish Sign Language signs with HamNoSys and SiGML, but its data-availability statement requires requesting the dataset from the authors. LSE entries are not ASL signs.
- [ASL Signbank](https://aslsignbank.haskins.yale.edu/) is the closest language match: it provides ASL signs, videos, and translation equivalents. Its [copyright page](https://aslsignbank.haskins.yale.edu/about/copyright/) specifies CC BY-NC-SA 4.0, and access to some details requires approval. It is not a direct SiGML export, so entries would need licensed sign descriptions and expert HamNoSys transcription before addition.

For these reasons, the bundled SiGML lexicon is still the existing small NGT example set. The new avatar's much larger animation lookup expands the separate local word-animation demo, but it does not add SiGML files. A valid next SiGML expansion needs a target language decision plus authorized source data or expert-authored transcriptions.

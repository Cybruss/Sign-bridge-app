# Kaggle setup and safe workflow

## Environment inspected

The supplied environment is activated with:

```bash
source ~/Desktop/pyvenv/bin/activate
python --version
kaggle --version
```

At audit, Python 3.12.3 and Kaggle CLI 2.2.4 were available. Kaggle API authentication was verified with a read-only request:

```bash
kaggle kernels list -s sign-bridge --page-size 20
```

It returned the existing `abdurrehmanzubair/sign-bridge` notebook. Do not use `kaggle auth status`: CLI 2.2.4 does not implement that subcommand. Never run `kaggle auth print-access-token` in a shared terminal/log because it prints a credential.

The existing credential file `~/.kaggle/access_token` had filesystem mode `0600`; its contents were not viewed, logged, or copied. The successful API list request verifies authentication without exposing it.

## Secure setup (Linux)

1. Generate an API token from [Kaggle Settings](https://www.kaggle.com/settings) while signed into the intended account. Do not paste it into chat or a notebook.
2. Prefer the current CLI login flow when setting up a new machine: `kaggle auth login` opens the browser-based flow. If the CLI documents a token file for the current version, store it only in the user Kaggle config directory and set restrictive permissions (`chmod 600 ~/.kaggle/access_token`). Do not put it in this repository or a mobile app.
3. Verify without printing secrets by making a read-only request: `kaggle kernels list --page-size 1`.
4. If authentication fails, inspect CLI help (`kaggle auth --help`, `kaggle kernels list --help`) and current [Kaggle API documentation](https://www.kaggle.com/docs/api). Do not dump environment variables or token files for debugging.

## Windows setup

1. Install Python and the supported Kaggle CLI in a virtual environment: `py -m venv .venv`, then activate with `\.venv\Scripts\Activate.ps1` in PowerShell.
2. Run `python -m pip install kaggle` and `kaggle --version`.
3. Run `kaggle auth login` and complete the browser flow, or follow the exact current CLI credential instructions. Keep the credential under the per-user Kaggle configuration directory; restrict access using Windows file ACLs. Never save it beside project source or sync it into a public folder.
4. Verify with `kaggle kernels list --page-size 1`. Avoid commands that print the access token.

If using legacy `kaggle.json`, follow the CLI's current documented path and restrictive file permissions for the installed version; do not assume old setup instructions apply unchanged.

## Existing project notebook and inputs

The read-only notebook pull used:

```bash
kaggle kernels pull abdurrehmanzubair/sign-bridge -p /tmp/sign_bridge_kaggle_audit
```

The original notebook references MuteMotion features at `/kaggle/input/datasets/abd0kamel/mutemotion-output/` and private weights/log data under `/kaggle/input/datasets/abdurrehmanzubair/poutput/` or `signbridge-checkpoint-v2`. Its 36-cell source had duplicated export sections and its resume logic inferred the epoch from a CSV while reloading weights only, not optimizer state. It had no saved outputs.

## Reproducible training/export kernel

The project now includes `scripts/train_sign_bridge.py` and a generated, self-contained notebook under `kaggle/sign_bridge_fyp_reproducible/`. Regenerate the notebook after changing the trainer:

```bash
python3 scripts/build_kaggle_training_notebook.py
```

The private kernel metadata attaches `abd0kamel/mutemotion-output` and `abdurrehmanzubair/signbridge-checkpoint-v2`, requests a GPU, and disables Internet access. The notebook fine-tunes the supplied checkpoint for up to 80 epochs by default. Outputs include the model, label vectors, training log/curve, official-split dataset summary, held-out top-1/top-5 and macro/per-class metrics, confusion matrix, export parity validation, and TFLite CPU latency.

Set `INITIAL_WEIGHTS = None` in the notebook to train the same model from random initialization. The `BackupAndRestore` callback saves optimizer and training state if an active run is interrupted; the H5 checkpoint is initialization only and contains no optimizer state. The official split does not establish signer-disjointness.

Kaggle CLI 2.2.4 `kernels push --help` does not expose `--no-run` (although newer CLI documentation does). Pushing this new private kernel submits it for execution. Only submit it when the inputs are accessible and GPU quota is available. Download outputs with `kaggle kernels output abdurrehmanzubair/sign-bridge-fyp-reproducible -p <destination>`. Keep the kernel private because it depends on private checkpoint data. Do not commit checkpoints or large data to Git.

## Completed run (2026-10-18)

Private kernel version 1 completed 80 epochs in a GPU runtime where two Tesla T4 devices were visible. The trainer did not configure mirrored multi-GPU training, so it does not claim that both devices were used. It produced 2,770 train, 748 validation and 560 test samples over 351 labels after the trainer's dataset filters. Held-out Keras top-1/top-5 were 26.25%/40.89%; macro-F1 was 19.41%. The exported 3.02 MB TFLite model had `[1,64,180,3] → [1,300]` tensors and max absolute parity error 0.001083. Downloaded metrics, confusion matrix, per-class metrics, curves, logs, checkpoint and TFLite export are saved locally under the gitignored `artifacts/kaggle_run_2026-10-18/`; the app TFLite was tested against its prior version on the same held-out features and the improved export was integrated. No raw dataset or feature cache is intended to be retained in that artifact directory.

The initial unfiltered `kaggle kernels output` request included the remote feature cache. It was stopped, and the deliverables were downloaded with an anchored filename filter. For a future download, use a pattern anchored to the output file's basename so it does not match all files inside `sign_bridge_export/feature_cache/`:

```bash
kaggle kernels output abdurrehmanzubair/sign-bridge-fyp-reproducible \
  -p /path/to/output \
  --file-pattern '(^|/)(evaluation\.json|export_validation\.json|dataset_summary\.json|labels\.json|best_signbridge\.weights\.h5|sign_bridge\.tflite|training_curves\.png|training_log\.csv|per_class_metrics\.csv|confusion_matrix\.csv)$'
```

The training run used the supplied private initialization checkpoint whose license metadata is unknown. Keep the model/checkpoint private until its terms and the applicable WLASL restrictions are confirmed. The current model improved over the prior app export on the same official test feature cache; this does not establish signer-disjoint or real-user accuracy.

#!/usr/bin/env python3
"""Generate the self-contained Kaggle notebook from train_sign_bridge.py."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts' / 'train_sign_bridge.py'
OUT = ROOT / 'kaggle' / 'sign_bridge_fyp_reproducible'
OUT.mkdir(parents=True, exist_ok=True)

source = SCRIPT.read_text()
cells = [
    {
        'cell_type': 'markdown', 'id': 'overview', 'metadata': {},
        'source': [
            '# Sign Bridge FYP — Reproducible WLASL landmark model\n',
            '\n',
            'This notebook prepares the existing Sign Bridge embedding model for mobile export. '
            'It preserves the app contract `[1,64,180,3] -> [1,300]`, loads the already trained '
            'checkpoint when supplied, continues training with the MuteMotion/WLASL official split '
            'fields, evaluates only on the held-out test partition, and exports a built-ins-only '
            'TFLite model plus label vectors and evidence.\n',
            '\n',
            '**Inputs:** attach `abd0kamel/mutemotion-output` and '
            '`abdurrehmanzubair/signbridge-checkpoint-v2`. Check the WLASL C-UDA and checkpoint '
            'rights before redistributing outputs. The notebook does not publish data.\n',
            '\n',
            '**Limits:** reported test metrics describe this dataset split; signer-disjointness is '
            'not established. This trains an isolated-word embedding retriever, not continuous ASL '
            'translation. GPU availability is printed and training remains compatible with CPU.\n',
        ],
    },
    {
        'cell_type': 'code', 'id': 'trainer-source', 'execution_count': None,
        'metadata': {}, 'outputs': [],
        'source': ['%%writefile /kaggle/working/train_sign_bridge.py\n']
        + [line + '\n' for line in source.splitlines()],
    },
    {
        'cell_type': 'markdown', 'id': 'run-guide', 'metadata': {},
        'source': ['## Configure and run\n',
                   'The defaults fine-tune the attached checkpoint for up to 80 epochs. '
                   'Set `INITIAL_WEIGHTS = None` to train the same architecture from scratch. '
                   'The Kaggle working output contains the export, evaluation, per-class metrics, '
                   'confusion matrix, training log and feature cache.\n'],
    },
    {
        'cell_type': 'code', 'id': 'train-and-export', 'execution_count': None,
        'metadata': {}, 'outputs': [],
        'source': [
            'from pathlib import Path\n',
            'import subprocess, sys\n',
            '\n',
            "DATA_DIR = Path('/kaggle/input/datasets/abd0kamel/mutemotion-output')\n",
            "CHECKPOINT = Path('/kaggle/input/datasets/abdurrehmanzubair/signbridge-checkpoint-v2/best_signbridge.weights.h5')\n",
            "OUTPUT_DIR = Path('/kaggle/working/sign_bridge_export')\n",
            'EPOCHS = 80\n',
            'BATCH_SIZE = 32\n',
            'INITIAL_WEIGHTS = CHECKPOINT if CHECKPOINT.is_file() else None\n',
            '\n',
            "required = ['landmarks_V3.npz', 'labels.npz', 'WLASL_parsed_data.json', 'filtered_labels.txt']\n",
            'missing = [name for name in required if not (DATA_DIR / name).is_file()]\n',
            'if missing:\n',
            "    raise FileNotFoundError(f'Missing MuteMotion inputs in {DATA_DIR}: {missing}')\n",
            "print('GPU(s):', __import__('tensorflow').config.list_physical_devices('GPU'))\n",
            "command = [sys.executable, '/kaggle/working/train_sign_bridge.py', '--data-dir', str(DATA_DIR), '--output-dir', str(OUTPUT_DIR), '--epochs', str(EPOCHS), '--batch-size', str(BATCH_SIZE)]\n",
            'if INITIAL_WEIGHTS is not None:\n',
            "    command += ['--initial-weights', str(INITIAL_WEIGHTS)]\n",
            'print("Running:", " ".join(command))\n',
            'subprocess.run(command, check=True)\n',
            '\n',
            "print('Validated deliverables:', sorted(path.name for path in OUTPUT_DIR.iterdir() if path.is_file()))\n",
        ],
    },
]

notebook = {
    'cells': cells,
    'metadata': {
        'kernelspec': {'display_name': 'Python 3', 'language': 'python', 'name': 'python3'},
        'language_info': {'name': 'python', 'version': '3.12'},
    },
    'nbformat': 4,
    'nbformat_minor': 5,
}
(OUT / 'sign_bridge_fyp_reproducible.ipynb').write_text(json.dumps(notebook, indent=1) + '\n')
(OUT / 'kernel-metadata.json').write_text(json.dumps({
    'id': 'abdurrehmanzubair/sign-bridge-fyp-reproducible',
    'title': 'Sign Bridge FYP Reproducible',
    'code_file': 'sign_bridge_fyp_reproducible.ipynb',
    'language': 'python',
    'kernel_type': 'notebook',
    'is_private': True,
    'enable_gpu': True,
    'enable_tpu': False,
    'enable_internet': False,
    'dataset_sources': [
        'abd0kamel/mutemotion-output',
        'abdurrehmanzubair/signbridge-checkpoint-v2',
    ],
    'kernel_sources': [],
    'competition_sources': [],
    'model_sources': [],
}, indent=2) + '\n')
print(f'Generated Kaggle kernel source in {OUT}')

# =============================================================================
# SIGN BRIDGE — STANDALONE Flex-free TFLite export
# =============================================================================
# WHAT THIS DOES
#   Rebuilds your trained GRU model with unroll=True (so it converts to pure
#   built-in TFLite ops — no Flex), loads your existing checkpoint weights, and
#   exports a Flex-free sign_bridge.tflite that tflite_flutter CAN run.
#
# HOW TO RUN (easiest path — no re-training, ~1 minute)
#   1. Open the notebook editor:
#        https://www.kaggle.com/code/abdurrehmanzubair/sign-bridge  ->  "Edit"
#   2. In the right panel "Input", make sure this dataset is attached:
#        abdurrehmanzubair/signbridge-checkpoint-v2   (your trained weights)
#      (You do NOT need the mutemotion dataset for this — labels.json is
#       unchanged, we already have it in the app.)
#   3. Add a NEW cell at the very bottom, paste THIS ENTIRE FILE into it, Run it.
#   4. When it finishes it prints "Flex ops remaining: NONE" and shows a
#      download link. Click the link to download sign_bridge.tflite.
#   5. Put that file at:  <project>/assets/ml/sign_bridge.tflite   (replace the
#      old one), then tell me — I'll rebuild and test on your phone.
# =============================================================================

import os
os.environ['CUDA_VISIBLE_DEVICES'] = ''          # CPU export (avoids CudnnRNN)

import numpy as np
import tensorflow as tf
print('TF version:', tf.__version__)

# ── Config (must match training exactly) ─────────────────────────────────────
DESIRED_FRAMES  = 64
TOTAL_LANDMARKS = 180
COORDS          = 3
OUTPUT_DIM      = 300

CHECKPOINT_DIR = '/kaggle/input/signbridge-checkpoint-v2'
# Kaggle sometimes mounts under /kaggle/input/datasets/<user>/<slug>; handle both.
_cands = [
    os.path.join(CHECKPOINT_DIR, 'best_signbridge.weights.h5'),
    '/kaggle/input/datasets/abdurrehmanzubair/signbridge-checkpoint-v2/best_signbridge.weights.h5',
]
best_weights = next((p for p in _cands if os.path.exists(p)), None)
if best_weights is None:
    # last resort: search for it
    for root, _, files in os.walk('/kaggle/input'):
        for f in files:
            if f == 'best_signbridge.weights.h5':
                best_weights = os.path.join(root, f)
assert best_weights and os.path.exists(best_weights), \
    'Could not find best_signbridge.weights.h5 — attach the signbridge-checkpoint-v2 dataset.'
print('Using weights:', best_weights)

EXPORT_DIR = '/kaggle/working/sign_bridge_export'
os.makedirs(EXPORT_DIR, exist_ok=True)

tf.keras.backend.clear_session()


def build_gru_model_unrolled():
    inputs = tf.keras.Input(
        shape=(DESIRED_FRAMES, TOTAL_LANDMARKS, COORDS), name='landmarks')

    x = tf.keras.layers.Reshape(
        (DESIRED_FRAMES, TOTAL_LANDMARKS * COORDS), name='reshape')(inputs)
    x = tf.keras.layers.TimeDistributed(
        tf.keras.layers.Dense(256, activation='relu'), name='frame_proj')(x)
    x = tf.keras.layers.TimeDistributed(
        tf.keras.layers.LayerNormalization(), name='frame_norm')(x)
    x = tf.keras.layers.Dropout(0.2, name='frame_drop')(x)

    # unroll=True -> static graph, no TensorList/While -> no Flex ops.
    # dropout/recurrent_dropout only affect training, so we omit them here;
    # the trained weights are identical and load by layer name.
    x = tf.keras.layers.Bidirectional(
        tf.keras.layers.GRU(256, return_sequences=True, unroll=True),
        name='bigru_1')(x)
    x = tf.keras.layers.LayerNormalization(name='ln_1')(x)
    x = tf.keras.layers.Bidirectional(
        tf.keras.layers.GRU(128, return_sequences=True, unroll=True),
        name='bigru_2')(x)
    x = tf.keras.layers.LayerNormalization(name='ln_2')(x)

    scores  = tf.keras.layers.TimeDistributed(
        tf.keras.layers.Dense(1), name='attn_score')(x)
    weights = tf.keras.layers.Softmax(axis=1, name='attn_weights')(scores)
    x       = tf.keras.layers.Multiply(name='attn_apply')([x, weights])
    x       = tf.keras.layers.Lambda(
        lambda t: tf.reduce_sum(t, axis=1), name='attn_pool')(x)

    x = tf.keras.layers.Dense(512, activation='relu', name='head_1')(x)
    x = tf.keras.layers.Dropout(0.4, name='drop_1')(x)
    x = tf.keras.layers.Dense(256, activation='relu', name='head_2')(x)
    x = tf.keras.layers.Dropout(0.3, name='drop_2')(x)
    x = tf.keras.layers.Dense(OUTPUT_DIM, activation='linear', name='output_vec')(x)
    outputs = tf.keras.layers.Lambda(
        lambda t: tf.math.l2_normalize(t, axis=-1), name='l2_norm')(x)

    return tf.keras.Model(inputs, outputs, name='SignBridge_GRU')


with tf.device('/CPU:0'):
    model = build_gru_model_unrolled()
    model.load_weights(best_weights)
    dummy = np.zeros((1, DESIRED_FRAMES, TOTAL_LANDMARKS, COORDS), dtype=np.float32)
    out = model.predict(dummy, verbose=0)
    print('Keras output shape:', out.shape,
          '| L2 norm (≈1.0 expected):', float(np.linalg.norm(out)))

# ── Convert: builtins only, no SELECT_TF_OPS ─────────────────────────────────
converter = tf.lite.TFLiteConverter.from_keras_model(model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]        # dynamic-range quant
converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS]
tflite_model = converter.convert()

tflite_path = os.path.join(EXPORT_DIR, 'sign_bridge.tflite')
with open(tflite_path, 'wb') as f:
    f.write(tflite_model)
print(f'\nsign_bridge.tflite written: {os.path.getsize(tflite_path)/1e6:.2f} MB')

# ── Verify: no Flex ops + real inference ─────────────────────────────────────
interp = tf.lite.Interpreter(model_path=tflite_path)
interp.allocate_tensors()
inp = interp.get_input_details()[0]
outp = interp.get_output_details()[0]
print('Input :', inp['shape'], inp['dtype'])     # [1,64,180,3] float32
print('Output:', outp['shape'], outp['dtype'])   # [1,300] float32
try:
    op_names = {d['op_name'] for d in interp._get_ops_details()}
    flex = sorted(o for o in op_names if 'Flex' in o)
    print('Flex ops remaining:', flex if flex else 'NONE ✅  (good — tflite_flutter can run this)')
except Exception as e:
    print('op-detail check skipped:', e)

interp.set_tensor(inp['index'], dummy)
interp.invoke()
tout = interp.get_tensor(outp['index'])
print('TFLite output norm (≈1.0 expected):', float(np.linalg.norm(tout)))

# ── Download link ────────────────────────────────────────────────────────────
try:
    from IPython.display import FileLink, display
    print('\n⬇️  Click to download, then replace assets/ml/sign_bridge.tflite:')
    display(FileLink(tflite_path))
except Exception:
    print('\nDownload from the Output panel: sign_bridge_export/sign_bridge.tflite')

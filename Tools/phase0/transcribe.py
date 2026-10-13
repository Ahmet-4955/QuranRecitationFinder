"""Phase 0 – Alle Clips mit den Kandidatenmodellen transkribieren.

Ergebnisse werden in results/transcripts.json zwischengespeichert;
ein erneuter Aufruf macht nur fehlende Clips (z. B. neue eigene Aufnahmen).

Aufruf:  python transcribe.py
         python transcribe.py --models tarteel-ai/whisper-tiny-ar-quran
         python transcribe.py --models tarteel-ai/whisper-base-ar-quran openai/whisper-base
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

from clip_manifest import load_clips

ROOT = Path(__file__).resolve().parent
RESULTS = ROOT / "results"
CACHE = RESULTS / "transcripts.json"
SR = 16000
DEFAULT_MODELS = ["tarteel-ai/whisper-tiny-ar-quran", "tarteel-ai/whisper-base-ar-quran"]


def pick_device():
    import torch

    if torch.backends.mps.is_available():
        return "mps"
    if torch.cuda.is_available():
        return "cuda"
    return "cpu"


class WhisperRunner:
    def __init__(self, model_id: str, device: str):
        from transformers import WhisperForConditionalGeneration, WhisperProcessor

        self.processor = WhisperProcessor.from_pretrained(model_id)
        self.model = WhisperForConditionalGeneration.from_pretrained(model_id).to(device).eval()
        self.device = device
        self._lang_kwargs = {"language": "ar", "task": "transcribe"}

    def transcribe(self, audio) -> str:
        import torch

        features = self.processor(audio, sampling_rate=SR, return_tensors="pt").input_features.to(self.device)
        with torch.inference_mode():
            try:
                ids = self.model.generate(features, max_new_tokens=220, **self._lang_kwargs)
            except (ValueError, KeyError, AttributeError, TypeError):
                # ältere Feintuning-Konfigurationen kennen language/task nicht
                self._lang_kwargs = {}
                ids = self.model.generate(features, max_new_tokens=220)
        return self.processor.batch_decode(ids, skip_special_tokens=True)[0].strip()


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--models", nargs="+", default=DEFAULT_MODELS)
    p.add_argument("--device", default=None, help="mps / cpu / cuda (Standard: automatisch)")
    args = p.parse_args()

    import librosa
    import numpy as np

    clips = load_clips()
    if not clips:
        raise SystemExit("Keine Clips gefunden – erst fetch_data.py ausführen bzw. clips/own/manifest.csv füllen.")
    RESULTS.mkdir(exist_ok=True)
    cache = json.loads(CACHE.read_text(encoding="utf-8")) if CACHE.exists() else {}
    device = args.device or pick_device()
    print(f"Gerät: {device} | Clips: {len(clips)}")

    audio_cache = {}
    for model_id in args.models:
        done = cache.setdefault(model_id, {})
        todo = [c for c in clips if c["id"] not in done]
        if not todo:
            print(f"✓ {model_id}: alles transkribiert")
            continue
        print(f"→ {model_id}: {len(todo)} Clips")
        runner = WhisperRunner(model_id, device)
        runner.transcribe(np.zeros(SR, dtype=np.float32))  # Aufwärmen
        for i, clip in enumerate(todo, 1):
            if clip["path"] not in audio_cache:
                audio, _ = librosa.load(clip["path"], sr=SR, mono=True)
                if len(audio) > 30 * SR:
                    print(f"  ⚠ {clip['id']} länger als 30 s – nur die ersten 30 s werden genutzt")
                    audio = audio[: 30 * SR]
                audio_cache[clip["path"]] = audio
            audio = audio_cache[clip["path"]]
            t0 = time.perf_counter()
            text = runner.transcribe(audio)
            elapsed = time.perf_counter() - t0
            done[clip["id"]] = {"text": text, "seconds": round(elapsed, 3), "audio_seconds": round(len(audio) / SR, 2)}
            print(f"  [{i}/{len(todo)}] {clip['id']} ({elapsed:.2f} s): {text[:70]}")
            if i % 10 == 0:
                CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=1), encoding="utf-8")
        CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"✓ Gespeichert: {CACHE.relative_to(ROOT)}")


if __name__ == "__main__":
    main()

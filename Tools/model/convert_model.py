"""Phase 3 – Tarteel-Whisper-Modell für das iPhone umwandeln (Core ML / WhisperKit).

Läuft auf dem Mac in der whisperkittools-Umgebung (siehe README.md).

Ablauf:
1. Modell von Hugging Face laden (tarteel-ai/whisper-<größe>-ar-quran)
2. Fehlende `alignment_heads` aus dem OpenAI-Grundmodell ergänzen
   (sonst bricht die Umwandlung ab: "Number of outputs ... 4 ... 3")
3. whisperkit-generate-model ausführen → *.mlmodelc
4. Ordner Models/WhisperModel/ für die App zusammenstellen:
   Modelle + config.json + generation_config.json + tokenizer.json (offline nutzbar)
   + model-info.json (Name, Quelle, Lizenz für die App-Anzeige)

Aufruf:  python convert_model.py --size base
         python convert_model.py --size tiny
"""

from __future__ import annotations

import argparse
import glob
import json
import platform
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
WORK = Path(__file__).resolve().parent / "work"
TARGET = REPO / "Models" / "WhisperModel"
MODELS = {
    "tiny": ("tarteel-ai/whisper-tiny-ar-quran", "openai/whisper-tiny"),
    "base": ("tarteel-ai/whisper-base-ar-quran", "openai/whisper-base"),
}
REQUIRED = ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc"]
OPTIONAL = ["TextDecoderContextPrefill.mlmodelc"]


def check_environment() -> None:
    if platform.system() != "Darwin":
        sys.exit("✗ Die Core-ML-Umwandlung läuft nur auf macOS.")
    if sys.version_info >= (3, 13):
        sys.exit("✗ Python 3.13 wird von whisperkittools (torch 2.5) nicht unterstützt – Python 3.11 verwenden.")
    if shutil.which("whisperkit-generate-model") is None:
        sys.exit("✗ whisperkit-generate-model nicht gefunden – whisperkittools installieren (README.md, Schritt 1).")


def download_source(model_id: str) -> Path:
    from huggingface_hub import snapshot_download

    target = WORK / "source" / model_id.replace("/", "_")
    print(f"↓ {model_id}")
    snapshot_download(repo_id=model_id, local_dir=target)
    return target


def patch_generation_config(source: Path, base_id: str) -> None:
    """Fehlende Felder (u. a. alignment_heads) aus dem OpenAI-Grundmodell übernehmen."""
    from huggingface_hub import hf_hub_download

    base = json.loads(Path(hf_hub_download(repo_id=base_id, filename="generation_config.json")).read_text())
    path = source / "generation_config.json"
    config = json.loads(path.read_text()) if path.exists() else {}
    added = []
    for key in ("alignment_heads", "lang_to_id", "task_to_id", "is_multilingual", "no_timestamps_token_id"):
        if key not in config and key in base:
            config[key] = base[key]
            added.append(key)
    path.write_text(json.dumps(config, indent=2))
    print(f"✓ generation_config.json ergänzt: {', '.join(added) or 'nichts nötig'}")


def convert(source: Path) -> Path:
    out = WORK / "out"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    print("→ whisperkit-generate-model (dauert je nach Mac 5–20 Min.) …")
    subprocess.run(
        ["whisperkit-generate-model", "--model-version", str(source), "--output-dir", str(out)],
        check=True,
    )
    # Ausgabeordner heißt wie der Quellpfad mit "_" statt "/" – daher suchen
    hits = glob.glob(str(out / "**" / "AudioEncoder.mlmodelc"), recursive=True)
    if not hits:
        sys.exit("✗ Keine AudioEncoder.mlmodelc erzeugt – Ausgabe oben prüfen.")
    return Path(hits[0]).parent


def assemble(generated: Path, source: Path, model_id: str, size: str) -> None:
    from transformers import WhisperTokenizerFast

    if TARGET.exists():
        shutil.rmtree(TARGET)
    TARGET.mkdir(parents=True)
    for name in REQUIRED + OPTIONAL:
        src = generated / name
        if src.exists():
            shutil.copytree(src, TARGET / name)
        elif name in REQUIRED:
            sys.exit(f"✗ {name} fehlt in {generated}")
    for name in ("config.json", "generation_config.json", "preprocessor_config.json"):
        if (source / name).exists():
            shutil.copy(source / name, TARGET / name)
    # tokenizer.json im Modellordner → WhisperKit braucht kein Internet
    WhisperTokenizerFast.from_pretrained(source).save_pretrained(TARGET)
    if not (TARGET / "tokenizer.json").exists():
        sys.exit("✗ tokenizer.json konnte nicht erzeugt werden.")

    commit = subprocess.run(["pip", "show", "whisperkittools"], capture_output=True, text=True).stdout
    version = next((line.split(":", 1)[1].strip() for line in commit.splitlines() if line.startswith("Version")), "?")
    info = {
        "displayName": f"Tarteel Whisper {size}",
        "model": model_id,
        "size": size,
        "license": "Apache-2.0",
        "sourceURL": f"https://huggingface.co/{model_id}",
        "convertedWith": f"whisperkittools {version}",
        "convertedAt": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
    }
    (TARGET / "model-info.json").write_text(json.dumps(info, indent=2, ensure_ascii=False))
    total = sum(f.stat().st_size for f in TARGET.rglob("*") if f.is_file())
    print(f"✓ {TARGET.relative_to(REPO)} ({total / 1e6:.0f} MB)")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--size", choices=sorted(MODELS), required=True, help="Ergebnis aus Phase 0")
    args = p.parse_args()
    check_environment()
    model_id, base_id = MODELS[args.size]
    source = download_source(model_id)
    patch_generation_config(source, base_id)
    generated = convert(source)
    assemble(generated, source, model_id, args.size)
    print("Weiter mit README.md, Schritt 3 (Ordner in Xcode einbinden).")


if __name__ == "__main__":
    main()

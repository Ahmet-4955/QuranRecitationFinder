"""Offline-Tests für convert_model.py (Hugging Face, whisperkittools und Tokenizer simuliert)."""

import json
import sys
import types
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import convert_model as cm  # noqa: E402

BASE_GEN_CONFIG = {
    "alignment_heads": [[3, 1], [4, 2]],
    "lang_to_id": {"<|ar|>": 50272},
    "task_to_id": {"transcribe": 50359},
    "is_multilingual": True,
}


@pytest.fixture
def fake_hub(tmp_path, monkeypatch):
    base_file = tmp_path / "base_generation_config.json"
    base_file.write_text(json.dumps(BASE_GEN_CONFIG))
    hub = types.ModuleType("huggingface_hub")
    hub.hf_hub_download = lambda repo_id, filename: str(base_file)
    monkeypatch.setitem(sys.modules, "huggingface_hub", hub)

    class FakeTokenizer:
        @classmethod
        def from_pretrained(cls, path):
            return cls()

        def save_pretrained(self, target):
            (Path(target) / "tokenizer.json").write_text("{}")
            (Path(target) / "tokenizer_config.json").write_text("{}")

    tf = types.ModuleType("transformers")
    tf.WhisperTokenizerFast = FakeTokenizer
    monkeypatch.setitem(sys.modules, "transformers", tf)
    return tmp_path


def test_patch_adds_missing_alignment_heads(fake_hub):
    source = fake_hub / "source"
    source.mkdir()
    (source / "generation_config.json").write_text(json.dumps({"max_length": 448, "is_multilingual": False}))
    cm.patch_generation_config(source, "openai/whisper-base")
    patched = json.loads((source / "generation_config.json").read_text())
    assert patched["alignment_heads"] == [[3, 1], [4, 2]]
    assert patched["lang_to_id"]["<|ar|>"] == 50272
    assert patched["is_multilingual"] is False  # vorhandene Werte bleiben unverändert
    assert patched["max_length"] == 448


def test_patch_creates_config_if_missing(fake_hub):
    source = fake_hub / "source2"
    source.mkdir()
    cm.patch_generation_config(source, "openai/whisper-tiny")
    assert "alignment_heads" in json.loads((source / "generation_config.json").read_text())


def test_assemble_builds_offline_model_folder(fake_hub, monkeypatch):
    generated = fake_hub / "out" / "_Users_x_work_source_tarteel-ai_whisper-base-ar-quran"
    for name in cm.REQUIRED:
        (generated / name / "weights").mkdir(parents=True)
        (generated / name / "weights" / "weight.bin").write_bytes(b"0" * 10)
    source = fake_hub / "src"
    source.mkdir()
    (source / "config.json").write_text("{}")
    (source / "generation_config.json").write_text("{}")
    target = fake_hub / "Models" / "WhisperModel"
    monkeypatch.setattr(cm, "TARGET", target)
    monkeypatch.setattr(cm, "REPO", fake_hub)

    cm.assemble(generated, source, "tarteel-ai/whisper-base-ar-quran", "base")

    names = {p.name for p in target.iterdir()}
    assert set(cm.REQUIRED) <= names
    assert {"config.json", "generation_config.json", "tokenizer.json", "model-info.json"} <= names
    info = json.loads((target / "model-info.json").read_text())
    assert info["displayName"] == "Tarteel Whisper base"
    assert info["license"] == "Apache-2.0"
    assert (target / "AudioEncoder.mlmodelc" / "weights" / "weight.bin").exists()


def test_assemble_fails_without_required_model(fake_hub, monkeypatch):
    generated = fake_hub / "out2"
    (generated / "AudioEncoder.mlmodelc").mkdir(parents=True)
    monkeypatch.setattr(cm, "TARGET", fake_hub / "M" / "WhisperModel")
    with pytest.raises(SystemExit) as e:
        cm.assemble(generated, fake_hub, "tarteel-ai/whisper-tiny-ar-quran", "tiny")
    assert "TextDecoder.mlmodelc" in str(e.value)

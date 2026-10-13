"""Tests für calibrate.py mit erzeugten Messdaten."""

import csv
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import calibrate as cal  # noqa: E402


def _phase0_csv(path: Path) -> Path:
    rows = []
    # simple-clean: sauber getrennt (richtig ≥ 0.7, falsch ≤ 0.5); uthmani: schlechter
    for i in range(30):
        rows.append(["m", "simple-clean", f"c{i}", "own", "x", "1:1", "1:1", 0.7 + i * 0.01, True, True, "a b c d"])
        rows.append(["m", "uthmani", f"c{i}", "own", "x", "1:1", "1:1", 0.5 + i * 0.01, i % 3 != 0, True, "a b c d"])
    for i in range(5):
        rows.append(["m", "simple-clean", f"w{i}", "own", "x", "1:1", "2:2", 0.4 + i * 0.02, False, False, "a b"])
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["model", "edition", "id", "category", "speaker", "truth", "pred", "score", "top1", "top3", "transcript"])
        w.writerows(rows)
    return path


def _app_json(path: Path) -> Path:
    records = [
        {"verdict": "correct", "candidates": [{"ref": "1:1", "score": 0.9}], "wordCount": 6},
        {"verdict": "wrong", "candidates": [{"ref": "2:2", "score": 0.45}], "wordCount": 2},
        {"verdict": "unrated", "candidates": [{"ref": "3:3", "score": 0.99}], "wordCount": 5},
        {"verdict": "wrong", "candidates": [], "wordCount": 0},
    ]
    path.write_text(json.dumps(records), encoding="utf-8")
    return path


def test_app_export_uses_only_rated_records(tmp_path):
    samples = cal.load_app(_app_json(tmp_path / "a.json"))
    assert [(s.score, s.correct) for s in samples] == [(0.9, True), (0.45, False)]


def test_recommendation_separates_correct_from_wrong():
    samples = [cal.Sample(0.8, True, "t")] * 20 + [cal.Sample(0.45, False, "t")] * 5
    best = cal.recommend(cal.table(samples), 0.95)
    assert 0.45 < best["threshold"] <= 0.8
    assert best["precision"] == 1.0
    assert best["recall"] == 0.8  # Trefferquote bezogen auf alle Messpunkte (20 von 25 richtig)


def test_no_recommendation_when_target_unreachable():
    samples = [cal.Sample(0.9, i % 2 == 0, "t") for i in range(30)]
    assert cal.recommend(cal.table(samples), 0.95) is None


def test_writes_config_and_picks_better_edition(tmp_path, monkeypatch):
    config = tmp_path / "recognition-config.json"
    config.write_text(json.dumps({"acceptThreshold": 0.6, "tieMargin": 0.01}), encoding="utf-8")
    monkeypatch.setattr(cal, "CONFIG", config)
    monkeypatch.setattr(cal, "REPO", tmp_path)
    monkeypatch.setattr(sys, "argv", ["calibrate.py", "--phase0", str(_phase0_csv(tmp_path / "d.csv")), "--model", "m"])
    cal.main()
    written = json.loads(config.read_text())
    assert written["edition"] == "simpleClean"
    assert written["acceptThreshold"] == 0.5  # höher als der beste Fehltreffer (0.48), ohne Treffer zu verlieren
    assert written["tieMargin"] == 0.01  # unveränderte Felder bleiben erhalten
    assert "Phase 0" in written["calibrationNote"]


def test_dry_run_does_not_write(tmp_path, monkeypatch):
    config = tmp_path / "recognition-config.json"
    monkeypatch.setattr(cal, "CONFIG", config)
    monkeypatch.setattr(sys, "argv", ["calibrate.py", "--phase0", str(_phase0_csv(tmp_path / "d.csv")), "--dry-run"])
    cal.main()
    assert not config.exists()


def test_unknown_model_lists_available(tmp_path, monkeypatch):
    monkeypatch.setattr(sys, "argv", ["calibrate.py", "--phase0", str(_phase0_csv(tmp_path / "d.csv")), "--model", "x"])
    with pytest.raises(SystemExit) as e:
        cal.main()
    assert "m" in str(e.value)

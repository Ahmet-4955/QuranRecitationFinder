"""Tests für Tools/l10n/check_strings.py."""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_strings as cs  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]


def unit(v):
    return {"stringUnit": {"state": "translated", "value": v}}


def catalog(entries):
    return {"sourceLanguage": "en", "version": "1.0",
            "strings": {k: {"localizations": {"de": unit(d), "tr": unit(t)}} for k, (d, t) in entries.items()}}


def test_extracts_swiftui_and_nslocalized():
    src = '''
    Text("Hello")
    Label("Share", systemImage: "square")
    .navigationTitle("Settings")
    let s = NSLocalizedString("Match: %@", comment: "")
    Text(verbatim: "1:1")
    Text(title)
    // Text("Kommentar")
    Text("1 / 2")
    '''
    keys, problems = cs.extract(src)
    assert keys == {"Hello", "Share", "Settings", "Match: %@"}
    assert problems == []


def test_flags_interpolation_and_ternary():
    _, problems = cs.extract('Text("Score \\(x) %")\n.accessibilityLabel(on ? "Stop" : "Start")')
    assert len(problems) == 2
    assert "Interpolation" in problems[0]
    assert "ternär" in problems[1]


def test_question_mark_inside_literal_is_not_ternary():
    _, problems = cs.extract('.confirmationDialog("Delete all?", isPresented: $x)')
    assert problems == []


def test_catalog_missing_stale_and_placeholders():
    cat = catalog({"Hello": ("Hallo", "Merhaba"), "Old": ("Alt", "Eski"), "Match: %@": ("Treffer", "Eşleşme: %@")})
    problems = cs.check_catalog(cat, {"Hello", "Match: %@", "New"})
    text = "\n".join(problems)
    assert 'fehlt im Katalog: "New"' in text
    assert 'veralteter Eintrag (nicht im Quelltext): "Old"' in text
    assert "[de] Platzhalter passen nicht" in text
    assert "[tr]" not in text


def test_positional_placeholders_may_be_reordered():
    cat = catalog({"%1$@ of %2$@": ("%1$@ von %2$@", "%2$@ içinde %1$@")})
    assert cs.check_catalog(cat, {"%1$@ of %2$@"}) == []


def test_empty_translation_is_reported():
    cat = catalog({"Hello": ("", "Merhaba")})
    assert any("[de] keine Übersetzung" in p for p in cs.check_catalog(cat, {"Hello"}))


def test_repository_is_fully_translated():
    keys, problems = cs.collect(ROOT)
    assert problems == []
    cat = json.loads((ROOT / cs.CATALOG).read_text(encoding="utf-8"))
    assert cs.check_catalog(cat, keys) == []
    assert cs.main(["--root", str(ROOT)]) == 0

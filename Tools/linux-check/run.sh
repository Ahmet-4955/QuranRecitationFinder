#!/usr/bin/env bash
# Kompiliert den plattformunabhängigen App-Kern mit Swift 6.2 unter Linux (Docker)
# und führt die zugehörigen Swift-Tests mit echten Daten aus.
#
# Geprüft: Core/Quran, Core/Matching, Core/Translation, Core/Recognition, Core/Recording, Core/Feedback, QuranLibrary
#          + Tests QuranDataTests, VerseMatcherTests, RecognizerTests, Phase5Tests, Phase6Tests (inkl. Python-Vergleichsfälle)
#          + WhisperKitRecognizer gegen ein Ersatz-Modul mit den Signaturen von WhisperKit v1.1.1
#          + Ablaufsteuerung (RecognitionViewModel), Einstellungen, Verlauf – mit Combine-Ersatz
#            + Tests RecognitionFlowTests, AppSettingsTests (simuliertes Mikrofon)
# Nicht geprüft (gibt es unter Linux nicht): SwiftUI-Oberfläche, AVFoundation-Aufnahme → Xcode
#
# Aufruf:  Tools/linux-check/run.sh [Ressourcen-Ordner] [--swift6]
#          Ressourcen-Ordner: Standard QuranRecitationFinder/Resources (aus Tools/data/build_resources.py)
#          --swift6: zusätzlich im strengen Swift-6-Sprachmodus übersetzen (Warnungen sichtbar machen)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
RESOURCES="${1:-$REPO/QuranRecitationFinder/Resources}"
MODE="${2:-}"
IMAGE="swift:6.2-noble"
BUILD="$(mktemp -d)"
# Der Container schreibt .build als root – deshalb im Container löschen; Aufräumfehler
# dürfen das Testergebnis nicht verändern.
cleanup() {
  docker run --rm -v "$BUILD:/work" "$IMAGE" rm -rf /work/.build >/dev/null 2>&1 || true
  rm -rf "$BUILD" 2>/dev/null || true
}
trap cleanup EXIT

[[ -f "$RESOURCES/Quran/quran-uthmani.xml" ]] || { echo "✗ Ressourcen fehlen: $RESOURCES (erst Tools/data/build_resources.py)"; exit 1; }

SRC="$BUILD/Sources/QuranRecitationFinder"
TST="$BUILD/Tests/CoreTests"
mkdir -p "$SRC" "$TST/Resources"
APP="$REPO/QuranRecitationFinder"
cp -R "$APP/Core/Quran" "$APP/Core/Matching" "$APP/Core/Translation" "$APP/Core/Recognition" "$APP/Core/Recording" "$SRC/"
cp "$APP/Core/QuranLibrary.swift" "$APP/Core/Settings/TranslationLanguage.swift" "$SRC/"
mkdir -p "$SRC/Feedback" && cp "$APP/Core/Feedback/FeedbackLog.swift" "$SRC/Feedback/"
# Ablaufsteuerung + Einstellungen + Verlauf (brauchen Combine → Ersatz-Modul)
cp "$APP/Core/Audio/AudioCapturing.swift" "$APP/Core/Settings/AppSettings.swift" "$APP/Core/History/HistoryStore.swift" \
   "$APP/Features/Recognize/RecognitionViewModel.swift" "$SRC/"

for f in QuranDataTests NormalizerFixtures VerseMatcherTests MatcherFixtures RecognizerTests Phase5Tests Phase6Tests \
         RecognitionFlowTests AppSettingsTests; do
  # Im Xcode-Test liegen die Daten im App-Bundle (.main), hier im Test-Bundle (.module)
  sed -e 's/from: \.main/from: .module/g' -e 's/bundle: \.main/bundle: .module/g' -e 's/in: \.main/in: .module/g' \
    "$REPO/QuranRecitationFinderTests/$f.swift" > "$TST/$f.swift"
done
cp -R "$RESOURCES/Quran" "$RESOURCES/Translations" "$TST/Resources/"
# Ersatz-Modul WhisperKit (Signaturen aus v1.1.1), damit WhisperKitRecognizer mitkompiliert wird
mkdir -p "$BUILD/Sources/WhisperKit" "$BUILD/Sources/Combine"
cp "$REPO/Tools/linux-check/stubs/WhisperKit/WhisperKit.swift" "$BUILD/Sources/WhisperKit/"
cp "$REPO/Tools/linux-check/stubs/Combine/Combine.swift" "$BUILD/Sources/Combine/"
cp "$REPO/Tools/linux-check/tests/"*.swift "$TST/"

LANGMODE=".v5"   # wie im Xcode-Projekt (SWIFT_VERSION = 5.0)
[[ "$MODE" == "--swift6" ]] && LANGMODE=".v6"
cat > "$BUILD/Package.swift" <<EOF
// swift-tools-version: 6.2
import PackageDescription

// Einstellungen wie im Xcode-Projekt: Standard-Isolation MainActor, "Approachable Concurrency"
let settings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "QuranRecitationFinderCore",
    targets: [
        .target(name: "WhisperKit", path: "Sources/WhisperKit"),
        .target(name: "Combine", path: "Sources/Combine"),
        .target(name: "QuranRecitationFinder", dependencies: ["WhisperKit", "Combine"], path: "Sources/QuranRecitationFinder",
                swiftSettings: settings),
        .testTarget(name: "CoreTests", dependencies: ["QuranRecitationFinder", "WhisperKit"], path: "Tests/CoreTests",
                    resources: [.copy("Resources")]),
    ],
    swiftLanguageModes: [$LANGMODE]
)
EOF

echo "→ Swift 6.2 ($LANGMODE) in Docker: Kompilieren + Tests …"
docker run --rm -v "$BUILD:/work" -w /work "$IMAGE" swift test ${SWIFT_TEST_ARGS:-} 2>&1 | tee "$BUILD/log.txt" | grep -Ev "^\[[0-9]+/[0-9]+\] (Compiling|Emitting|Write|Planning)" || true
WARN=$(grep -c "warning:" "$BUILD/log.txt" || true)
if [[ "$WARN" != "0" ]]; then echo "⚠ $WARN Warnungen:"; grep "warning:" "$BUILD/log.txt" | sed "s|/work/||" | sort -u; fi
grep -qE "Test run with .* passed|✔ Test run" "$BUILD/log.txt" && echo "✓ Kern kompiliert, alle Tests bestanden" && exit 0
echo "✗ Fehler – siehe Ausgabe oben"
exit 1

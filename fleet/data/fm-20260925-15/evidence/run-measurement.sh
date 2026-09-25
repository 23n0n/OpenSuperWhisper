#!/bin/bash
# fm-20260925-15 — one run of the bilingual library measurement, detached.
#
# Everything is exported in both forms: dev-run.sh forwards TEST_RUNNER_<name>
# for the multilingual model it discovers itself, and XCTest is what strips the
# prefix for the rest.
set -euo pipefail

WORKTREE="/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-bilingual"
DATA="/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet/data/fm-20260925-15"
APP_SUPPORT="$HOME/Library/Application Support/ru.starmel.OpenSuperWhisper"
RECORDINGS="$APP_SUPPORT/recordings"
DB="$APP_SUPPORT/recordings.sqlite"
WHISPER_MODEL="$APP_SUPPORT/whisper-models/ggml-large-v3-turbo.bin"
TRANSFORM_MODELS="$APP_SUPPORT/transform-models"
EVIDENCE="$DATA/evidence/decode-evidence.log"

rm -f "$EVIDENCE"
export OSW_TEST_CAPTAIN_RECORDINGS="$RECORDINGS"
export TEST_RUNNER_OSW_TEST_CAPTAIN_RECORDINGS="$RECORDINGS"
export OSW_TEST_EVIDENCE="$EVIDENCE"
export TEST_RUNNER_OSW_TEST_EVIDENCE="$EVIDENCE"
export OSW_TEST_LIBRARY_DB="$DB"
export TEST_RUNNER_OSW_TEST_LIBRARY_DB="$DB"
export OSW_TEST_TRANSFORM_MODELS_DIR="$TRANSFORM_MODELS"
export TEST_RUNNER_OSW_TEST_TRANSFORM_MODELS_DIR="$TRANSFORM_MODELS"
export OSW_TEST_MULTILINGUAL_MODEL="$WHISPER_MODEL"
export TEST_RUNNER_OSW_TEST_MULTILINGUAL_MODEL="$WHISPER_MODEL"
export OSW_TEST_LIBRARY_BUDGET_SECONDS="5400"
export TEST_RUNNER_OSW_TEST_LIBRARY_BUDGET_SECONDS="5400"

cd "$WORKTREE"
exec Scripts/dev-run.sh test \
  -only-testing:OpenSuperWhisperTests/BilingualLibraryMeasurementTests

#!/bin/bash

# Builds and launches a Debug OpenSuperWhisper that keeps its permission grants
# across rebuilds.
#
# This is run.sh with the three things that broke the permission screen changed:
#
#   1. ENABLE_DEBUG_DYLIB=NO - Xcode's Debug default puts the target's code into
#      OpenSuperWhisper.debug.dylib behind a stub executable. That is not the
#      binary people are testing, and the stub is what makes the bundle look
#      "signed but resource-less" to codesign --verify --deep --strict.
#   2. The bundle is signed with a real (self-signed) identity afterwards, via
#      Scripts/dev-sign.sh, instead of being left unsigned/linker-signed. That
#      gives it the identity-based designated requirement TCC grants survive.
#   3. A build from a linked git worktree gets bundle id
#      ru.starmel.OpenSuperWhisper.dev through OSW_BUNDLE_ID_SUFFIX, so a crew
#      build can never take over the bundle id whose grant is being tested.
#      In the checkout whose app is tested the suffix is empty, as shipped.
#
# Like run.sh, the two vendored engines are built through Scripts/build-native.sh:
# llama.cpp owns the single ggml and whisper.cpp only configures against the
# package that script installs, so that order is not reproduced here.
#
# Usage:
#   Scripts/dev-run.sh              - build, sign, then run the app in the foreground
#   Scripts/dev-run.sh build        - build and sign only
#   Scripts/dev-run.sh test [flags]
#                                   - build, run the unit suite, then re-sign.
#                                     xcodebuild flags are forwarded, so
#                                     `test -only-testing:OpenSuperWhisperTests/Foo`
#                                     runs one class and still ends signed
#   Scripts/dev-run.sh --reset-tcc  - also drop the current Accessibility grant
#                                     before launching (needed once when moving
#                                     off an ad-hoc-signed build; see Readme)
#
# Why `test` is a mode of this script and not a bare xcodebuild: `xcodebuild test`
# rebuilds the app target with CODE_SIGNING_ALLOWED=NO, which leaves the bundle on
# disk linker-signed, i.e. `# designated => cdhash H"..."`. Launching that copy
# reintroduces the exact failure this script exists to prevent - tccd refuses the
# identity requirement the Accessibility grant is stored with (`status: -67050`) -
# so the suite runs here and the bundle is signed and asserted afterwards, whether
# the tests passed or not.
#
# Environment overrides:
#   DEVELOPER_DIR   Xcode to build with (default: /Applications/Xcode.app/Contents/Developer)
#   DEV_SIGN_IDENTITY / DEV_SIGN_KEYCHAIN / DEV_SIGN_ENTITLEMENTS  - see Scripts/dev-sign.sh

set -euo pipefail

# Non-interactive shells (and anything started from a daemon) default to
# /Library/Developer/CommandLineTools, which cannot build an app.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

# Crew worktrees must not build the shipped bundle id: several bundles sharing
# ru.starmel.OpenSuperWhisper is one of the reasons macOS kept re-prompting for
# Accessibility. A linked git worktree has .git as a file; the checkout whose app
# is being tested has it as a directory. The project turns OSW_BUNDLE_ID_SUFFIX
# into PRODUCT_BUNDLE_IDENTIFIER, so the tested checkout keeps the shipped id.
BUNDLE_ID_SUFFIX=""
if [[ -f .git ]]; then
    BUNDLE_ID_SUFFIX=".dev"
fi
BUNDLE_ID="ru.starmel.OpenSuperWhisper${BUNDLE_ID_SUFFIX}"

APP="$REPO_ROOT/build/Build/Products/Debug/OpenSuperWhisper.app"
APP_BINARY="$APP/Contents/MacOS/OpenSuperWhisper"
DR_RECORD="$REPO_ROOT/build/.dev-sign-dr"

JUST_BUILD=false
RUN_TESTS=false
RESET_TCC=false
TEST_ARGS=()

for arg in "$@"; do
    case "$arg" in
        build) JUST_BUILD=true ;;
        test) RUN_TESTS=true ;;
        --reset-tcc) RESET_TCC=true ;;
        -h|--help)
            awk 'NR > 1 { if ($0 == "set -euo pipefail") exit; sub(/^# ?/, ""); print }' "$0"
            exit 0 ;;
        # `test` forwards flag-shaped arguments to xcodebuild, so a focused run
        # (`test -only-testing:OpenSuperWhisperTests/SomeTests`) still ends with
        # the signing pass the mode exists for.
        -*) TEST_ARGS+=("$arg") ;;
        *) echo "dev-run.sh: unknown argument: $arg" >&2; exit 2 ;;
    esac
done

for tool in cmake cargo xcodebuild codesign; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "dev-run.sh: missing required tool: $tool" >&2
        exit 1
    fi
done

# Whatever the build or the test run did, the split debug-dylib layout must not
# reach the signing step or a launch: the leftovers are removed, and the script
# fails loudly if they survive the removal, or if the executable is still the
# ~40 KB debug stub (the binary TCC attributes and refuses).
assert_single_binary_layout() {
    local leftover split_left exec_bytes

    for leftover in "$APP/Contents/MacOS"/*.debug.dylib "$APP/Contents/MacOS/__preview.dylib"; do
        [[ -e "$leftover" ]] && rm -f "$leftover"
    done

    split_left="$(find "$APP/Contents/MacOS" -maxdepth 1 \
        \( -name "*.debug.dylib" -o -name "__preview.dylib" \) 2>/dev/null)"
    if [[ -n "$split_left" ]]; then
        echo "dev-run.sh: the bundle still contains Xcode's debug dylib layout:" >&2
        echo "$split_left" >&2
        echo "  a split bundle cannot hold a TCC grant; investigate the build first" >&2
        exit 1
    fi

    exec_bytes="$(stat -f %z "$APP_BINARY" 2>/dev/null || echo 0)"
    if (( exec_bytes < 1000000 )); then
        echo "dev-run.sh: $APP_BINARY is ${exec_bytes} bytes - Xcode's debug stub, not the app." >&2
        echo "  Remove the product and build again:" >&2
        echo "    rm -rf \"$APP\"" >&2
        exit 1
    fi
}

# Reads the designated requirement back off the finished bundle and refuses to
# leave an ad-hoc one behind, because `cdhash H"..."` is invalidated by every
# rebuild and is what makes the Accessibility grant unusable. dev-sign.sh applies
# the same rule at signing time; this asserts the *state of the bundle on disk*,
# so a build, a test run or a bare re-sign all end the same way instead of
# trusting that nothing overwrote the signature afterwards.
assert_identity_requirement() {
    DESIGNATED="$(codesign -d -r- "$APP" 2>&1 \
        | grep -E '^#?[[:space:]]*designated =>' \
        | sed -E 's/^#?[[:space:]]*designated => //')"

    if [[ -z "$DESIGNATED" ]]; then
        echo "dev-run.sh: the bundle has no designated requirement; it is not signed" >&2
        exit 1
    fi
    if [[ "$DESIGNATED" == *"cdhash H"* \
          && "$DESIGNATED" != *"certificate leaf"* \
          && "$DESIGNATED" != *"anchor apple"* ]]; then
        echo "dev-run.sh: the bundle on disk is ad-hoc signed: $DESIGNATED" >&2
        echo "  Launching it would refuse the stored Accessibility grant again." >&2
        echo "  Sign it with the identity: Scripts/dev-sign.sh \"$APP\"" >&2
        exit 1
    fi
}

# A multilingual whisper model this machine happens to have, offered to the
# language-report cases through their documented opt-in. Nothing is exported when
# there is no candidate, which is the state CI runs in: the plain suite must never
# depend on a developer's downloaded files.
multilingual_test_model() {
    local dir file
    for dir in \
        "$REPO_ROOT/.build/test-models" \
        "$HOME/Library/Application Support/ru.starmel.OpenSuperWhisper${BUNDLE_ID_SUFFIX}/whisper-models" \
        "$HOME/Library/Application Support/ru.starmel.OpenSuperWhisper/whisper-models"
    do
        [[ -d "$dir" ]] || continue
        for file in "$dir"/*.bin; do
            [[ -e "$file" ]] || continue
            case "$(basename "$file")" in
                # English-only (cannot detect a language), or not a whisper model.
                *.en.bin|*.en-*.bin|ggml-silero*) continue ;;
            esac
            printf '%s\n' "$file"
            return 0
        done
    done
    return 1
}

# The suite is app-hosted: XCTest injects the test bundle into the app this
# script builds, so a test process runs under the bundle id the developer's own
# build uses, and the domain behind it is the one place a test run could reach -
# `$PREFS_PATH`. The suite has to see an empty store (its new-install cases read
# exactly that state), and no test run may leave that domain changed, so the real
# store is put aside for the length of the run and put back: by the run itself
# when it ends, and by the EXIT trap for a failed suite, a Ctrl-C or any other
# exit. A run that is killed outright (SIGKILL, a power cut) runs no trap at all,
# and that is what `recover_stranded_store` picks up on the next start.
#
# Two fixed paths hold the store while a run has it, both directly in the home
# directory and both named after this script:
#
#   $HOME/.dev-run-preference-stash       the store itself, while a run holds it
#   $HOME/.dev-run-preference-stash.lock  the run that holds it
#
# They are NOT app data and must never be treated as such: an uninstaller, a
# packaging script or a developer tidying the app's folders would delete the only
# copy of the preferences if the stash lived under ~/Library next to the app's
# own data, which is why it does not. A temp directory is no good either - a run
# killed after the store was moved has to be findable again, and $TMPDIR is a
# different directory by then.
PREFS_PATH="$HOME/Library/Preferences/$BUNDLE_ID.plist"
STASH_DIR="$HOME/.dev-run-preference-stash"
LOCK_DIR="$STASH_DIR.lock"
# The stash file is named after a digest of the domain, so neither the app's name
# nor the bundle id is spelled out in a path something could mistake for app data.
if command -v md5 >/dev/null 2>&1; then
    STASH_KEY="$(printf '%s' "$BUNDLE_ID" | md5 -q)"
else
    STASH_KEY="$(printf '%s' "$BUNDLE_ID" | cksum | cut -d' ' -f1)"
fi
STASH_PATH="$STASH_DIR/$STASH_KEY.plist"
PRESERVED_STORE=""
PRESERVED_STORE_STASHED=false
PRESERVED_STORE_WAS_ABSENT=false
LOCK_HELD=false

# One run at a time. A second run must not read, recover or overwrite a stash a
# first run is holding, so the lock goes up before anything looks at either path
# and is released by the trap on the way out. A lock whose owner is gone is the
# aftermath of a killed run rather than a run in progress: taking that one over
# is what makes the recovery below reachable at all.
acquire_run_lock() {
    trap on_exit_restore_and_unlock EXIT
    local holder
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        LOCK_HELD=true
        printf '%s\n' "$$" > "$LOCK_DIR/pid"
        return 0
    fi
    holder="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
    if [[ -n "$holder" ]] && kill -0 "$holder" 2>/dev/null; then
        echo "dev-run.sh: another run (pid $holder) is holding the preference store:" >&2
        echo "  lock:  $LOCK_DIR" >&2
        echo "  stash: $STASH_PATH" >&2
        echo "  Neither is touched. Wait for that run to end; if it is not one of" >&2
        echo "  yours, remove $LOCK_DIR and try again." >&2
        exit 75
    fi
    echo "dev-run.sh: taking over the lock of run ${holder:-an unnamed process}, which is gone" >&2
    rm -f "$LOCK_DIR/pid"
    rmdir "$LOCK_DIR" 2>/dev/null || true
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        echo "dev-run.sh: cannot take the lock at $LOCK_DIR; remove it and try again" >&2
        exit 75
    fi
    LOCK_HELD=true
    printf '%s\n' "$$" > "$LOCK_DIR/pid"
}

release_run_lock() {
    [[ "$LOCK_HELD" == true ]] || return 0
    LOCK_HELD=false
    rm -f "$LOCK_DIR/pid"
    rmdir "$LOCK_DIR" 2>/dev/null || true
}

# Copies $1 to $2 and unlinks $1 only once the copy has been verified byte for
# byte. The store and the stash sit on the same volume here by construction, but
# a cross-volume `mv` is a copy and an unlink by another name, so the ordering is
# spelled out rather than trusted: a death in the middle of it leaves at least
# one good copy, and a copy that does not match is an error, never a success.
move_verified() {
    cp -p "$1" "$2" || return 1
    cmp -s "$1" "$2" || return 1
    rm -f "$1" || return 1
}

# Run before anything is stashed. A stash that is still there belongs to a run
# that died: with the real store gone it is the only copy left and goes back
# where it belongs; with a store there as well nothing on this machine can tell
# which of the two the developer wants, so both stay exactly as they are and the
# run stops instead of choosing one.
recover_stranded_store() {
    [[ -e "$STASH_PATH" ]] || return 0
    if [[ -e "$PREFS_PATH" ]]; then
        echo "dev-run.sh: a preference store left aside by an earlier run was not put back:" >&2
        echo "  stashed: $STASH_PATH" >&2
        echo "  in use:  $PREFS_PATH" >&2
        echo "  Neither is touched. Keep one of them first, for instance:" >&2
        echo "    mv -f \"$STASH_PATH\" \"$PREFS_PATH\"   # the stashed one wins" >&2
        echo "    rm -f \"$STASH_PATH\"                   # the one in use wins" >&2
        exit 1
    fi
    move_verified "$STASH_PATH" "$PREFS_PATH" || {
        echo "dev-run.sh: could not put $PREFS_PATH back; the store kept aside is $STASH_PATH" >&2
        exit 1
    }
    echo "dev-run.sh: put back the preferences a run that was killed left stashed:"
    echo "  $PREFS_PATH"
    rmdir "$STASH_DIR" 2>/dev/null || true
}

# The trap went up with the lock, before anything was read or moved; this records
# which of the two states the run is in - stashed (the trap puts it back) or
# absent (the trap removes what the run leaves, because the absence recorded here
# is the state worth restoring) - and refuses to run if the store cannot be set
# aside safely.
stash_real_store() {
    PRESERVED_STORE="$PREFS_PATH"
    PRESERVED_STORE_STASHED=false
    PRESERVED_STORE_WAS_ABSENT=false
    if [[ ! -e "$PRESERVED_STORE" ]]; then
        # Nothing to stash. Recorded now, before the run: the trap may remove a
        # store later only because this absence was established here.
        PRESERVED_STORE_WAS_ABSENT=true
        return 0
    fi
    # Explicitly checked, not left to errexit: the call site is
    # `run_unit_tests || TEST_STATUS=$?`, which switches errexit off for this
    # whole function, and a half-done stash must stop the run rather than let it
    # loose on the store still sitting in place.
    if [[ -e "$STASH_PATH" ]]; then
        echo "dev-run.sh: $STASH_PATH is there although no run holds it; it is not overwritten and the suite will not run" >&2
        return 1
    fi
    mkdir -p "$STASH_DIR" || {
        echo "dev-run.sh: cannot create $STASH_DIR; the suite will not run with the developer's own preferences in place" >&2
        return 1
    }
    # Copied, verified, and only then removed from where the app reads it: a
    # copy that fails or does not match leaves the store exactly where it is.
    cp -p "$PRESERVED_STORE" "$STASH_PATH" || {
        echo "dev-run.sh: cannot copy $PRESERVED_STORE to $STASH_PATH; it is left where it is and the suite will not run" >&2
        rm -f "$STASH_PATH"
        return 1
    }
    if ! cmp -s "$PRESERVED_STORE" "$STASH_PATH"; then
        echo "dev-run.sh: the copy of $PRESERVED_STORE at $STASH_PATH does not match it; the store is left where it is and the suite will not run" >&2
        rm -f "$STASH_PATH"
        return 1
    fi
    rm -f "$PRESERVED_STORE" || {
        echo "dev-run.sh: $PRESERVED_STORE could not be removed after its verified copy; the suite will not run with it in place" >&2
        rm -f "$STASH_PATH"
        return 1
    }
    PRESERVED_STORE_STASHED=true
}

restore_preserved_store() {
    [[ -n "$PRESERVED_STORE" ]] || return 0
    if [[ "$PRESERVED_STORE_STASHED" == true ]]; then
        # The file that was there before the run, byte for byte; whatever the
        # run wrote into the domain goes away with it.
        if move_verified "$STASH_PATH" "$PRESERVED_STORE"; then
            rmdir "$STASH_DIR" 2>/dev/null || true
        else
            # Nothing verified reached the real path and the stash is still the
            # only good copy, so a partial file is not left where the app reads it.
            rm -f "$PRESERVED_STORE"
            echo "dev-run.sh: could not put $PRESERVED_STORE back; the store kept aside is $STASH_PATH" >&2
        fi
    elif [[ "$PRESERVED_STORE_WAS_ABSENT" == true && -e "$PRESERVED_STORE" ]]; then
        # There was no store before the run, so the state to restore is the
        # absence of one: the run's file does not survive it either.
        rm -f "$PRESERVED_STORE"
    fi
    PRESERVED_STORE=""
    PRESERVED_STORE_STASHED=false
    PRESERVED_STORE_WAS_ABSENT=false
}

on_exit_restore_and_unlock() {
    local status=$?
    restore_preserved_store || true
    release_run_lock || true
    exit "$status"
}

run_unit_tests() {
    # `xcodebuild test` launches the app-hosted test bundle with a stripped
    # environment: a plain `OSW_TEST_MULTILINGUAL_MODEL=... xcodebuild test` is
    # ignored and the cases skip. XCTest forwards `TEST_RUNNER_<name>` as
    # `<name>`, which is the form that actually arrives, so both are exported.
    local model="${OSW_TEST_MULTILINGUAL_MODEL:-}"

    # A caller-supplied `-only-testing:` narrows the run; without one the whole
    # unit bundle runs.
    local selection=(-only-testing:OpenSuperWhisperTests)
    local arg
    for arg in ${TEST_ARGS[@]+"${TEST_ARGS[@]}"}; do
        if [[ "$arg" == -only-testing:* ]]; then
            selection=()
            break
        fi
    done

    # Each test process gets its own scratch preference suite (AppPreferences),
    # which leaves one small file per process behind in ~/Library/Preferences.
    # Sweep the ones whose process is gone; a suite running in parallel elsewhere
    # is still alive and is therefore left alone.
    local store pid
    for store in "$HOME/Library/Preferences/OpenSuperWhisperTests."*.plist; do
        [[ -e "$store" ]] || continue
        pid="${store##*OpenSuperWhisperTests.}"
        pid="${pid%.plist}"
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        if kill -0 "$pid" 2>/dev/null; then continue; fi
        rm -f "$store"
    done
    if [[ -z "$model" ]]; then
        model="$(multilingual_test_model || true)"
    fi
    if [[ -n "$model" ]]; then
        export OSW_TEST_MULTILINGUAL_MODEL="$model"
        export TEST_RUNNER_OSW_TEST_MULTILINGUAL_MODEL="$model"
        echo "Multilingual cases run against:"
        echo "  $model"
    else
        echo "No multilingual model on this machine; those cases will skip."
    fi

    # The store the tests see has to be empty, and the developer's own store has
    # to come back exactly as it was, so the real one is moved aside - only the
    # file is touched, nothing here writes into it - and the trap that
    # stash_real_store arms before it moves anything guarantees the move back
    # even if the run fails or is interrupted.
    stash_real_store || return 1

    local status=0
    xcodebuild test -project OpenSuperWhisper.xcodeproj -scheme OpenSuperWhisper \
        -destination 'platform=macOS,arch=arm64' \
        -derivedDataPath build -clonedSourcePackagesDirPath SourcePackages \
        -skipPackagePluginValidation -skipMacroValidation -skipUnavailableActions \
        CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
        ENABLE_DEBUG_DYLIB=NO \
        OSW_BUNDLE_ID_SUFFIX="$BUNDLE_ID_SUFFIX" \
        ${selection[@]+"${selection[@]}"} \
        ${TEST_ARGS[@]+"${TEST_ARGS[@]}"} || status=$?

    # The run is over, so the store goes back before the signing steps that
    # follow; the trap repeats this if the run never reached here.
    restore_preserved_store
    return "$status"
}

# One run at a time, and the stranded store first: the lock goes up before either
# path is read, and a store left stashed by a run that was killed is put back -
# or, when a store is there as well, reported without touching either - before
# anything is built, signed or launched.
acquire_run_lock
recover_stranded_store

# The engines come first, in the one order that works: build-native.sh configures
# and builds libllama (which owns the single ggml), installs that ggml package and
# only then configures libwhisper against it with WHISPER_USE_SYSTEM_GGML=ON.
# Configuring libwhisper directly here fails with "the vendored ggml package is
# missing"; the xcodebuild below builds the two projects this generates.
echo "Building native engines..."
"$SCRIPT_DIR/build-native.sh" Debug

echo "Building autocorrect-swift..."
mkdir -p build
CARGO_PROFILE_RELEASE_LTO=true \
CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 \
CARGO_PROFILE_RELEASE_STRIP=symbols \
CARGO_PROFILE_RELEASE_PANIC=abort \
cargo build -p autocorrect-swift --release --target aarch64-apple-darwin --manifest-path=libautocorrect/Cargo.toml
cp ./libautocorrect/target/aarch64-apple-darwin/release/libautocorrect_swift.dylib ./build/libautocorrect_swift.dylib
install_name_tool -id "@rpath/libautocorrect_swift.dylib" ./build/libautocorrect_swift.dylib
# install_name_tool invalidates any existing signature.
codesign --force --sign - ./build/libautocorrect_swift.dylib

# run.sh copies Homebrew's libomp in because the app links -lomp. A branch that
# dropped libomp from the project (and the link flag with it) needs no copy, and
# should not fail when Homebrew's libomp is absent.
if grep -q "libomp" OpenSuperWhisper.xcodeproj/project.pbxproj; then
    if [[ ! -f /opt/homebrew/opt/libomp/lib/libomp.dylib ]]; then
        echo "The project links libomp but /opt/homebrew/opt/libomp/lib/libomp.dylib is missing." >&2
        echo "Install it with: brew install libomp" >&2
        exit 1
    fi
    echo "Copying libomp.dylib..."
    cp -f /opt/homebrew/opt/libomp/lib/libomp.dylib ./build/libomp.dylib
    install_name_tool -id "@rpath/libomp.dylib" ./build/libomp.dylib
    codesign --force --sign - ./build/libomp.dylib
else
    echo "libomp is not part of this project; skipping its dylib."
fi

# A product left in Xcode's split debug-dylib layout cannot be built over. With
# ENABLE_DEBUG_DYLIB=NO the linker writes the real code to
# Contents/MacOS/OpenSuperWhisper, but the previous build's
# OpenSuperWhisper.debug.dylib and __preview.dylib can stay behind, and with
# them the ~40 KB stub executable that loads them - the binary TCC attributes
# and refuses:
#
#   matchesCodeRequirement:]: SecStaticCodeCheckValidity() static code ... from
#   ru.starmel.OpenSuperWhisper : identifier "ru.starmel.OpenSuperWhisper" and
#   certificate leaf = H"32266bcc..."; status: -67050
#
# So the split product is dropped before the build rather than signed as-is.
if [[ -d "$APP" ]]; then
    STALE_SPLIT="$(find "$APP/Contents/MacOS" -maxdepth 1 \
        \( -name "*.debug.dylib" -o -name "__preview.dylib" \) 2>/dev/null)"
    EXEC_BYTES="$(stat -f %z "$APP_BINARY" 2>/dev/null || echo 0)"
    if [[ -n "$STALE_SPLIT" ]] || (( EXEC_BYTES > 0 && EXEC_BYTES < 1000000 )); then
        echo "Removing the split debug-dylib product left by an earlier run.sh build:"
        echo "  $APP"
        rm -rf "$APP"
    fi
fi

# Signing is off during the build: Xcode would try to use the Apple Development
# identity from the project (TEAM 8LLDD7HWZK), which does not exist on this
# machine. Scripts/dev-sign.sh signs the finished bundle instead.
echo "Building OpenSuperWhisper..."
if [[ -n "$BUNDLE_ID_SUFFIX" ]]; then
    echo "  worktree build: bundle id ${BUNDLE_ID}"
fi
# `set -e` would abort at the assignment itself if xcodebuild failed, before the
# captured output below is ever echoed — so a failed build looked like a build
# that simply stopped mid-sentence, with the reason only in
# build/Logs/Build/*.xcactivitylog. Capture the status without errexit, then
# restore it: the failure path below is the one that must be able to speak.
set +e
BUILD_OUTPUT=$(xcodebuild -scheme OpenSuperWhisper -configuration Debug -jobs 8 \
    -derivedDataPath build -quiet -destination 'platform=macOS,arch=arm64' \
    -skipPackagePluginValidation -skipMacroValidation -UseModernBuildSystem=YES \
    -clonedSourcePackagesDirPath SourcePackages -skipUnavailableActions \
    CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
    ENABLE_DEBUG_DYLIB=NO \
    OSW_BUNDLE_ID_SUFFIX="$BUNDLE_ID_SUFFIX" \
    build 2>&1)
BUILD_STATUS=$?
set -e

if command -v xcpretty >/dev/null 2>&1; then
    echo "$BUILD_OUTPUT" | xcpretty --simple --color
else
    echo "$BUILD_OUTPUT"
fi

if [[ $BUILD_STATUS -ne 0 || "$BUILD_OUTPUT" == *"BUILD FAILED"* ]]; then
    echo "Build failed!" >&2
    exit 1
fi

if [[ ! -d "$APP" ]]; then
    echo "Build reported success but there is no bundle at $APP" >&2
    exit 1
fi

# The suite rebuilds the app target ad-hoc, so it runs before the bundle is
# signed and asserted. A failing suite must not skip that: the app on disk has to
# be launchable and grant-bearing whatever the tests said, so the status is kept
# and reported at the end.
TEST_STATUS=0
if $RUN_TESTS; then
    echo "Running the unit suite..."
    run_unit_tests || TEST_STATUS=$?
fi

assert_single_binary_layout

"$SCRIPT_DIR/dev-sign.sh" "$APP"

assert_identity_requirement

# A designated requirement that changes between rebuilds is the exact failure
# this whole path exists to avoid, so remember it and compare. `$DESIGNATED` was
# read back off the bundle by assert_identity_requirement above.
mkdir -p "$(dirname "$DR_RECORD")"
if [[ -f "$DR_RECORD" ]]; then
    PREVIOUS="$(cat "$DR_RECORD")"
    if [[ "$PREVIOUS" == "$DESIGNATED" ]]; then
        echo "Designated requirement unchanged since the previous build:"
        echo "  $DESIGNATED"
    else
        echo "WARNING: the designated requirement changed since the previous build." >&2
        echo "  previous: $PREVIOUS" >&2
        echo "  current:  $DESIGNATED" >&2
        echo "Existing permission grants will no longer match; re-grant once." >&2
    fi
fi
printf '%s' "$DESIGNATED" > "$DR_RECORD"

xattr -d com.apple.quarantine "$APP" 2>/dev/null || true

if $RESET_TCC; then
    # Only when moving from an ad-hoc-signed build: the recorded grant is keyed
    # to the old cdhash requirement and would otherwise be matched to nothing.
    echo "Resetting the Accessibility grant for $BUNDLE_ID..."
    tccutil reset Accessibility "$BUNDLE_ID"
fi

if $JUST_BUILD; then
    echo "Built and signed: $APP"
    exit 0
fi

if $RUN_TESTS; then
    echo "Bundle on disk: $APP"
    echo "  designated requirement: $DESIGNATED"
    if [[ $TEST_STATUS -eq 0 ]]; then
        echo "Unit suite passed and the app is signed for the next launch."
        exit 0
    fi
    echo "Unit suite FAILED; the app was re-signed anyway so the next launch" >&2
    echo "cannot be the ad-hoc copy the test run left behind." >&2
    exit "$TEST_STATUS"
fi

echo "Starting the app..."
# `exec` runs no trap, and the app must not keep a test run locked out.
release_run_lock
exec "$APP_BINARY"

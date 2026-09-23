#!/bin/bash

# Packaging contract verification for the one-artifact install/uninstall.
#
# Exercises, without root and without touching the real machine:
#
#   * the uninstaller's path list, against a scratch install (OSW_INSTALL_ROOT)
#   * uninstall twice, uninstall with the app already gone, unrelated data survives
#   * argument handling (--help, unknown flags)
#   * the payload of a built .pkg: the app, the uninstall command, the receipt id,
#     the preinstall script, and the installer's version
#
# Usage:
#   Scripts/verify-packaging.sh                 # uninstaller checks only
#   Scripts/verify-packaging.sh --app <path>    # also build and inspect a .pkg
#
# Exits non-zero if any assertion fails.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNINSTALL="$REPO_ROOT/packaging/uninstall.sh"
PKG_BUILDER="$REPO_ROOT/packaging/build-pkg.sh"
BUNDLE_ID="ru.starmel.OpenSuperWhisper"

CHECKS=0
FAILURES=0

pass() {
    CHECKS=$((CHECKS + 1))
    echo "  ok   $1"
}

fail() {
    CHECKS=$((CHECKS + 1))
    FAILURES=$((FAILURES + 1))
    echo "  FAIL $1"
}

check() { # description, 0 = ok
    if [[ "$2" -eq 0 ]]; then pass "$1"; else fail "$1"; fi
}

die() {
    echo "ERROR: $1" >&2
    exit 2
}

APP_FOR_PKG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --app) APP_FOR_PKG="$2"; shift 2 ;;
        -h|--help)
            sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) die "unknown argument: $1" ;;
    esac
done

[[ -f "$UNINSTALL" ]] || die "cannot find $UNINSTALL"

PROBE="$(mktemp -d "${TMPDIR:-/tmp}/osw-verify.XXXXXX")"
trap 'rm -rf "$PROBE"' EXIT

echo "Packaging contract verification"
echo "  uninstaller: $UNINSTALL"
echo ""

# MARK: - Scratch install

scratch_install() { # root
    local root="$1"
    mkdir -p \
        "$root/Applications/OpenSuperWhisper.app/Contents/MacOS" \
        "$root/Users/tester/Library/Application Support/$BUNDLE_ID/recordings" \
        "$root/Users/tester/Library/Application Support/$BUNDLE_ID/transform-models" \
        "$root/Users/tester/Library/Application Support/$BUNDLE_ID/whisper-models" \
        "$root/Users/tester/Library/Caches/$BUNDLE_ID" \
        "$root/Users/tester/Library/HTTPStorages/$BUNDLE_ID" \
        "$root/Users/tester/Library/Preferences" \
        "$root/Users/tester/Library/Saved Application State/$BUNDLE_ID.savedState" \
        "$root/Users/tester/Library/Application Scripts/$BUNDLE_ID" \
        "$root/Users/tester/models" \
        "$root/Users/tester/Library/Application Support/com.example.other"

    echo app > "$root/Applications/OpenSuperWhisper.app/Contents/MacOS/OpenSuperWhisper"
    echo db > "$root/Users/tester/Library/Application Support/$BUNDLE_ID/recordings.sqlite"
    echo wav > "$root/Users/tester/Library/Application Support/$BUNDLE_ID/recordings/dictation.wav"
    echo gguf > "$root/Users/tester/Library/Application Support/$BUNDLE_ID/transform-models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
    echo ggml > "$root/Users/tester/Library/Application Support/$BUNDLE_ID/whisper-models/ggml-tiny.en.bin"
    echo plist > "$root/Users/tester/Library/Preferences/$BUNDLE_ID.plist"
    echo cache > "$root/Users/tester/Library/Caches/$BUNDLE_ID/Cache.db"
    echo http > "$root/Users/tester/Library/HTTPStorages/$BUNDLE_ID/httpstorages.sqlite"
    echo state > "$root/Users/tester/Library/Saved Application State/$BUNDLE_ID.savedState/data.data"
    echo script > "$root/Users/tester/Library/Application Scripts/$BUNDLE_ID/script"
    echo KEEP > "$root/Users/tester/models/Qwen3-30B-A3B-Instruct-2507-q4_k_m.gguf"
    echo KEEP > "$root/Users/tester/Library/Application Support/com.example.other/state.json"
}

run_uninstall() { # root, extra args...
    local root="$1"
    shift
    HOME="/Users/tester" OSW_INSTALL_ROOT="$root" /bin/sh "$UNINSTALL" "$@" 2>&1
}

# MARK: - The path list

echo "== uninstaller (scratch install) =="

INSTALL="$PROBE/install"
scratch_install "$INSTALL"

OUTPUT="$(run_uninstall "$INSTALL")"
STATUS=$?
check "uninstall exits 0" $STATUS
check "the app bundle is gone" "$([[ ! -e "$INSTALL/Applications/OpenSuperWhisper.app" ]] && echo 0 || echo 1)"
check "the app support directory is gone (history, models, settings)" \
    "$([[ ! -e "$INSTALL/Users/tester/Library/Application Support/$BUNDLE_ID" ]] && echo 0 || echo 1)"
check "the caches are gone" "$([[ ! -e "$INSTALL/Users/tester/Library/Caches/$BUNDLE_ID" ]] && echo 0 || echo 1)"
check "the HTTP storage is gone" "$([[ ! -e "$INSTALL/Users/tester/Library/HTTPStorages/$BUNDLE_ID" ]] && echo 0 || echo 1)"
check "the saved application state is gone" \
    "$([[ ! -e "$INSTALL/Users/tester/Library/Saved Application State/$BUNDLE_ID.savedState" ]] && echo 0 || echo 1)"
check "the application scripts directory is gone" \
    "$([[ ! -e "$INSTALL/Users/tester/Library/Application Scripts/$BUNDLE_ID" ]] && echo 0 || echo 1)"
check "the preferences plist is gone" "$([[ ! -e "$INSTALL/Users/tester/Library/Preferences/$BUNDLE_ID.plist" ]] && echo 0 || echo 1)"
check "~/models is untouched" "$([[ -e "$INSTALL/Users/tester/models/Qwen3-30B-A3B-Instruct-2507-q4_k_m.gguf" ]] && echo 0 || echo 1)"
check "another application's data is untouched" \
    "$([[ -e "$INSTALL/Users/tester/Library/Application Support/com.example.other/state.json" ]] && echo 0 || echo 1)"

# MARK: - Idempotence

echo ""
echo "== idempotence =="

OUTPUT="$(run_uninstall "$INSTALL" --quiet)"
STATUS=$?
check "uninstalling twice exits 0" $STATUS
check "uninstalling twice says nothing (--quiet)" "$([[ -z "$OUTPUT" ]] && echo 0 || echo 1)"

SECOND="$(run_uninstall "$INSTALL")"
case "$SECOND" in
    *"has been removed"*) SECOND_OK=0 ;;
    *) SECOND_OK=1 ;;
esac
check "uninstalling twice still reports success" "$SECOND_OK"

GONE="$PROBE/gone"
scratch_install "$GONE"
rm -rf "$GONE/Applications/OpenSuperWhisper.app"
OUTPUT="$(run_uninstall "$GONE")"
check "uninstalling with the app already gone exits 0" $?
check "and still clears the app's state" \
    "$([[ ! -e "$GONE/Users/tester/Library/Application Support/$BUNDLE_ID" ]] && echo 0 || echo 1)"

REINSTALL="$PROBE/reinstall"
scratch_install "$REINSTALL"
run_uninstall "$REINSTALL" --quiet >/dev/null
scratch_install "$REINSTALL"
check "reinstalling over a fresh tree leaves nothing of the previous install" \
    "$([[ -e "$REINSTALL/Applications/OpenSuperWhisper.app" ]] && echo 0 || echo 1)"

# MARK: - Argument handling and reach

echo ""
echo "== script surface =="

/bin/sh "$UNINSTALL" --help >/dev/null 2>&1
check "--help exits 0" $?

OUTPUT="$(/bin/sh "$UNINSTALL" --not-a-flag 2>&1)"
STATUS=$?
check "an unknown argument exits 2" "$([[ $STATUS -eq 2 ]] && echo 0 || echo 1)"
case "$OUTPUT" in
    *"--not-a-flag"*) ARG_REPORTED=0 ;;
    *) ARG_REPORTED=1 ;;
esac
check "and says which argument" "$ARG_REPORTED"

grep -qE '(^|[[:space:];&])rm[[:space:]][^|]*(/opt/homebrew|HOME/models|~/models)' "$UNINSTALL"
check "the uninstaller never removes anything under /opt/homebrew or ~/models" "$([[ $? -ne 0 ]] && echo 0 || echo 1)"

grep -qE 'rm -rf "/"' "$UNINSTALL"
check "the uninstaller never removes the filesystem root" "$([[ $? -ne 0 ]] && echo 0 || echo 1)"

grep -q 'OSW_INSTALL_ROOT' "$UNINSTALL"
check "the uninstaller supports the scratch-root test hook" $?

# MARK: - The package

if [[ -n "$APP_FOR_PKG" ]]; then
    echo ""
    echo "== package payload =="

    if [[ ! -d "$APP_FOR_PKG" ]]; then
        fail "no app at $APP_FOR_PKG"
    else
        PACKAGE="$PROBE/OpenSuperWhisper-test.pkg"
        if "$PKG_BUILDER" --app "$APP_FOR_PKG" --out "$PACKAGE" > "$PROBE/pkg.log" 2>&1; then
            pass "packaging/build-pkg.sh produced a package"

            FILES="$(pkgutil --payload-files "$PACKAGE")"
            case "$FILES" in
                *"./Applications/OpenSuperWhisper.app/Contents/MacOS/OpenSuperWhisper"*) PAYLOAD_APP=0 ;;
                *) PAYLOAD_APP=1 ;;
            esac
            case "$FILES" in
                *"./Applications/Uninstall OpenSuperWhisper.command"*) PAYLOAD_COMMAND=0 ;;
                *) PAYLOAD_COMMAND=1 ;;
            esac
            check "the payload contains the app" "$PAYLOAD_APP"
            check "the payload contains the uninstall command" "$PAYLOAD_COMMAND"
            # pkgbuild records extended attributes as AppleDouble ("._name")
            # companions in the BOM; the installer applies them as xattrs, so
            # they are not stray files. Count the real entries only.
            IN_APPLICATIONS="$(printf '%s\n' "$FILES" | grep -E '^\./Applications/[^/]*$' | grep -vc '/\._')"
            check "the payload puts exactly two entries in /Applications (the app and the uninstall command)" \
                "$([[ "$IN_APPLICATIONS" -eq 2 ]] && echo 0 || echo 1)"

            grep -q "$BUNDLE_ID" "$PROBE/pkg.log" \
                && pass "the component package carries the receipt id $BUNDLE_ID" \
                || fail "the component package does not carry $BUNDLE_ID"

            grep -q "preinstall" "$PROBE/pkg.log" \
                && pass "the installer ships the preinstall hook" \
                || fail "the installer has no preinstall hook"

            # The shipped command must be the same script the app runs, byte for byte.
            pkgutil --expand-full "$PACKAGE" "$PROBE/expanded" >/dev/null 2>&1
            SHIPPED="$PROBE/expanded/OpenSuperWhisper-component.pkg/Payload/Applications/Uninstall OpenSuperWhisper.command"
            check "the payload carries the uninstall command" \
                "$([[ -f "$SHIPPED" ]] && echo 0 || echo 1)"
            cmp -s "$SHIPPED" "$UNINSTALL" \
                && pass "the shipped command is packaging/uninstall.sh, byte for byte" \
                || fail "the shipped command differs from packaging/uninstall.sh"
            check "the shipped command is executable" \
                "$([[ -x "$SHIPPED" ]] && echo 0 || echo 1)"

            # The app itself has to be inside the payload with its resources.
            check "the payload app carries the uninstall script resource" \
                "$([[ -f "$PROBE/expanded/OpenSuperWhisper-component.pkg/Payload/Applications/OpenSuperWhisper.app/Contents/Resources/uninstall.sh" ]] && echo 0 || echo 1)"
            check "the payload app carries the default whisper model" \
                "$([[ -f "$PROBE/expanded/OpenSuperWhisper-component.pkg/Payload/Applications/OpenSuperWhisper.app/Contents/Resources/ggml-tiny.en.bin" ]] && echo 0 || echo 1)"
            EXTRACTED="$PROBE/expanded/OpenSuperWhisper-component.pkg/Payload"
            check "the extracted payload has no AppleDouble files on disk" \
                "$([[ -z "$(find "$EXTRACTED" -name '._*' -print -quit)" ]] && echo 0 || echo 1)"
            check "the extracted payload puts nothing in /Applications but the app and the command" \
                "$([[ "$(ls -1 "$EXTRACTED/Applications" | wc -l | tr -d ' ')" == "2" ]] && echo 0 || echo 1)"

            pkgutil --expand "$PACKAGE" "$PROBE/unpacked" >/dev/null 2>&1
            check "the component package is present" \
                "$([[ -f "$PROBE/unpacked/OpenSuperWhisper-component.pkg/Payload" ]] && echo 0 || echo 1)"
            check "the distribution declares the arm64/macOS 14 floor" \
                "$(grep -q 'hostArchitectures="arm64"' "$PROBE/unpacked/Distribution" && grep -q 'min="14.0"' "$PROBE/unpacked/Distribution" && echo 0 || echo 1)"
            check "the distribution shows a conclusion page" \
                "$(grep -q 'conclusion' "$PROBE/unpacked/Distribution" && echo 0 || echo 1)"
            check "the distribution substitutes the version" \
                "$(! grep -q '@@VERSION@@' "$PROBE/unpacked/Distribution" && echo 0 || echo 1)"
        else
            fail "packaging/build-pkg.sh failed (see the log below)"
            sed 's/^/       /' "$PROBE/pkg.log" | tail -20
        fi
    fi
fi

echo ""
if [[ "$FAILURES" -eq 0 ]]; then
    echo "ALL CHECKS PASSED (checks: $CHECKS)"
    exit 0
fi
echo "FAILURES: $FAILURES (checks: $CHECKS)"
exit 1

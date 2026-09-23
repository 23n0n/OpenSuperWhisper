#!/bin/sh
#
# Uninstall OpenSuperWhisper: the app, everything it wrote under your home
# directory, and its installer receipt.
#
# Two entry points, one implementation:
#
#   * Settings -> Advanced -> Uninstall OpenSuperWhisper..., or the same item in
#     the menu-bar menu. The app copies this script to a temporary file, starts
#     it with `--wait-pid <its own pid>` and quits. The script waits for that
#     process to exit before it removes anything.
#   * `/Applications/Uninstall OpenSuperWhisper.command`, shipped by the
#     installer, for when the app is already gone from /Applications.
#
# Idempotent by construction: every step tolerates absence, so running it twice
# -- or after deleting the app by hand -- is harmless.
#
# Nothing outside the list below is touched. In particular this never removes
# ~/models (where `Scripts/transform-server.sh` may have put a copy of the
# transform weights), /opt/homebrew (where a user-installed llama.cpp lives),
# or any other application's data.
#
# Testing: OSW_INSTALL_ROOT prefixes every absolute path (default "/"), so the
# whole path list can be exercised against a scratch tree. Everything that needs
# the real machine -- quitting the app, cfprefsd, the installer receipt, TCC --
# runs only when the root is "/", so a probe can never disturb the live system.

set -u

BUNDLE_ID="ru.starmel.OpenSuperWhisper"
APP_NAME="OpenSuperWhisper"

ROOT="${OSW_INSTALL_ROOT:-/}"
WAIT_PID=""
RESET_PERMISSIONS=0
SELF_DELETE=0
QUIET=0

usage() {
    cat <<'EOF'
Uninstall OpenSuperWhisper.

Usage: uninstall.sh [options]

  --wait-pid <pid>       wait for that process to exit before removing anything
                         (used by the in-app uninstall action)
  --reset-permissions    also reset the microphone/accessibility grants
  --self-delete          remove this script when done (the in-app action runs a
                         temporary copy of it)
  --quiet                say nothing
  -h, --help             this text

Environment:
  OSW_INSTALL_ROOT       prefix every path with this directory (default "/").
                         For testing the path list against a scratch tree.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --wait-pid)
            WAIT_PID="${2:-}"
            shift 2
            ;;
        --reset-permissions)
            RESET_PERMISSIONS=1
            shift
            ;;
        --self-delete)
            SELF_DELETE=1
            shift
            ;;
        --quiet)
            QUIET=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "uninstall: unknown argument: $1" >&2
            echo "Try --help." >&2
            exit 2
            ;;
    esac
done

say() {
    [ "$QUIET" -eq 1 ] || echo "$1"
}

IS_REAL_ROOT=0
if [ "$ROOT" = "/" ]; then
    IS_REAL_ROOT=1
fi

APP="$ROOT/Applications/$APP_NAME.app"
SUPPORT_DIR="$ROOT$HOME/Library/Application Support/$BUNDLE_ID"
CACHES_DIR="$ROOT$HOME/Library/Caches/$BUNDLE_ID"
HTTP_STORAGES_DIR="$ROOT$HOME/Library/HTTPStorages/$BUNDLE_ID"
SAVED_STATE_DIR="$ROOT$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"
APP_SCRIPTS_DIR="$ROOT$HOME/Library/Application Scripts/$BUNDLE_ID"
PREFS_PLIST="$ROOT$HOME/Library/Preferences/$BUNDLE_ID.plist"
CRASH_PLIST_DIR="$ROOT$HOME/Library/Application Support/CrashReporter"
DIAGNOSTIC_REPORTS_DIR="$ROOT$HOME/Library/Logs/DiagnosticReports"
TEMP_RECORDINGS_DIR="$ROOT${TMPDIR:-/tmp}/temp_recordings"

# 1. Let the app finish quitting. The in-app action passes its own pid, because
#    an app cannot delete the bundle it is running from.
if [ -n "$WAIT_PID" ]; then
    waited=0
    while kill -0 "$WAIT_PID" 2>/dev/null; do
        [ "$waited" -ge 600 ] && break
        sleep 0.1
        waited=$((waited + 1))
    done
fi

# 2. Quit a copy that is still running (the .command entry point).
if [ "$IS_REAL_ROOT" -eq 1 ]; then
    osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1
    pkill -x "$APP_NAME" >/dev/null 2>&1
    waited=0
    while pgrep -x "$APP_NAME" >/dev/null 2>&1; do
        [ "$waited" -ge 40 ] && break
        sleep 0.25
        waited=$((waited + 1))
    done
fi

# 3. The app itself. A .pkg install owns the bundle as root, so a plain user
#    cannot always remove it; that case asks for administrator authorisation
#    once. The .command and in-app entry points both land here.
rm -rf "$APP"
if [ -e "$APP" ] && [ "$IS_REAL_ROOT" -eq 1 ]; then
    say "Removing $APP needs administrator authorisation."
    osascript -e "do shell script \"rm -rf '$APP'\" with administrator privileges" >/dev/null 2>&1
fi

# 4. Everything the app owns: dictation history, the database, whisper models,
#    transform weights, caches, saved state and preferences.
rm -rf "$SUPPORT_DIR"
rm -rf "$CACHES_DIR"
rm -rf "$HTTP_STORAGES_DIR"
rm -rf "$SAVED_STATE_DIR"
rm -rf "$APP_SCRIPTS_DIR"
rm -f "$PREFS_PLIST"

if [ "$IS_REAL_ROOT" -eq 1 ]; then
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1
    killall cfprefsd >/dev/null 2>&1
fi

# 5. OS leftovers named after the app.
rm -f "$CRASH_PLIST_DIR/$APP_NAME"_*.plist
rm -f "$DIAGNOSTIC_REPORTS_DIR/$APP_NAME"-*.ips
rm -rf "$TEMP_RECORDINGS_DIR"

# 6. The installer receipt, so `pkgutil --pkg-info` agrees the app is gone and a
#    later install is a clean first install.
if [ "$IS_REAL_ROOT" -eq 1 ]; then
    pkgutil --forget "$BUNDLE_ID" >/dev/null 2>&1

    # 7. Optional: the microphone/accessibility/input-monitoring grants. Off by
    #    default, because re-prompting on the next install is worse than leaving
    #    a stale grant behind.
    if [ "$RESET_PERMISSIONS" -eq 1 ]; then
        tccutil reset All "$BUNDLE_ID" >/dev/null 2>&1
    fi
fi

say "OpenSuperWhisper has been removed."
say "Removed: $APP"
say "Removed: $SUPPORT_DIR (dictation history, models and settings)"
if [ "$IS_REAL_ROOT" -eq 1 ]; then
    say "Removed: the $BUNDLE_ID installer receipt"
    say "Left alone: ~/models, /opt/homebrew and every other application's data."
fi

# 8. The in-app action runs a temporary copy of this script; drop it.
if [ "$SELF_DELETE" -eq 1 ]; then
    rm -f "$0"
fi

# The only failure worth reporting is a bundle that is still there afterwards.
if [ -e "$APP" ]; then
    say "Could not remove $APP."
    exit 1
fi

exit 0

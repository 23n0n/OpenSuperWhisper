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
#   Scripts/dev-run.sh --reset-tcc  - also drop the current Accessibility grant
#                                     before launching (needed once when moving
#                                     off an ad-hoc-signed build; see Readme)
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
RESET_TCC=false

for arg in "$@"; do
    case "$arg" in
        build) JUST_BUILD=true ;;
        --reset-tcc) RESET_TCC=true ;;
        -h|--help)
            awk 'NR > 1 { if ($0 == "set -euo pipefail") exit; sub(/^# ?/, ""); print }' "$0"
            exit 0 ;;
        *) echo "dev-run.sh: unknown argument: $arg" >&2; exit 2 ;;
    esac
done

for tool in cmake cargo xcodebuild codesign; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "dev-run.sh: missing required tool: $tool" >&2
        exit 1
    fi
done

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

# Signing is off during the build: Xcode would try to use the Apple Development
# identity from the project (TEAM 8LLDD7HWZK), which does not exist on this
# machine. Scripts/dev-sign.sh signs the finished bundle instead.
echo "Building OpenSuperWhisper..."
if [[ -n "$BUNDLE_ID_SUFFIX" ]]; then
    echo "  worktree build: bundle id ${BUNDLE_ID}"
fi
BUILD_OUTPUT=$(xcodebuild -scheme OpenSuperWhisper -configuration Debug -jobs 8 \
    -derivedDataPath build -quiet -destination 'platform=macOS,arch=arm64' \
    -skipPackagePluginValidation -skipMacroValidation -UseModernBuildSystem=YES \
    -clonedSourcePackagesDirPath SourcePackages -skipUnavailableActions \
    CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
    ENABLE_DEBUG_DYLIB=NO \
    OSW_BUNDLE_ID_SUFFIX="$BUNDLE_ID_SUFFIX" \
    build 2>&1)
BUILD_STATUS=$?

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

# Any Xcode debug dylib left in the bundle means this build is not the layout
# the app is tested as; report it rather than silently signing a stub.
if compgen -G "$APP/Contents/MacOS/*.debug.dylib" >/dev/null; then
    echo "Unexpected: the bundle still contains a Xcode debug dylib." >&2
    exit 1
fi

"$SCRIPT_DIR/dev-sign.sh" "$APP"

# A designated requirement that changes between rebuilds is the exact failure
# this whole path exists to avoid, so remember it and compare.
DESIGNATED="$(codesign -d -r- "$APP" 2>&1 | grep '^designated =>' | sed 's/^designated => //')"
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

echo "Starting the app..."
exec "$APP_BINARY"

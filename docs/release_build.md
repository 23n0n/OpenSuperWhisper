## Release build

The artifact users install is `OpenSuperWhisper-<version>.pkg`: the app bundle plus a
double-clickable `Uninstall OpenSuperWhisper.command`, and the installer receipt that
uninstall relies on. Both inference engines (whisper.cpp and llama.cpp) are linked into
the app, so a release build is a native build plus one `xcodebuild` — there is no server
process to ship and nothing to install alongside the app.

### Prerequisites

    git submodule update --init --recursive
    brew install cmake rust ruby
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

`DEVELOPER_DIR` matters: `Scripts/build-native.sh` and `xcodebuild` both need the Xcode
toolchain, and with only the Command Line Tools selected every build stops at
`xcode-select: error: tool 'xcodebuild' requires Xcode`.

For a distributable build you also need a **Developer ID Application** identity (the app
and its nested code), a **Developer ID Installer** identity (the package) and a
`notarytool` keychain profile. Without them the same scripts still build the app and the
package, unsigned — see [Signing](#signing) below.

### One command

    ./make_release.sh <version> "<Developer ID Application: … (TEAM_ID)>" [github-token]

It bumps `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, runs `notarize_app.sh`, then
tags the release, uploads `OpenSuperWhisper-<version>.pkg` (and, when `swifty-dmg` is
installed, the optional cask DMG) to the GitHub release, and prints the Homebrew cask
stanza that matches the artifacts.

### The same steps by hand

    Scripts/build-native.sh Release

    CARGO_PROFILE_RELEASE_LTO=true CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 \
    CARGO_PROFILE_RELEASE_STRIP=symbols CARGO_PROFILE_RELEASE_PANIC=abort \
    cargo build -p autocorrect-swift --release --target aarch64-apple-darwin \
      --manifest-path=libautocorrect/Cargo.toml
    cp libautocorrect/target/aarch64-apple-darwin/release/libautocorrect_swift.dylib \
      build/libautocorrect_swift.dylib
    install_name_tool -id "@rpath/libautocorrect_swift.dylib" build/libautocorrect_swift.dylib

    xcodebuild -scheme OpenSuperWhisper -configuration Release -jobs 8 \
      -derivedDataPath build -destination 'platform=macOS,arch=arm64' \
      -skipPackagePluginValidation -skipMacroValidation build

    packaging/build-pkg.sh --version <version> \
      --app build/Build/Products/Release/OpenSuperWhisper.app \
      --out "OpenSuperWhisper-<version>.pkg" \
      [--sign "<Developer ID Installer: …>" --notarize <keychain-profile>]

`Scripts/build-native.sh Release` builds llama.cpp (which owns the single ggml the app
links) and installs its ggml package, then configures whisper.cpp against that package
with `WHISPER_USE_SYSTEM_GGML=ON`. The app's Xcode project references both vendored
projects, so the Release configuration of each is built by the `xcodebuild` above.

`notarize_app.sh <identity>` is exactly this order plus signing, notarization and
stapling; it writes `OpenSuperWhisper-<version>.pkg` next to the checkout.

### Verify the packaging contract

    Scripts/verify-packaging.sh --app build/Build/Products/Release/OpenSuperWhisper.app

Checks the uninstaller's path list, its idempotence against a scratch root, and a built
package's payload (app, uninstall command, receipt id, no stray files). Green means the
declared paths and the shipped scripts agree.

### Signing

What ends up inside the package is the signature `build-pkg.sh` reports when it runs. The
designated requirement is the part that matters:

    codesign -d -r- path/to/OpenSuperWhisper.app

An ad-hoc build (no identity) reports `designated => cdhash H"…"`, which changes on every
build; macOS keys Accessibility and Microphone grants in TCC against that requirement, so a
rebuilt app silently loses them. A certificate-signed build reports

    designated => identifier "ru.starmel.OpenSuperWhisper" and certificate leaf = H"…"

which survives rebuilds signed with the same identity. `build-pkg.sh` prints this line for
the app it packages, and refuses to call a cdhash-only build distributable.

Package signing and notarization are parameterised, not baked in:

    OSW_SIGN_IDENTITY="Developer ID Installer: … (TEAM_ID)" \
    OSW_NOTARY_PROFILE=<keychain-profile> \
    packaging/build-pkg.sh --version <version>

With neither set, the package is built unsigned and `pkgutil --check-signature` says so.

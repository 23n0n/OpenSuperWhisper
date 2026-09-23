#!/bin/zsh

# Builds the two vendored inference engines for OpenSuperWhisper.
#
# Both engines live in the app process behind the shipped Swift wrappers, and
# they share ONE ggml:
#
#   1. libllama  (vendored llama.cpp) is configured and built, and its ggml
#                package is installed into libllama/build/ggml-prefix.
#   2. libwhisper is configured with WHISPER_USE_SYSTEM_GGML=ON against that
#      package, so whisper.cpp does NOT add its own ggml copy.
#
# The app links libllama.a + the ggml set from libllama's build tree and
# libwhisper.a from libwhisper's. Linking whisper.cpp's vendored ggml as well
# fails with duplicate symbols (936 shared globals in libggml-base alone): never
# add a second ggml to the link line.
#
# The Xcode projects the app target references are generated here:
#   libllama/build/libllama.xcodeproj
#   libwhisper/build/libwhisper.xcodeproj
#
# Usage:
#   Scripts/build-native.sh [Debug|Release]      (default: Debug)

set -e

CONFIG="${1:-Debug}"
REPO_ROOT="${0:A:h}/.."
cd "$REPO_ROOT"

JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"

echo "Configuring libllama (vendored llama.cpp, owns the single ggml)..."
cmake -G Xcode -B libllama/build -S libllama

echo "Building libllama (${CONFIG})..."
cmake --build libllama/build --config "$CONFIG" -j "$JOBS"

echo "Installing the ggml package for whisper.cpp..."
cmake --install libllama/build --config "$CONFIG" --prefix "$PWD/libllama/build/ggml-prefix"

echo "Configuring libwhisper against that ggml (WHISPER_USE_SYSTEM_GGML=ON)..."
cmake -G Xcode -B libwhisper/build -S libwhisper

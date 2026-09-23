# The in-process transform engine: llama.cpp, vendored exactly like whisper.cpp is.
#
# This project owns the ONE ggml in the app image. whisper.cpp is configured with
# WHISPER_USE_SYSTEM_GGML=ON against the ggml package this project installs, so
# the two engines share a single ggml (see libwhisper/CMakeLists.txt and
# Scripts/build-native.sh for the order). Linking whisper's own vendored ggml
# next to this one duplicates ~936 base, ~602 cpu and ~259 metal global symbols
# and fails at link time; never link a second ggml into the app.

# NOTE: we need this version for deterministic Xcode GUIDs:
# https://gitlab.kitware.com/cmake/cmake/-/merge_requests/9241
# Without this change, the GUIDs will be different every time the project is generated.
cmake_minimum_required(VERSION 3.30)

set(CMAKE_CXX_FLAGS_INIT "-fvisibility=hidden")
set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0")

project(libllama)

option(BUILD_SHARED_LIBS "build shared libraries" OFF)

# Disable i8mm/MATMUL_INT8 to fix compilation on GitHub Actions runners
# The feature detection passes but compilation fails with the newer Xcode toolchain
# Undefine the feature macro to prevent i8mm intrinsics from being used
add_compile_definitions(GGML_MATMUL_INT8=0)
add_compile_options(-U__ARM_FEATURE_MATMUL_INT8)

# Only the libraries. No tools, no server, no examples, no tests: the app calls
# the llama C API in-process.
set(LLAMA_BUILD_COMMON   OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS    OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS    OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER   OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_APP      OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_MTMD     OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL           OFF CACHE BOOL "" FORCE)
set(LLAMA_OPENSSL        OFF CACHE BOOL "" FORCE)

# OpenMP stays off on purpose: it used to be a Homebrew build dependency of this
# repo through `brew install libomp` even though nothing ever called an omp_*
# symbol. The engine is Metal + Accelerate here, and a deterministic OFF keeps a
# stray libomp out of the link line on any machine that happens to have one.
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)

# Metal with the shaders embedded in the static archive, exactly like the
# whisper build: no .metallib resource, no bundle payload.
set(GGML_METAL ON CACHE BOOL "" FORCE)
set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "" FORCE)

add_subdirectory(llama.cpp)

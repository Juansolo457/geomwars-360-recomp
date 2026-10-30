# geomwars - Geometry Wars: Retro Evolved (Xbox 360, Xbox Live Arcade) on ReXGlue, Vulkan only.
#
# SDK boilerplate lives in generated/rexglue.cmake (emitted by `rexglue init`). The SDK is the
# Vulkan-only build tools/setup.ps1 installs (third_party/rexglue-sdk-bd833a2/out/install).

cmake_minimum_required(VERSION 3.25)
project(geomwars LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Built for x86-64-v3 (tools/build.ps1: AVX2 and FMA), so the translated code's std::fma is one
# instruction. No floating-point contraction: clang would otherwise fuse a separate a*b+c into
# one FMA, rounding once where the PowerPC rounded twice.
add_compile_options($<$<CXX_COMPILER_ID:Clang,AppleClang>:-ffp-contract=off>)

include(generated/rexglue.cmake)

set(GEOMWARS_SOURCES
    src/main.cpp
    src/audio_dump.cpp
    src/crash_report.cpp
    src/autopilot.cpp
    src/ui_style.cpp
    src/ui_pad.cpp
    src/timer_resolution.cpp
    src/frame_timing.cpp
    src/cpu_check.cpp
    src/fpscr_guard.cpp
)

# The CPU check runs before any x86-64-v3 code (src/cpu_check.cpp), so it is built for v2 and
# without the precompiled header.
set_source_files_properties(src/cpu_check.cpp PROPERTIES COMPILE_OPTIONS "-march=x86-64-v2"
                            SKIP_PRECOMPILE_HEADERS ON)

if(WIN32)
    add_executable(geomwars WIN32 ${GEOMWARS_SOURCES})
else()
    add_executable(geomwars ${GEOMWARS_SOURCES})
endif()

# The Xenos plugin (Vulkan backend only) is copied next to the program so the runtime can load it.
rexglue_setup_target(geomwars GPU_PLUGINS xenos)
if(WIN32)
    target_link_libraries(geomwars PRIVATE dbghelp)   # crash reports
endif()

cmake_minimum_required(VERSION 3.25)
project(uc2_xberecomp LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(UC2_VERBOSE_LOGS "Keep XboxXBERecomp runtime Info logs in optimized builds" ON)

# SDL options that need headers but not optional desktop services. This keeps
# the Linux build self-contained and avoids unrelated D-Bus/IBus pkg-config
# requirements on systems that do not use those SDL integrations.
set(SDL_DBUS OFF CACHE BOOL "" FORCE)
set(SDL_IBUS OFF CACHE BOOL "" FORCE)

set(XBERECOMP_ROOT "$ENV{XBERECOMP_ROOT}" CACHE PATH "XboxXBERecomp Linux checkout")
if(NOT XBERECOMP_ROOT)
    set(XBERECOMP_ROOT "$ENV{HOME}/Projects/uc2-xberecomp-linux-evaluation" CACHE PATH
        "XboxXBERecomp Linux checkout" FORCE)
endif()
set(XBERECOMP_CMAKE "${XBERECOMP_ROOT}/sdk/cmake/XbeRecomp.cmake")
if(NOT EXISTS "${XBERECOMP_CMAKE}")
    message(FATAL_ERROR "XboxXBERecomp checkout not found. Set XBERECOMP_ROOT to its root directory.")
endif()

include("${XBERECOMP_CMAKE}")

# Reuse the Linux fork's shared host backends and runtime. UC2 supplies only
# its own title metadata and the generated XBE code from config/uc2.toml.
file(GLOB XBE_HOST_SOURCES CONFIGURE_DEPENDS "${XBERECOMP_ROOT}/src/*/*.cpp")
list(FILTER XBE_HOST_SOURCES EXCLUDE REGEX "/src/game/")
list(FILTER XBE_HOST_SOURCES EXCLUDE REGEX "/src/common/game_info\\.cpp$")
list(FILTER XBE_RUNTIME_SOURCES EXCLUDE REGEX "/app/game_files\\.cpp$")
list(FILTER XBE_RUNTIME_SOURCES EXCLUDE REGEX "/gpu/render_thread\\.cpp$")

add_xbe_image(UC2 default.xbe uc2.toml 64 uc2)
target_include_directories(UC2 PRIVATE "${XBERECOMP_ROOT}/src" "${sdl3_SOURCE_DIR}/include")
if(UC2_VERBOSE_LOGS AND NOT MSVC)
    # The fork uses NDEBUG to suppress Info logs in Release. Keep the optimized
    # code while retaining boot, D3D and per-frame performance diagnostics.
    target_compile_options(UC2 PRIVATE -UNDEBUG)
endif()
set_target_properties(UC2 PROPERTIES OUTPUT_NAME uc2_recomp)

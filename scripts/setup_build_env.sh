#!/bin/bash
#
# setup_build_env.sh — Prepare a fresh macOS machine to build the core
# frameworks via scripts/configure_frameworks.sh.
#
# It installs every dependency, sets up Rosetta, initialises the required git
# submodules, applies the source patch needed for recent Xcode/clang, and (with
# --build) runs the framework build with the correct environment.
#
# Usage:
#   sh scripts/setup_build_env.sh            # install/prepare everything
#   sh scripts/setup_build_env.sh --build    # ...then also build the frameworks
#
# Safe to re-run: every step is idempotent.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." >/dev/null && pwd)"

# Full Xcode (NOT just Command Line Tools) is required by configure_frameworks.sh.
XCODE_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
# CMake 4.x removed compatibility with cmake_minimum_required(VERSION < 3.5),
# which some bundled sources (mozjpeg, td) still declare. This lets them configure.
export CMAKE_POLICY_VERSION_MINIMUM=3.5

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0. Sanity checks
# ---------------------------------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || die "This script must be run on macOS."
ARCH="$(uname -m)"
log "Detected macOS on $ARCH"

# ---------------------------------------------------------------------------
# 1. Homebrew
# ---------------------------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
  log "Installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Make brew available on the current shell (Apple Silicon vs Intel prefix).
  if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"; fi
else
  log "Homebrew already installed: $(brew --version | head -1)"
fi

# ---------------------------------------------------------------------------
# 2. Build tools (Homebrew packages)
#    NOTE: nasm (OpenH264) and meson (dav1d) are required but were missing from
#    the original INSTALL.md list.
# ---------------------------------------------------------------------------
BREW_PACKAGES=(
  cmake        # libwebp / mozjpeg / tde2e / webrtc (tg_owt)
  ninja        # webrtc (tg_owt), dav1d
  meson        # dav1d
  nasm         # OpenH264 (x86_64 assembly)
  yasm         # ffmpeg / libvpx assembly
  zlib
  autoconf
  libtool
  automake
  pkg-config
)
log "Installing build dependencies: ${BREW_PACKAGES[*]}"
brew install "${BREW_PACKAGES[@]}"

# ---------------------------------------------------------------------------
# 3. Rosetta 2 (Apple Silicon only)
#    The tde2e/td build compiles a code-generation tool (tl-parser) for the
#    x86_64 slice and RUNS it during the build. On Apple Silicon that requires
#    Rosetta, otherwise it fails with "Bad CPU type in executable".
# ---------------------------------------------------------------------------
if [ "$ARCH" = "arm64" ]; then
  if arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
    log "Rosetta 2 already available"
  else
    log "Installing Rosetta 2 (needed to run the x86_64 codegen tool during the build)"
    softwareupdate --install-rosetta --agree-to-license
  fi
fi

# ---------------------------------------------------------------------------
# 4. Xcode (full IDE, with command line tools selected)
# ---------------------------------------------------------------------------
if [ -d "$XCODE_DEVELOPER_DIR" ]; then
  ACTIVE="$(xcode-select -p 2>/dev/null || true)"
  if [ "$ACTIVE" != "$XCODE_DEVELOPER_DIR" ]; then
    warn "Active developer dir is '$ACTIVE'."
    warn "configure_frameworks.sh needs full Xcode. Select it with:"
    warn "    sudo xcode-select -s \"$XCODE_DEVELOPER_DIR\""
    warn "(or run this build via DEVELOPER_DIR, which --build below does automatically)."
  fi
  # Accept the license if needed (no-op if already accepted).
  DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" xcodebuild -version >/dev/null 2>&1 \
    || warn "Xcode may require accepting its license: sudo xcodebuild -license accept"
  log "Full Xcode found at $XCODE_DEVELOPER_DIR"
else
  warn "Full Xcode not found at $XCODE_DEVELOPER_DIR."
  warn "Install it from the App Store (Command Line Tools alone are NOT enough)."
fi

# ---------------------------------------------------------------------------
# 5. Git submodules
#    The framework projects build from submodule sources (tg_owt, telegram-ios
#    third-party: td/dav1d/mozjpeg/ffmpeg, etc.).
# ---------------------------------------------------------------------------
log "Initialising git submodules (recursive)"
if ! git -C "$REPO_DIR" submodule update --init --recursive; then
  die "Submodule initialization failed. Resolve the Git error above and rerun this script."
fi

# ---------------------------------------------------------------------------
# 6. Source patch for recent Xcode/clang (Xcode 16+ / 26.x)
#    clang now hard-errors on [[clang::lifetimebound]] applied to a parameter
#    of a void-returning function (tg_owt's abseil). Neutralise the macro; it is
#    a static-analysis annotation only, with no runtime or ABI effect.
# ---------------------------------------------------------------------------
ABSL_ATTR="$REPO_DIR/submodules/tg_owt/src/third_party/abseil-cpp/absl/base/attributes.h"
if [ -f "$ABSL_ATTR" ]; then
  if grep -q '^#define ABSL_ATTRIBUTE_LIFETIME_BOUND \[\[clang::lifetimebound\]\]' "$ABSL_ATTR"; then
    log "Patching ABSL_ATTRIBUTE_LIFETIME_BOUND (clang lifetimebound compatibility)"
    /usr/bin/sed -i '' \
      -e 's|^#define ABSL_ATTRIBUTE_LIFETIME_BOUND \[\[clang::lifetimebound\]\]|#define ABSL_ATTRIBUTE_LIFETIME_BOUND|' \
      -e 's|^#define ABSL_ATTRIBUTE_LIFETIME_BOUND __attribute__((lifetimebound))|#define ABSL_ATTRIBUTE_LIFETIME_BOUND|' \
      "$ABSL_ATTR"
  else
    log "abseil lifetimebound already neutralised (or not present) — skipping patch"
  fi
else
  warn "tg_owt abseil attributes.h not found yet (submodules not initialised?) — skipping patch"
fi

# ---------------------------------------------------------------------------
# Done / optional build
# ---------------------------------------------------------------------------
log "Environment ready."
cat <<EOF

To build the frameworks, run with full Xcode selected and the CMake policy set:

    DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" \\
    CMAKE_POLICY_VERSION_MINIMUM=3.5 \\
    sh "$SCRIPT_DIR/configure_frameworks.sh"

Tip: configure_frameworks.sh validates cached inputs and required outputs.
Rerun it after an interrupted build to repair incomplete outputs. To force a
clean rebuild, set scripts/rebuild to "yes", run the script, then restore "no".
EOF

if [ "${1:-}" = "--build" ]; then
  log "Building frameworks (configure_frameworks.sh)"
  DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" \
  CMAKE_POLICY_VERSION_MINIMUM=3.5 \
  sh "$SCRIPT_DIR/configure_frameworks.sh"
  log "Framework build finished."
fi

#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
#  OMARCHY TERMUX — like-for-like native Omarchy installer
#  Repo:    https://github.com/NaustudentX18/omarchy-termux
#  Target:  Android 8+ / aarch64 / Termux from F-Droid or GitHub (NOT Play Store)
#
#  WHAT THIS INSTALLS (like-for-like with a real Omarchy machine):
#    Termux:X11 → patched Weston (nested Wayland) → patched Hyprland → the
#    REAL Omarchy Shell (quickshell bar, menu, notifications, OSD) + Foot,
#    Nautilus, Chromium, the omarchy CLI, Tokyo Night theme, wallpapers.
#
#    The heavy graphics stack (patched Hyprland/Aquamarine/Mesa-KGSL + a
#    pre-provisioned Omarchy rootfs) comes from BlackFireAlex's checksummed
#    omarchy-android release bundle (MIT). Nothing is compiled on the phone;
#    we only verify, deploy, and wire the launchers.
#    See: https://github.com/BlackFireAlex/omarchy-android
#
#  Legacy X11+i3 fallback installer is preserved at install-x11.sh in the repo.
# ==============================================================================

set -u

# --- Testability overrides (used by tests/run-tests.sh) -----------------------
TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
PROOT_STATE_DIR="$TERMUX_PREFIX/var/lib/proot-distro"
OA_CONTAINER="${OMARCHY_CONTAINER_NAME:-omarchy-android}"
OA_PREFIX="${OMARCHY_HOST_PREFIX:-$HOME/.local/share/omarchy-android}"
OA_STATE_DIR="${OMARCHY_STATE_DIR:-$HOME/.local/state/$OA_CONTAINER}"
BUNDLE="${OMARCHY_BUNDLE:-}"

# Pinned release (manifest/release.lock of BlackFireAlex/omarchy-android).
# Keep RELEASE_* and OA_GIT_REF on the same tag when bumping with Android Bundle.
RELEASE_URL="https://github.com/BlackFireAlex/omarchy-android/releases/download/v0.1.1/omarchy-android-aarch64-0.1.1.bundle.tar"
RELEASE_SHA256="7e9f1cd67533bc0d3988b5cb3831aef52f1527dd90391d9d868ed9345021cdb2"
BUNDLE_ASSET="omarchy-android-aarch64-0.1.1.bundle.tar"
OA_GIT_REPO="https://github.com/BlackFireAlex/omarchy-android.git"
OA_GIT_REF="v0.1.1"

# --- Pretty logging ------------------------------------------------------------
BOLD="\033[1m"; GREEN="\033[32m"; BLUE="\033[34m"; YELLOW="\033[33m"
RED="\033[31m"; CYAN="\033[36m"; MAGENTA="\033[35m"; RESET="\033[0m"
log_info() { printf '%b\n' "${BLUE}${BOLD}[*]${RESET} $*"; }
log_ok()   { printf '%b\n' "${GREEN}${BOLD}[✓]${RESET} $*"; }
log_warn() { printf '%b\n' "${YELLOW}${BOLD}[!]${RESET} $*"; }
log_fail() { printf '%b\n' "${RED}${BOLD}[✗]${RESET} $*"; }
log_step() { printf '\n%b\n' "${CYAN}${BOLD}==>${RESET} ${BOLD}$*${RESET}"; }
die() { log_fail "$*"; exit 1; }

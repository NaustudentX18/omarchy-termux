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

getprop_val() {
    if command -v getprop >/dev/null 2>&1; then
        getprop "$1" 2>/dev/null
    elif [ -x /system/bin/getprop ]; then
        /system/bin/getprop "$1" 2>/dev/null
    else
        printf ''
    fi
}

# --- doctor subcommand: inspect host readiness, change nothing -----------------
run_doctor() {
    local failures=0
    printf '%-22s %-6s %s\n' "CHECK" "RESULT" "DETAIL"
    check() { printf '%-22s %-6s %s\n' "$1" "$2" "$3"; }
    if [ -n "${TERMUX_VERSION:-}" ] || [ -d /data/data/com.termux ]; then
        check "Termux" PASS "PREFIX=${TERMUX_PREFIX}"
    else check "Termux" FAIL "not in Termux"; failures=$((failures+1)); fi
    case "$(uname -m)" in
        aarch64|arm64) check "Architecture" PASS "$(uname -m)" ;;
        *) check "Architecture" FAIL "$(uname -m) (aarch64 required)"; failures=$((failures+1)) ;;
    esac
    for cmd in proot-distro termux-x11 weston pulseaudio xwininfo curl sha256sum; do
        if command -v "$cmd" >/dev/null 2>&1; then
            check "$cmd" PASS "$(command -v "$cmd")"
        else
            check "$cmd" MISS "install with: pkg install $cmd"
            failures=$((failures+1))
        fi
    done
    if [ -r /dev/kgsl-3d0 ] && [ -w /dev/kgsl-3d0 ]; then
        check "Adreno KGSL" PASS "/dev/kgsl-3d0 read+write -> direct GPU accel"
    else
        check "Adreno KGSL" WARN "absent -> VirGL software fallback"
    fi
    if [ "$(getprop_val persist.sys.fflag.override.settings_enable_monitor_phantom_procs)" = "false" ]; then
        check "Phantom processes" PASS "child-process restriction disabled"
    else
        check "Phantom processes" FAIL "enable Developer options -> 'Disable child process restrictions'"
        failures=$((failures+1))
    fi
    if command -v am >/dev/null 2>&1; then
        if am start -n com.termux.x11/.MainActivity --dry-run >/dev/null 2>&1 || \
           am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p com.termux.x11 >/dev/null 2>&1; then
            check "Termux:X11 app" PASS "installed"
        else
            check "Termux:X11 app" WARN "not detected - install NIGHTLY APK (github.com/termux/termux-x11/releases)"
        fi
    else
        check "Termux:X11 app" WARN "cannot probe without 'am'"
    fi
    if [ -f "$OA_PREFIX/config/runtime.conf" ]; then
        check "omarchy-termux" PASS "runtime installed at $OA_PREFIX"
    else
        check "omarchy-termux" MISS "not installed yet - run this installer"
    fi
    echo
    if [ "$failures" = 0 ]; then log_ok "Doctor: all required checks passed."
    else die "Doctor: $failures required check(s) failing."; fi
    exit 0
}
[ "${1:-}" = "doctor" ] && run_doctor

banner() {
    cat << "BANNER_TXT"
  ___  __  __   _   ___  ___ _  ___   __
 / _ \|  \/  | /_\ | _ \/ __| || \ \ / /
| (_) | |\/| |/ _ \|   / (__| __ |\ V /
 \___/|_|  |_/_/ \_\_|_\\___|_||_| |_|
     Android Termux Edition — native parity
BANNER_TXT
    printf '%b\n' "${MAGENTA}  The real Omarchy: Hyprland + Omarchy Shell on Android (PRoot)${RESET}"
    printf '\n'
}
banner

# ==============================================================================
# STEP 1/7 — Preflight: Termux, arch, Android, phantom processes, storage
# ==============================================================================
log_step "Step 1/7: Preflight (run '$0 doctor' for details anytime)"

if [ -z "${TERMUX_VERSION:-}" ] && [ ! -d "/data/data/com.termux" ]; then
    die "This installer must run inside Termux on Android.
         Install Termux from F-Droid: https://f-droid.org/en/packages/com.termux/"
fi

ARCH="$(uname -m)"
case "$ARCH" in
    aarch64|arm64) ;;
    *) die "Unsupported architecture: $ARCH. The native-parity stack (Hyprland
            KGSL build) is aarch64-only. On other devices use install-x11.sh." ;;
esac
log_ok "Architecture: aarch64"

command -v termux-wake-lock >/dev/null 2>&1 && { termux-wake-lock || true; log_ok "Wake-lock acquired."; }

# Android 12+ kills background child processes ("phantom process killer").
# A full Omarchy session needs many processes; without the developer-options
# override the desktop dies within ~30s of starting.
getprop_val() {
    if command -v getprop >/dev/null 2>&1; then
        getprop "$1" 2>/dev/null
    elif [ -x /system/bin/getprop ]; then
        /system/bin/getprop "$1" 2>/dev/null
    else
        ""
    fi
}
if [ "$(getprop_val persist.sys.fflag.override.settings_enable_monitor_phantom_procs)" = "false" ]; then
    log_ok "Android child-process restriction: disabled (phantom processes OK)."
else
    log_warn "Android's phantom-process restriction appears ACTIVE.
         A full Omarchy session will be reaped. To disable:
           Settings → About phone → tap 'Build number' 7×  →  Developer options
           → enable 'Disable child process restrictions'
         Then re-run this installer (or: install anyway and fix later)."
fi

# Storage is optional (like omarchy-android: no host sharing by default).
if [ -d "$HOME/storage/shared" ]; then
    log_ok "Storage permission present (not used by default — sharing is opt-in)."
else
    log_info "Storage permission not granted (optional; sharing is opt-in)."
fi

# ==============================================================================
# STEP 2/7 — Termux host packages
# ==============================================================================
log_step "Step 2/7: Installing Termux host packages"

APT_OPTS=(-o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold")
log_info "Updating package index..."
if ! pkg update -y "${APT_OPTS[@]}"; then
    log_warn "pkg update failed — trying apt directly..."
    apt-get update -y || log_warn "Index update failed. If installs fail: termux-change-repo"
fi
pkg upgrade -y "${APT_OPTS[@]}" || log_warn "pkg upgrade had issues — continuing."

# x11-repo provides weston + termux-x11-nightly; main repo provides the rest.
log_info "Enabling the Termux X11 repository..."
pkg install -y x11-repo "${APT_OPTS[@]}" || log_warn "x11-repo enable failed — weston/termux-x11 may be missing."

HOST_PACKAGES=(proot-distro git curl wget tar pulseaudio pactl
               weston termux-x11-nightly xorg-xwininfo
               mesa-vulkan-icd-freedreno virglrenderer-android jq bash)
log_info "Installing host packages: ${HOST_PACKAGES[*]}"
for p in "${HOST_PACKAGES[@]}"; do
    command -v "$p" >/dev/null 2>&1 && continue
    case "$p" in
        termux-x11-nightly) command -v termux-x11 >/dev/null 2>&1 && continue ;;
    esac
    pkg install -y "$p" "${APT_OPTS[@]}" || log_warn "Could not install '$p' — continuing."
done
# mesa-vulkan-icd-freedreno installs a binary that pkg sees under a different name
command -v termux-x11 >/dev/null 2>&1 \
    || pkg install -y termux-x11-nightly "${APT_OPTS[@]}" \
    || log_warn "termux-x11 missing — GUI cannot start without it."

MISSING=""
for p in proot-distro termux-x11 weston pulseaudio xwininfo sha256sum; do
    command -v "$p" >/dev/null 2>&1 || MISSING="$MISSING $p"
done
[ -z "$MISSING" ] || die "Required host commands still missing:$MISSING
         Fix with: pkg install$MISSING   then re-run."
log_ok "Termux host packages ready."

# ==============================================================================
# STEP 3/7 — Fetch & verify the omarchy-android release bundle
# ==============================================================================
log_step "Step 3/7: Fetching verified Omarchy ARM64 release bundle (~1.1 GB)"

BUNDLE_DIR="$HOME/.cache/omarchy-termux"
mkdir -p "$BUNDLE_DIR"
BUNDLE_PATH="$BUNDLE_DIR/$BUNDLE_ASSET"

if [ -n "$BUNDLE" ] && [ -f "$BUNDLE" ]; then
    log_info "Using local bundle: $BUNDLE"
    BUNDLE_PATH="$BUNDLE"
else
    NEED_DL=1
    if [ -f "$BUNDLE_PATH" ]; then
        log_info "Found cached bundle — verifying checksum..."
        ACTUAL="$(sha256sum "$BUNDLE_PATH" | awk '{print $1}')"
        if [ "$ACTUAL" = "$RELEASE_SHA256" ]; then
            NEED_DL=0
            log_ok "Cached bundle checksum OK — skipping download."
        else
            log_warn "Cached bundle checksum mismatch — re-downloading."
        fi
    fi
    if [ "$NEED_DL" = "1" ]; then
        log_info "Downloading release bundle (one-time, ~1.1 GB)..."
        if ! curl --fail --location --retry 3 --progress-bar \
              --output "$BUNDLE_PATH" "$RELEASE_URL"; then
            rm -f "$BUNDLE_PATH"
            die "Release download failed. Check network and re-run the installer."
        fi
    fi
fi

ACTUAL="$(sha256sum "$BUNDLE_PATH" | awk '{print $1}')"
[ "$ACTUAL" = "$RELEASE_SHA256" ] || die "Bundle checksum mismatch.
         expected $RELEASE_SHA256
         actual   $ACTUAL
         Delete $BUNDLE_PATH and re-run, or pass a local file: OMARCHY_BUNDLE=<path> $0"
log_ok "Bundle verified (sha256 OK)."

# ==============================================================================
# STEP 4/7 — Extract bundle & deploy rootfs + host runtime
# ==============================================================================
log_step "Step 4/7: Deploying Omarchy rootfs & host runtime"

UNPACK="$BUNDLE_DIR/unpacked"
rm -rf "$UNPACK"
mkdir -p "$UNPACK"

# Path-safety scan before extraction (never trust tar members blindly)
if tar -tf "$BUNDLE_PATH" | grep -qE '^(/|\.\./|/\.\./|\.\.(/|$))'; then
    die "Unsafe path in release bundle — refusing to extract."

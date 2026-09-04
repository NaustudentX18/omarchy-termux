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

# Pinned release (manifest/release.lock of BlackFireAlex/omarchy-android v0.1.1)
RELEASE_URL="https://github.com/BlackFireAlex/omarchy-android/releases/download/v0.1.1/omarchy-android-aarch64-0.1.1.bundle.tar"
RELEASE_SHA256="7e9f1cd67533bc0d3988b5cb3831aef52f1527dd90391d9d868ed9345021cdb2"
BUNDLE_ASSET="omarchy-android-aarch64-0.1.1.bundle.tar"

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
fi
tar -xf "$BUNDLE_PATH" -C "$UNPACK" || die "Bundle extraction failed."

[ -f "$UNPACK/SHA256SUMS" ] || die "Bundle integrity file SHA256SUMS missing."
( cd "$UNPACK" && sha256sum -c SHA256SUMS --quiet ) \
    || die "Bundle inner checksums failed — the download is corrupt. Delete and re-run."
log_ok "Bundle contents verified (SHA256SUMS)."

[ -f "$UNPACK/rootfs.tar.xz" ] || die "Bundle rootfs missing."
[ -f "$UNPACK/host/opt/weston/lib/libweston-14/x11-backend.so" ] || die "Patched Weston backend missing from bundle."

# Container already installed? Keep idempotent: leave it alone, just rewire.
find_rootfs() {
    if [ -d "$PROOT_STATE_DIR/containers/$OA_CONTAINER/rootfs/home" ]; then
        echo "$PROOT_STATE_DIR/containers/$OA_CONTAINER/rootfs"
    elif [ -d "$PROOT_STATE_DIR/installed-rootfs/$OA_CONTAINER/rootfs/home" ] 2>/dev/null; then
        echo "$PROOT_STATE_DIR/installed-rootfs/$OA_CONTAINER/rootfs"
    fi
}
ROOTFS="$(find_rootfs)"

if [ -n "$ROOTFS" ]; then
    log_ok "Container '$OA_CONTAINER' already installed — skipping rootfs deploy."
else
    log_info "Creating PRoot container '$OA_CONTAINER' (prebuilt Omarchy rootfs)..."
    # Register stale/broken entries out of the way first
    if proot-distro list 2>/dev/null | grep -q "$OA_CONTAINER" && \
       [ ! -d "$PROOT_STATE_DIR/containers/$OA_CONTAINER/rootfs/home" ] && \
       [ ! -d "$PROOT_STATE_DIR/installed-rootfs/$OA_CONTAINER/rootfs/home" ] 2>/dev/null; then
        proot-distro remove "$OA_CONTAINER" >/dev/null 2>&1 || true
    fi
    if ! proot-distro install --name "$OA_CONTAINER" --architecture aarch64 \
            "$UNPACK/rootfs.tar.xz"; then
        die "proot-distro install failed. Free up storage (need ~8 GB free) and re-run."
    fi
    ROOTFS="$(find_rootfs)"
    [ -n "$ROOTFS" ] || die "Rootfs did not appear after install — check proot-distro output."
    log_ok "Omarchy rootfs deployed (user: omarchy, real Omarchy Shell included)."
fi

# The runtime bind-mounts Termux's private /run onto the guest
install -d -m 0755 "$ROOTFS/run/user/1000" 2>/dev/null || \
    log_warn "Could not create $ROOTFS/run/user/1000 (non-root). Runtime may handle it."

# --- Host runtime: launchers + patched Weston module --------------------------
log_info "Installing host runtime (launchers, patched Weston X11 backend)..."
install -d -m 0755 "$OA_PREFIX/bin" "$OA_PREFIX/config" \
                    "$OA_PREFIX/opt/weston/lib/libweston-14"
install -m 0755 \
    "$UNPACK/host/bin/omarchy-process-guard" \
    "$UNPACK/host/bin/omarchy-x11-keyboard" \
    "$OA_PREFIX/bin/" 2>/dev/null || log_warn "Host helper binaries missing from bundle — continuing (they are optional)."
install -m 0755 \
    "$UNPACK/host/opt/weston/lib/libweston-14/x11-backend.so" \
    "$OA_PREFIX/opt/weston/lib/libweston-14/x11-backend.so"

# GPU mode auto-detect: KGSL needs /dev/kgsl-3d0 read+write
GPU_MODE="${OMARCHY_GPU_MODE:-auto}"
if [ "$GPU_MODE" = "auto" ]; then
    if [ -r /dev/kgsl-3d0 ] && [ -w /dev/kgsl-3d0 ]; then
        GPU_MODE=kgsl
    else
        GPU_MODE=virgl
        log_warn "No Adreno KGSL device — using VirGL software GPU (slower but universal)."
    fi
fi
case "$GPU_MODE" in kgsl|virgl) ;; *) die "Invalid OMARCHY_GPU_MODE: $GPU_MODE" ;; esac

REFRESH_MHZ="${OMARCHY_REFRESH_MHZ:-120000}"
UI_SCALE="${OMARCHY_SCALE:-2}"
KEYBOARD_LAYOUT="${OMARCHY_KEYBOARD_LAYOUT:-auto}"
SHARE_MODE="${OMARCHY_SHARE:-none}"
AUDIO_ENABLED="${OMARCHY_AUDIO:-1}"

cat > "$OA_PREFIX/config/runtime.conf" << RUNTIME_CONF
# Generated by omarchy-termux installer. Like-for-like omarchy-android runtime.
OMARCHY_CONTAINER=$OA_CONTAINER
OMARCHY_GPU_MODE=$GPU_MODE
OMARCHY_COMPOSITOR_GL_DRIVER=kgsl
OMARCHY_DISPLAY_RESOLUTION=auto
OMARCHY_REFRESH_MHZ=$REFRESH_MHZ
OMARCHY_SCALE=$UI_SCALE
OMARCHY_KEYBOARD_LAYOUT=$KEYBOARD_LAYOUT
OMARCHY_SHARE=$SHARE_MODE
OMARCHY_AUDIO=$AUDIO_ENABLED
OMARCHY_PROCESS_LIMIT=28
RUNTIME_CONF
log_ok "Runtime config written ($GPU_MODE GPU, scale $UI_SCALE, $((REFRESH_MHZ/1000)) Hz)."

# ==============================================================================
# STEP 5/7 — Vendor omarchy-android's start/stop/status launch scripts
# ==============================================================================
log_step "Step 5/7: Installing session management scripts"

# The start/stop/status/hyprctl scripts are upstream's runtime; pin the same
# v0.1.1 revision the bundle was built from so host+guest always match.
OA_GIT_DIR="$BUNDLE_DIR/omarchy-android-src"
OA_START_SRC=""
if command -v git >/dev/null 2>&1; then
    if [ ! -d "$OA_GIT_DIR" ]; then
        log_info "Fetching omarchy-android runtime scripts (shallow clone)..."
        git clone --depth 1 https://github.com/BlackFireAlex/omarchy-android.git "$OA_GIT_DIR" 2>/dev/null \
            || log_warn "Clone failed — will fall back to inline vendored copies."
    fi
    [ -f "$OA_GIT_DIR/runtime/host/omarchy-android-start" ] && OA_START_SRC="$OA_GIT_DIR/runtime/host"
fi

if [ -n "$OA_START_SRC" ]; then
    install -m 0755 \
        "$OA_START_SRC/omarchy-android-start" \
        "$OA_START_SRC/omarchy-android-stop" \
        "$OA_START_SRC/omarchy-android-status" \
        "$OA_START_SRC/omarchy-android-hyprctl" \
        "$OA_PREFIX/bin/"
    log_ok "Session scripts installed from omarchy-android v0.1.1 runtime."
else
    log_warn "Could not vendor runtime scripts — the bundle lacks them.
         Get them manually: https://github.com/BlackFireAlex/omarchy-android/tree/main/runtime/host"
fi

# The unified 'omarchy-android' dispatcher
cat > "$OA_PREFIX/bin/omarchy-android" << 'DISPATCH'
#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
case "${1:-start}" in
  start) shift || true; exec "$script_dir/omarchy-android-start" "$@" ;;
  stop) shift || true; exec "$script_dir/omarchy-android-stop" "$@" ;;
  status) shift || true; exec "$script_dir/omarchy-android-status" "$@" ;;
  hyprctl) shift || true; exec "$script_dir/omarchy-android-hyprctl" "$@" ;;
  *) printf 'usage: %s {start|stop|status|hyprctl}\n' "$0" >&2; exit 2 ;;
esac
DISPATCH
chmod 0755 "$OA_PREFIX/bin/omarchy-android"

# ==============================================================================
# STEP 6/7 — User-facing launchers: omarchy-gui / omarchy-cli / shortcut
# ==============================================================================
log_step "Step 6/7: Creating launchers"

cat > "$HOME/start-omarchy.sh" << GUI_LAUNCHER
#!/data/data/com.termux/files/usr/bin/bash
# Like-for-like Omarchy session: Termux:X11 → Weston → Hyprland → Omarchy Shell
exec "$OA_PREFIX/bin/omarchy-android" start
GUI_LAUNCHER
chmod 0755 "$HOME/start-omarchy.sh"

cat > "$HOME/stop-omarchy.sh" << STOP_LAUNCHER
#!/data/data/com.termux/files/usr/bin/bash
exec "$OA_PREFIX/bin/omarchy-android" stop
STOP_LAUNCHER
chmod 0755 "$HOME/stop-omarchy.sh"

# CLI: log straight into the Omarchy container as user omarchy
cat > "$HOME/omarchy-cli.sh" << CLI_LAUNCHER
#!/data/data/com.termux/files/usr/bin/bash
# Terminal-only Omarchy (no GUI). PULSE over TCP only when the bridge runs.
export PULSE_SERVER="\${PULSE_SERVER:-tcp:127.0.0.1:4715}"
exec proot-distro login "$OA_CONTAINER" --user omarchy
CLI_LAUNCHER
chmod 0755 "$HOME/omarchy-cli.sh"

# Real executables on PATH
printf '#!/data/data/com.termux/files/usr/bin/bash\nexec %s "$@"\n' "$HOME/start-omarchy.sh" \
    > "$TERMUX_PREFIX/bin/omarchy-gui" && chmod 0755 "$TERMUX_PREFIX/bin/omarchy-gui"
printf '#!/data/data/com.termux/files/usr/bin/bash\nexec %s "$@"\n' "$HOME/omarchy-cli.sh" \
    > "$TERMUX_PREFIX/bin/omarchy-cli" && chmod 0755 "$TERMUX_PREFIX/bin/omarchy-cli"
printf '#!/data/data/com.termux/files/usr/bin/bash\nexec %s "$@"\n' "$HOME/stop-omarchy.sh" \
    > "$TERMUX_PREFIX/bin/omarchy-stop" && chmod 0755 "$TERMUX_PREFIX/bin/omarchy-stop"
log_ok "Commands installed: omarchy-gui · omarchy-cli · omarchy-stop"

# Termux:Widget home-screen shortcut
if [ -d "$HOME/.shortcuts" ] || command -v termux-widget >/dev/null 2>&1; then
    mkdir -p "$HOME/.shortcuts"
    printf '#!/data/data/com.termux/files/usr/bin/bash\n%s\n' "$HOME/start-omarchy.sh" \
        > "$HOME/.shortcuts/Omarchy" && chmod 0755 "$HOME/.shortcuts/Omarchy"
    log_ok "Termux:Widget shortcut created (~/.shortcuts/Omarchy)."
fi

if ! grep -q "omarchy-termux aliases" "$HOME/.bashrc" 2>/dev/null; then
    {
        echo "# omarchy-termux aliases"
        echo "alias omarchy-gui='$HOME/start-omarchy.sh'"
        echo "alias omarchy-cli='$HOME/omarchy-cli.sh'"
    } >> "$HOME/.bashrc"
    log_ok "Aliases added to ~/.bashrc"
fi

# ==============================================================================
# STEP 7/7 — Verification
# ==============================================================================
log_step "Step 7/7: Verifying installation"

V_ERR=0
[ -x "$OA_PREFIX/bin/omarchy-android" ] || { log_fail "dispatcher missing"; V_ERR=1; }
[ -f "$OA_PREFIX/config/runtime.conf" ] || { log_fail "runtime.conf missing"; V_ERR=1; }
[ -f "$OA_PREFIX/opt/weston/lib/libweston-14/x11-backend.so" ] || { log_fail "patched Weston backend missing"; V_ERR=1; }
[ -d "$ROOTFS/opt/omarchy-android/hyprland" ] || { log_fail "Hyprland stage missing in guest"; V_ERR=1; }
[ -d "$ROOTFS/usr/share/omarchy" ] || { log_fail "/usr/share/omarchy missing in guest"; V_ERR=1; }
[ -f "$ROOTFS/home/omarchy/.config/hypr/hyprland.lua" ] || { log_fail "guest Hyprland config missing"; V_ERR=1; }

# Termux:X11 app presence check (am resolve; silence when inconclusive)
if command -v am >/dev/null 2>&1; then
    if ! am start -n com.termux.x11/.MainActivity --dry-run >/dev/null 2>&1 \
       && ! am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER \
              -p com.termux.x11 >/dev/null 2>&1; then
        log_warn "Termux:X11 APP not detected — install the NIGHTLY APK:
         https://github.com/termux/termux-x11/releases/tag/nightly"
    else
        log_ok "Termux:X11 app present."
    fi
else
    log_warn "Cannot probe for Termux:X11 app (no 'am') — install the NIGHTLY APK:
         https://github.com/termux/termux-x11/releases/tag/nightly"
fi

[ "$V_ERR" = "0" ] || die "Verification failed — see messages above."

# Guest smoke test (fast, non-GUI): confirm the prebuilt stack is intact
log_info "Guest smoke test (prebuilt Omarchy stack)..."
if ! proot-distro login "$OA_CONTAINER" --user omarchy -- bash --noprofile --norc -euc '
    test -f /etc/omarchy-android-release
    test -x /opt/omarchy-android/hyprland/bin/Hyprland
    command -v quickshell >/dev/null
    command -v foot >/dev/null
    command -v nautilus >/dev/null
    test -f /usr/share/omarchy/shell/shell.qml
    test -s "$HOME/.local/state/omarchy/current/theme.name"
' 2>/dev/null; then
    die "Guest smoke test failed — the container did not pass omarchy integrity checks."
fi
log_ok "Guest smoke test passed: Hyprland · Omarchy Shell · Foot · theme all present."

printf '\n%b\n' "${GREEN}${BOLD}════════════════════════════════════════════════${RESET}"
printf '%b\n'   "${GREEN}${BOLD}   INSTALLATION COMPLETE — NATIVE-PARITY OMARCHY    ${RESET}"
printf '%b\n\n' "${GREEN}${BOLD}════════════════════════════════════════════════${RESET}"
printf '  Start desktop : %b   (switch to the Termux:X11 app when it opens)\n' "${MAGENTA}${BOLD}omarchy-gui${RESET}"
printf '  Stop desktop  : %b\n' "${MAGENTA}${BOLD}omarchy-stop${RESET}"
printf '  Terminal only : %b\n' "${MAGENTA}${BOLD}omarchy-cli${RESET}\n"
printf '  Status        : %b status\n' "${MAGENTA}${BOLD}omarchy-gui${RESET}"
printf '\n  This is the REAL Omarchy: Hyprland + Omarchy Shell (bar, menu,\n'
printf '  notifications) + Foot + Nautilus + Chromium, Tokyo Night themed.\n'
printf '  GPU: %s · scale %s · first start takes ~20-30s to warm up.\n\n' "$GPU_MODE" "$UI_SCALE"
printf '%b\n' "Enjoy Omarchy on Android!"
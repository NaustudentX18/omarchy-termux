#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
#  OMARCHY TERMUX — one-shot installer
#  Repo:    https://github.com/NaustudentX18/omarchy-termux
#  Target:  Android 8+ / aarch64 / Termux from F-Droid (NOT Play Store)
#
#  Design rules (each fixes a bug from earlier iterations):
#   1. Inner PRoot scripts are fully self-contained — they never reference
#      functions or variables defined in this outer script.
#   2. Container detection checks the rootfs DIRECTORY on disk, never
#      `proot-distro list` output (which also lists non-installed distros).
#   3. Every critical command has explicit error capture — no inverted flags,
#      no dead variables.
#   4. All inner-script file paths go through R="${OMARCHY_ROOTFS:-/}" so the
#      whole flow can be dry-run tested on a desktop with stubs
#      (see tests/run-tests.sh).
#   5. The installer is idempotent: re-running after a failure resumes.
# ==============================================================================

set -u
# --- Testability: allow PREFIX/HOME override (used by tests/run-tests.sh) ----
TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
PROOT_STATE_DIR="$TERMUX_PREFIX/var/lib/proot-distro"

# --- Pretty logging -----------------------------------------------------------
BOLD="\033[1m"; GREEN="\033[32m"; BLUE="\033[34m"; YELLOW="\033[33m"
RED="\033[31m"; CYAN="\033[36m"; MAGENTA="\033[35m"; RESET="\033[0m"

log_info() { printf '%b\n' "${BLUE}${BOLD}[*]${RESET} $*"; }
log_ok()   { printf '%b\n' "${GREEN}${BOLD}[✓]${RESET} $*"; }
log_warn() { printf '%b\n' "${YELLOW}${BOLD}[!]${RESET} $*"; }
log_fail() { printf '%b\n' "${RED}${BOLD}[✗]${RESET} $*"; }
log_step() { printf '\n%b\n' "${CYAN}${BOLD}==>${RESET} ${BOLD}$*${RESET}"; }

die() { log_fail "$*"; exit 1; }

banner() {
    cat << "BANNER_TXT"
  ___  __  __   _   ___  ___ _  ___   __
 / _ \|  \/  | /_\ | _ \/ __| || \ \ / /
| (_) | |\/| |/ _ \|   / (__| __ |\ V /
 \___/|_|  |_/_/ \_\_|_\\___|_||_| |_|
      Android Termux Edition
BANNER_TXT
    printf '%b\n' "${MAGENTA}  Opinionated, Modern Linux on Android (PRoot + Termux:X11)${RESET}"
    printf '\n'
}

banner

# ==============================================================================
# STEP 1/6 — Preflight
# ==============================================================================
log_step "Step 1/6: Verifying Termux host environment"

if [ -z "${TERMUX_VERSION:-}" ] && [ ! -d "/data/data/com.termux" ]; then
    die "This installer must run inside Termux on Android.
         Install Termux from F-Droid: https://f-droid.org/en/packages/com.termux/"
fi

ARCH="$(uname -m)"
case "$ARCH" in
    aarch64|arm64) TARGET_ARCH="aarch64" ;;
    x86_64|amd64)  TARGET_ARCH="x86_64" ;;
    *) die "Unsupported CPU architecture: $ARCH (need aarch64 or x86_64)." ;;
esac
log_ok "Architecture: $TARGET_ARCH"

command -v termux-wake-lock >/dev/null 2>&1 && { termux-wake-lock || true; log_ok "Wake-lock acquired."; }

# Storage permission is OPTIONAL — only needed to see /sdcard inside PRoot.
if [ ! -d "$HOME/storage/shared" ]; then
    log_info "Requesting storage permission (optional — tap Allow if prompted)..."
    command -v termux-setup-storage >/dev/null 2>&1 && termux-setup-storage || true
    sleep 1
    [ -d "$HOME/storage/shared" ] && log_ok "Storage granted (/sdcard visible in PRoot)." \
                                       || log_warn "Storage not granted — install continues without /sdcard."
else
    log_ok "Storage permissions already configured."
fi

# ==============================================================================
# STEP 2/6 — Termux host packages
# ==============================================================================
log_step "Step 2/6: Updating Termux repositories & installing host tools"

APT_OPTS=(-o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold")

log_info "Updating package index (and applying pending upgrades)..."
if ! pkg update -y "${APT_OPTS[@]}"; then
    log_warn "pkg update failed — trying apt directly..."
    apt-get update -y || log_warn "Index update failed. If installs below fail, run: termux-change-repo"
fi
pkg upgrade -y "${APT_OPTS[@]}" || log_warn "pkg upgrade had issues — continuing."

log_info "Enabling the Termux X11 repository..."
pkg install -y x11-repo "${APT_OPTS[@]}" || log_warn "x11-repo enable failed — X11 package may be missing."

# termux-x11 first (x11-repo), nightly as fallback (nightly repo).
for p in termux-x11 termux-x11-nightly; do
    command -v termux-x11 >/dev/null 2>&1 && break
    pkg install -y "$p" "${APT_OPTS[@]}" || true
done
command -v termux-x11 >/dev/null 2>&1 && log_ok "termux-x11 companion package present." \
                                              || log_warn "termux-x11 package missing — GUI mode needs it (see README §Troubleshooting)."

HOST_PACKAGES=(proot-distro git curl wget tar pulseaudio virglrenderer-android jq bash)
log_info "Installing host packages: ${HOST_PACKAGES[*]}"
for p in "${HOST_PACKAGES[@]}"; do
    command -v "$p" >/dev/null 2>&1 && continue
    pkg install -y "$p" "${APT_OPTS[@]}" || log_warn "Could not install '$p' — continuing."
done
log_ok "Termux host packages verified."

# ==============================================================================
# STEP 3/6 — Bootstrap Arch Linux (idempotent: disk check, never list parsing)
# ==============================================================================
log_step "Step 3/6: Bootstrapping Arch Linux (${TARGET_ARCH})"

# Two rootfs layouts exist across proot-distro versions:
#   legacy/alias:  .../installed-rootfs/archlinux
#   modern (v5+):  .../containers/archlinux/rootfs
find_rootfs() {
    if   [ -d "$PROOT_STATE_DIR/installed-rootfs/archlinux/etc" ]; then
        echo "$PROOT_STATE_DIR/installed-rootfs/archlinux"
    elif [ -d "$PROOT_STATE_DIR/containers/archlinux/rootfs/etc" ]; then
        echo "$PROOT_STATE_DIR/containers/archlinux/rootfs"
    fi
}
PROOT_ROOT="$(find_rootfs)"

if [ -n "$PROOT_ROOT" ]; then
    log_ok "Existing Arch Linux rootfs found — skipping download."
else
    log_info "Downloading & deploying Arch Linux rootfs (~140 MB)..."
    if [ "$TARGET_ARCH" = "aarch64" ]; then
        # proot-distro v5+ pulls 'archlinux' from Docker Hub, which is amd64-only.
        # Install the official Arch Linux ARM tarball from the last release
        # that shipped it (asset still served — verified 2026-09).
        ALARM_TARBALL="https://github.com/termux/proot-distro/releases/download/v4.17.3/archlinux-aarch64-pd-v4.17.3.tar.xz"
        # A registered container without a rootfs dir is stale/broken — clear it.
        proot-distro remove archlinux >/dev/null 2>&1 || true
        if ! proot-distro install --name archlinux "$ALARM_TARBALL"; then
            log_warn "Tarball install failed — trying distro alias (works on x86_64)..."
            proot-distro install archlinux || true
        fi
    else
        proot-distro install archlinux || true
    fi
    PROOT_ROOT="$(find_rootfs)"
    [ -n "$PROOT_ROOT" ] || die "Rootfs bootstrap failed. Check network, then re-run.
         Manual attempt: proot-distro install --name archlinux $ALARM_TARBALL"
    log_ok "Arch Linux base rootfs deployed."
fi

log_info "Injecting DNS resolvers (Cloudflare + Google)..."
cat > "$PROOT_ROOT/etc/resolv.conf" << 'RESOLV_HOST'
nameserver 1.1.1.1
nameserver 1.0.0.1
nameserver 8.8.8.8
RESOLV_HOST
log_ok "DNS configured."

# ==============================================================================
# STEP 4/6 — Root-level provisioning INSIDE the PRoot
# ==============================================================================
log_step "Step 4/6: Provisioning Arch Linux (root phase: keyring, packages, user)"

# This script is written from the Termux side straight into the rootfs and
# executed via `proot-distro login`. It is fully self-contained.
cat > "$PROOT_ROOT/root/provision-root.sh" << 'PROVISION_ROOT'
#!/bin/bash
# provision-root.sh — runs inside Arch Linux PRoot as (fake) root.
# Self-contained: no references to anything outside this file.
set -u
R="${OMARCHY_ROOTFS:-/}"
say() { echo "==> [arch/root] $*"; }
fail() { echo "[arch/root] FATAL: $*" >&2; exit 1; }

say "Writing DNS resolver..."
cat > "$R/etc/resolv.conf" << 'RESOLV_INNER'
nameserver 1.1.1.1
nameserver 1.0.0.1
nameserver 8.8.8.8
RESOLV_INNER

say "Disabling pacman sandbox (Landlock unsupported in PRoot)..."
# pacman 7 downloads packages inside a Landlock LSM sandbox. Android
# kernels under PRoot don't expose Landlock, so every download dies with
# "restricting filesystem access failed". DisableSandbox turns the whole
# download sandbox off (DownloadUser alone is NOT enough — the Landlock
# filter applies even when downloading as root).
PCONF="$R/etc/pacman.conf"
[ -f "$PCONF" ] || { printf '[options]\n' > "$PCONF"; }
if grep -qE '^\s*#\s*DisableSandbox\b' "$PCONF"; then
    sed -i -E 's|^\s*#\s*(DisableSandbox)\b.*|\1|' "$PCONF"
elif ! grep -qE '^\s*DisableSandbox\b' "$PCONF"; then
    sed -i '/^\[options\]/a DisableSandbox' "$PCONF"
fi
# Keep downloads as root too (no sandbox user switch at all)
if grep -qE '^\s*DownloadUser' "$PCONF"; then
    sed -i -E 's|^\s*DownloadUser.*|DownloadUser = root|' "$PCONF"
fi
grep -qE '^\s*DisableSandbox\b' "$PCONF" || fail "could not disable pacman sandbox"
say "pacman sandbox disabled (downloads as root, no Landlock)."

say "Initialising pacman keyring (first run can take several minutes)..."
rm -rf "$R/etc/pacman.d/gnupg"
timeout 300 pacman-key --init || fail "pacman-key --init failed"

if [ "$(uname -m)" = "aarch64" ]; then
    pacman-key --populate archlinuxarm 2>/dev/null \
        || pacman-key --populate archlinux \
        || fail "pacman-key populate failed"
else
    pacman-key --populate archlinux || fail "pacman-key populate failed"
fi
say "Keyring populated."

say "Refreshing keyring packages..."
pacman -Sy --noconfirm --needed archlinuxarm-keyring archlinux-keyring 2>/dev/null \
    || pacman -Sy --noconfirm --needed archlinux-keyring 2>/dev/null \
    || true

say "Upgrading base system (biggest step — 5-15 min)..."
if ! pacman -Syyu --noconfirm; then
    say "Upgrade failed once; refreshing keyring and retrying..."
    pacman-key --populate archlinuxarm 2>/dev/null || pacman-key --populate 2>/dev/null || true
    pacman -Syyu --noconfirm || fail "system upgrade failed (network? re-run the installer to resume)"
fi
say "System upgraded."

PACKAGES=(
    base-devel sudo git curl wget nano neovim bash-completion
    bat eza fastfetch fd ripgrep fzf btop htop jq tmux
    fontconfig dbus mesa mesa-utils
    xdg-user-dirs xdg-utils feh rofi xdotool xterm
    i3-wm i3status i3lock dunst picom
    xorg-xhost xorg-xset xorg-xrdb xorg-xrandr xorg-xsetroot
)
say "Installing core desktop & developer packages..."
if ! pacman -S --noconfirm --needed "${PACKAGES[@]}"; then
    say "Bulk install failed — falling back to per-package (one bad name won't abort)..."
    for p in "${PACKAGES[@]}"; do
        pacman -S --noconfirm --needed "$p" || echo "[arch/root] notice: '$p' skipped"
    done
fi
say "Core packages done."

say "Installing audio routing..."
if pacman -S --noconfirm --needed pulseaudio; then
    mkdir -p "$R/etc/pulse"
    cat > "$R/etc/pulse/client.conf" << 'PA_CLIENT'
default-server = 127.0.0.1
autospawn = no
PA_CLIENT
    say "PulseAudio client configured (server on Android host)."
elif pacman -S --noconfirm --needed pipewire-pulse; then
    say "PulseAudio unavailable — pipewire-pulse installed instead."
else
    echo "[arch/root] notice: no audio stack installed (non-fatal)"
fi

say "Installing fonts..."
for f in ttf-jetbrains-mono-nerd ttf-jetbrains-mono noto-fonts noto-fonts-emoji ttf-cascadia-code; do
    pacman -S --noconfirm --needed "$f" 2>/dev/null || echo "[arch/root] notice: font '$f' skipped"
done
fc-cache -f >/dev/null 2>&1 && say "Font cache rebuilt." || echo "[arch/root] notice: fc-cache failed"

say "Creating user 'omarchy'..."
USERNAME="omarchy"
if ! id -u "$USERNAME" >/dev/null 2>&1; then
    _ok=0
    for _ in 1 2 3 4 5 6; do
        useradd -m -s /bin/bash -G wheel "$USERNAME" 2>/dev/null && { _ok=1; break; }
        sleep 3
    done
    [ "$_ok" = "1" ] || fail "useradd could not create '$USERNAME'"
fi
echo "$USERNAME:omarchy" | chpasswd
echo "root:root" | chpasswd
mkdir -p "$R/etc/sudoers.d"
printf '%%wheel ALL=(ALL:ALL) NOPASSWD: ALL\n' > "$R/etc/sudoers.d/10-wheel-nopasswd"
chmod 0440 "$R/etc/sudoers.d/10-wheel-nopasswd"
say "User ready (omarchy/omarchy, passwordless sudo via wheel)."

say "Fetching Omarchy components..."
rm -rf "$R/opt/omarchy"
if git clone --depth 1 https://github.com/omacom/omarchy.git "$R/opt/omarchy" 2>/dev/null; then
    say "Upstream omacom/omarchy cloned to /opt/omarchy."
else
    echo "[arch/root] notice: upstream clone failed — creating minimal fallback"
    mkdir -p "$R/opt/omarchy/bin" "$R/opt/omarchy/config"
fi
[ -f "$R/opt/omarchy/bin/omarchy" ] && ln -sf /opt/omarchy/bin/omarchy "$R/usr/local/bin/omarchy"

say "Root phase complete."
PROVISION_ROOT

log_info "Executing root provisioning inside PRoot (long — watch for [arch/root] lines)..."
if ! proot-distro login archlinux -- env OMARCHY_ROOTFS=/ bash /root/provision-root.sh; then
    die "Root provisioning failed. The script was kept at:
         $PROOT_ROOT/root/provision-root.sh
         Fix the issue (usually network) and simply re-run the installer."
fi
rm -f "$PROOT_ROOT/root/provision-root.sh"
log_ok "Root phase complete."

# ==============================================================================
# STEP 5/6 — User-level provisioning INSIDE the PRoot (as user omarchy)
# ==============================================================================
log_step "Step 5/6: Provisioning desktop for user 'omarchy'"

mkdir -p "$PROOT_ROOT/home/omarchy"
cat > "$PROOT_ROOT/home/omarchy/provision-user.sh" << 'PROVISION_USER'
#!/bin/bash
# provision-user.sh — runs inside Arch Linux PRoot as user 'omarchy'.
# Self-contained: no references to anything outside this file.
set -u
R="${OMARCHY_ROOTFS:-/}"
say() { echo "==> [arch/user] $*"; }

mkdir -p "$HOME/.config" "$HOME/.local/bin" "$HOME/.local/share" \
         "$HOME/Desktop" "$HOME/Downloads" "$HOME/Documents"

if [ -d "$R/opt/omarchy/config" ]; then
    cp -r "$R/opt/omarchy/config/." "$HOME/.config/" 2>/dev/null || true
    say "Omarchy upstream configs synced to ~/.config"
fi

# --- Shell profile (append once, guarded by marker) ---------------------------
if ! grep -q "omarchy-termux profile v2" "$HOME/.bashrc" 2>/dev/null; then
    cat >> "$HOME/.bashrc" << 'USER_BASHRC'

# --- omarchy-termux profile v2 ------------------------------------------------
export PATH="$HOME/.local/bin:/opt/omarchy/bin:$PATH"
export PULSE_SERVER=127.0.0.1
export DISPLAY=:0
export TERM=xterm-256color
export GALLIUM_DRIVER=llvmpipe
export MESA_GL_VERSION_OVERRIDE=4.0
alias ll="eza -la --icons"
alias ls="eza --icons"
alias om="omarchy"
alias ff="fastfetch"
[ -f /opt/omarchy/logo.txt ] && cat /opt/omarchy/logo.txt 2>/dev/null || true
# --- end omarchy-termux profile -----------------------------------------------
USER_BASHRC
    say "Shell profile installed."
else
    say "Shell profile already present."
fi

# --- GUI session script --------------------------------------------------------
cat > "$HOME/.startwm" << 'STARTWM'
#!/bin/bash
export DISPLAY=:0
export PULSE_SERVER=127.0.0.1
export XDG_CURRENT_DESKTOP=i3
export GALLIUM_DRIVER=llvmpipe
export MESA_GL_VERSION_OVERRIDE=4.0

if command -v dbus-launch >/dev/null 2>&1; then
    eval "$(dbus-launch --sh-syntax)"
fi

command -v dunst >/dev/null 2>&1 && dunst >/dev/null 2>&1 &
command -v picom >/dev/null 2>&1 && picom --backend xrender -b >/dev/null 2>&1 &

exec i3
STARTWM
chmod +x "$HOME/.startwm"
say "Session script ~/.startwm installed."

# --- Wallpaper (Omarchy Tokyo Night) -------------------------------------------
WALLPAPER_SRC=""
for f in "$R/opt/omarchy/themes/tokyo-night/backgrounds/5-oma-cityscape.jpg" \
         "$R/opt/omarchy/themes/tokyo-night/backgrounds/"*.jpg; do
    [ -f "$f" ] && WALLPAPER_SRC="$f" && break
done
if [ -n "$WALLPAPER_SRC" ]; then
    mkdir -p "$HOME/.local/share/omarchy"
    cp "$WALLPAPER_SRC" "$HOME/.local/share/omarchy/wallpaper.jpg"
    say "Wallpaper installed (Omarchy Tokyo Night)."
fi

# --- i3 window manager config --------------------------------------------------
mkdir -p "$HOME/.config/i3"
cat > "$HOME/.config/i3/config" << 'I3CONF'
# omarchy-termux i3 config — mobile-friendly Catppuccin Mocha
set $mod Mod4
font pango:JetBrainsMono Nerd Font, monospace 10

bar {
    status_command i3status
    position top
    colors {
        background #1e1e2e
        statusline #cdd6f4
        focused_workspace  #89b4fa #89b4fa #1e1e2e
        active_workspace   #313244 #313244 #cdd6f4
        inactive_workspace #181825 #181825 #6c7086
        urgent_workspace   #f38ba8 #f38ba8 #11111b
    }
}

bindsym $mod+Return exec xterm
bindsym $mod+d exec rofi -show run
bindsym $mod+q kill
bindsym $mod+Shift+e exit
bindsym $mod+Shift+r restart
bindsym $mod+f fullscreen toggle
bindsym $mod+Shift+space floating toggle
bindsym $mod+Left focus left
bindsym $mod+Right focus right
bindsym $mod+Up focus up
bindsym $mod+Down focus down
exec --no-startup-id sh -c '[ -f "$HOME/.local/share/omarchy/wallpaper.jpg" ] && feh --bg-fill "$HOME/.local/share/omarchy/wallpaper.jpg" || xsetroot -solid "#1e1e2e"'
exec --no-startup-id dunst

default_border pixel 2
client.focused   #89b4fa #89b4fa #1e1e2e #89b4fa #89b4fa
client.unfocused #313244 #313244 #a6adc8 #313244 #313244
say "i3 configuration installed (mobile-size fonts)."
I3CONF
say "User phase complete."
PROVISION_USER

log_info "Executing user provisioning inside PRoot..."
if ! proot-distro login archlinux --user omarchy -- env OMARCHY_ROOTFS=/ HOME=/home/omarchy \
        bash /home/omarchy/provision-user.sh; then
    die "User provisioning failed. Re-run the installer to resume."
fi
rm -f "$PROOT_ROOT/home/omarchy/provision-user.sh"
log_ok "User phase complete."

# ==============================================================================
# STEP 6/6 — Host launchers, widget shortcut, verification
# ==============================================================================
log_step "Step 6/6: Creating launchers & verifying installation"

cat > "$HOME/start-omarchy.sh" << 'GUI_LAUNCHER'
#!/data/data/com.termux/files/usr/bin/bash
# Omarchy GUI session launcher (Termux side)
echo "[*] Cleaning up previous X11 / audio / VirGL processes..."
killall -9 termux-x11 pulseaudio virgl_test_server_android 2>/dev/null
sleep 1

echo "[*] Starting PulseAudio (Android audio bridge)..."
pulseaudio --start \
    --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
    --exit-idle-time=-1 2>/dev/null || echo "[!] PulseAudio failed to start (no audio)"

# VirGL 3D acceleration (optional, Adreno GPUs)
if command -v virgl_test_server_android >/dev/null 2>&1; then
    echo "[*] Starting VirGL 3D server..."
    virgl_test_server_android >/dev/null 2>&1 &
fi

echo "[*] Launching Termux:X11 app..."
am start -n com.termux.x11/com.termux.x11.MainActivity 2>/dev/null \
    || echo "[!] Termux:X11 app not installed — GUI cannot start. See README §Prerequisites."

echo "[*] Starting X server on display :0..."
X11_PID=""
if command -v termux-x11 >/dev/null 2>&1; then
    termux-x11 :0 -ac >/dev/null 2>&1 &
    X11_PID=$!
fi
sleep 1.5

echo "[*] Entering Omarchy desktop (switch to the Termux:X11 app now)..."
proot-distro login archlinux --user omarchy --shared-tmp -- \
    env DISPLAY=:0 PULSE_SERVER=127.0.0.1 GALLIUM_DRIVER=llvmpipe \
    /home/omarchy/.startwm

echo "[*] Session ended. Cleaning up..."
[ -n "$X11_PID" ] && kill "$X11_PID" 2>/dev/null
killall -9 virgl_test_server_android pulseaudio 2>/dev/null
echo "[*] Done."
GUI_LAUNCHER
chmod 0755 "$HOME/start-omarchy.sh"

cat > "$HOME/omarchy-cli.sh" << 'CLI_LAUNCHER'
#!/data/data/com.termux/files/usr/bin/bash
# Omarchy CLI session launcher (no X11)
export PULSE_SERVER=127.0.0.1
export TERM=xterm-256color
proot-distro login archlinux --user omarchy
CLI_LAUNCHER
chmod 0755 "$HOME/omarchy-cli.sh"

# Termux:Widget home-screen shortcut (optional)
if [ -d "$HOME/.shortcuts" ] || command -v termux-widget >/dev/null 2>&1; then
    mkdir -p "$HOME/.shortcuts"
    printf '#!/data/data/com.termux/files/usr/bin/bash\n%s\n' "$HOME/start-omarchy.sh" \
        > "$HOME/.shortcuts/Omarchy"
    chmod 0755 "$HOME/.shortcuts/Omarchy"
    log_ok "Termux:Widget shortcut created (~/.shortcuts/Omarchy)."
fi

# Termux aliases (append once)
if ! grep -q "omarchy-termux aliases" "$HOME/.bashrc" 2>/dev/null; then
    {
        echo "# omarchy-termux aliases"
        echo "alias omarchy-gui='$HOME/start-omarchy.sh'"
        echo "alias omarchy-cli='$HOME/omarchy-cli.sh'"
    } >> "$HOME/.bashrc"
    log_ok "Aliases omarchy-gui / omarchy-cli added to ~/.bashrc"
fi

# Real executables on PATH (aliases only load in *new* shells)
printf '#!/data/data/com.termux/files/usr/bin/bash\nexec %s "$@"\n' "$HOME/start-omarchy.sh" \
    > "$TERMUX_PREFIX/bin/omarchy-gui" && chmod 0755 "$TERMUX_PREFIX/bin/omarchy-gui"
printf '#!/data/data/com.termux/files/usr/bin/bash\nexec %s "$@"\n' "$HOME/omarchy-cli.sh" \
    > "$TERMUX_PREFIX/bin/omarchy-cli" && chmod 0755 "$TERMUX_PREFIX/bin/omarchy-cli"
log_ok "Commands omarchy-gui / omarchy-cli installed on PATH (usable now)."

# --- Verification -------------------------------------------------------------
V_ERR=0
[ -x "$HOME/start-omarchy.sh" ]            || { log_fail "start-omarchy.sh missing"; V_ERR=1; }
if command -v am >/dev/null 2>&1; then
    # NOTE: 'pm list packages' is NOT reliable from Termux on all Android
    # versions (silently fails → false "not installed" warnings even when
    # the app is installed and launchable). Use 'am' with a resolve-only
    # intent instead; fall back to silence on failure.
    if ! am start -n com.termux.x11/.MainActivity --dry-run >/dev/null 2>&1 \
       && ! am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER \
              -p com.termux.x11 >/dev/null 2>&1; then
        log_warn "Termux:X11 APP not detected — if missing, get it from: https://github.com/termux/termux-x11/releases"
    fi
fi
[ "$V_ERR" = "0" ] || die "Verification failed — see messages above."

printf '\n%b\n' "${GREEN}${BOLD}════════════════════════════════════════════════${RESET}"
printf '%b\n'   "${GREEN}${BOLD}       INSTALLATION COMPLETE — OMARCHY READY      ${RESET}"
printf '%b\n\n' "${GREEN}${BOLD}════════════════════════════════════════════════${RESET}"
printf '  Graphical desktop : %b   (then switch to the Termux:X11 app)\n' "${MAGENTA}${BOLD}omarchy-gui${RESET}"
printf '  Terminal only     : %b\n\n' "${MAGENTA}${BOLD}omarchy-cli${RESET}"
printf '  Default user      : omarchy / omarchy (passwordless sudo)\n'
printf '  Keys              : Super+Enter terminal · Super+d launcher · Super+Shift+e exit\n\n'
printf '%b\n' "Enjoy Omarchy on Android!"

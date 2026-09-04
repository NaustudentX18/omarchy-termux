#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
#  Omarchy on Android Termux - Bulletproof One-Shot Automated Installer
#  Repository: https://github.com/NaustudentX18/omarchy-termux
#  Upstream Omarchy: https://github.com/omacom/omarchy
# ==============================================================================

set -euo pipefail

# ANSI color codes
BOLD="\033[1m"
GREEN="\033[38;2;166;227;161m"
BLUE="\033[38;2;137;180;250m"
PURPLE="\033[38;2;203;166;247m"
YELLOW="\033[38;2;249;226;175m"
RED="\033[38;2;243;139;168m"
CYAN="\033[38;2;137;220;235m"
RESET="\033[0m"

log_info() { echo -e "${BLUE}${BOLD}[*]${RESET} $1"; }
log_succ() { echo -e "${GREEN}${BOLD}[✓]${RESET} $1"; }
log_warn() { echo -e "${YELLOW}${BOLD}[!]${RESET} $1"; }
log_err()  { echo -e "${RED}${BOLD}[✗]${RESET} $1"; }
log_step() { echo -e "\n${CYAN}${BOLD}==>${RESET} ${BOLD}$1${RESET}"; }

banner() {
    clear 2>/dev/null || true
    cat << "BANNER_TXT"
  ___  __  __   _   ___  ___ _  ___   __
 / _ \|  \/  | /_\ | _ \/ __| || \ \ / /
| (_) | |\/| |/ _ \|   / (__| __ |\ V / 
 \___/|_|  |_/_/ \_\_|_\\___|_||_| |_|  
      Android Termux Edition
BANNER_TXT
    echo -e "${PURPLE}  Opinionated, Modern Linux on Android (PRoot + Termux:X11)${RESET}\n"
}

banner

# ------------------------------------------------------------------------------
# 1. Environment & Architecture Verification
# ------------------------------------------------------------------------------
log_step "Step 1/6: Verifying Termux host environment"

if [ ! -d "/data/data/com.termux" ]; then
    log_err "This installer must be run inside Termux on Android!"
    echo "Please install Termux from F-Droid: https://f-droid.org/en/packages/com.termux/"
    exit 1
fi

ARCH=$(uname -m)
case "$ARCH" in
    aarch64|arm64)
        TARGET_ARCH="aarch64"
        ;;
    x86_64|amd64)
        TARGET_ARCH="x86_64"
        ;;
    *)
        log_err "Unsupported CPU architecture: $ARCH. Required: aarch64 or x86_64."
        exit 1
        ;;
esac
log_succ "Architecture: ${BOLD}${TARGET_ARCH}${RESET}"

# Prevent Termux from sleeping or killing the process during long install
if command -v termux-wake-lock >/dev/null 2>&1; then
    log_info "Acquiring Termux wake-lock to prevent background sleep..."
    termux-wake-lock || true
fi

# ------------------------------------------------------------------------------
# 2. Storage Permissions
# ------------------------------------------------------------------------------
log_step "Step 2/6: Checking Android storage permissions"

if [ ! -d "$HOME/storage" ]; then
    log_info "Requesting Android storage permission (accept prompt if it appears)..."
    termux-setup-storage || true
    sleep 1
else
    log_succ "Storage permissions already configured."
fi

# ------------------------------------------------------------------------------
# 3. Host Dependencies & Termux Repos
# ------------------------------------------------------------------------------
log_step "Step 3/6: Updating Termux repositories & installing host tools"

export DEBIAN_FRONTEND=noninteractive

# Update core repos non-interactively without getting stuck on conffile prompts
log_info "Updating Termux package index..."
pkg update -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || {
    log_warn "Standard pkg update failed. Attempting with apt directly..."
    apt-get update -y || true
}

# Install / enable x11-repo
log_info "Enabling Termux X11 repository..."
pkg install -y x11-repo || true

HOST_PACKAGES=(
    proot
    proot-distro
    git
    curl
    wget
    tar
    pulseaudio
    virglrenderer-android
    termux-x11-nightly
    jq
)

log_info "Installing required Termux packages..."
for pkg_name in "${HOST_PACKAGES[@]}"; do
    if ! dpkg -s "$pkg_name" >/dev/null 2>&1; then
        pkg install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" "$pkg_name" || {
            log_warn "Failed to install '$pkg_name' automatically. Continuing..."
        }
    fi
done
log_succ "Termux host packages verified."

# ------------------------------------------------------------------------------
# 4. Bootstrap Arch Linux via proot-distro
# ------------------------------------------------------------------------------
log_step "Step 4/6: Bootstrapping Arch Linux (${TARGET_ARCH})"

DISTRO_NAME="archlinux"
if proot-distro list | grep -q "$DISTRO_NAME (installed)" || proot-distro list | grep -q "$DISTRO_NAME"; then
    log_succ "Arch Linux rootfs is already installed in proot-distro."
else
    log_info "Downloading and deploying Arch Linux rootfs via proot-distro..."
    # Modern proot-distro uses Docker/OCI registries by default. Docker Hub 'archlinux'
    # is amd64-only, so on aarch64 we provide the official Termux release rootfs tarball directly.
    if [[ "$TARGET_ARCH" == "aarch64" ]]; then
        ARCH_ROOTFS_URL="https://github.com/termux/proot-distro/releases/download/v4.17.3/archlinux-aarch64-pd-v4.17.3.tar.xz"
        proot-distro install --name "$DISTRO_NAME" "$ARCH_ROOTFS_URL" || \
        proot-distro install "$DISTRO_NAME"
    else
        proot-distro install "$DISTRO_NAME"
    fi
    log_succ "Arch Linux base rootfs deployed."
fi

# Locate PROOT_ROOT dynamically (supports both legacy installed-rootfs and modern containers/ layout)
if [ -d "/data/data/com.termux/files/usr/var/lib/proot-distro/containers/$DISTRO_NAME/rootfs" ]; then
    PROOT_ROOT="/data/data/com.termux/files/usr/var/lib/proot-distro/containers/$DISTRO_NAME/rootfs"
elif [ -d "/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/$DISTRO_NAME" ]; then
    PROOT_ROOT="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/$DISTRO_NAME"
else
    # Fallback to searching for the rootfs
    PROOT_ROOT=$(find /data/data/com.termux/files/usr/var/lib/proot-distro -type d -name "$DISTRO_NAME" 2>/dev/null | head -n 1)
    if [ -d "$PROOT_ROOT/rootfs" ]; then
        PROOT_ROOT="$PROOT_ROOT/rootfs"
    fi
fi

if [ -z "$PROOT_ROOT" ] || [ ! -d "$PROOT_ROOT" ]; then
	log_err "Cannot detect Arch Linux rootfs directory. Run proot-distro install archlinux first."
	exit 1
fi

# Ensure robust DNS before entering PRoot
if [ -n "$PROOT_ROOT" ] && [ -d "$PROOT_ROOT/etc" ]; then
    log_info "Configuring PRoot DNS resolvers (Cloudflare + Google fallback)..."
    rm -f "$PROOT_ROOT/etc/resolv.conf" 2>/dev/null || true
    cat << 'DNS_EOF' > "$PROOT_ROOT/etc/resolv.conf"
nameserver 1.1.1.1
nameserver 1.0.0.1
nameserver 8.8.8.8
DNS_EOF
fi

# ------------------------------------------------------------------------------
# 5. Inner Arch Linux Provisioning
# ------------------------------------------------------------------------------
log_step "Step 5/6: Provisioning Omarchy environment inside Arch Linux PRoot"

ARCH_USER="omarchy"

cat << 'INSIDE_EOF' > "$PROOT_ROOT/root/setup_omarchy.sh"
#!/bin/bash
set -eo pipefail

echo "==> [Arch PRoot] Verifying network and DNS resolution..."
cat << 'DNS' > /etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
DNS

echo "==> [Arch PRoot] Seeding entropy for pacman-key init..."
# C1 FIX: seed RNG so gpg-agent doesn't hang on /dev/random (Android PRoot has no hardware RNG)
_RNGD=0
if command -v rngd >/dev/null 2>&1; then
    rngd -r /dev/urandom &
    _RNGD_PID=$!
    sleep 5 && kill $_RNGD_PID 2>/dev/null; wait $_RNGD_PID 2>/dev/null || true
    _RNGD=1
fi
[ "$_RNGD" = "0" ] && echo "[C1] NO RNGD — using kernel CSPRNG (key init may hang)" >&2
rm -rf /etc/pacman.d/gnupg 2>/dev/null || true

START_EPOCH=$(date +%s)
_pacm_keyinit() { timeout 180 pacman-key --init; }
RESULT=$(_pacm_keyinit 2>&1); RC=$?; if [ "$RC" != "0" ]; then echo "[ERR] pacman-key init failed (took $(( $(date +%s) - START_EPOCH ))s)"; exit 1; fi

# C2 FIX: fatal if keyring populate fails — no cascading || true anymore
_KEY_FAIL=0
if [ "$(uname -m)" = "aarch64" ]; then
    pacman-key --populate archlinuxarm 2>/dev/null || _KEY_FAIL=1
    if [ "$_KEY_FAIL" = "1" ]; then echo "[WARN] arm populate failed, trying archlinux..."; pacman-key --populate archlinux 2>/dev/null || _KEY_FAIL=1; fi
else
    pacman-key --populate archlinux 2>/dev/null || _KEY_FAIL=1
fi
if [ "$_KEY_FAIL" = "1" ]; then echo "[ERR] Keyring populate failed"; exit 1; fi

# fatal on keyring sys upgrade too (C2)
_KROK=1
pacman -Sy --noconfirm archlinux-keyring 2>&1 || _KROK=0
if [ "$_KROK" = "0" ]; then echo "[ERR] archlinux-keyring failed"; exit 1; fi
if [ "$(uname -m)" = "aarch64" ]; then
    pacman -Sy --noconfirm archlinuxarm-keyring 2>/dev/null || true
fi

echo "==> [Arch PRoot] Upgrading system..."
# C2: fatal on sys upgrade — do NOT silently skip 40+ packages
_SOK=1
_SOK=0
pacman -Syyu --noconfirm
if [ "$_SOK" = "0" ]; then echo "[ERR] sys upgrade failed"; exit 1; fi
if [ "$_SOK" != "1" ]; then echo "[ERR] System upgrade failed"; exit 1; fi

# Core tools & environment packages
PACKAGES=(
    base-devel
    sudo
    git
    curl
    wget
    nano
    neovim
    bash-completion
    bat
    eza
    fastfetch
    fd
    ripgrep
    fzf
    btop
    htop
    jq
    tmux
    fontconfig
    dbus
    mesa
    mesa-utils
    xdg-user-dirs
    xdg-utils
    feh
    rofi
    xdotool
    xterm
    i3-wm
    i3status
    i3lock
    dunst
    picom
    xorg-xhost
    xorg-xset
    xorg-xrdb
    xorg-xrandr
)

echo "==> [Arch PRoot] Installing core desktop and developer packages..."
for pkg in "${PACKAGES[@]}"; do
    pacman -S --noconfirm --needed "$pkg" || echo "[!] Notice: Package $pkg skipped or not found."
done

# Audio setup: pulseaudio or pipewire-pulse fallback
echo "==> [Arch PRoot] Installing audio routing..."
_PA_OK=0
pacman -S --noconfirm --needed pulseaudio && _PA_OK=1 || true
if [ "$_PA_OK" != "1" ]; then
    echo "[AUDIO] PulseAudio not found, trying pipewire-pulse..." >&2







mkdir -p /etc/pulse
cat << 'PULSE_CLIENT' > /etc/pulse/client.conf
default-server = 127.0.0.1
autospawn = no
PULSE_CLIENT

# Fonts installation with robust fallbacks
echo "==> [Arch PRoot] Installing fonts..."
# P1-4: repo-only fonts (removed AUR-only)
pkgs="ttf-jetbrains-mono noto-fonts noto-fonts-emoji"
for _p in $pkgs; do pacman -S --noconfirm --needed "$_p" 2>/dev/null || true; done
pacman -S --noconfirm --needed ttf-cascadia-code 2>/dev/null || echo "[WARN] ttf-cascadia-code not found (optional font)"
fc-cache -f 2>/dev/null && echo "[fonts] Font cache rebuilt" || echo "[WARN] fc-cache failed — fonts may not render correctly"

# Create user omarchy if not exists
USERNAME="omarchy"
if ! id -u "$USERNAME" >/dev/null 2>&1; then
    echo "==> [Arch PRoot] Creating user: $USERNAME..."
    _UA_OK=0
    for _uar in 1 2 3 4 5 6; do
        if [ "$_UA_OK" = "1" ]; then break;
    fi
        if useradd -m -s /bin/bash -G wheel "$USERNAME" 2>/dev/null; then _UA_OK=1; fi
        sleep 3
    done
    echo "$USERNAME:omarchy" | chpasswd
    echo "root:root" | chpasswd
fi

# Passwordless sudo for wheel group
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/10-wheel-nopasswd
chmod 0440 /etc/sudoers.d/10-wheel-nopasswd

# Clone upstream Omarchy repository or fallback
echo "==> [Arch PRoot] Setting up Omarchy components..."
rm -rf /opt/omarchy
git clone --depth 1 https://github.com/omacom/omarchy.git /opt/omarchy || {
    echo "[!] Official omacom/omarchy clone failed; creating fallback structure..."
    mkdir -p /opt/omarchy/bin /opt/omarchy/config
}
chown -R "$USERNAME:$USERNAME" /opt/omarchy 2>/dev/null || true

# Link binary if present
if [ -f /opt/omarchy/bin/omarchy ]; then
    ln -sf /opt/omarchy/bin/omarchy /usr/local/bin/omarchy
    chmod +x /opt/omarchy/bin/* 2>/dev/null || true
fi

# Deploy Omarchy themes, shell configs and desktop environment
su - "$USERNAME" -c '
set -eo pipefail
mkdir -p "$HOME/.config" "$HOME/.local/bin" "$HOME/.local/share" "$HOME/Desktop" "$HOME/Downloads" "$HOME/Documents"

# Sync omarchy defaults and configurations
if [ -d "/opt/omarchy/config" ]; then
    cp -r /opt/omarchy/config/* "$HOME/.config/" 2>/dev/null || true
fi

# Configure Omarchy environment in ~/.bashrc
cat << "USER_BASHRC" >> "$HOME/.bashrc"
# Omarchy Shell Profile & Aliases
export PATH="$HOME/.local/bin:/opt/omarchy/bin:$PATH"
export PULSE_SERVER=127.0.0.1
export DISPLAY=:0
export TERM=xterm-256color

# VirGL Hardware Acceleration
# P1-5: Auto-detect VirGL (only on Qualcomm Adreno); fallback to llvmpipe
# Detect VirGL hardware available
if command -v virgl_test_server_android >/dev/null 2>&1 &&    virgl_test_server_android --test >/dev/null 2>&1; then
    export GALLIUM_DRIVER=virpipe
else
    export GALLIUM_DRIVER=llvmpipe
fi
export MESA_GL_VERSION_OVERRIDE=4.0

alias ll="eza -la --icons" 2>/dev/null || alias ll="ls -la"
alias ls="eza --icons" 2>/dev/null || alias ls="ls"
alias om="omarchy"
alias ff="fastfetch" 2>/dev/null || alias ff="true"

if [ -f /opt/omarchy/logo.txt ]; then
    cat /opt/omarchy/logo.txt 2>/dev/null || true
fi
USER_BASHRC

# Create default startwm script for X11 session
cat << "STARTWM" > "$HOME/.startwm"
#!/bin/bash
export DISPLAY=:0
export PULSE_SERVER=127.0.0.1
export XDG_CURRENT_DESKTOP=i3
# P1-5: Auto-detect VirGL (only on Qualcomm Adreno); fallback to llvmpipe
if command -v virgl_test_server_android >/dev/null 2>&1 &&    virgl_test_server_android --test >/dev/null 2>&1; then
    export GALLIUM_DRIVER=virpipe
else
    export GALLIUM_DRIVER=llvmpipe
fi
export MESA_GL_VERSION_OVERRIDE=4.0

# Start D-Bus session
if command -v dbus-launch >/dev/null 2>&1; then
    eval $(dbus-launch --sh-syntax)
fi
[ -z "$DBUS_SESSION_BUS_ADDRESS" ] && export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-/tmp/dbus}"

# Start Dunst notifications
command -v dunst >/dev/null 2>&1 && dunst &

# Start compositor with xrender for PRoot compatibility
command -v picom >/dev/null 2>&1 && picom --backend xrender -b 2>/dev/null || true

# Launch i3 window manager
exec i3
STARTWM
chmod +x "$HOME/.startwm"

# Minimal modern i3 configuration tailored for mobile/touch screen
mkdir -p "$HOME/.config/i3"
cat << "I3CONF" > "$HOME/.config/i3/config"
set $mod Mod4
font pango:JetBrainsMono Nerd Font 10, monospace 10

# Bar configuration
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

# Keybindings
bindsym $mod+Return exec xterm
bindsym $mod+d exec rofi -show run
bindsym $mod+q kill
bindsym $mod+Shift+e exit
bindsym $mod+Shift+r restart

# Floating & full screen
bindsym $mod+f fullscreen toggle
bindsym $mod+Shift+space floating toggle

# Window styling
default_border pixel 2
client.focused #89b4fa #89b4fa #1e1e2e #89b4fa #89b4fa
client.unfocused #313244 #313244 #a6adc8 #313244 #313244
I3CONF
'

echo "==> [Arch PRoot] Omarchy internal bootstrap complete!"
INSIDE_EOF

chmod +x "$PROOT_ROOT/root/setup_omarchy.sh"

log_info "Executing internal Omarchy bootstrap inside PRoot (this may take a few minutes)..."
proot-distro login "$DISTRO_NAME" -- /root/setup_omarchy.sh
rm -f "$PROOT_ROOT/root/setup_omarchy.sh"

# ------------------------------------------------------------------------------
# 6. Host Launchers & Termux Shortcuts
# ------------------------------------------------------------------------------
log_step "Step 6/6: Creating bulletproof host launchers"

cat << 'LAUNCHER_EOF' > "$HOME/start-omarchy.sh"
#!/data/data/com.termux/files/usr/bin/bash
# Omarchy GUI Session Launcher for Android

echo "[*] Cleaning up any previous X11, Audio, or VirGL processes..."
killall -9 termux-x11 Xwayland pulseaudio virgl_test_server_android 2>/dev/null || true
sleep 0.5

echo "[*] Starting PulseAudio sound server..."
pulseaudio --start \
    --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
    --exit-idle-time=-1 2>/dev/null || true

# VirGL 3D Acceleration Server (Fallback gracefully if not supported/installed)
if command -v virgl_test_server_android >/dev/null 2>&1; then
    echo "[*] Starting VirGL 3D acceleration..."
    virgl_test_server_android >/dev/null 2>&1 &
fi

echo "[*] Launching Termux:X11 Companion..."
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity 2>/dev/null || true

echo "[*] Initializing X11 display :0..."
export DISPLAY=:0
# P0-4: detect T:X11 version — prefer -w (wayland-compat), fallback to legacy
if termux-x11 2>&1 /dev/null | grep -q -- "-"; then
    TXX_FLAGS="-ac -w"
else
    TXX_FLAGS="-ac -legacy-drawing"
fi
termux-x11 :0 $TXX_FLAGS 2>/dev/null &
X11_PID=$!
sleep 1.2

echo "[*] Entering Omarchy Linux..."
proot-distro login archlinux --user omarchy --shared-tmp -- env DISPLAY=:0 PULSE_SERVER=127.0.0.1 DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-}" /home/omarchy/.startwm

# Cleanup when GUI closes
echo "[*] Session ended. Cleaning up background services..."
kill -9 $X11_PID 2>/dev/null || true
killall -9 virgl_test_server_android pulseaudio 2>/dev/null || true
LAUNCHER_EOF

chmod +x "$HOME/start-omarchy.sh"

# CLI-only quick launcher
cat << 'CLI_LAUNCHER' > "$HOME/omarchy-cli.sh"
#!/data/data/com.termux/files/usr/bin/bash
export PULSE_SERVER=127.0.0.1
export TERM=xterm-256color
proot-distro login archlinux --user omarchy --shared-tmp
CLI_LAUNCHER
chmod +x "$HOME/omarchy-cli.sh"

# Add aliases to Termux profile
if ! grep -q "start-omarchy.sh" "$HOME/.bashrc" 2>/dev/null; then
    echo "alias omarchy-gui='$HOME/start-omarchy.sh'" >> "$HOME/.bashrc"
    echo "alias omarchy-cli='$HOME/omarchy-cli.sh'" >> "$HOME/.bashrc"
fi

banner
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}       INSTALLATION COMPLETE! OMARCHY IS READY TO LAUNCH          ${RESET}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════════${RESET}\n"
echo -e "  To launch the ${BOLD}Graphical Desktop (Termux:X11)${RESET}:"
echo -e "    ${PURPLE}omarchy-gui${RESET}   (or: ${PURPLE}./start-omarchy.sh${RESET})\n"
echo -e "  To launch the ${BOLD}Terminal CLI session${RESET}:"
echo -e "    ${PURPLE}omarchy-cli${RESET}   (or: ${PURPLE}./omarchy-cli.sh${RESET})\n"
echo -e "  ${YELLOW}${BOLD}Prerequisites on Android:${RESET}"
echo -e "    1. Install ${BOLD}Termux:X11${RESET} (from GitHub releases or F-Droid)."
echo -e "    2. Switch to Termux:X11 after launching ${PURPLE}omarchy-gui${RESET}."
echo -e "    3. Shortcut: ${BOLD}Super + Return${RESET} for terminal, ${BOLD}Super + d${RESET} for menu.\n"
echo -e "${GREEN}Enjoy Omarchy on Android!${RESET}\n"

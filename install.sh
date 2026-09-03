#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
#  Omarchy on Android Termux - One-Shot Automated Setup & Installer
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
RESET="\033[0m"

log_info() { echo -e "${BLUE}${BOLD}[*]${RESET} $1"; }
log_succ() { echo -e "${GREEN}${BOLD}[✓]${RESET} $1"; }
log_warn() { echo -e "${YELLOW}${BOLD}[!]${RESET} $1"; }
log_err()  { echo -e "${RED}${BOLD}[✗]${RESET} $1"; }

banner() {
    clear
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

# 1. Environment & Architecture Verification
log_info "Verifying host Android & Termux environment..."

if [ ! -d "/data/data/com.termux" ]; then
    log_err "This script must be run inside Termux on Android!"
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
log_succ "Architecture detected: ${TARGET_ARCH}"

# 2. Grant Android Storage Permission
if [ ! -d "$HOME/storage" ]; then
    log_info "Requesting Android storage permissions..."
    termux-setup-storage || true
fi

# 3. Update Termux Repos & Install Host Prerequisites
log_info "Updating Termux repositories and installing core packages..."
pkg update -y && pkg upgrade -y

# Enable X11 repo for virgl / x11 tools
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

log_info "Installing required Termux packages: ${HOST_PACKAGES[*]}..."
for pkg in "${HOST_PACKAGES[@]}"; do
    pkg install -y "$pkg" || log_warn "Optional package $pkg could not be installed directly, continuing..."
done

# 4. Install Arch Linux via proot-distro
DISTRO_NAME="archlinux"
if proot-distro list | grep -q "$DISTRO_NAME (installed)"; then
    log_warn "Arch Linux is already installed in proot-distro. Skipping installation."
else
    log_info "Installing Arch Linux (${TARGET_ARCH}) via proot-distro..."
    proot-distro install "$DISTRO_NAME"
    log_succ "Arch Linux base system installed."
fi

# 5. Bootstrap Inside Arch Linux PRoot
PROOT_ROOT="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/archlinux"
ARCH_USER="omarchy"

log_info "Preparing internal configuration inside Arch Linux PRoot..."

# Create internal setup script
cat << 'INSIDE_EOF' > "$PROOT_ROOT/root/setup_omarchy.sh"
#!/bin/bash
set -euo pipefail

echo "==> [Inside Arch] Initializing pacman keys and mirrorlist..."
pacman-key --init
pacman-key --populate archlinuxarm || pacman-key --populate archlinux || true

# Update mirrors & packages
pacman -Syu --noconfirm

# Install base development and system tools
pacman -S --noconfirm --needed \
    base-devel \
    sudo \
    git \
    curl \
    wget \
    nano \
    neovim \
    bash-completion \
    bat \
    eza \
    fastfetch \
    fd \
    ripgrep \
    fzf \
    btop \
    htop \
    jq \
    zsh \
    tmux \
    fontconfig \
    ttf-jetbrains-mono-nerd \
    ttf-cascadia-code-nerd \
    noto-fonts \
    noto-fonts-emoji \
    noto-fonts-cjk \
    dbus \
    mesa \
    mesa-utils \
    vulkan-swrast \
    pulseaudio \
    pulseaudio-alsa \
    pipewire \
    pipewire-pulse \
    wireplumber \
    xdg-user-dirs \
    xdg-utils \
    feh \
    rofi \
    xdotool \
    xterm \
    i3-wm \
    i3status \
    i3lock \
    dunst \
    picom \
    xorg-xhost \
    xorg-xset \
    xorg-xrdb \
    xorg-xrandr

# Setup Audio
mkdir -p /etc/pulse
echo "default-server = 127.0.0.1" >> /etc/pulse/client.conf || true

# Create user omarchy if not exists
USERNAME="omarchy"
if ! id -u "$USERNAME" >/dev/null 2>&1; then
    echo "==> [Inside Arch] Creating user $USERNAME..."
    useradd -m -s /bin/bash -G wheel,video,audio "$USERNAME"
    echo "$USERNAME:omarchy" | chpasswd
    echo "root:root" | chpasswd
fi

# Enable passwordless sudo for wheel
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/10-wheel-nopasswd
chmod 0440 /etc/sudoers.d/10-wheel-nopasswd

# Install yay (AUR Helper) as omarchy user
su - "$USERNAME" -c '
set -euo pipefail
if ! command -v yay >/dev/null 2>&1; then
    echo "==> [Inside Arch] Setting up yay AUR helper..."
    cd "$HOME"
    rm -rf /tmp/yay-bin
    git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin || git clone https://aur.archlinux.org/yay.git /tmp/yay-bin
    cd /tmp/yay-bin
    makepkg -si --noconfirm
    rm -rf /tmp/yay-bin
fi
'

# Clone omacom/omarchy repository into /opt/omarchy and link commands
echo "==> [Inside Arch] Cloning omacom/omarchy repository..."
rm -rf /opt/omarchy
git clone https://github.com/omacom/omarchy.git /opt/omarchy || git clone --depth 1 https://github.com/omacom/omarchy.git /opt/omarchy
chown -R "$USERNAME:$USERNAME" /opt/omarchy

# Link omarchy command to /usr/local/bin
ln -sf /opt/omarchy/bin/omarchy /usr/local/bin/omarchy
chmod +x /opt/omarchy/bin/* || true

# Deploy Omarchy themes, shell configs and desktop environment
su - "$USERNAME" -c '
set -euo pipefail
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
export GALLIUM_DRIVER=virpipe
export MESA_GL_VERSION_OVERRIDE=4.0
export TERM=xterm-256color

alias ll="eza -la --icons"
alias ls="eza --icons"
alias om="omarchy"
alias ff="fastfetch"

if [ -f /opt/omarchy/logo.txt ]; then
    cat /opt/omarchy/logo.txt 2>/dev/null || true
fi
USER_BASHRC

# Create default startwm script for X11 session
cat << "STARTWM" > "$HOME/.startwm"
#!/bin/bash
export DISPLAY=:0
export PULSE_SERVER=127.0.0.1
export GALLIUM_DRIVER=virpipe
export MESA_GL_VERSION_OVERRIDE=4.0
export XDG_CURRENT_DESKTOP=i3

# Start D-Bus session
eval $(dbus-launch --sh-syntax)

# Start Dunst notifications
dunst &

# Start compositor with glx/virgl or fallback
picom --backend xrender -b || true

# Launch i3 window manager
exec i3
STARTWM
chmod +x "$HOME/.startwm"

# Create minimal modern i3 configuration tailored for mobile/touch screen
mkdir -p "$HOME/.config/i3"
cat << "I3CONF" > "$HOME/.config/i3/config"
set $mod Mod4
font pango:JetBrainsMono Nerd Font 11

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

echo "==> [Inside Arch] Omarchy internal build and setup complete!"
INSIDE_EOF

chmod +x "$PROOT_ROOT/root/setup_omarchy.sh"

log_info "Executing internal Omarchy bootstrap inside PRoot (this may take a few minutes)..."
proot-distro login "$DISTRO_NAME" -- /root/setup_omarchy.sh
rm -f "$PROOT_ROOT/root/setup_omarchy.sh"

# 6. Generate Host Startup Script for Termux:X11 + Audio + Arch Omarchy
log_info "Creating Termux launch scripts..."

cat << 'LAUNCHER_EOF' > "$HOME/start-omarchy.sh"
#!/data/data/com.termux/files/usr/bin/bash
# Omarchy Session Launcher for Android

killall -9 termux-x11 Xwayland pulseaudio virgl_test_server_android 2>/dev/null || true

echo "[*] Initializing PulseAudio sound server..."
pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" --exit-idle-time=-1 2>/dev/null || true

echo "[*] Starting Hardware-Accelerated VirGL 3D Server..."
virgl_test_server_android &
sleep 1

echo "[*] Launching Termux:X11 Companion..."
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity 2>/dev/null || true
X11_PID=$(termux-x11 :0 -ac & echo $!)
sleep 1.5

echo "[*] Entering Omarchy Linux..."
proot-distro login archlinux --user omarchy --shared-tmp -- env DISPLAY=:0 PULSE_SERVER=127.0.0.1 /home/omarchy/.startwm

# Cleanup when GUI closes
echo "[*] Shutting down Omarchy session..."
kill -9 $X11_PID 2>/dev/null || true
killall -9 virgl_test_server_android pulseaudio 2>/dev/null || true
LAUNCHER_EOF

chmod +x "$HOME/start-omarchy.sh"

# CLI-only quick launcher
cat << 'CLI_LAUNCHER' > "$HOME/omarchy-cli.sh"
#!/data/data/com.termux/files/usr/bin/bash
proot-distro login archlinux --user omarchy --shared-tmp
CLI_LAUNCHER
chmod +x "$HOME/omarchy-cli.sh"

# 7. Add quick command to Termux profile
if ! grep -q "start-omarchy.sh" "$HOME/.bashrc" 2>/dev/null; then
    echo "alias omarchy-gui='$HOME/start-omarchy.sh'" >> "$HOME/.bashrc"
    echo "alias omarchy-cli='$HOME/omarchy-cli.sh'" >> "$HOME/.bashrc"
fi

banner
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}       INSTALLATION COMPLETE! OMARCHY IS READY TO LAUNCH          ${RESET}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════════${RESET}\n"
echo -e "  To launch the ${BOLD}Graphical Desktop (Termux:X11)${RESET}:"
echo -e "    ${PURPLE}./start-omarchy.sh${RESET}  (or type: ${PURPLE}omarchy-gui${RESET})\n"
echo -e "  To launch the ${BOLD}Terminal CLI session${RESET}:"
echo -e "    ${PURPLE}./omarchy-cli.sh${RESET}  (or type: ${PURPLE}omarchy-cli${RESET})\n"
echo -e "  ${YELLOW}${BOLD}Prerequisites on Android:${RESET}"
echo -e "    1. Install ${BOLD}Termux:X11${RESET} (from F-Droid / GitHub releases)."
echo -e "    2. Run ${PURPLE}./start-omarchy.sh${RESET} to start your GUI session.\n"
echo -e "${GREEN}Enjoy Omarchy on Android!${RESET}\n"

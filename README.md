# Omarchy on Android Termux 🚀

> An automated, one-shot installer that bootstraps **[Omarchy](https://github.com/omacom/omarchy)** (the opinionated Linux environment by DHH) inside **Arch Linux (PRoot)** on Android using **Termux** & **Termux:X11**.

---

## 📱 Features

- **⚡ One-Shot Setup**: Installs base Arch Linux ARM, dependencies, audio, fontconfig, and Omarchy configs in one run.
- **🎨 Modern Tiling & Theming**: Integrated window management configured for mobile and external displays with Catppuccin / Omarchy-inspired colorways.
- **🚀 GPU Hardware Acceleration**: Leverages `virglrenderer-android` for accelerated 3D graphics inside PRoot.
- **🔊 Low Latency Audio**: Native PulseAudio server routing from Arch PRoot directly to Android.
- **🧰 Native Omarchy Tools**: Clones the official `omacom/omarchy` toolkit, linking CLI utilities, menus, and themes.

---

## 📋 Prerequisites & Fresh Start Guide

If you are deleting Termux and starting fresh, follow this exact sequence:

### 1. Required Android Apps
* **Termux**: Download and install from [F-Droid](https://f-droid.org/en/packages/com.termux/) or [Droid-ify](https://github.com/Droid-ify/client).  
  ⚠️ **NEVER** use the Google Play Store version (it is deprecated, abandoned, and will break package mirrors).
* **Termux:X11**: Download `app-arm64-v8a-debug.apk` directly from [Termux:X11 GitHub Releases](https://github.com/termux/termux-x11/releases).

### 2. Android 12+ Settings (Important!)
On Android 12, 13, 14, and 15, Android’s "Phantom Process Killer" can kill compiler/proot processes in the background. To guarantee smooth operation:
1. In Android Settings, set **Battery Usage** for both Termux and Termux:X11 to **Unrestricted** (turn off battery optimization).
2. Inside Termux, allow Termux to acquire a wake-lock while installing:
   ```bash
   termux-wake-lock
   ```

### 3. Fresh Termux Initialization (First-Time Only)
When opening Termux for the very first time on a fresh install:
```bash
pkg update -y
```
*(If prompted about configuration files, press Enter to keep defaults).*

---

## 🚀 One-Shot Installation

Run this single command in Termux:

```bash
curl -sL https://raw.githubusercontent.com/NaustudentX18/omarchy-termux/main/install.sh | bash
```

### What the installer handles automatically:
1. **Acquires Wake-Lock**: Ensures Android does not kill the session during downloads.
2. **Storage Permissions**: Prompts for `termux-setup-storage`.
3. **Repository Setup**: Upgrades packages non-interactively and installs `x11-repo`.
4. **Host Stack**: Installs `proot-distro`, `virglrenderer-android`, `termux-x11-nightly`, and `pulseaudio`.
5. **Arch Linux ARM Bootstrapping**: Deploys rootfs and automatically configures `/etc/resolv.conf` (Cloudflare/Google DNS) to avoid DNS lookup errors.
6. **Keyring Repair**: Automatically re-initializes Pacman GPG keys and imports `archlinuxarm-keyring` to prevent pacman signature failures.
7. **Desktop & Tools**: Installs i3-wm, Rofi, Dunst, Picom, Fastfetch, Eza, Neovim, Tmux, JetBrains Mono Nerd Font, and Cascadia Code.
8. **Omarchy Core**: Clones `omacom/omarchy` with fallback safety, establishes environment variables, and configures `.startwm`.
9. **Launchers**: Generates `omarchy-gui` and `omarchy-cli` shortcuts.

---

## 🎮 Launching Omarchy

### 1. Graphical Desktop (Termux:X11)
Launch the desktop environment:

```bash
omarchy-gui
# or:
./start-omarchy.sh
```

**Next:** Switch to your **Termux:X11** app! You will see the Omarchy desktop running with VirGL acceleration and audio routing.

### 2. Terminal-Only Mode
If you prefer a fast terminal shell inside Arch Linux without starting the X11 display server:

```bash
omarchy-cli
# or:
./omarchy-cli.sh
```

---

## ⌨️ Desktop Shortcuts

| Shortcut | Action |
|---|---|
| `Super + Return` | Open Terminal (`xterm`) |
| `Super + d` | Application Launcher (`rofi`) |
| `Super + q` | Close Window |
| `Super + f` | Toggle Fullscreen |
| `Super + Shift + Space` | Toggle Floating Window |
| `Super + Shift + e` | Exit Session |
| `Super + Shift + r` | Reload Window Manager |

*(Note: On mobile software keyboards, the `Super` key is typically mapped to `Meta` or `Alt` in Termux:X11 settings).*

---

## 🛠️ Maintenance & Troubleshooting

* **DNS / Cannot Resolve Domain Inside PRoot**:  
  If pacman ever says "Failed to resolve host", run:
  ```bash
  echo "nameserver 1.1.1.1" | proot-distro login archlinux -- tee /etc/resolv.conf
  ```
* **Termux:X11 Display Resolution**:  
  In the Termux:X11 preferences (pull down from top of screen or swipe from left edge):
  - Set display scale to **100%** or **125%** for mobile high-DPI screens.
  - Choose between **Trackpad** mode (cursor) or **Direct touch**.
* **Audio Not Playing**:  
  Run `pulseaudio --kill && pulseaudio --start` in Termux.

---

## 📜 Credits & Upstream
- **[Omarchy](https://github.com/omacom/omarchy)** by David Heinemeier Hansson (DHH) & Omacom Foundation.
- **[Termux](https://termux.dev/)** & **[Termux:X11](https://github.com/termux/termux-x11)** community.

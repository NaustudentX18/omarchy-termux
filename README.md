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

## 📋 Prerequisites

Before starting, install the following apps on your Android device (preferably from **Droid-ify** or **F-Droid**):

1. **Termux**: [F-Droid](https://f-droid.org/en/packages/com.termux/) or [Droid-ify](https://github.com/Droid-ify/client) *(Never use the Google Play Store version, as it is outdated).*
2. **Termux:X11 Companion**: [Termux:X11 GitHub Releases](https://github.com/termux/termux-x11/releases) *(Download `app-arm64-v8a-debug.apk`)*.

---

## 🚀 One-Shot Installation

Open **Termux** and run this single command:

```bash
curl -sL https://raw.githubusercontent.com/NaustudentX18/omarchy-termux/main/install.sh | bash
```

The installer will:
1. Request Android storage permissions (`termux-setup-storage`).
2. Update packages and configure the `x11-repo`.
3. Install `proot-distro`, `virglrenderer`, `pulseaudio`, and dependencies.
4. Download and initialize Arch Linux ARM rootfs.
5. Create a standard `omarchy` user with passwordless `sudo`.
6. Install JetBrains Mono & Cascadia Code Nerd Fonts.
7. Clone and link the official `omacom/omarchy` binary scripts and themes.
8. Generate one-click startup launchers: `start-omarchy.sh` and `omarchy-cli.sh`.

---

## 🎮 Launching Omarchy

### 1. Full Graphical Desktop (Termux:X11)
To start the GUI desktop:

```bash
./start-omarchy.sh
# or simply:
omarchy-gui
```
Switch to the **Termux:X11** app to interact with your desktop!

### 2. Terminal-Only Mode
If you just want the fast Omarchy CLI shell inside Arch Linux without starting the display server:

```bash
./omarchy-cli.sh
# or simply:
omarchy-cli
```

---

## ⌨️ Desktop Shortcuts

| Shortcut | Action |
|---|---|
| `Super + Return` | Open Terminal |
| `Super + d` | Application Launcher (Rofi) |
| `Super + q` | Close Window |
| `Super + f` | Toggle Fullscreen |
| `Super + Shift + Space` | Toggle Floating Window |
| `Super + Shift + e` | Exit Session |

---

## 🛠️ Maintenance & Tips

- **Update Packages**: Inside Omarchy, run `sudo pacman -Syu` or `yay -Syu`.
- **Termux:X11 Display Tuning**: Open Termux:X11 preferences and adjust:
  - Display resolution scaling (e.g. 100% or 125% for high-DPI phone screens).
  - Touchscreen gesture settings (Trackpad mode vs Direct Touch).
- **Audio Troubleshooting**: If sound is muted, run `pulseaudio --kill && pulseaudio --start` in Termux.

---

## 📜 Credits & Upstream
- **[Omarchy](https://github.com/omacom/omarchy)** by David Heinemeier Hansson (DHH) & Omacom Foundation.
- **[Termux](https://termux.dev/)** & **[Termux:X11](https://github.com/termux/termux-x11)** community.

# ⚡ OMARCHY ON ANDROID TERMUX

> **The Opinionated, Modern Linux Workstation in Your Pocket**

[![Arch Linux](https://img.shields.io/badge/Arch_Linux-ARM64%20%7C%20x86__64-1793D1?style=for-badge&logo=arch-linux&logoColor=white)](https://archlinuxarm.org/)
[![Termux](https://img.shields.io/badge/Termux-Environment-000000?style=for-badge&logo=termux&logoColor=white)](https://termux.dev/)
[![PRoot](https://img.shields.io/badge/PRoot--Distro-Rootless%20Chroot-25D366?style=for-badge)](https://github.com/termux/proot-distro)
[![VirGL 3D](https://img.shields.io/badge/3D%20Accel-VirGL%20%7C%20llvmpipe-E64A19?style=for-badge&logo=vulkan&logoColor=white)](https://mesa3d.org/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg?style=for-badge)](LICENSE)

<p align="center">
  A <b>bulletproof one-shot bootstrap installer</b> that transforms your Android device into a complete, hardware-accelerated developer desktop powered by <b>Arch Linux ARM</b>, <b>i3 tiling window manager</b>, <b>PulseAudio/PipeWire audio</b>, and <b>DHH's Omarchy toolchain</b>.
</p>

---

## ⚡ Features

<table>
  <tr>
    <td width="50%">
      <h3>⚡ Bulletproof Installation</h3>
      Automated with automatic DNS injection, pacman keyring repair, entropy seeding (prevents hangs), and wake-lock protection.
    </td>
    <td width="50%">
      <h3>🚀 3D Graphics</h3>
      Hardware acceleration via VirGL (Snapdragon only) with automatic fallback to llvmpipe software rendering on non-Adreno chips.
    </td>
  </tr>
  <tr>
    <td width="50%">
      <h3>🔊 Native Audio</h3>
      Low-latency PulseAudio or PipeWire routing directly to Android speakers/headphones.
    </td>
    <td width="50%">
      <h3>🎨 Modern Developer Desktop</h3>
      JetBrains Mono + Noto fonts, Catppuccin i3-wm, rofi launcher, fastfetch, neovim, tmux, and more.
    </td>
  </tr>
</table>

---

## 📋 Hardware & Software Requirements

| Requirement | Details |
|---|---|
| **Device** | Android 12+ (64-bit aarch64) |
| **Storage** | ≥8GB free disk space |
| **Network** | Stable internet connection (WiFi/5G) — installs ~3GB packages |
| **Termux** | Installed from **F-Droid** or Droid-ify ⚠️ (NOT Google Play Store) |
| **Termux:X11** | Companion app for graphical desktop mode (see below) |

---

## 📋 Pre-Installation Checklist

> *Follow these steps BEFORE pasting the install command. Skipping them will cause failures.*

### ✅ Step 1: Install Termux from F-Droid

1. Go to [F-Droid](https://f-droid.org/) and search for **Termux** (package `com.termux`)
2. Download and install — do NOT use the Google Play Store version (outdated since 2020)
3. Alternatively, install from [Droid-ify app store](https://github.com/Droid-ify/client), or sideload the APK directly

### ✅ Step 2: Install Termux:X11

For graphical desktop mode, download `app-arm64-v8a-debug.apk` from:
👉 [Termux:X11 GitHub Releases](https://github.com/termux/termux-x11/releases)

Install it and leave it open — you'll switch to it after installing.

### ✅ Step 3: Disable Battery Optimization (Android 12+)

Android's "Phantom Process Killer" will terminate PRoot if background restrictions are active.

**Do this for BOTH Termux AND Termux:X11:**
1. Open **Android Settings** → Apps → Termux → App Battery Usage → Select **Unrestricted**
2. Repeat for Termux:X11 → Select **Unrestricted**

### ✅ Step 4: (Highly Recommended) Optimize Mirrors

In Termux, run:
```bash
termux-change-repo
```
Select the **Main repository** and choose a fast mirror like **Grimler** or **Cloudflare**.

### ✅ Step 5: Open Termux & Get Ready to Paste

Open your Termux terminal. Make sure you have at least 8GB of free storage and a stable WiFi/5G connection.

---

## 🚀 One-Shot Installation

Copy and paste the entire command below into your Termux terminal (**press Enter once it finishes**):

```bash
pkg update -y && curl -sL https://raw.githubusercontent.com/NaustudentX18/omarchy-termux/main/install.sh | bash
```

### What Happens During Install (~5-10 minutes)

<details>
  <summary>🔍 <b>See what the installer does step-by-step</b></summary><br>

<br>

1. **Environment Detection**: Detects whether you're on aarch64 or x86_64 and acquires a Termux wake-lock to prevent background sleep
2. **Permission Check**: Ensures Termux storage permissions are granted via `termux-setup-storage`
3. **Package Installation**: Installs `proot-distro`, `termux-x11-nightly`, `virglrenderer-android`, `pulseaudio`, and other host dependencies
4. **Arch Linux Bootstrap**: Downloads the official Arch Linux ARM rootfs via proot-distro with Cloudflare + Google DNS pre-configured
5. **Keyring Setup**: Seeds system entropy (prevents hangs), initializes pacman GPG keyrings, populates both archlinux and archlinuxarm keys
6. **Full System Upgrade**: Upgrades base Arch packages, installs 39 desktop/dev apps (i3-wm, neovim, fastfetch, etc.)
7. **Audio & Fonts**: Configures PulseAudio/PipeWire for Android audio routing, installs JetBrains Mono + Noto fonts with automatic cache rebuild
8. **User Account**: Creates the `omarchy` user with passwordless wheel sudo access (with retry loop to handle PRoot filesystem locks)
9. **Omarchy Integration**: Clones DHH's upstream omacom/omarchy toolkit and configures shell profiles
10. **Desktop Launchers**: Writes `omarchy-gui` (GUI mode) and `omarchy-cli` (terminal-only mode) shortcut scripts

*If any step fails, the installer stops immediately (no partial installs that silently break later)*<br>

</details>

---

## 🎮 Launching Omarchy After Install

Once installation completes (%100), you have two launch options:

### 🖥️ Option A: Full Graphical Desktop
```bash
omarchy-gui   # or: ./start-omarchy.sh
```
Then switch to the Termux:X11 app — your i3 desktop with status bar, terminal, and full mouse/keyboard support will appear.

### ⌨️ Option B: Terminal-Only Mode (Faster)
```bash
omarchy-cli   # or: ./omarchy-cli.sh
```
Quick terminal session inside Arch Linux without launching X11 (ideal for coding or server work).

---

## ⌨️ Desktop Keyboard Shortcuts

Press <kbd>Super</kbd> (⌘) + these keys from the desktop:
| Key | Action | Shortcut |
|---|---|---|
| <kbd>T</kbd> | Open Terminal | Super + Return |
| <kbd>M</kbd> | App Search Menu | Super + d |
| <kbd>Q</kbd> | Close Window | Super + q |
| <kbd>F</kbd> | Toggle Fullscreen | Super + f |
| <kbd>E</kbd> | Exit Desktop Mode | Super + Shift + e |
| <kbd>R</kbd> | Reload i3 Config | Super + Shift + r |

> **Pro-tip:** In Termux:X11 (⚡), swipe from the left edge to access Preferences → Remap `Super` key to your phone's Volume Up, Volume Down, or on-screen touch controls.

---

## 🛠️ Troubleshooting & FAQ

### ❓ "Installation says 'Cannot detect Arch rootfs directory'"
The rootfs didn't download correctly (network issue). Run:
```bash
proot-distro install archlinux
pkg update -y && curl -sL https://raw.githubusercontent.com/NaustudentX18/omarchy-termux/main/install.sh | bash  
```

### ❓ "Terminal shows gibberish characters / fonts broken"
The font cache didn't rebuild after install:
```bash
fc-cache -f  
```

### ❓ "Nothing appears on screen — black screen in Termux:X11"
Two quick fixes:
1. **Restart i3** to reload config: `Super + Shift + r`
2. **Kill stale processes** and retry: `omarchy-gui` (the launcher cleans up automatically), or manually:
   ```bash
   killall -9 termux-x11 Xwayland virgl_test_server_android 2>/dev/null; sleep 1 && omarchy-gui
   ```

### ❓ "Audio not playing"
The PulseAudio server on the Android host crashed. Restart it from Termux:
```bash
pulseaudio --kill && pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" --exit-idle-time=-1
```

For more detailed help, refer to the [Arch Linux ARM wiki](https://archlinuxarm.org/), or join the omarchy-termux community channels (if any).

---

## ⚡ Hardware Acceleration Notes

VirGL hardware acceleration works best on **Snapdragon devices** and may cause black screens or crashes on MediaTek Dimensity or other non-Adreno chips.

If you're having graphical glitches, try these Termux:X11 settings:
* Open Preferences → Display Resolution → Set to *Scaled* (not Raw)
* Switch between Trackpad (mouse) and Direct Touch modes
* Disable hardware acceleration by removing `-w` flag from the launcher script (falls back to llvmpipe software rendering)

---

## 📜 Credits & Acknowledgements

- **[Omarchy](https://github.com/omacom/omarchy)** by David Heinemeier Hansson (DHH)  
  Opinionated shell configuration & desktop environment
- **[Termux](https://termux.dev/)** — Full Linux environment on Android without root
- **[Termux:X11](https://github.com/termux/termux-x11)** — X Window System server for Termux
- **[Arch Linux ARM](https://archlinuxarm.org/)** — Rolling-release Linux distro for ARM devices

---

<details>
  <summary><b>Pure Terminal Mode</b></summary><br><br>
If you don't have Termux:X11 installed, you can still run the full desktop environment in pure terminal mode:

```bash
pkg install neovim fastfetch eza bat ttmux tmux git i3-r0w-i3status rofi dunst picom  
omarchy-cli  # starts Arch Linux ARM PRoot session
```
This installs everything without X11 dependency for terminal-only use (great for remote SSH sessions or when Termux:X11 is unavailable)

</details>

<br>
<div align="center">
<sub>Created by NaustudentX18 — Opinionated, Modern Linux on Android (PRoot + Termux:X11)</sub><br>
<br>
<sub>Happy hacking from your pocket!</sub><br>
  
</div>

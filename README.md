# Omarchy Termux

> Arch Linux + i3 desktop with the Omarchy toolchain, running rootless on your Android phone via Termux + PRoot + Termux:X11.

[![Arch Linux ARM](https://img.shields.io/badge/Arch_Linux_ARM-aarch64%20%7C%20x86__64-1793D1?style=flat-square&logo=arch-linux&logoColor=white)](https://archlinuxarm.org/)
[![Termux](https://img.shields.io/badge/Termux-PRoot--Distro-000000?style=flat-square&logo=termux&logoColor=white)](https://termux.dev/)
[![Termux:X11](https://img.shields.io/badge/Display-Termux%3AX11-17B2A8?style=flat-square)](https://github.com/termux/termux-x11)
[![Tests](https://img.shields.io/badge/tests-32%2F32%20passing-2EA043?style=flat-square)](tests/run-tests.sh)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)

<p align="center">
  <img src="assets/banner.jpg" alt="Omarchy Termux" width="720">
</p>

One script turns a plain Termux install into a full developer desktop: Arch Linux ARM under `proot-distro`, i3 window manager with Catppuccin theming, PulseAudio routed to Android speakers, Mesa graphics (VirGL or llvmpipe), and DHH's [Omarchy](https://github.com/omacom/omarchy) CLI toolchain.

**The installer is resumable** — if anything fails (usually network), fix nothing and just re-run it. Every step detects what is already done and skips it.

---

## Prerequisites — install these first, in this exact order

Each step exists because skipping it breaks a later one. Do them top to bottom, once.

### Step 1 — Remove the Play Store Termux (skip if you never had it)

The Google Play build of Termux has been abandoned since 2020 and cannot run proot-distro. Check **Settings → Apps**:
- **Termux installed from Play Store?** Uninstall it. You lose nothing — its data is incompatible anyway.
- **Termux installed from F-Droid or GitHub?** Keep it, skip to Step 3.

### Step 2 — Install F-Droid

F-Droid is the app store we'll pull Termux and Termux:Widget from.

1. Open [f-droid.org](https://f-droid.org) in your phone's browser
2. Download the F-Droid APK and install it (allow "install unknown apps" when prompted)
3. Open F-Droid once and let it refresh its index

### Step 3 — Install Termux (from F-Droid)

1. In F-Droid, search for **Termux** (package `com.termux`)
2. Install it
3. Open Termux once, grant any permission it asks for, then close it

> Alternative if you prefer GitHub: grab the Termux APK from [termux/termux-app releases](https://github.com/termux/termux-app/releases). Pick **one** source and stay with it for Termux *and* Termux:Widget.

### Step 4 — Install Termux:Widget (from F-Droid, optional)

Gives you a home-screen button that launches the Omarchy desktop with one tap.

1. In F-Droid, search for **Termux:Widget** (package `com.termux.widget`)
2. Install it

### Step 5 — Install Termux:X11 (from GitHub — it is NOT on F-Droid)

This is the display server app; the desktop renders inside it.

1. Go to [termux/termux-x11 Releases](https://github.com/termux/termux-x11/releases)
2. Download the latest **`app-arm64-v8a.apk`** (use `app-x86_64.apk` only on an x86 emulator)
3. Install it (allow "install unknown apps" for your browser when prompted)

> If you ever upgrade Termux:X11, uninstall the old one first — release and debug builds are signed differently and refuse to overwrite each other.

### Step 6 — Disable battery optimization (all three apps)

Android's phantom process killer will murder PRoot mid-install otherwise. For **Termux**, **Termux:X11** and **Termux:Widget**:

**Settings → Apps → (app) → Battery → Unrestricted**

### Step 7 — Open Termux and run the installer

That's everything. Continue to the next section.

---

## Install — one command

Open Termux and paste:

```bash
curl -sL https://raw.githubusercontent.com/NaustudentX18/omarchy-termux/main/install.sh | bash
```

If Android's clipboard mangles long pasted lines, use this instead:

```bash
wget -qO i.sh https://raw.githubusercontent.com/NaustudentX18/omarchy-termux/main/install.sh && bash i.sh
```

**Requirements:** Android 8+ · 64-bit · ~8 GB free storage · stable Wi-Fi (downloads ~3 GB).

### What the installer does

| Step | Action | Skips if… |
|---|---|---|
| 1 | Verifies Termux + CPU architecture, takes a wake-lock | — |
| 2 | Updates Termux packages, installs `proot-distro`, `termux-x11`, audio + graphics helpers | already installed |
| 3 | Downloads the official Arch Linux ARM rootfs (~140 MB) | rootfs dir already on disk |
| 4 | Inside PRoot: pacman keyring init, full system upgrade, 39 desktop/dev packages, user `omarchy` | `--needed` skips installed pkgs |
| 5 | Inside PRoot as `omarchy`: shell profile, i3 config, session script | profile marker exists |
| 6 | Writes launchers + home-screen shortcut, verifies the install | — |

Expect **5–15 minutes** total. Watch for `==> [arch/root]` lines — that's the inner Arch Linux provisioning talking.

If anything fails the installer stops **at that step**, tells you why, and keeps the failing script for debugging. Re-running resumes from where it stopped.

---

## Launch

```bash
omarchy-gui    # full desktop — then switch to the Termux:X11 app
omarchy-cli    # terminal-only Arch session (no X11)
```

Or tap the **Omarchy** button if you added the Termux:Widget (long-press desktop → Widgets → Termux:Widget).

Default login inside Arch: user `omarchy`, password `omarchy`, passwordless sudo.

### Desktop shortcuts (Super = the ⊞/⌘ key)

| Shortcut | Action |
|---|---|
| Super + Enter | Terminal (xterm) |
| Super + d | App launcher (rofi) |
| Super + q | Close window |
| Super + f | Fullscreen |
| Super + arrows | Focus windows |
| Super + Shift + r | Reload i3 |
| Super + Shift + e | Exit desktop |

---

## Troubleshooting

**Install failed mid-way**
Re-run the installer — it resumes. Persistent failures are almost always network; try `termux-change-repo` in Termux and pick a nearer mirror, then re-run.

**`termux-x11` companion package missing (warned at end of install)**
```bash
pkg install x11-repo && pkg install termux-x11
```
Then re-run the installer once.

**Termux:X11 app missing (warned at end of install)**
Back to Prerequisites Step 5 — the app only comes from [GitHub releases](https://github.com/termux/termux-x11/releases).

**Black screen after `omarchy-gui`**
The session usually needs one retry the first time: wait 10 s, run `omarchy-gui` again. Still black → in Termux:X11 Preferences, set *Display Resolution Mode* to *Scaled* and relaunch.

**No audio**
```bash
pulseaudio --kill; omarchy-gui
```
The launcher restarts PulseAudio with the Android bridge module.

**`Cannot detect Arch rootfs directory`**
```bash
proot-distro remove archlinux
```
Then re-run the installer (rootfs re-downloads cleanly).

---

## Repository structure

```
omarchy-termux/
├── install.sh              # the one-shot installer (Termux side)
├── tests/
│   └── run-tests.sh        # sandbox harness: full install flow on any Linux box
├── assets/
│   ├── banner.jpg
│   └── architecture.jpg
├── CHANGELOG.md
└── LICENSE                 # MIT
```

### Development

The installer is written to be testable off-device — inner PRoot scripts take their rootfs from `OMARCHY_ROOTFS`, so a stubbed sandbox can execute the whole flow:

```bash
bash tests/run-tests.sh    # 32 assertions: fresh install, re-run, failure path
```

---

## Credits

- **[Omarchy](https://github.com/omacom/omarchy)** — David Heinemeier Hansson's opinionated Arch desktop, which this project brings to Android
- **[Termux](https://termux.dev/)** / **[proot-distro](https://github.com/termux/proot-distro)** — rootless Linux on Android
- **[Termux:X11](https://github.com/termux/termux-x11)** — X server for the graphical desktop
- **[Arch Linux ARM](https://archlinuxarm.org/)** — the rootfs underneath

MIT licensed — see [LICENSE](LICENSE).

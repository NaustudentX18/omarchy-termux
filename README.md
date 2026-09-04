# Omarchy Termux (native parity)

A one-shot installer that puts the **real Omarchy** on an Android phone:
Hyprland compositor, the actual **Omarchy Shell** (quickshell bar / menu /
notifications / OSD), Foot terminal, Nautilus, Chromium — all themed with
the native Tokyo Night palette, rendered through a patched nested Wayland
stack because the upstream Hyprland can't drive PRoot without it.

```
┌──────────────────── Phone ────────────────────┐
│  Termux host (Bionic/Android)                 │
│  ┌───────────────┐    ┌────────────────────┐   │
│  │  Termux:X11   │ ◄──│  Weston (patched)  │   │
│  │  surface &    │    │  nested Wayland    │   │
│  │  input bridge │    │  parent            │   │
│  └───────────────┘    └────────┬───────────┘   │
│  ┌──── PRoot Arch ARM ────────│─────────────┐  │
│  │  guest /                   │             │  │
│  │   Hyprland (patched) ──────┘             │  │
│  │   ─ Aquamarine Wayland backend (no KMS)  │  │
│  │   ─ Omarchy Shell  quickshell QML        │  │
│  │   ─ foot / nautilus / chromium           │  │
│  │   ─ Hyprland config + Tokyo Night theme  │  │
│  └──────────────────────────────────────────┘  │
└────────────────────────────────────────────────┘
```

The prebuilt graphics stack (patched Weston module, patched Hyprland +
Aquamarine stages, Mesa KGSL/Turnip build) ships in the checksum-verified
[omarchy-android v0.1.1 release bundle](https://github.com/BlackFireAlex/omarchy-android/releases/tag/v0.1.1).
Nothing compiles on the phone.

## What you need on the phone

| Requirement   | Notes |
|---|---|
| **Android 8+**, ARM64 | S25 / Tab S9 / any Adreno or Mali phone with ≥8 GB free |
| Termux from F-Droid **or** GitHub | **NOT** the Play Store build — it is years out of date |
| **Termux:X11 nightly APK** from GitHub releases | `com.termux.x11` — stable build won't work for the AHardwareBuffer path |
| Developer options → **"Disable child process restrictions"** | Without it the Android 12+ phantom-process killer reaps the desktop within ~30 s |
| ≥8 GB free storage | The container takes ~4 GB; ~1.1 GB to download the bundle |

## Quick start

```bash
curl -sL https://raw.githubusercontent.com/NaustudentX18/omarchy-termux/main/install.sh | bash
```

(or `wget -qO- ... | bash`).

The first run auto-detects every prerequisite and walks through:
**preflight → host packages → fetch & verify the bundle → deploy the
rootfs & host runtime → vendor session scripts → launchers & shortcuts →
smoke-test the guest.**

When installation finishes you can drive the desktop with:

```bash
omarchy-gui      # start desktop (switch to the Termux:X11 app)
omarchy-stop     # tear it down
omarchy-cli      # drop straight into the omarchy shell (no GUI)
omarchy-gui status
```

A home-screen launcher (`Termux:Widget` → `~/.shortcuts/Omarchy`) appears
the first time `termux-widget` is run.

## Preflight at any time

```bash
./install.sh doctor
```

Prints PASS/WARN/FAIL for Termux, architecture, host packages, KGSL GPU,
phantom-process state, Termux:X11 app presence, install state.

## How it picks a GPU

| Device has… | Picks |
|---|---|
| Read+write `/dev/kgsl-3d0` (Adreno) | `kgsl` — direct Adreno GPU acceleration via the private Mesa build in the bundle |
| Otherwise | `virgl` — universal VirGL software path (`virgl_test_server_android`) |

You can override either path at install time:

```bash
OMARCHY_GPU_MODE=kgsl  ./install.sh   # force KGSL
OMARCHY_GPU_MODE=virgl ./install.sh   # force VirGL
```

## Like-for-like vs i3

| Feature | omarchy-termux v2 (this build) | omarchy-termux v1 (`install-x11.sh`) |
|---|---|---|
| Compositor | **Hyprland (patched)** | i3 |
| Display backend | nested Weston → Wayland | Termux:X11 → X11 |
| Shell | **Omarchy Shell** (quickshell bar, menu, notifications, OSD) | polybar + rofi, custom bash prompts |
| Terminal | **foot** | xterm |
| Themes | native (`omarchy-theme-set "Tokyo Night"`) | hand-rolled colour swaps |
| Theme switcher | full `omarchy-theme-set` + per-bar widget | none |
| Audio | PulseAudio over TCP, AAudio sink | PulseAudio over TCP, `module-native-protocol-tcp` |
| Launcher menus | real Omarchy menu, Spotlight search, keyboard panel | `rofi -show run` |
| v1 retention | `install-x11.sh` in the repo (deprecated, kept for git-history access) | — |

## Storage and bandwidth

The release bundle is **1.18 GB** (xz-compressed rootfs + patched stages +
weston `.so`). It is downloaded once and cached at
`~/.cache/omarchy-termux/`. If the bundle ever fails to verify (e.g.
truncated download), the installer **deletes the partial copy and retries**;
`OMARCHY_BUNDLE=/path/to/local.bundle ./install.sh` accepts a sideloaded
copy.

## Tested on

| Component | Version |
|---|---|
| omarchy-android release | v0.1.1 (pinned SHA256 in install.sh) |
| Termux | `0.118+` from F-Droid / GitHub |
| Termux:X11 | nightly `v1.5+` |
| Weston (Termux pkg) | `weston 14.0.2-1` from `x11-repo` |
| Mesa Turnip (Termux pkg) | `mesa-vulkan-icd-freedreno 26.0.6-3` |
| Android | API 31+ (Android 12+) |

## Troubleshooting

- **`omarchy-gui` starts but the desktop dies in 30 s** — phantom processes
  are active. Re-enable Developer options → "Disable child process
  restrictions", re-run `omarchy-gui`.
- **`KGSL mode needs read/write access to /dev/kgsl-3d0`** — your phone's
  KGSL node is restricted. Install with `OMARCHY_GPU_MODE=virgl ./install.sh`
  to fall back automatically; VirGL is slower but universal.
- **`GET_PROC: cannot read …/proot/.…`** — old container half-installed;
  `proot-distro remove omarchy-android && bash ./install.sh`.
- **Weston says `libweston-14 ... not found`** — your Termux `weston` pkg
  was updated past 14. The install depends on the `libweston-14` module
  directory for the patched x11-backend. Either downgrade
  (`apt install weston=14.0.2-1`) or wait for the upstream omarchy-android
  release that supports libweston-15.

## Attribution

This installer is a thin wrapper that deploys, wires, and verifies the
upstream projects that make the native Omarchy experience possible on
Android:

| Component | License | Source |
|---|---|---|
| omarchy-android release bundle | MIT + per-component | [BlackFireAlex/omarchy-android](https://github.com/BlackFireAlex/omarchy-android) (release v0.1.1) |
| Omarchy (guest rootfs) | MIT | [basecamp/omarchy](https://github.com/basecamp/omarchy) (pinned revision) |
| Hyprland | BSD-3-Clause | [hyprwm/Hyprland](https://github.com/hyprwm/Hyprland) |
| Aquamarine | BSD-3-Clause | [hyprwm/aquamarine](https://github.com/hyprwm/aquamarine) |
| Weston | MIT | [wayland/weston](https://gitlab.freedesktop.org/wayland/weston) |
| Mesa / Turnip | MIT + SGI-B-2.0 | [mesa/mesa](https://gitlab.freedesktop.org/mesa/mesa) |
| Termux | GPL-3 | [termux/termux-app](https://github.com/termux/termux-app) |
| Termux:X11 | MIT | [termux/termux-x11](https://github.com/termux/termux-x11) |

The installer scripts in this repo are MIT-licensed — see `LICENSE`.

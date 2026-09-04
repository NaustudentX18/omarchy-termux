# Changelog

## [2.0.0] — 2026-09-04 (native-parity rehaul)

### Changed — the desktop is now the REAL Omarchy
- **Compositor: i3 → Hyprland (patched).** Native Omarchy runs on
  Hyprland + Aquamarine; under PRoot, stock Hyprland requires DRM/KMS
  (which PRoot cannot expose) and its Wayland backend has unfixed
  Android buffer-presentation bugs. We now consume the patched
  Hyprland+Aquamarine+Weston stacks from the checksum-verified
  [omarchy-android v0.1.1 release bundle](https://github.com/BlackFireAlex/omarchy-android/releases/tag/v0.1.1)
  (MIT). The full prebuilt guest rootfs is part of that bundle — quickshell
  0.3.1, foot 1.27, nautilus 50, chromium 151, omarchy Shell v4 plus the
  pinned basecamp/omarchy repository at /usr/share/omarchy.
- **Display chain: Termux:X11 → X11 with i3 → Termux:X11 → patched Weston
  (nested Wayland parent) → patched Hyprland (Wayland client of Weston)
  → real Omarchy Shell.**
- **Shell: hand-rolled i3 config → real Omarchy Shell (quickshell QML
  bar, menu, Spotlight-style launcher, notifications, OSD).** Themes
  switch via the upstream `omarchy-theme-set` command, against any of
  the bundled theme packages (`themes/tokyo-night`, `catppuccin`,
  `nord`, `gruvbox`, …).
- **Terminal: xterm → foot.**
- **Installer architecture: pacman bootstrap → bundle deploy.** The new
  flow downloads (~1.1 GB once), SHA256-verifies, extracts, deploys the
  prebuilt rootfs into a `omarchy-android` PRoot container, vendors the
  upstream start/stop/status/hyprctl scripts, writes
  `runtime.conf`, and runs a smoke test.
- **Default container name is `omarchy-android`** to keep the upstream
  release.bundle the single source of truth (its `/proc/maps` matching
  expects that name). Renamable via `OMARCHY_CONTAINER_NAME=<name>`.
- **GPU auto-detect:** KGSL (Adreno) with direct DMA-BUF when
  `/dev/kgsl-3d0` is rw; otherwise VirGL (universal but slower).
- **Status, stop, and hyprctl commands** added (`omarchy-gui status`,
  `omarchy-stop`, the `omarchy-android` dispatcher at
  `~/.local/share/omarchy-android/bin/`).
- **Storage / bandwidth:** baseline install now needs ~8 GB free storage
  and downloads ~1.18 GB once. Doctor check enforces and explains this.

### Added
- **`install.sh doctor`** — non-destructive host-readiness inspector.
  Checks Termux env, architecture, host packages, Adreno KGSL,
  phantom-process state, Termux:X11 app, install state.
- **`OMARCHY_BUNDLE=/path/to/file.tar`** — sideload a pre-downloaded
  bundle (useful in low-bandwidth environments).
- **`OMARCHY_GPU_MODE=kgsl|virgl|auto`** — override GPU selection at
  install time.
- **`OMARCHY_SCALE`, `OMARCHY_REFRESH_MHZ`, `OMARCHY_KEYBOARD_LAYOUT`,
  `OMARCHY_SHARE`, `OMARCHY_AUDIO`** — runtime.tunables written into
  `runtime.conf`.
- **Phantom-process guidance** — doctor reports Developer-options
  "Disable child process restrictions" requirement with the exact path
  (Build number × 7 → Developer options).
- **Manifest-level checksum verify** — bundle extracted only after
  outer SHA256, inner `SHA256SUMS -c`, and tar member path-safety scan
  (no `/…` or `..` member paths).
- **Brand new `tests/run-tests.sh`** (38 assertions):
  static checks, full sandbox install (fresh), idempotency re-run,
  tamper detection with cache re-seed + recovery, unsafe-tar-path
  refusal, missing-host-command abort with fix hint, doctor mode.
  Runs the entire flow on any Linux box without a phone.
- **`install-x11.sh` is preserved** in the repo (deprecated; contains
  the v1 i3 implementation reachable from git history or for fallback
  needs).

### Removed
- The deprecated Tokyo Night copy + i3 config dropped in v1 — the new
  flow uses the upstream omarchy Shell + pinned Tokyo Night from the
  release bundle.
- Hand-rolled `.startwm`, manually-configured `pulseaudio` module
  ceremony, custom rofi theme — all delegated to upstream omarchy.

### Attribution
The native-parity build would not exist without the
[BlackFireAlex/omarchy-android](https://github.com/BlackFireAlex/omarchy-android)
project, which ships the proven patched display stack and the prebuilt
guest rootfs. See `README.md` § "Attribution" for full credits. Special
thanks to hyprwm, basecamp/omarchy, and the Mesa Turnip maintainers.

## [1.1.0] — 2026-09-04

### Fixed
- Inner provisioning script always aborted after system upgrade (inverted
  `_SOK` flag with no error capture).
- aarch64 bootstrap impossible on proot-distro v5+ (Docker Hub pull).
- Every package download failed inside PRoot (Landlock sandbox).
- `omarchy-gui: command not found` right after install (aliases only
  load in new shells).
- Step-4 container detection false results (parsed `proot-distro list`).
- Gutted audio block, fragile rootfs URL, PAM-flaky `su`.

### Added
- Sandbox test harness (`tests/run-tests.sh`, 32 assertions).
- Resume-safe installs.
- Termux:Widget home-screen shortcut.

## [1.0.0] — 2026-09-03

- Initial one-shot installer: Arch ARM rootfs, keyring repair, DNS
  injection, i3 + Catppuccin desktop, audio bridge, VirGL/llvmpipe
  graphics, `omarchy-gui` / `omarchy-cli` launchers.

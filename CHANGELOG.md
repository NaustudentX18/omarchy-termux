# Changelog

## [1.1.0] — 2026-09-04

### Fixed
- **Inner provisioning script always aborted after system upgrade** — inverted `_SOK` flag with no error capture made every install end in `[ERR] sys upgrade failed` even when pacman succeeded. All inner commands now use explicit `if !` error capture.
- **aarch64 bootstrap impossible on proot-distro v5+** — newer versions pull `archlinux` from Docker Hub (amd64-only: "No image found for architecture 'arm64'"). The installer now installs the official Arch Linux ARM tarball from the last proot-distro release that shipped it (`v4.17.3`, asset verified live), with the distro alias as fallback. Rootfs detection also covers both on-disk layouts (`installed-rootfs/` and `containers/<name>/rootfs`).
- **Every package download failed inside PRoot** — pacman 7's download sandbox (`DownloadUser = alpm` + Landlock LSM) can't work on Android kernels under PRoot ("restricting filesystem access failed because Landlock is not supported"). The installer now sets `DownloadUser = root` in the rootfs pacman.conf before any install.
- **`omarchy-gui: command not found` right after install** — the aliases only load in *new* shells. Real executables are now installed in `$PREFIX/bin` so the commands work in the current session immediately.
- **Step-4 container detection false results** — detection parsed `proot-distro list`, which lists *available* (not-yet-installed) distros too, so fresh devices skipped bootstrap and existing devices could double-install. Detection now checks the rootfs directory on disk (`$PREFIX/var/lib/proot-distro/installed-rootfs/archlinux`) and is immune to proot-distro output-format changes.
- **Gutted audio block** — empty remnants of a failed patch left the PulseAudio/PipeWire fallback dead. Rewritten: PulseAudio with client config, pipewire-pulse fallback, non-fatal if neither.
- **Removed fragile pinned rootfs URL** (`v4.17.3` + `--name` flag) in favour of plain `proot-distro install archlinux`, which always resolves the right tarball for the device architecture.
- **User provisioning no longer uses `su` inside PRoot** (PAM-flaky on Android). Runs via `proot-distro login --user omarchy`.
- **Broken `termux-x11` version detection** (`2>&1 /dev/null` redirect nonsense) replaced by a `command -v` guard with `termux-x11` / `termux-x11-nightly` package fallback.
- **Shell profiles appended on every run** — now guarded by markers; re-runs no longer duplicate `.bashrc` content.
- Installer no longer `clear`s the terminal on start, preserving error scrollback for debugging.

### Added
- **Sandbox test harness** (`tests/run-tests.sh`) — 32 assertions covering fresh install, idempotent re-run, and failure paths, runnable on any Linux box without a phone. Inner scripts honour `OMARCHY_ROOTFS` to make this possible.
- **Resume-safe installs** — every step detects completed work and skips it; a failed root provisioning keeps its script on disk for inspection.
- **Termux:Widget home-screen shortcut** (`~/.shortcuts/Omarchy`) created automatically when Termux:Widget is present.
- **Post-install verification** — checks launchers, inner session files, sudoers, and whether the Termux:X11 *app* is installed, with precise remediation messages.
- Restructured README with an exact-order prerequisites guide (Play-Store removal → F-Droid → Termux → Widget → X11 app → battery optimisation).

### Removed
- Debug debris from the hotfix sessions (`FIX-PLAN.md`, `fix_*.py`).

## [1.0.0] — 2026-09-03

- Initial one-shot installer: Arch ARM rootfs, keyring repair, DNS injection, i3 + Catppuccin desktop, audio bridge, VirGL/llvmpipe graphics, `omarchy-gui` / `omarchy-cli` launchers.

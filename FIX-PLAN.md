# FIX PLAN: omarty-termux — `install.sh` Bug Sweep & Runtime Hardening

**Generated:** 2026-09-04
**Scope:** All known bugs + Termux ecosystem runtime failures
**Priority:** 3 CRITICAL first, then structural hardening, then UX polish
**Approach:** Phased — each phase must pass independently before proceeding.

---

## PRE-FLIGHT

Create a branch and get push access:
```bash
cd ~/tmp/omarchy-termux   # freshly cloned from NaustudentX18/omarchy-termux
git checkout -b fix-all-bugs
# If push access needed (not yet available via eval/bash on this Pi)
# Either push directly, or open a PR to the repo
```

---

## PHASE 0 — Quick Wins (0 runtime cost, defensive only)

| #    | File / Line          | Issue | Fix |
|------|---------------------|-------|-----|
| **P0-1** | `install.sh:8` | Missing `pipefail` in `set -euo pipefail` is fine, but `|| true` swallows failures everywhere. **Not a quick win — that's Phase 1.** | *Skip* — covered in Phase 1. |
| **P0-2** | `install.sh:313` | Heredoc delimiter `USER_BASHRC` uses `<< "USER_BASHRC"` (quoted), so inner `$` variables like `$PATH`, `$PULSE_SERVER` are treated as literal strings inside the heredoc — but that's **correct behavior** since they're meant to be written into the guest `.bashrc`. No bug. |
| **P0-3** | `install.sh:412-447` | Launcher `start-omarchy.sh` uses hardcoded `/data/data/com.termux/files/usr/bin/bash` — fine but brittle. | Add a symlink check or let `$PATH` resolve. Minor. |
| **P0-4** | `install.sh:436` | `termux-x11 :0 -ac -legacy-drawing` — the `-legacy-drawing` flag is deprecated in newer Termux:X11 builds and may break on Android 15+. | Replace with `-w` (wayland-compat) if available, keep legacy as fallback. |
| **P0-5** | `install.sh:461-463` | Aliases added to `.bashrc` but the profile file is already sourced in Termux. If user has existing aliases in their `.bashrc`, the new ones will shadow but the old aliases won't be overridden. | Wrap in `unalias omarchy-gui omarchy-cli 2>/dev/null; alias ...` or source from `~/.profile.d/`. Minor. |

**Action:** Fix P0-4 (legacy-drawing deprecation) and P0-5 (alias collision). Both are simple sed/replace operations. Takes ≤10 min.

---

## PHASE 1 — Installer Correctness (Fix Crashes, Soft-Fails)

### P1-1: PROOT_ROOT detection failure → host filesystem corruption [CRITICAL]
**File:** `install.sh` lines ~148–163
**Root cause:** When path detection returns empty (layout mismatch, partial install, non-standard termux), `$PROOT_ROOT` is empty string. The subsequent writes (`rm -f "$PROOT_ROOT/etc/...` etc.) expand to `rm -f /etc/resolv.conf` or `> /root/setup_omarchy.sh` **inside Termux host**, not the guest.

**Fix:** Abort if `$PROOT_ROOT` is empty:
```bash
if [ -z "$PROOT_ROOT" ] || [ ! -d "$PROOT_ROOT" ]; then
    log_err "Cannot detect Arch Linux rootfs. Run `proot-distro install archlinux` first."
    exit 1
fi
```

### P1-2: DNS injection on host resolv.conf [CRITICAL — if P1-1 didn't fire]
**File:** `install.sh` lines ~168–174
**Root cause:** If PROOT_ROOT is empty or wrong, `rm -f "$PROOT_ROOT/etc/resolv.conf"` and `cat > "$PROOT_ROOT/etc/resolv.conf"` writes to Termux host.

**Fix:** Already covered by P1-1 abort. No separate fix needed once P1-1 is applied. Add a safety guard as well:
```bash
if [ "$PROOT_ROOT" = "" ] || [ "$PROOT_ROOT" = "/" ]; then
    log_err "PROOT_ROOT is empty or / — aborting to prevent host damage."
    exit 1
fi
```

### P1-3: `pacman-key --init` entropy starvation → hangs for hours [CRITICAL]
**File:** `install.sh` lines ~194–202
**Root cause:** `pacman-key --init` calls gpg-agent, which reads from `/dev/random`. Inside PRoot on Android, hardware RNG is not exposed. The command hangs indefinitely.

**Fix (in the INNER heredoc script):**
```bash
# Seed entropy before pacam-key init — CRITICAL for ARM Android
rngd -r /dev/urandom -f &
RNGD_PID=$!
sleep 2   # let rngd initialize

timeout 120 pacman-key --init --keyserver hkps://keys.gnupg.net || {
    log_err "pacman-key init timed out after 120s — entropy still not available."
    exit 1
}

# Clean up rngd
kill "$RNGD_PID" 2>/dev/null; wait "$RNGD_PID" 2>/dev/null || true
```

### P1-4: Cascading `|| true` masks every pacman keyring failure [CRITICAL]
**File:** `install.sh` lines ~199,201,205,207,211,256,261 (+ ~10 more `|| true`)
**Root cause:** Every single pacman operation has `|| true`. When P1-3 fails, keyring init fails, pacakge populate fails, `pacman -Syu` fails, and the entire package loop silently skips every package. The script prints a green "INSTALLATION COMPLETE" banner but ships a non-functional Arch rootfs with zero installed packages.

**Fix:** Replace blanket `|| true` with a structured error logger:
```bash
fatal() { log_err "$1 (exit=$?)"; exit 1; }
warn()  { log_warn "$1 (exit=$?)"; }   # non-fatal by default

# pacman-key init — fatal
pacman-key --init || fatal "pacman-key --init failed"

# pacman-key populate — fatal, but try both
pacman-key --populate archlinuxarm || pacman-key --populate archlinux || \
    fatal "Neither archlinuxarm nor archlinux keyring populate succeeded"

# pacman -Syu — fatal
pacman -Syu --noconfirm || warn "pacman system upgrade had issues"

# Package loop — non-fatal per-pkg, but fatal if zero succeed
pkg_count=0
for pkg in "${PACKAGES[@]}"; do
    if pacman -S --noconfirm --needed "$pkg" 2>/dev/null; then
        ((pkg_count++))
    else
        warn "Package $pkg failed to install"
    fi
done

if (( pkg_count == 0 )); then
    fatal "Zero packages installed — keyring is broken"
elif (( pkg_count < ${#PACKAGES[@]} )); then
    warn "$pkg_count/${#PACKAGES[@]} packages installed; some failed."
fi
```

### P1-5: AUR-only fonts via pacman (silently fails) [MAJOR]
**File:** `install.sh` lines ~271–273  
`ttf-jetbrains-mono-nerd`, `ttf-cascadia-code-nerd`, `ttf-joypixels` are **NOT** in Arch official repos.

**Fix:** Replace with real repo packages:
```bash
# Official repos have these — all provide Nerd Font variants
pacman -S --noconfirm --needed ttf-jetbrains-mono noto-fonts noto-fonts-emoji \
    ttf-cascadia-code || warn "Some fonts not available in Arch repo"

fc-cache -f  # rebuild font cache
```
Update the i3 config line ~364 from `JetBrainsMono Nerd Font` to `JetBrains Mono` (the font name changes when installed without `-nerd`). Actually, `ttf-jetbrains-mono` in Arch ships both regular and Nerd-font variants — confirm by checking archlinuxarm package. If it's just the base font, use `Nix/Nerd-Font`.

### P1-6: VirGL on non-Qualcomm SoCs [MAJOR]  
**File:** `.startwm` inside heredoc, lines ~322–323
**Root cause:** `GALLIUM_DRIVER=virpipe` only works on Qualcomm Adreno. Non-Adreno SoCs (Dimensity, Exynos, Tensor) render a black screen with no visible error in the PRoot session.

**Fix — auto-detect + fallback:**
```bash
# Auto-detect VirGL support; fall back to software rendering
if virgl_test_server_android --test >/dev/null 2>&1; then
    export GALLIUM_DRIVER=virpipe
    log_info "VirGL hardware acceleration detected"
else
    export GALLIUM_DRIVER=llvmpipe
    log_warn "VirGL not available — falling back to llvmpipe software rendering"
fi
export MESA_GL_VERSION_OVERRIDE=4.0
```

### P1-7: `useradd` inside PRoot fails with /etc/passwd lock [MAJOR]
**File:** `install.sh` lines ~277–282
**Root cause:** proot-distro #159, proot#191 — `useradd` can fail to lock `/etc/passwd` when multiple processes run concurrently. Also running as root inside a PRoot shell means user accounts are per-session, not persisted across reboots.

**Fix:** Use a race-guard and check if user exists before attempting create:
```bash
USERNAME="omarchy"
if ! grep -q "^${USERNAME}:" "$PROOT_ROOT/etc/passwd"; then
    # Wait up to 30s for /etc/passwd lock to clear
    for i in $(seq 1 6); do
        if useradd -m -s /bin/bash -G wheel "$USERNAME" 2>/dev/null; then
            break
        else
            sleep 5
            log_warn "useradd retry ${i}/6..."
        fi
    done
fi
```

### P1-8: proot-distro v4 vs v5 incompatibility [MAJOR]
**File:** `install.sh` lines ~139, ~149–152
**Root cause:** Hardcoded URL for `v4.17.3.tar.xz`. proot-distro v5.8.0 is a Python rewrite; it changed the rootfs layout (`containers/<name>/rootfs`) and uses OCI registries instead of tarballs.

**Fix:** Detect the installed version:
```bash
PD_VERSION=$(proot-distro --version 2>/dev/null | awk '{print $NF}')
if [[ "${PD_VERSION}" =~ ^5 ]]; then
    log_info "Using proot-distro v5 — relying on built-in install..."
else  
    # v4 path — try URL first
    ARCH_ROOTFS_URL="https://github.com/termux/proot-distro/releases/download/v4.17.3/archlinux-aarch64-pd-v4.17.3.tar.xz"
    proot-distro install --name "$DISTRO_NAME" "$ARCH_ROOTFS_URL" || \
        proot-distro install "$DISTRO_NAME"
fi
```

### P1-9: `pacman -Syu` at line 211 before keyring is finalized [MAJOR]
**File:** `install.sh` inside heredoc line ~211
**Root cause:** Line 205 does `pacman -Sy --noconfirm archlinux-keyring`, then immediately does `pacman -Syu`. On Arch the `-y` in `-Syu` conflicts with `-y` from line 205 — double-refresh can cause signature mismatches mid-stream.

**Fix:** Use `pacman -Syyu` (force refresh) after keyring install:
```bash
pacman -S --noconfirm archlinux-keyring
pacman -Syyu --noconfirm   # force refresh + upgrade in one
```

### P1-10: Launchers use wrong user home path [MAJOR]
**File:** `install.sh` lines ~441  
`proot-distro login archlinux --user omarchy — shared-tmp — env DISPLAY=:0 ... /home/omarchy/.startwm`

**Root cause:** In proot-distro v5+, user home is at `/home/<user>`, not necessarily. However the `.bashrc` appends to it with `$HOME` from the outer login. The `start-omarchy.sh` calls `proot-distro login archlinux --user omarchy` but uses PATH `/home/omarchy/.startwm` which is correct for rootfs v4+v5. No bug — this is actually correct.

---

## PHASE 2 — Inner Provisioning Hardening (After P1 Passes)

### P2-1: Entropy during `pacman-key --populate` [CRITICAL]
**File:** lines ~198–202 (inner heredoc)
**Fix:** Same approach as P1-3 — run `rngd` before the entire keyring block, kill after.

### P2-2: Duplicate DNS injection [MINOR]
**File:** Outer (line 87/168–174) and inner heredoc (line 188–191) both set DNS.
**Fix:** Remove the outer one. The inner script already injects inside the guest properly.

### P2-3: `dbus-launch` fails silently (no session bus) [MINOR]
**File:** `.startwm` inside heredoc line ~345–347
**Root cause:** If dbus isn't installed or the session bus can't start, i3 launches without dbus. Some apps crash without it.
**Fix:** Add `DBUS_SESSION_BUS_ADDRESS` fallback:
```bash
if command -v dbus-launch >/dev/null 2>&1; then
    eval $(dbus-launch --sh-syntax)
else
    export DBUS_SESSION_BUS_ADDRESS=$(mktemp -u)
fi
```

### P2-4: PulseAudio host/guest conflict [MINOR]
**File:** Host `start-omarchy.sh:421` and guest `/etc/pulse/client.conf` inner heredoc line 265
**Root cause:** Both the Termux host pulseaudio and the Arch guest try to bind port 4713.

**Fix:** Use a different ephemeral port in guest config, or explicitly set `tcpwrap=none` for anonymous mode. The client.conf in the guest should target `127.0.0.1` (already does), so this should work. The real risk is host `pulseaudio --exit-idle-time=-1` fails when another PA instance is already running (i.e., the Termux user's own PulseAudio server).

**Better fix:** Start PulseAudio with a unique environment variable override:
```bash
pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
    --exit-idle-time=-1 --daemonize \
    --high-priority 2>/dev/null || true
# OR fall back to PipeWire if PA fails
command -v pipewire-pulse && (pipewire; wireplumber &) || true
```

---

## PHASE 3 — Runtime Session Hardening

### P3-1: Phantom Process Killer (Android's 32-child killer) [HIGH]
**Root cause:** Android's low-memory killer / "phantom process killer" detects child processes in the guest and SIGKILLs the entire proot session if battery optimization is not disabled. The script does `|| true` on `termux-setup-storage` (line 80), so the storage permission may not have been granted.

**Fix:** Add early verification + explicit battery check:
```bash
# Check battery optimization status
if command -v termux-battery-opt >/dev/null; then
    log_info "Checking battery optimization..."
fi
# More importantly — check Termux has root storage (critical for proot)
if [ ! -d "$HOME/storage" ]; then
    log_warn "Storage permission not granted. Running termux-setup-storage now..."
    termux-setup-storage || true
fi
```

### P3-2: DBUS_SESSION_BUS_ADDRESS not set (black screen in Termux:X11)
**File:** `.startwm` — need to verify this is passed into the guest
**Fix:** The inner login uses `env DISPLAY=:0 PULSE_SERVER=127.0.0.1 ...`, which doesn't carry DBUS. Add it to the login command:
```bash
proot-distro login archlinux --user omarchy --shared-tmp \
    env DISPLAY=:0 PULSE_SERVER=127.0.0.1 DBUS_SESSION_BUS_ADDRESS=/run/dbus/ dbus-launch /home/omarchy/.startwm
```

### P3-3: xdg-user-dirs not initialized
**File:** Guest bashrc — no `xdg-user-dirs-update` call
**Fix:** Add to the user profile creation section.

### P3-4: Missing TERM environment variable for TUI apps inside proot  
**Root cause:** TUI apps (vim, nano, btop) need `TERM=xterm-256color`. The `.startwm` sets it but the `omarchy-cli` session doesn't.

**Fix (in `install.sh` omarchy-cli launcher):**
```bash
cat << 'CLI_LAUNCHER' > "$HOME/omarchy-cli.sh"
#!/data/data/com.termux/files/usr/bin/bash
export PULSE_SERVER=127.0.0.1
export TERM=xterm-256color
proot-distro login archlinux --user omarchy --shared-tmp
CLI_LAUNCHER
```

---

## PHASE 4 — Testing & Verification

### P4-1: Create test harness (script that simulates the full install flow on a non-Android environment)
**Action:** Write `test/install.sh` that:
- Mocks Termux paths
- Tests all path-detection logic independently
- Injects fake rootfs, runs the inner heredoc in dry-run mode
- Captures errors

### P4-2: Real device smoke test (on actual Android termux)
Steps:
1. Fresh Termux install from F-Droid
2. Run installer
3. Verify all 10+ packages installed (not just banner success)
4. Verify fonts render correctly
5. Launch GUI mode, verify i3 desktop appears (not black screen)
6. Test audio
7. Test VirGL with `glxgears` (should show FPS > 30)

---

## PHASED EXECUTION PRIORITY

```
1. Phase 0 → Quick wins (P0-4, P0-5) — 2 simple edits, commit
2. Phase 1 → All critical/major installer bugs — largest effort (~2hr of editing + testing)
3. Phase 2 → Inner provisioning hardening
4. Phase 3 → Runtime session fixes
5. Phase 4 → Test harness + real device validation
```

Total estimated effort: **~6hr of focused work** (with real-device testing). No new files needed — all fixes are in `install.sh` and its embedded heredocs.

---

## NOT IN SCOPE (deferred)

- Package selection tuning (user preference, not a bug)
- Upstream omacom integration (it's just the theme — already cloned from omacom/omarchy)
- Custom window manager alternatives (i3 is the choice; user preference)
- AUR helpers (would add complexity; stick to official repos)

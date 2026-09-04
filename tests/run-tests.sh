#!/usr/bin/env bash
# ==============================================================================
# tests/run-tests.sh — sandbox test harness for install.sh
#
# Runs the FULL installer flow on any Linux box (no Android needed) inside a
# sandbox that fakes the Termux environment:
#
#   PREFIX=$SB/usr  HOME=$SB/home  PATH=$SB/usr/bin:$PATH
#
# `proot-distro` is stubbed: `install` lays down a skeleton rootfs,
# `login` re-executes the provisioning scripts against the sandbox rootfs with
# translated paths. `pacman` & friends are stubbed and logged.
#
# Usage:  bash tests/run-tests.sh
# ==============================================================================
set -u
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

INSTALLER=./install.sh
PASS=0; FAIL=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
head_(){ printf '\n\033[1m== %s\033[0m\n' "$*"; }

SB="$(mktemp -d /tmp/omarchy-test.XXXXXX)"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/usr/bin" "$SB/home" "$SB/log" "$SB/state"
ROOTFS="$SB/usr/var/lib/proot-distro/installed-rootfs/archlinux"
LEGACY_ROOTFS="$ROOTFS"
MODERN_ROOTFS="$SB/usr/var/lib/proot-distro/containers/archlinux/rootfs"

# ------------------------------------------------------------------------------
# Stub: pkg — fakes package install (creates dummy binaries), logs everything
# ------------------------------------------------------------------------------
cat > "$SB/usr/bin/pkg" <<STUB
#!/bin/bash
echo "pkg \$*" >> "$SB/log/pkg.log"
case "\$1" in
  install)
    shift; while [ \$# -gt 0 ]; do
      case "\$1" in
        -y|-o|*::*) ;;
        x11-repo) ;;
        *) [ -e "$SB/usr/bin/\$1" ] || { printf '#!/bin/bash\n' > "$SB/usr/bin/\$1"; chmod +x "$SB/usr/bin/\$1"; } ;;
      esac
      shift
    done ;;
esac
exit 0
STUB
chmod +x "$SB/usr/bin/pkg"

# ------------------------------------------------------------------------------
# Stub: proot-distro — install lays skeleton rootfs; login translates paths
# ------------------------------------------------------------------------------
cat > "$SB/usr/bin/proot-distro" <<STUB
#!/bin/bash
echo "proot-distro \$*" >> "$SB/log/pd.log"
case "\$1" in
  install)
    echo "PD-INSTALL-ARGS: \$*" >> "$SB/log/pd.log"
    mkdir -p "$LEGACY_ROOTFS"/{etc/pacman.d,etc/pulse,etc/sudoers.d,root,home/omarchy,opt,usr/local/bin,tmp}
    printf '[options]\nHoldPkg   = pacman glibc\n#DisableSandbox\n#DownloadUser = alpm\n' > "$LEGACY_ROOTFS/etc/pacman.conf"
    exit 0 ;;
  remove)
    rm -rf "$LEGACY_ROOTFS" "$SB/usr/var/lib/proot-distro/containers"
    exit 0 ;;
  login)
    shift  # drop "login"
    [ "\$1" = "archlinux" ] && shift
    USER_MODE=0
    while [ "\$#" -gt 0 ]; do
      case "\$1" in
        --user) USER_MODE=1; shift ;;
        --shared-tmp|--) shift ;;
        *) break ;;
      esac
    done
    # Remaining args: env K=V ... bash /path/script.sh — keep only the script
    RFSDIR="$LEGACY_ROOTFS"
    [ -d "$MODERN_ROOTFS" ] && RFSDIR="$MODERN_ROOTFS"
    SCRIPT=""
    while [ \$# -gt 0 ]; do
      case "\$1" in
        /*) SCRIPT="\$(echo "\$1" | sed -e "s|^/root/|\$RFSDIR/root/|" -e "s|^/home/omarchy|\$RFSDIR/home/omarchy|")" ;;
      esac
      shift
    done
    export OMARCHY_ROOTFS="\$RFSDIR"
    export HOME="\$RFSDIR/home/omarchy"
    echo "LOGIN user_mode=\$USER_MODE cmd=\$SCRIPT" >> "$SB/log/login.log"
    exec bash "\$SCRIPT"
    ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$SB/usr/bin/proot-distro"

# ------------------------------------------------------------------------------
# Stub: pacman + friends — success unless $SB/state/pacman_rc forces failure
# ------------------------------------------------------------------------------
cat > "$SB/usr/bin/pacman" <<STUB
#!/bin/bash
echo "pacman \$*" >> "$SB/log/pacman.log"
[ -f "$SB/state/pacman_rc" ] && exit "\$(cat "$SB/state/pacman_rc")"
exit 0
STUB
chmod +x "$SB/usr/bin/pacman"

for c in pacman-key fc-cache chpasswd; do
  { echo '#!/bin/bash'; echo "echo \"$c \$*\" >> \"$SB/log/$c.log\""; echo 'exit 0'; } > "$SB/usr/bin/$c"
  chmod +x "$SB/usr/bin/$c"
done

# useradd creates state marker + home dir; id honours it
cat > "$SB/usr/bin/useradd" <<STUB
#!/bin/bash
echo "useradd \$*" >> "$SB/log/useradd.log"
mkdir -p "$ROOTFS/home/omarchy"
touch "$SB/state/user_created"
exit 0
STUB
chmod +x "$SB/usr/bin/useradd"

cat > "$SB/usr/bin/id" <<STUB
#!/bin/bash
[ -f "$SB/state/user_created" ] && exit 0
exec /usr/bin/id "\$@"
STUB
chmod +x "$SB/usr/bin/id"

# git stub: clone creates the omarchy layout
cat > "$SB/usr/bin/git" <<STUB
#!/bin/bash
if [ "\$1" = "clone" ]; then
  TARGET="\${@: -1}"
  mkdir -p "\$TARGET/bin" "\$TARGET/config" "\$TARGET/themes/tokyo-night/backgrounds"
  printf '#!/bin/bash\necho omarchy\n' > "\$TARGET/bin/omarchy"
  chmod +x "\$TARGET/bin/omarchy"
  printf 'fakejpg' > "\$TARGET/themes/tokyo-night/backgrounds/5-oma-cityscape.jpg"
  exit 0
fi
exit 0
STUB
chmod +x "$SB/usr/bin/git"

# Misc stubs referenced by the installer
for c in termux-wake-lock termux-setup-storage termux-widget am pm killall; do
  printf '#!/bin/bash\nexit 0\n' > "$SB/usr/bin/$c"
  chmod +x "$SB/usr/bin/$c"
done

export PATH="$SB/usr/bin:$PATH"

run_installer() {
  TERMUX_VERSION="0.118-stub" PREFIX="$SB/usr" HOME="$SB/home" bash "$INSTALLER"
}

# ==============================================================================
head_ "1. Static checks"
# ==============================================================================
bash -n "$INSTALLER" && ok "install.sh: bash -n clean" || bad "install.sh: syntax error"

# Extract every generated script via its heredoc and syntax-check it standalone
extract() { # file start_marker end_marker out
  awk -v s="$2" -v e="$3" 'found && $0==e {exit} index($0,s) {found=1; next} found' "$1" > "$4"
}
extract "$INSTALLER" "cat > \"\$PROOT_ROOT/root/provision-root.sh\" << 'PROVISION_ROOT'" \
          PROVISION_ROOT "$SB/x-provision-root.sh"
extract "$INSTALLER" "cat > \"\$PROOT_ROOT/home/omarchy/provision-user.sh\" << 'PROVISION_USER'" \
          PROVISION_USER "$SB/x-provision-user.sh"
extract "$INSTALLER" "cat > \"\$HOME/start-omarchy.sh\" << 'GUI_LAUNCHER'" \
          GUI_LAUNCHER "$SB/x-gui-launcher.sh"
for f in "$SB"/x-*.sh; do
  [ -s "$f" ] || { bad "extraction empty: $f"; continue; }
  bash -n "$f" && ok "$(basename "$f"): extracted & bash -n clean" || bad "$(basename "$f"): syntax error"
done

# Inner heredocs must be self-contained (the bug that started this saga)
for inner in provision-root provision-user; do
  if grep -qE 'log_(err|warn|info|ok) ' "$SB/x-$inner.sh"; then
    bad "$inner references outer log_* functions"
  else ok "$inner is self-contained (no outer function refs)"
  fi
done
grep -q '_SOK' "$INSTALLER" && bad "zombie _SOK variable still present" || ok "no _SOK leftovers"
grep -qE 'proot-distro list[[:space:]]*\|' "$INSTALLER" \
  && bad "fragile 'proot-distro list' detection present" || ok "detection is disk-based"

# ==============================================================================
head_ "2. Full sandbox install (fresh device)"
# ==============================================================================
rm -rf "$ROOTFS" "$SB/home"
mkdir -p "$SB/home" "$SB/usr/var/lib/proot-distro/installed-rootfs"
if run_installer > "$SB/log/run1.out" 2>&1; then ok "installer exit 0"; else
  bad "installer failed — output tail:"; tail -25 "$SB/log/run1.out"; fi

[ -d "$ROOTFS/etc" ] && ok "rootfs bootstrapped" || bad "rootfs missing"
[ -x "$SB/home/start-omarchy.sh" ] && ok "start-omarchy.sh created+executable" || bad "start-omarchy.sh missing"
bash -n "$SB/home/start-omarchy.sh" 2>/dev/null && ok "generated launcher syntax clean" || bad "launcher syntax error"
[ -x "$SB/home/.shortcuts/Omarchy" ] && ok "Termux:Widget shortcut created" || bad "widget shortcut missing"
[ "$(grep -c 'omarchy-termux aliases' "$SB/home/.bashrc" 2>/dev/null || echo 0)" = "1" ] \
  && ok "Termux aliases added once" || bad "Termux aliases wrong count"

grep -q '1.1.1.1' "$ROOTFS/etc/resolv.conf" && ok "DNS injected into rootfs" || bad "DNS missing"
[ -f "$ROOTFS/etc/sudoers.d/10-wheel-nopasswd" ] && ok "passwordless sudo configured" || bad "sudoers missing"
[ -f "$ROOTFS/etc/pulse/client.conf" ] && ok "PulseAudio client configured" || bad "pulse client.conf missing"
[ -x "$ROOTFS/home/omarchy/.startwm" ] && ok "inner ~/.startwm executable" || bad "inner ~/.startwm missing"
[ -f "$ROOTFS/home/omarchy/.config/i3/config" ] && ok "inner i3 config present" || bad "i3 config missing"
[ "$(grep -c 'omarchy-termux profile v2' "$ROOTFS/home/omarchy/.bashrc" 2>/dev/null || echo 0)" = "1" ] \
  && ok "user profile appended exactly once" || bad "user profile wrong count"
[ -f "$ROOTFS/opt/omarchy/bin/omarchy" ] && ok "omarchy toolkit fetched" || bad "omarchy toolkit missing"
[ ! -f "$ROOTFS/root/provision-root.sh" ] && ok "provision scripts cleaned up" || bad "provision-root.sh left behind"
grep -q 'user_mode=1' "$SB/log/login.log" && ok "user phase ran via --user login (no su)" || bad "user phase never ran"
grep -q -- '-Syyu' "$SB/log/pacman.log" && ok "system upgrade invoked" || bad "no system upgrade"
grep -q 'i3-wm' "$SB/log/pacman.log" && ok "desktop packages installed" || bad "desktop packages missing"
grep -q 'PD-INSTALL-ARGS: install --name archlinux' "$SB/log/pd.log" \
  && ok "aarch64 installs via official ALARM tarball (--name)" || bad "aarch64 did not use tarball install"
grep -q 'archlinux-aarch64-pd-' "$SB/log/pd.log" \
  && ok "tarball URL passed to proot-distro" || bad "tarball URL missing from install args"
grep -qE '^DisableSandbox' "$ROOTFS/etc/pacman.conf" \
  && ok "pacman sandbox disabled (DisableSandbox)" || bad "DisableSandbox not set in pacman.conf"
[ -x "$SB/usr/bin/omarchy-gui" ] && ok "omarchy-gui executable on PATH" || bad "omarchy-gui not on PATH"
[ -x "$SB/usr/bin/omarchy-cli" ] && ok "omarchy-cli executable on PATH" || bad "omarchy-cli not on PATH"
[ -f "$ROOTFS/home/omarchy/.local/share/omarchy/wallpaper.jpg" ] \
  && ok "wallpaper installed from omarchy themes" || bad "wallpaper missing"
grep -q 'feh --bg-fill' "$ROOTFS/home/omarchy/.config/i3/config" \
  && ok "i3 sets wallpaper via feh" || bad "i3 wallpaper autostart missing"

# ==============================================================================
head_ "3. Idempotency (re-run on installed device)"
# ==============================================================================
if run_installer > "$SB/log/run2.out" 2>&1; then ok "re-run exit 0"; else
  bad "re-run failed — output tail:"; tail -25 "$SB/log/run2.out"; fi
grep -q 'Existing Arch Linux rootfs found' "$SB/log/run2.out" \
  && ok "re-run skipped rootfs download" || bad "re-run re-downloaded rootfs"
[ "$(grep -c 'omarchy-termux profile v2' "$ROOTFS/home/omarchy/.bashrc" 2>/dev/null || echo 0)" = "1" ] \
  && ok "no duplicate profile on re-run" || bad "profile duplicated on re-run"
[ "$(grep -c 'omarchy-termux aliases' "$SB/home/.bashrc" 2>/dev/null || echo 0)" = "1" ] \
  && ok "no duplicate aliases on re-run" || bad "aliases duplicated on re-run"

# ==============================================================================
head_ "3b. Modern proot-distro layout (containers/<name>/rootfs)"
# ==============================================================================
mkdir -p "$(dirname "$MODERN_ROOTFS")"
mv "$ROOTFS" "$MODERN_ROOTFS"
if run_installer > "$SB/log/run4.out" 2>&1; then ok "installer exit 0 on modern layout"; else
  bad "modern-layout run failed — output tail:"; tail -25 "$SB/log/run4.out"; fi
grep -q 'Existing Arch Linux rootfs found' "$SB/log/run4.out" \
  && ok "modern containers/ layout detected (no re-download)" || bad "modern layout not detected"
mv "$MODERN_ROOTFS" "$ROOTFS"

# ==============================================================================
head_ "4. Failure path (pacman broken → clean abort, script kept for debug)"
# ==============================================================================
echo 1 > "$SB/state/pacman_rc"
rm -f "$SB/log/run3.out"
if run_installer > "$SB/log/run3.out" 2>&1; then
  bad "installer should fail when pacman fails"
else ok "installer aborts cleanly on pacman failure"; fi
grep -q 'Root provisioning failed' "$SB/log/run3.out" \
  && ok "clear failure message shown" || bad "no clear failure message"
[ -f "$ROOTFS/root/provision-root.sh" ] \
  && ok "failed provision script kept for debugging" || bad "failed script discarded"
rm -f "$SB/state/pacman_rc"

# ==============================================================================
printf '\n\033[1mRESULT: %d passed, %d failed\033[0m\n\n' "$PASS" "$FAIL"
[ "$FAIL" = "0" ]

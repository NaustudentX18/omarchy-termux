#!/usr/bin/env bash
# ==============================================================================
# tests/run-tests.sh — sandbox test harness for install.sh (native-parity build)
#
# Runs the FULL like-for-like installer flow on any Linux box (no Android
# needed) inside a sandbox that fakes the Termux environment:
#
#   PREFIX=$SB/usr  HOME=$SB/home  PATH=$SB/usr/bin:$PATH
#
# Stubs: pkg (logs + fake binaries), proot-distro (fake rootfs deploy/login),
# curl (fake bundle download), getprop (fake Android), am (absent).
# A FAKE omarchy-android bundle is synthesized in the sandbox so the whole
# verify→extract→deploy→runtime→verify pipeline is exercised for real.
#
# Usage:  bash tests/run-tests.sh        (from repo root or tests/)
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
mkdir -p "$SB/usr/bin" "$SB/home" "$SB/log"
export PREFIX="$SB/usr"
export HOME="$SB/home"
export PATH="$SB/usr/bin:/usr/bin:/bin"
export OMARCHY_HOST_PREFIX="$SB/home/.local/share/omarchy-android"
export OMARCHY_STATE_DIR="$SB/home/.local/state/omarchy-android"

SHA_SED='s/^/sha256 /' # placeholder

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
        -*) shift; continue ;;
        proot-distro) mkdir -p "$SB/usr/bin"; touch "$SB/usr/bin/proot-distro" ;;
        termux-x11-nightly) touch "$SB/usr/bin/termux-x11" ;;
        weston) touch "$SB/usr/bin/weston" ;;
        pulseaudio) touch "$SB/usr/bin/pulseaudio" "$SB/usr/bin/pactl" ;;
        xorg-xwininfo) touch "$SB/usr/bin/xwininfo" ;;
        mesa-vulkan-icd-freedreno) ;;
        virglrenderer-android) touch "$SB/usr/bin/virgl_test_server_android" ;;
        *) touch "$SB/usr/bin/\$1" 2>/dev/null ;;
      esac
      chmod +x "$SB/usr/bin/\$1" 2>/dev/null
      shift
    done ;;
  update|upgrade) ;;
  *) ;;
esac
exit 0
STUB
chmod +x "$SB/usr/bin/pkg"

# Pre-seed commands pkg stubs don't create. We COPY executables (not
# symlink) so subsequent stub overwrites via `cat >` land in $SB, not on the
# real root-owned /usr/bin.
for c in git curl tar sha256sum am; do
  [ "$c" = am ] && continue
  real="$(command -v "$c")" || continue
  cp -f "$real" "$SB/usr/bin/$c"
  chmod +x "$SB/usr/bin/$c"
done

# Stub: getprop — pretend phantom-process restriction is DISABLED (dev opts on)
cat > "$SB/usr/bin/getprop" <<STUB
#!/bin/bash
case "\$1" in
  persist.sys.fflag.override.settings_enable_monitor_phantom_procs) echo "false" ;;
  *) echo "" ;;
esac
STUB
chmod +x "$SB/usr/bin/getprop"

# Fake Termux identity
export TERMUX_VERSION=0.118

# Stub: proot-distro — fake container deploy + login
cat > "$SB/usr/bin/proot-distro" <<STUB
#!/bin/bash
echo "proot-distro \$*" >> "$SB/log/proot.log"
case "\$1" in
  install)
    # parse --name <name> and the trailing tarball path
    NAME="omarchy-android"; TARBALL=""
    shift; while [ \$# -gt 0 ]; do
      case "\$1" in
        --name) NAME="\$2"; shift 2 ;;
        --architecture) shift 2 ;;
        *) TARBALL="\$1"; shift ;;
      esac
    done
    [ -f "\$TARBALL" ] || { echo "tarball missing: \$TARBALL" >&2; exit 1; }
    ROOT="$SB/usr/var/lib/proot-distro/containers/\$NAME/rootfs"
    mkdir -p "\$ROOT"
    tar -xJf "\$TARBALL" -C "\$ROOT" || exit 1
    exit 0 ;;
  login)
    NAME="\$2"; shift 2
    while [ \$# -gt 0 ] && [ "\$1" != "--" ]; do
      case "\$1" in
        --user|--bind|--isolated|--architecture) shift 2 ;;
        -*) shift ;;
        *) shift ;;
      esac
    done
    [ "\$1" = "--" ] && shift
    ROOT="$SB/usr/var/lib/proot-distro/containers/\$NAME/rootfs"
    # Emulate the installer smoke test: real proot chroots, this sandbox cannot.
    if [ "\$1" = "bash" ] && [ "\$2" = "--noprofile" ] && [ "\$3" = "--norc" ] && [ "\$4" = "-euc" ]; then
      miss=0
      for f in "\$ROOT/etc/omarchy-android-release" "\$ROOT/usr/share/omarchy/shell/shell.qml"; do
        [ -e "\$f" ] || miss=1
      done
      for f in "\$ROOT/opt/omarchy-android/hyprland/bin/Hyprland" "\$ROOT/usr/bin/quickshell" "\$ROOT/usr/bin/foot" "\$ROOT/usr/bin/nautilus"; do
        [ -x "\$f" ] || miss=1
      done
      [ -s "\$ROOT/home/omarchy/.local/state/omarchy/current/theme.name" ] || miss=1
      [ "\$miss" = 1 ] && exit 1
      exit 0
    fi
    export HOME="\$ROOT/home/omarchy"
    export PATH="\$ROOT/usr/local/bin:\$ROOT/usr/bin:/usr/bin:/bin"
    exec bash --noprofile --norc "\$@"
    exit 42 ;;
  list) echo "(omarchy-android installed)" ;;
  remove) exit 0 ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$SB/usr/bin/proot-distro"

# ------------------------------------------------------------------------------
# Build a FAKE omarchy-android release bundle in the sandbox
# ------------------------------------------------------------------------------
FAKE_REL="$SB/release"
mkdir -p "$FAKE_REL/host/bin" "$FAKE_REL/host/opt/weston/lib/libweston-14" \
         "$FAKE_REL/rootfs/run/user/1000"

# host artifacts
echo "FAKE-SO-$(date +%s)" > "$FAKE_REL/host/opt/weston/lib/libweston-14/x11-backend.so"
printf '#!/bin/sh\necho guard\n' > "$FAKE_REL/host/bin/omarchy-process-guard"
printf '#!/bin/sh\necho kbd\n'  > "$FAKE_REL/host/bin/omarchy-x11-keyboard"
chmod +x "$FAKE_REL/host/bin/"*

# guest artifacts (the "prebuilt" Omarchy)
mkdir -p "$FAKE_REL/rootfs/etc"
echo "v0.1.1-fake" > "$FAKE_REL/rootfs/etc/omarchy-android-release"
mkdir -p "$FAKE_REL/rootfs/opt/omarchy-android/hyprland/bin"
mkdir -p "$FAKE_REL/rootfs/usr/share/omarchy/shell"
mkdir -p "$FAKE_REL/rootfs/usr/bin"
mkdir -p "$FAKE_REL/rootfs/home/omarchy/.local/state/omarchy/current"
mkdir -p "$FAKE_REL/rootfs/home/omarchy/.config/hypr"
printf '#!/bin/sh\necho Hyprland 0.56.1\n' > "$FAKE_REL/rootfs/opt/omarchy-android/hyprland/bin/Hyprland"
chmod +x "$FAKE_REL/rootfs/opt/omarchy-android/hyprland/bin/Hyprland"
echo "shell-qml-stuff" > "$FAKE_REL/rootfs/usr/share/omarchy/shell/shell.qml"
for tool in quickshell foot nautilus chromium; do
  printf '#!/bin/sh\nexit 0\n' > "$FAKE_REL/rootfs/usr/bin/$tool"
  chmod +x "$FAKE_REL/rootfs/usr/bin/$tool"
done
echo "-- config" > "$FAKE_REL/rootfs/home/omarchy/.config/hypr/hyprland.lua"
echo "tokyo-night" > "$FAKE_REL/rootfs/home/omarchy/.local/state/omarchy/current/theme.name"

# rootfs tarball
tar -cJf "$FAKE_REL/rootfs.tar.xz" -C "$FAKE_REL/rootfs" .

# bundle: rootfs + host + SHA256SUMS
mkdir -p "$FAKE_REL/unpacked"
cp -r "$FAKE_REL/rootfs.tar.xz" "$FAKE_REL/unpacked/"
cp -r "$FAKE_REL/host" "$FAKE_REL/unpacked/"
( cd "$FAKE_REL/unpacked" && find . -type f ! -name SHA256SUMS -exec sha256sum {} \; | sort -k2 > SHA256SUMS )
BUNDLE_TAR="$SB/home/.cache-bundle/omarchy-android-aarch64-0.1.1.bundle.tar"
mkdir -p "$(dirname "$BUNDLE_TAR")"
tar -cf "$BUNDLE_TAR" -C "$FAKE_REL/unpacked" .

# Pre-seed the cache so curl is never hit: compute what install.sh expects
CACHE_PATH="$HOME/.cache/omarchy-termux/$FAKE_REL/../$(basename $BUNDLE_TAR)"
mkdir -p "$HOME/.cache/omarchy-termux"
cp "$BUNDLE_TAR" "$HOME/.cache/omarchy-termux/$(basename "$BUNDLE_TAR")"

# Real bundle sha won't match the pinned one — tests must override. The
# installer pins sha256 of the REAL release; in the sandbox we patch the
# expected constant via OMARCHY_BUNDLE + sed the installer? NO — better:
# tests extract the real sha of our fake bundle and swap it in a copy.
REAL_FAKE_SHA="$(sha256sum "$BUNDLE_TAR" | awk '{print $1}')"
TEST_INSTALLER="$SB/install-test.sh"
sed "s/^RELEASE_SHA256=.*/RELEASE_SHA256=\"$REAL_FAKE_SHA\"/" "$INSTALLER" > "$TEST_INSTALLER"
chmod +x "$TEST_INSTALLER"
INSTALLER="$TEST_INSTALLER"

# Stub: curl — must never download in tests (bundle is pre-seeded)
cat > "$SB/usr/bin/curl" <<STUB
#!/bin/bash
echo "curl \$*" >> "$SB/log/curl.log"
exit 1
STUB
chmod +x "$SB/usr/bin/curl"

# Fake runtime scripts repo (upstream clone): pre-seed the git clone target
mkdir -p "$HOME/.cache/omarchy-termux/omarchy-android-src/runtime/host"
for f in omarchy-android-start omarchy-android-stop omarchy-android-status omarchy-android-hyprctl; do
  printf '#!/usr/bin/env bash\necho "fake %s"\n' "\$f" > "$HOME/.cache/omarchy-termux/omarchy-android-src/runtime/host/$f"
  chmod +x "$HOME/.cache/omarchy-termux/omarchy-android-src/runtime/host/$f"
done
# and make git a no-op success so the clone step short-circuits on existing dir
cat > "$SB/usr/bin/git" <<STUB
#!/bin/bash
exit 0
STUB
chmod +x "$SB/usr/bin/git"

echo "sandbox ready: $SB"

# ==============================================================================
head_ "1. Static checks"
# ==============================================================================
bash -n "$INSTALLER" && ok "installer parses cleanly (bash -n)" || bad "bash -n failed"
grep -q "BlackFireAlex/omarchy-android" "$INSTALLER" \
  && ok "credits upstream omarchy-android" || bad "missing upstream credit"
grep -qE "RELEASE_SHA256=\"[0-9a-f]{64}\"" "$INSTALLER" \
  && ok "release sha256 pinned" || bad "release sha256 not pinned"
grep -q "sha256sum -c SHA256SUMS" "$INSTALLER" \
  && ok "bundle inner checksums verified" || bad "no SHA256SUMS verification"
grep -q "omarchy-gui" "$INSTALLER" && ok "omarchy-gui launcher wired" || bad "no omarchy-gui"
grep -q "doctor" "$INSTALLER" && ok "doctor subcommand present" || bad "no doctor"
grep -q "phantom" "$INSTALLER" && ok "phantom-process guidance present" || bad "no phantom guidance"

# ==============================================================================
head_ "2. Full sandbox install (fresh device)"
# ==============================================================================
OUT="$(bash "$INSTALLER" 2>&1)"; RC=$?
echo "$OUT" > "$SB/run1.out"
echo "$OUT" | sed 's/^/    | /'

[ $RC -eq 0 ] && ok "installer exits 0" || bad "installer exit=$RC"

echo "$OUT" | grep -q "Bundle verified (sha256 OK)" \
  && ok "bundle checksum verified" || bad "bundle sha verification missing from output"
echo "$OUT" | grep -q "SHA256SUMS" \
  && ok "inner checksum verification ran" || bad "inner checksums not verified"

ROOTFS="$SB/usr/var/lib/proot-distro/containers/omarchy-android/rootfs"
[ -d "$ROOTFS/usr/share/omarchy" ] \
  && ok "rootfs deployed with /usr/share/omarchy" || bad "rootfs not deployed"
[ -d "$ROOTFS/opt/omarchy-android/hyprland" ] \
  && ok "Hyprland stage deployed in guest" || bad "Hyprland stage missing"
[ -f "$ROOTFS/run/user/1000" ] || [ -d "$ROOTFS/run/user/1000" ] \
  && ok "guest /run/user/1000 bind-point created" || bad "no /run/user/1000"

[ -f "$OMARCHY_HOST_PREFIX/bin/omarchy-android" ] \
  && ok "omarchy-android dispatcher installed" || bad "dispatcher missing"
[ -f "$OMARCHY_HOST_PREFIX/config/runtime.conf" ] \
  && ok "runtime.conf written" || bad "runtime.conf missing"
[ -f "$OMARCHY_HOST_PREFIX/opt/weston/lib/libweston-14/x11-backend.so" ] \
  && ok "patched Weston backend installed" || bad "Weston backend missing"
grep -q "OMARCHY_GPU_MODE=virgl" "$OMARCHY_HOST_PREFIX/config/runtime.conf" \
  && ok "GPU auto-detect picked virgl (no /dev/kgsl)" || bad "GPU mode wrong"
grep -q "OMARCHY_CONTAINER=omarchy-android" "$OMARCHY_HOST_PREFIX/config/runtime.conf" \
  && ok "container name pinned in runtime.conf" || bad "container name wrong"

[ -f "$OMARCHY_HOST_PREFIX/bin/omarchy-android-start" ] \
  && ok "upstream start/stop/status vendored" || bad "session scripts not vendored"

[ -x "$PREFIX/bin/omarchy-gui" ] && ok "omarchy-gui on PATH" || bad "no omarchy-gui on PATH"
[ -x "$PREFIX/bin/omarchy-cli" ] && ok "omarchy-cli on PATH" || bad "no omarchy-cli on PATH"
[ -x "$PREFIX/bin/omarchy-stop" ] && ok "omarchy-stop on PATH" || bad "no omarchy-stop on PATH"
[ -x "$HOME/start-omarchy.sh" ] && ok "start-omarchy.sh created" || bad "no start-omarchy.sh"

echo "$OUT" | grep -q "Guest smoke test passed" \
  && ok "guest smoke test passed" || bad "guest smoke test failed/absent"
echo "$OUT" | grep -q "INSTALLATION COMPLETE" \
  && ok "success banner shown" || bad "no success banner"

[ ! -s "$SB/log/curl.log" ] \
  && ok "no network fetch happened (bundle came from cache)" || bad "curl was invoked"

# ==============================================================================
head_ "3. Idempotency (re-run on installed device)"
# ==============================================================================
OUT2="$(bash "$INSTALLER" 2>&1)"; RC2=$?
[ $RC2 -eq 0 ] && ok "re-run exits 0" || bad "re-run exit=$RC2"
echo "$OUT2" | grep -q "already installed — skipping rootfs deploy" \
  && ok "re-run skips rootfs deploy" || bad "re-run re-deployed rootfs"
# Second run must not have re-extracted a fresh unpack dir over a live container destructively —
# but extraction is fine; the guard is the container check. Verify container intact:
[ -d "$ROOTFS/usr/share/omarchy" ] && ok "container intact after re-run" || bad "container damaged"

# ==============================================================================
head_ "4. Tamper detection (bad bundle sha → clean abort)"
# ==============================================================================
TAMPER_INSTALLER="$SB/install-tamper.sh"
sed "s/^RELEASE_SHA256=.*/RELEASE_SHA256=\"$(printf 'a%.0s' {1..64})\"/" "$INSTALLER" > "$TAMPER_INSTALLER"
chmod +x "$TAMPER_INSTALLER"
OUT3="$(bash "$TAMPER_INSTALLER" 2>&1)"; RC3=$?
[ $RC3 -ne 0 ] && ok "tampered bundle rejected (non-zero exit)" || bad "tampered bundle accepted!"
echo "$OUT3" | grep -q "checksum mismatch" \
  && ok "clear checksum-mismatch error" || bad "no checksum error surfaced"
# Re-seed the cache (tamper flow deliberately deleted it), then recover.
cp "$BUNDLE_TAR" "$HOME/.cache/omarchy-termux/$(basename "$BUNDLE_TAR")"
OUT4="$(bash "$INSTALLER" 2>&1)"; RC4=$?
[ $RC4 -eq 0 ] && ok "recovery re-run succeeds after tamper fix" || bad "recovery failed exit=$RC4"

# ==============================================================================
head_ "5. Unsafe tar path rejection"
# ==============================================================================
# Create a bundle with an absolute path member and confirm refusal
EVIL_DIR="$SB/evil"; mkdir -p "$EVIL_DIR"
touch "$EVIL_DIR/pwned"
( cd "$EVIL_DIR" && tar -cf "$SB/evil.tar" ./pwned /tmp-absolute 2>/dev/null ) \
  || ( cd "$EVIL_DIR" && tar -cf "$SB/evil.tar" --transform 's,^pwned,/pwned,' ./pwned 2>/dev/null )
if [ -s "$SB/evil.tar" ]; then
  EVIL_SHA="$(sha256sum "$SB/evil.tar" | awk '{print $1}')"
  EVIL_INSTALLER="$SB/install-evil.sh"
  cp "$INSTALLER" "$EVIL_INSTALLER"
  # point the cache at the evil bundle: easiest is OMARCHY_BUNDLE env
  OUT5="$(OMARCHY_BUNDLE="$SB/evil.tar" RELEASE_SHA256_OVERRIDE=1 bash -c "
    sed 's/^RELEASE_SHA256=.*/RELEASE_SHA256=\"$EVIL_SHA\"/' '$EVIL_INSTALLER' > '$SB/install-evil2.sh'
    chmod +x '$SB/install-evil2.sh'
    bash '$SB/install-evil2.sh'" 2>&1)"; RC5=$?
  [ $RC5 -ne 0 ] && ok "bundle with unsafe paths refused" || bad "unsafe paths extracted!"
else
  bad "could not build evil bundle for test"
fi

# ==============================================================================
head_ "6. Missing required host command → clear abort"
# ==============================================================================
# Replace pkg with a strict installer that ONLY answers "yes" for non-weston
# packages, so weston stays missing after reinstall.
cat > "$SB/usr/bin/pkg" <<STUB
#!/bin/bash
echo "pkg strict \$*" >> "$SB/log/pkg.log"
case "\$1" in
  install)
    shift; while [ \$# -gt 0 ]; do
      case "\$1" in
        weston|termux-x11|proot-distro) log_warn "stub pkg declines: \$1"; shift ;;
        -*) shift ;;
        *) case "\$1" in
            proot-distro) touch "$SB/usr/bin/proot-distro"; chmod +x "$SB/usr/bin/proot-distro" ;;
            termux-x11-nightly) touch "$SB/usr/bin/termux-x11"; chmod +x "$SB/usr/bin/termux-x11" ;;
            pulseaudio) touch "$SB/usr/bin/pulseaudio" "$SB/usr/bin/pactl"; chmod +x "$SB/usr/bin/pulseaudio" "$SB/usr/bin/pactl" ;;
            xorg-xwininfo) touch "$SB/usr/bin/xwininfo"; chmod +x "$SB/usr/bin/xwininfo" ;;
            mesa-vulkan-icd-freedreno) ;;
            virglrenderer-android) touch "$SB/usr/bin/virgl_test_server_android"; chmod +x "$SB/usr/bin/virgl_test_server_android" ;;
            *) touch "$SB/usr/bin/\$1"; chmod +x "$SB/usr/bin/\$1" 2>/dev/null ;;
          esac
          shift
        ;;
      esac
    done ;;
  update|upgrade) ;;
esac
exit 0
STUB
chmod +x "$SB/usr/bin/pkg"
rm -f "$SB/usr/bin/weston"
OUT6="$(bash "$INSTALLER" 2>&1)"; RC6=$?
[ $RC6 -ne 0 ] && ok "missing weston aborts with fix hint" || bad "missing weston not caught"
echo "$OUT6" | grep -q "pkg install" \
  && ok "fix hint shown" || bad "no fix hint"
touch "$SB/usr/bin/weston" && chmod +x "$SB/usr/bin/weston"

# ==============================================================================
head_ "7. Doctor works and reports sandbox state"
# ==============================================================================
OUT7="$(bash "$INSTALLER" doctor 2>&1)"; RC7=$?
echo "$OUT7" | sed 's/^/    | /'
[ $RC7 -eq 0 ] && ok "doctor exits 0 in healthy sandbox" || bad "doctor exit=$RC7"
echo "$OUT7" | grep -q "Phantom processes" \
  && ok "doctor checks phantom state" || bad "doctor lacks phantom check"
echo "$OUT7" | grep -q "omarchy-termux" \
  && ok "doctor reports install state" || bad "doctor lacks install-state check"

# ==============================================================================
head_ "RESULT"
# ==============================================================================
printf '\nRESULT: %d passed, %d failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
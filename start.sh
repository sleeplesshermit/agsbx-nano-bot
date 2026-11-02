#!/bin/bash
# agsbx-nano-bot — trimmed argosbx runner for ~128 MB containers.
# Runs ONLY xray (VMess-WS) + cloudflared (fixed Argo tunnel) via the
# argosbx installer. No SSH, no TTYD, no extra cores, and — unlike
# agsbx-min-bot — no second Node process for the placeholder web
# server (index.js serves $PORT in-process).
#
# Daemon binaries: seeded from ./vendor/ when present (they are
# gitignored — fetched per README); when absent, the argosbx installer
# downloads them itself.
#
# Required env (set in the provider panel, never in files):
#   UUID   - xray UUID
#   AGN    - tunnel hostname, e.g. cf-tunnel-<name>.example.org
#   AGK    - Cloudflare tunnel token for AGN's tunnel (~184-240 chars)
# Optional env:
#   VMPT   - xray VMess-WS port inside the container (default 8001)
#   PORT   - provider-assigned web port (served by index.js)

cd "$(dirname "$0")" || exit 1
mkdir -p logs bin

for v in UUID AGN AGK; do
  if [ -z "${!v:-}" ]; then
    echo "[agsbx-nano] FATAL: required env $v is not set — set it in the provider panel and restart"
    sleep 60
    exit 1
  fi
done
VMPT="${VMPT:-8001}"

# Token sanity: log LENGTH ONLY (never the value). A Cloudflare tunnel
# token is ~184-240 chars; anything else means the copy was mangled in
# transit and cloudflared will fail with "token is not valid".
echo "[agsbx-nano] AGK length: ${#AGK} (tokens run ~184-240 chars)"

# Some images ship neither curl nor wget, but the argosbx installer's
# download steps need one of them. tools/ bundles a zero-dependency
# Node shim that answers to both names; install whichever is missing
# into bin/ and put bin/ on PATH.
for toolname in curl wget; do
  if ! command -v "$toolname" >/dev/null 2>&1 && [ -f "tools/$toolname" ]; then
    cp -f "tools/$toolname" "bin/$toolname" && chmod +x "bin/$toolname"
    echo "[agsbx-nano] no system $toolname — using bundled Node shim"
  fi
done
case ":$PATH:" in
  *":$PWD/bin:"*) ;;
  *) export PATH="$PWD/bin:$PATH" ;;
esac

# Installer source: bundled copy first, previously fetched copy second,
# download (GitHub, jsDelivr fallback) only when neither exists.
INSTALLER=""
if [ -s vendor/argosbx.sh ]; then
  INSTALLER=vendor/argosbx.sh
elif [ -s bin/argosbx.sh ]; then
  INSTALLER=bin/argosbx.sh
else
  echo "[agsbx-nano] downloading argosbx installer"
  if curl -fsSL https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh -o bin/argosbx.sh \
    || curl -fsSL https://cdn.jsdelivr.net/gh/yonggekkk/argosbx@main/argosbx.sh -o bin/argosbx.sh; then
    INSTALLER=bin/argosbx.sh
  else
    echo "[agsbx-nano] installer download FAILED"; sleep 30; exit 1
  fi
fi

# A binary counts as valid only if it exists, is non-empty, and answers
# a version probe. A truncated download fails the probe — and is worse
# than a missing file, because the installer otherwise keeps it and the
# daemon then cannot run.
bin_valid() {
  local f="$1"
  [ -s "$f" ] || return 1
  case "$(basename "$f")" in
    xray) timeout 10 "$f" version >/dev/null 2>&1 ;;
    cloudflared) timeout 10 "$f" --version >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

# Seed the install dir from ./vendor/: replace any missing/broken
# daemon binary with the bundled copy; drop a broken one that has no
# bundled replacement so the installer downloads it fresh.
seed_binaries() {
  local d f name
  for d in "$HOME/agsbx" /agsbx; do
    [ -d "$d" ] || continue
    for name in xray cloudflared; do
      f="$d/$name"
      if ! bin_valid "$f"; then
        if bin_valid "vendor/$name"; then
          cp -f "vendor/$name" "$f" && chmod +x "$f"
          echo "[agsbx-nano] seeded $name from vendor bundle"
        elif [ -f "$f" ]; then
          rm -f "$f"
        fi
      fi
    done
  done
  # Fresh room: the install dir may not exist yet — create and seed it.
  if [ ! -d "$HOME/agsbx" ] && [ ! -d /agsbx ]; then
    if bin_valid vendor/xray || bin_valid vendor/cloudflared; then
      mkdir -p "$HOME/agsbx"
      for name in xray cloudflared; do
        if bin_valid "vendor/$name"; then
          cp -f "vendor/$name" "$HOME/agsbx/$name" && chmod +x "$HOME/agsbx/$name"
          echo "[agsbx-nano] seeded $name from vendor bundle"
        fi
      done
    fi
  fi
}

run_installer() {
  seed_binaries
  echo "[agsbx-nano] running argosbx installer (vmpt=$VMPT)"
  vmpt="$VMPT" uuid="$UUID" argo="vmpt" agn="$AGN" agk="$AGK" bash "$INSTALLER" >> logs/argosbx.log 2>&1
  tail -n 5 logs/argosbx.log
}

run_installer

# Process check that does NOT depend on procps/pgrep: on Galaxy the
# pgrep-based check silently failed (the daemons were healthy — the
# tunnel stayed connected — yet the check reported both gone and
# re-ran the installer every 60 s; found on the first Galaxy deploy,
# 2026-11-02). Pure-bash scan of /proc cmdlines instead: match the
# daemon's invocation form ("/<name> " or a cmdline starting with
# "<name> "). No self-match: neither this shell's ("bash start.sh")
# nor tr's cmdline contains those patterns.
proc_alive() {
  local name="$1" p cmd
  for p in /proc/[0-9]*/cmdline; do
    [ -r "$p" ] || continue
    cmd=$(tr '\0' ' ' < "$p" 2>/dev/null) || continue
    case "$cmd" in
      *"/$name "*|"$name "*) return 0 ;;
    esac
  done
  return 1
}

# Supervise: the installer daemonizes xray + cloudflared. If BOTH
# disappear (crash, OOM, platform cleanup), re-run the installer.
while true; do
  sleep 60
  if ! proc_alive xray && ! proc_alive cloudflared; then
    echo "[agsbx-nano] xray and cloudflared both gone — re-running installer"
    run_installer
  fi
done

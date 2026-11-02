# agsbx-nano-bot

Trimmed variant of [agsbx-min-bot](https://github.com/sleeplesshermit/agsbx-min-bot)
for **~128 MB containers** — built for the Galaxy Cloud Sandbox ("Nano",
128 MB / 0.1 ECU) free tier. Runs only xray (VMess-WS) + cloudflared
(fixed Argo tunnel) via the argosbx installer. No SSH, no TTYD.

## What was trimmed vs agsbx-min-bot

- **One Node process instead of two.** agsbx-min-bot spawns a separate
  `server.js` Node process just to answer `ok` on `$PORT`. A V8 instance
  costs ~30–40 MB — unaffordable at 128 MB. Here the supervisor
  (`index.js`) serves the placeholder in-process; `server.js` is gone.
- **`npm start` script added** (`node index.js`) for PaaS presets that
  require it.
- **Memory env knobs** (see `env.example`): `NODE_OPTIONS=--max-old-space-size=32`
  (note: `--optimize-for-size` is rejected in NODE_OPTIONS — Node won't
  start), `GOMEMLIMIT=48MiB` for cloudflared's Go GC, `MALLOC_ARENA_MAX=2`.

Steady-state target: ~85–110 MB (Node ~35–45 + xray ~15–20 +
cloudflared ~30–40 + bash ~4).

## Changelog

- **v1.0.1 (2026-11-02)** — supervision loop no longer uses `pgrep`:
  on Galaxy it silently reported both daemons dead every 60 s while
  they were in fact healthy (the tunnel never dropped), re-running
  the installer in a loop. Replaced with a dependency-free /proc
  cmdline scan. Also added a no-op `build` script (`true`) because
  Galaxy's default build command is `npm run build` and a missing
  script fails the first deploy.
- **v1.0.0** — initial trimmed release. Note: on Galaxy the free
  container actually provisioned as **g.nano = 384 MB RAM / 0.3 gCPU**
  (the docs' 128 MB figure is outdated), so the trims are headroom,
  not survival.

## Deploy (Galaxy)

1. Galaxy dashboard → Create New → Deploy New App → **Node.js**.
2. Connect GitHub, pick this repo, branch `main`.
3. Plan **Sandbox**, container **Nano** (the only free option),
   region is fixed to us-east-1 on the free tier.
4. Env vars (panel UI): `UUID`, `AGN`, `AGK`, `VMPT=8001`, plus the
   three memory knobs from `env.example`. Do **not** set `PORT` —
   Galaxy assigns it.
5. Health check path: `/` (the placeholder answers `ok` on any path).
6. Deploy. First boot downloads the xray + cloudflared binaries via
   the argosbx installer (they are gitignored, see below), so it takes
   a little longer; later boots reuse the container's copies until the
   container is recreated.

## Notes

- `vendor/xray` and `vendor/cloudflared` are **not in git** (~73 MB of
  binaries). If you drop them into `vendor/` locally before deploying
  from a filesystem upload, `start.sh` seeds them at boot and no
  download is needed; from a plain git deploy, the installer fetches
  them itself.
- Config is env-only. The AGK token is ~184–240 chars — after pasting,
  check the boot log line `AGK length: NNN`; a mangled token fails
  silently in cloudflared.
- Node info (subscription links) is written by the installer to
  `~/agsbx/jhsub.txt` inside the container.

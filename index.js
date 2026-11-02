// agsbx-nano-bot launcher — trimmed variant of agsbx-min-bot for
// ~128 MB containers (built for Galaxy Sandbox "Nano").
//
// Two jobs in ONE Node process (the trim: agsbx-min-bot runs a second
// Node process just for the placeholder web server; a V8 instance costs
// ~30-40 MB, which a 128 MB container cannot spare):
//   1. Placeholder HTTP server on $PORT answering "ok" — something for
//      platform health checks / port expectations to hit. The tunnel
//      itself is outbound-only and does not need this server.
//   2. Supervise start.sh (xray + cloudflared via the argosbx
//      installer); restart it if it exits.
// Zero dependencies, deliberately tiny.
const { spawn } = require('child_process');
const http = require('http');

// --- placeholder web server (in-process) ---
const port = parseInt(process.env.PORT || '3000', 10);
const srv = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('ok\n');
});
srv.on('error', (e) => {
  // Not fatal — the tunnel processes are what matter.
  console.log(`[agsbx-nano] web placeholder not started (${e.code || e.message})`);
});
srv.listen(port, '0.0.0.0', () => console.log(`[agsbx-nano] web placeholder on :${port}`));

// --- supervisor for start.sh ---
let child = null;
let stopping = false;

function start() {
  child = spawn('bash', ['start.sh'], { stdio: 'inherit' });
  child.on('exit', (code, signal) => {
    console.log(`[agsbx-nano] start.sh exited (code=${code}, signal=${signal})`);
    if (!stopping) {
      console.log('[agsbx-nano] restarting in 5s');
      setTimeout(start, 5000);
    }
  });
  child.on('error', (err) => {
    console.error('[agsbx-nano] failed to spawn start.sh:', err.message);
    if (!stopping) setTimeout(start, 5000);
  });
}

process.on('SIGTERM', () => { stopping = true; if (child) child.kill('SIGTERM'); });
process.on('SIGINT', () => { stopping = true; if (child) child.kill('SIGINT'); });

start();

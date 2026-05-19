'use strict';

const path = require('node:path');

const { createGatewayServer } = require('./server');

const port = Number.parseInt(process.env.GATEWAY_PORT || '4096', 10);
const host = process.env.GATEWAY_HOST || '127.0.0.1';
const dataFile =
  process.env.GATEWAY_DATA_FILE ||
  path.join(__dirname, '..', '.data', 'store.json');

const MAX_RESTART_DELAY_MS = 30_000;
const MIN_RESTART_DELAY_MS = 1_000;
let restartDelay = MIN_RESTART_DELAY_MS;
let lastStartedAt = 0;

async function main() {
  lastStartedAt = Date.now();
  const server = await createGatewayServer({ dataFile });
  let closing = false;
  const shutdown = () => {
    if (closing) return;
    closing = true;
    server.closeAllRuns?.();
    server.close(() => {
      process.exitCode = 0;
    });
  };
  process.once('SIGINT', shutdown);
  process.once('SIGTERM', shutdown);
  server.listen(port, host, () => {
    const address = server.address();
    const actualPort =
      typeof address === 'object' && address !== null ? address.port : port;
    console.log(`remote-multi-agent gateway listening on http://${host}:${actualPort}`);
    // Reset backoff once successfully listening.
    restartDelay = MIN_RESTART_DELAY_MS;
  });
}

function scheduleRestart(reason) {
  console.error(`[keepalive] ${reason} — restarting in ${restartDelay}ms...`);
  setTimeout(() => {
    // Remove stale listeners from previous attempt.
    process.removeAllListeners('SIGINT');
    process.removeAllListeners('SIGTERM');
    main().catch((error) => {
      scheduleRestart(`main() failed: ${error.message}`);
    });
  }, restartDelay);
  // Exponential backoff, capped.
  restartDelay = Math.min(restartDelay * 2, MAX_RESTART_DELAY_MS);
}

// Prevent process crash on unexpected errors.
process.on('uncaughtException', (error) => {
  console.error('[uncaughtException]', error);
  scheduleRestart(`uncaughtException: ${error.message}`);
});

process.on('unhandledRejection', (reason) => {
  console.error('[unhandledRejection]', reason);
  // Don't restart for unhandled rejections — just log.
});

main().catch((error) => {
  scheduleRestart(`initial start failed: ${error.message}`);
});

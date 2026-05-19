'use strict';

const path = require('node:path');

const { createGatewayServer } = require('./server');

const port = Number.parseInt(process.env.GATEWAY_PORT || '4096', 10);
const host = process.env.GATEWAY_HOST || '127.0.0.1';
const dataFile =
  process.env.GATEWAY_DATA_FILE ||
  path.join(__dirname, '..', '.data', 'store.json');

async function main() {
  const server = await createGatewayServer({ dataFile });
  server.listen(port, host, () => {
    const address = server.address();
    const actualPort =
      typeof address === 'object' && address !== null ? address.port : port;
    console.log(`remote-multi-agent gateway listening on http://${host}:${actualPort}`);
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

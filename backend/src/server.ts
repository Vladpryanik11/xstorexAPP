import { existsSync } from 'node:fs';
import { buildApp } from './app.js';
import { loadConfig } from './config.js';

if (existsSync('.env')) process.loadEnvFile('.env');

const config = loadConfig();
const app = await buildApp(config);

if (!config.adminToken) app.log.warn('ADMIN_TOKEN is not set: /admin/v1 answers 503');
if (!process.env.GRANT_SECRET) app.log.warn('GRANT_SECRET is not set: install links are invalidated on restart');
if (!config.publicBaseUrl.startsWith('https://')) {
  app.log.warn({ publicBaseUrl: config.publicBaseUrl }, 'PUBLIC_BASE_URL is not HTTPS: OTA install will not work on a device');
}

let closing = false;
async function shutdown(signal: string) {
  if (closing) return;
  closing = true;
  app.log.info({ signal }, 'shutting down');
  try {
    await app.close();
    process.exit(0);
  } catch (err) {
    app.log.error({ err }, 'shutdown failed');
    process.exit(1);
  }
}
process.on('SIGINT', () => void shutdown('SIGINT'));
process.on('SIGTERM', () => void shutdown('SIGTERM'));

try {
  await app.listen({ port: config.port, host: config.host });
} catch (err) {
  app.log.error({ err }, 'failed to start');
  process.exit(1);
}

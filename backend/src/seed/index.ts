import { existsSync } from 'node:fs';
import { createContext } from '../app.js';
import { loadConfig } from '../config.js';
import { openDatabase } from '../db/index.js';
import { seedDemo } from './run.js';

if (existsSync('.env')) process.loadEnvFile('.env');

const config = loadConfig();
const started = Date.now();
console.log(`Seeding ${config.databaseUrl ? 'PostgreSQL (DATABASE_URL)' : `PGlite at ${config.pgliteDir}`}`);
console.log(`Storage: ${config.storageDir}`);
console.log('Stop `npm run dev` first: PGlite allows only one process per data directory.\n');

const database = await openDatabase({ databaseUrl: config.databaseUrl, pgliteDir: config.pgliteDir });
try {
  const ctx = createContext(config, database);
  const result = await seedDemo(ctx, { images: true, log: (line) => console.log(`  • ${line}`) });
  ctx.bus.stop();
  const base = config.publicBaseUrl;
  console.log(`\nDone in ${((Date.now() - started) / 1000).toFixed(1)} s, catalog revision ${result.revision}.\n`);
  console.log('Activation codes (plan "month"):');
  console.log(`  ${result.demoCode}   (dev code, 30 days)`);
  for (const code of result.codes) console.log(`  ${code}`);
  console.log('\nDev token (account acc_dev, plan "year") — for curl only, keep it local:');
  console.log(`  ${result.devToken}`);
  console.log('\nTry:');
  console.log(`  curl -H "Authorization: Bearer ${result.devToken}" "${base}/api/v1/groupings?tab=today"`);
  console.log(
    `  curl -X POST -H "Content-Type: application/json" -d '{"activation_code":"${result.demoCode}","device":{"install_id":"6f1c2f8e-6a52-4c39-9a51-3d0f1f0c2b7a"}}' ${base}/api/v1/app/activate`,
  );
} finally {
  await database.close();
}

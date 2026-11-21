import { copyFile, mkdir, mkdtemp, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { buildApp } from '../dist/app.js';
import { loadConfig } from '../dist/config.js';
import { APPS, CATEGORIES, STOREFRONT, appId } from '../dist/seed/data.js';
import { seedDemo } from '../dist/seed/run.js';

const [destination] = process.argv.slice(2);
if (!destination) throw new Error('Укажите каталог для ресурсов предпросмотра');

const scratch = await mkdtemp(path.join(tmpdir(), 'xstore-preview-'));
try {
  const config = loadConfig({ PUBLIC_BASE_URL: 'https://xstore-preview.invalid', LOG_LEVEL: 'silent' }, scratch);
  const app = await buildApp({ ...config, pgliteDir: null });
  try {
    const { devToken } = await seedDemo(app.ctx, { images: true, extraCodes: 0 });
    const fixtures = {};
    for (const language of ['en', 'ru']) {
      const routes = {};
      const fetchFixture = async (url, key = url) => {
        const response = await app.inject({
          url,
          headers: { 'accept-language': language, authorization: `Bearer ${devToken}` },
        });
        if (response.statusCode !== 200) throw new Error(`${url}: HTTP ${response.statusCode}`);
        routes[key] = response.json();
      };
      for (const [tab, rooms] of Object.entries(STOREFRONT)) {
        await fetchFixture(`/api/v1/groupings?tab=${tab}`);
        for (const room of rooms.filter(({ style }) => style !== 'chips')) {
          const route = `/api/v1/groupings/${room.id}`;
          await fetchFixture(`${route}?limit=50`, route);
        }
      }
      for (const category of CATEGORIES) {
        const route = `/api/v1/catalog/categories/${category.id}`;
        await fetchFixture(`${route}?limit=50`, route);
      }
      for (const { slug } of APPS) {
        const route = `/api/v1/catalog/apps/${appId(slug)}`;
        await fetchFixture(route);
        await fetchFixture(`${route}/versions`);
      }
      await fetchFixture('/api/v1/client/store-state');
      fixtures[language] = routes;
    }

    await mkdir(destination, { recursive: true });
    const staticDir = path.join(config.storageDir, 'static');
    for (const folder of ['icons', 'screens', 'hero']) {
      const dir = path.join(staticDir, folder);
      for (const name of await readdir(dir)) {
        await copyFile(path.join(dir, name), path.join(destination, `preview-${folder}-${name}`));
      }
    }
    await writeFile(path.join(destination, 'VisualPreview.json'), JSON.stringify(fixtures));
    console.log(`Ресурсы предпросмотра собраны для ${APPS.length} приложений`);
  } finally {
    await app.close();
  }
} finally {
  await rm(scratch, { recursive: true, force: true });
}

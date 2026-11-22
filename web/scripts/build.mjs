import { cp, mkdir, rename, rm, mkdtemp } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const stage = await mkdtemp(join(root, '.stage-'));
try {
  for (const file of ['server.mjs', 'auth.mjs', 'academy.mjs', 'admin.mjs', 'upstream.mjs', 'config.mjs', 'public']) {
    await cp(join(root, file), join(stage, file), { recursive: true });
  }
  await mkdir(join(root, 'dist'), { recursive: true });
  await rm(join(root, 'dist'), { recursive: true });
  await rename(stage, join(root, 'dist'));
} finally {
  await rm(stage, { force: true, recursive: true });
}

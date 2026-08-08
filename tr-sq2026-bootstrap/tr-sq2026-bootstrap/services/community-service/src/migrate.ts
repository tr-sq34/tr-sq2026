import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { createDatabasePool } from './database.js';

const pool = createDatabasePool();

const migrationsDirectory = path.resolve(process.cwd(), 'migrations');
const files = (await readdir(migrationsDirectory))
  .filter((file) => /^\d+_.+\.sql$/.test(file))
  .sort();

const client = await pool.connect();
try {
  await client.query('BEGIN');
  await client.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      filename TEXT PRIMARY KEY,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `);
  const applied = await client.query<{ filename: string }>(
    'SELECT filename FROM schema_migrations',
  );
  const appliedFiles = new Set(applied.rows.map((row) => row.filename));

  for (const file of files) {
    if (appliedFiles.has(file)) continue;
    const sql = await readFile(path.join(migrationsDirectory, file), 'utf8');
    await client.query(sql);
    await client.query('INSERT INTO schema_migrations(filename) VALUES($1)', [file]);
  }
  await client.query('COMMIT');
} catch (error) {
  await client.query('ROLLBACK');
  throw error;
} finally {
  client.release();
  await pool.end();
}

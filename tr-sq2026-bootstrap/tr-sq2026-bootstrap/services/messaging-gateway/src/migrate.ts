import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import pg from 'pg';

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error('DATABASE_URL is required');

const pool = new pg.Pool({ connectionString: databaseUrl });
const directory = new URL('../migrations/', import.meta.url);

try {
  await pool.query(`CREATE TABLE IF NOT EXISTS schema_migrations (name TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())`);
  const names = (await readdir(directory)).filter((name) => name.endsWith('.sql')).sort();
  for (const name of names) {
    const exists = await pool.query('SELECT 1 FROM schema_migrations WHERE name = $1', [name]);
    if (exists.rowCount) continue;
    const sql = await readFile(join(directory.pathname, name), 'utf8');
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(sql);
      await client.query('INSERT INTO schema_migrations(name) VALUES($1)', [name]);
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }
} finally {
  await pool.end();
}

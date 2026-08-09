import pg from 'pg';

/**
 * Azure Database for PostgreSQL presents a certificate chained to a public root,
 * so Node's bundled trust store verifies it without a custom CA bundle. Never
 * downgrade this to `rejectUnauthorized: false`: the connection string carries
 * the database credential.
 */
export function createDatabasePool(max = 20): pg.Pool {
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) throw new Error('Missing required environment variable: DATABASE_URL');
  return new pg.Pool({
    connectionString,
    max,
    ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: true } : undefined,
  });
}

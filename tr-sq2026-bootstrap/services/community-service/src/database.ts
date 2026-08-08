import pg from 'pg';
import { readFileSync } from 'node:fs';

const required = (key: string) => {
  const value = process.env[key];
  if (!value) throw new Error(`Missing ${key}`);
  return value;
};

export function createDatabasePool(): pg.Pool {
  const ssl = process.env.NODE_ENV === 'production'
    ? {
        // Verify the RDS server certificate with AWS' published RDS trust
        // store. Never downgrade this to rejectUnauthorized: false: that
        // would expose the database credential to a network attacker.
        rejectUnauthorized: true,
        ca: readFileSync(new URL('../certs/rds-global-bundle.pem', import.meta.url), 'utf8'),
      }
    : undefined;

  if (process.env.DATABASE_URL) {
    return new pg.Pool({ connectionString: process.env.DATABASE_URL, max: 20, ssl });
  }
  return new pg.Pool({
    host: required('DATABASE_HOST'),
    port: Number(process.env.DATABASE_PORT ?? 5432),
    database: required('DATABASE_NAME'),
    user: required('DATABASE_USER'),
    password: required('DATABASE_PASSWORD'),
    max: 20,
    ssl,
  });
}

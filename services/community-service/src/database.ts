import pg from 'pg';

const required = (key: string) => {
  const value = process.env[key];
  if (!value) throw new Error(`Missing ${key}`);
  return value;
};

export function createDatabasePool(): pg.Pool {
  if (process.env.DATABASE_URL) {
    return new pg.Pool({ connectionString: process.env.DATABASE_URL, max: 20, ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: true } : undefined });
  }
  return new pg.Pool({
    host: required('DATABASE_HOST'),
    port: Number(process.env.DATABASE_PORT ?? 5432),
    database: required('DATABASE_NAME'),
    user: required('DATABASE_USER'),
    password: required('DATABASE_PASSWORD'),
    max: 20,
    ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: true } : undefined,
  });
}

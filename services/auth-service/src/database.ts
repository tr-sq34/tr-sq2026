import { readFileSync } from 'node:fs';

const required = (name: string) => {
  const value = process.env[name];
  if (!value) throw new Error(`Missing ${name}`);
  return value;
};

// Local development may use one URL. Production receives the RDS-managed
// credential fields separately, so no database password is ever copied into
// the application configuration secret.
export function databaseConnectionString() {
  if (process.env.DATABASE_URL) return process.env.DATABASE_URL;
  const user = encodeURIComponent(required('DATABASE_USER'));
  const password = encodeURIComponent(required('DATABASE_PASSWORD'));
  const host = required('DATABASE_HOST');
  const port = required('DATABASE_PORT');
  const database = encodeURIComponent(required('DATABASE_NAME'));
  return `postgresql://${user}:${password}@${host}:${port}/${database}`;
}

// Production connections use the official AWS RDS global CA bundle.  Do not
// weaken this to rejectUnauthorized:false: the database password must only be
// sent after the server certificate has been verified.
export function databaseSslOptions() {
  if (process.env.NODE_ENV !== 'production') return undefined;

  return {
    rejectUnauthorized: true,
    ca: readFileSync(new URL('../certs/rds-global-bundle.pem', import.meta.url), 'utf8'),
  };
}

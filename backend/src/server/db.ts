import { Pool } from 'pg';
import { drizzle } from 'drizzle-orm/node-postgres';
import { attachDatabasePool } from '@vercel/functions';
import * as schema from './schema';
import { required } from './config';
const globalDB = globalThis as unknown as { aiPool?: Pool };
export function database() {
  if (!globalDB.aiPool) {
    globalDB.aiPool = new Pool({ connectionString: secureConnection(required('DATABASE_URL')), max: 5, idleTimeoutMillis: 10000, connectionTimeoutMillis: 10000 });
    if (process.env.VERCEL) attachDatabasePool(globalDB.aiPool);
  }
  return drizzle(globalDB.aiPool, { schema });
}
export async function closeDatabase() { await globalDB.aiPool?.end(); globalDB.aiPool = undefined; }
export type DBTransaction = Parameters<Parameters<ReturnType<typeof database>['transaction']>[0]>[0];

export function secureConnection(value: string) { const url = new URL(value); url.searchParams.set('sslmode','verify-full'); return url.toString(); }

import nextEnv from '@next/env';
const { loadEnvConfig } = nextEnv;
import { Pool } from 'pg';
import { drizzle } from 'drizzle-orm/node-postgres';
import { migrate } from 'drizzle-orm/node-postgres/migrator';
loadEnvConfig(process.cwd(), process.env.NODE_ENV !== 'production');
const url = process.env.DATABASE_URL_UNPOOLED;
if (!url || new URL(url).hostname.includes('-pooler')) throw new Error('Set DATABASE_URL_UNPOOLED to the direct connection for the intended branch.');
const connection = new URL(url); connection.searchParams.set('sslmode','verify-full');
const pool = new Pool({ connectionString: connection.toString(), max: 1 });
try { await migrate(drizzle(pool), { migrationsFolder: './drizzle' }); console.log('Database migrations applied.'); }
finally { await pool.end(); }

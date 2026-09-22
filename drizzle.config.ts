import { createRequire } from 'node:module';
const { loadEnvConfig } = createRequire(import.meta.url)('@next/env');
import { defineConfig } from 'drizzle-kit';
loadEnvConfig(process.cwd(), true);
export default defineConfig({ dialect: 'postgresql', schema: './backend/src/server/schema.ts', out: './drizzle', dbCredentials: { url: process.env.DATABASE_URL_UNPOOLED! } });

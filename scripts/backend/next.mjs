import nextEnv from '@next/env';
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
const require=createRequire(import.meta.url);
const command=process.argv[2] || 'dev';
nextEnv.loadEnvConfig(process.cwd(), command==='dev');
const child=spawn(process.execPath,[require.resolve('next/dist/bin/next'),command,'backend',...(command==='dev'?['--hostname','127.0.0.1']:[]),...process.argv.slice(3)],{stdio:'inherit',env:process.env});
child.on('exit',code=>process.exit(code??1));
for(const signal of ['SIGINT','SIGTERM']) process.on(signal,()=>child.kill(signal));

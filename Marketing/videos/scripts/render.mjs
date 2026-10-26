// npm run render -- <video-id> [...]   writes renders/<video-id>.mp4 for each id.
import {execFileSync} from 'node:child_process';

const ids = process.argv.slice(2);
if (ids.length === 0) {
  console.error('Usage: npm run render -- <video-id> [...]\nVideo ids are listed in README.md (or run: npx remotion compositions).');
  process.exit(1);
}
for (const id of ids) {
  execFileSync('npx', ['remotion', 'render', id, `renders/${id}.mp4`], {stdio: 'inherit'});
}

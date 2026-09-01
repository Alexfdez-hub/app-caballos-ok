const { spawnSync } = require('node:child_process');
const path = require('node:path');

const root = path.join(__dirname, '..');

function git(args) {
  return spawnSync('git', args, {
    cwd: root,
    encoding: 'utf8',
    windowsHide: true,
  });
}

const tracked = git(['ls-files', '.env', '.env.*']);

if (tracked.status !== 0) {
  process.stderr.write(tracked.stderr);
  process.exit(tracked.status ?? 1);
}

const trackedFiles = tracked.stdout
  .split(/\r?\n/)
  .map((line) => line.trim())
  .filter(Boolean)
  .filter((file) => !file.endsWith('.example'));

if (trackedFiles.length > 0) {
  console.error('Tracked environment files that should be gitignored:');
  for (const file of trackedFiles) {
    console.error(`  ${file}`);
  }
  process.exit(1);
}

const mustIgnore = [
  '.env',
  '.env.local',
  '.env.supabase.local',
  '.env.supabase.remote',
];

for (const file of mustIgnore) {
  const ignore = git(['check-ignore', '-q', file]);
  if (ignore.status !== 0) {
    console.error(`${file} is not gitignored.`);
    process.exit(1);
  }
}

console.log('Environment secret files are gitignored.');

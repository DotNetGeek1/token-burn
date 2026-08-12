// Converts source art from the Godot project into web-sized WebP files in public/img.
// Run from site/: node scripts/prepare-assets.mjs
import { mkdir } from "node:fs/promises";
import path from "node:path";
import sharp from "sharp";

const repoRoot = path.resolve(import.meta.dirname, "..", "..");
const outDir = path.resolve(import.meta.dirname, "..", "public", "img");

const jobs = [
  ["presentation/title/title_key_art.png", "key-art.webp", 1600],
  ["presentation/rig/burn_rig.png", "burn-rig.webp", 900],
  ["shots/new_title.png", "shot-title.webp", 1280],
  ["shots/new_jobs.png", "shot-jobs.webp", 1280],
  ["shots/board.png", "shot-board.webp", 1280],
  ["shots/new_market.png", "shot-market.webp", 1280],
  ["shots/call.png", "shot-call.webp", 1280],
  ["shots/angel.png", "shot-angel.webp", 1280],
  ["shots/hot.png", "shot-heat.webp", 1280],
  ["shots/statement.png", "shot-statement.webp", 1280],
  ["shots/workflows.png", "shot-workflows.webp", 1280],
  ["shots/runend.png", "shot-runend.webp", 1280],
];

await mkdir(outDir, { recursive: true });

for (const [source, name, width] of jobs) {
  const from = path.join(repoRoot, source);
  const to = path.join(outDir, name);
  const info = await sharp(from)
    .resize({ width, withoutEnlargement: true })
    .webp({ quality: 80 })
    .toFile(to);
  console.log(`${name} ${info.width}x${info.height} ${(info.size / 1024).toFixed(0)}kb`);
}

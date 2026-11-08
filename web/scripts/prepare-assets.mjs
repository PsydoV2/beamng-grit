// Kopiert Branding und Screenshots aus dem Repo nach public/img und verkleinert sie fürs Web.
// Quelle bleibt branding/out und screenshots/, hier wird nichts von Hand gepflegt.
import sharp from "sharp";
import { mkdir, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "..", "..");
const outDir = path.resolve(here, "..", "public", "img");

const jobs = [
  // [Quelle, Ziel, Breite, Format, Rand abschneiden]
  ["branding/out/grit-banner.png", "og.jpg", 1200, "jpeg"],
  ["branding/out/grit-logo-transparent.png", "logo.png", 256, "png", true],
  ["branding/out/grit-logo-transparent.png", "icon.png", 64, "png", true],
  ["branding/out/grit-wordmark.png", "wordmark.webp", 1200, "webp", true],
  ["branding/out/grit-header-scratches.png", "header-scratches.webp", 1600, "webp"],
  ["branding/out/grit-header-dirt.png", "header-dirt.webp", 1600, "webp"],
  ["branding/out/grit-header-dust.png", "header-dust.webp", 1600, "webp"],
  ["screenshots/screenshot_scratch.png", "scratch.webp", 2000, "webp"],
  ["screenshots/screenshot_scratch_before.png", "scratch-before.webp", 2000, "webp"],
  ["screenshots/screenshot_scratch_after.png", "scratch-after.webp", 2000, "webp"],
  ["screenshots/screenshot_mud.png", "mud.webp", 2000, "webp"],
  ["screenshots/screenshot_mud_before.png", "mud-before.webp", 2000, "webp"],
  ["screenshots/screenshot_mud_after.png", "mud-after.webp", 2000, "webp"],
  ["screenshots/screenshot_dirt.png", "dust.webp", 2000, "webp"],
  ["screenshots/screenshot_rollover_dirt_grass.png", "rollover.webp", 2000, "webp"],
];

await mkdir(outDir, { recursive: true });

for (const [src, dst, width, fmt, trim] of jobs) {
  const from = path.join(repo, src);
  const to = path.join(outDir, dst);
  // Nur neu erzeugen, wenn die Quelle neuer ist.
  try {
    const [s, d] = await Promise.all([stat(from), stat(to)]);
    if (d.mtimeMs >= s.mtimeMs) continue;
  } catch {}
  let img = sharp(from);
  // Transparenten Rand abschneiden (Logo und Wortbild haben viel Luft).
  if (trim) img = sharp(await img.trim({ threshold: 1 }).toBuffer());
  img = img.resize({ width, withoutEnlargement: true });
  if (fmt === "webp") img = img.webp({ quality: 82 });
  else if (fmt === "jpeg") img = img.jpeg({ quality: 85 });
  else img = img.png();
  await img.toFile(to);
  console.log(`${src} -> public/img/${dst}`);
}

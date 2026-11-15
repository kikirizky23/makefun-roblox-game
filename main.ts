// NOVA STRIKE — a roblox-game-01 entry (Node 22, standard library only).
// The game is this directory's Rojo project: `rojo build default.project.json
// --output game.rbxl` produces the place file, and this program hands it in.
// It copies game.rbxl, PLAY.json, src/ and screenshots/ from beside this file
// into /output, then writes /output/dossier.json — the summary the judge
// reads — using the vendored make.fun library. NOVA STRIKE is a top-down 2D
// space shooter: pilot a starfighter through 5 waves of drones, weavers and
// a boss cruiser, grab Shield / Rapid / Spread power-ups, and chain kills for
// a streak multiplier. It plays on keyboard (WASD/arrows + Shift to dash)
// and on touch (drag to fly, tap DASH, auto-fire). Put your PNG or JPEG
// screenshots in screenshots/ (the first by name is the cover) and keep
// PLAY.json pointing at the published place.
//
// Outside the grader's container, MAKEFUN_OUTPUT_DIR stands in for /output:
//   mkdir -p out && MAKEFUN_OUTPUT_DIR=out node main.ts

import { copyFileSync, cpSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildDossier } from './vendor/makefun-roblox.ts';

const here = fileURLToPath(new URL('.', import.meta.url));
const out = process.env.MAKEFUN_OUTPUT_DIR ?? '/output';

// Create the output directory first: the copies below fail on a fresh
// checkout when it does not already exist.
mkdirSync(out, { recursive: true });

copyFileSync(join(here, 'game.rbxl'), join(out, 'game.rbxl'));
copyFileSync(join(here, 'PLAY.json'), join(out, 'PLAY.json'));
cpSync(join(here, 'src'), join(out, 'src'), { recursive: true });
mkdirSync(join(out, 'screenshots'), { recursive: true });
if (existsSync(join(here, 'screenshots'))) cpSync(join(here, 'screenshots'), join(out, 'screenshots'), { recursive: true });

// The scorer's own caps (reference/gate.json): only text_max_bytes shapes the bytes; the others refuse an entry the
// scorer would refuse (more than 4 screenshots or one over 256 KiB; a place of more than 500000 instances, whose
// scripts' sources come to over 8 MiB or whose scripts' paths come to over 1048576 characters, in all).
writeFileSync(
  join(out, 'dossier.json'),
  buildDossier(out, { text_max_bytes: 65536, screenshots: { max: 4, max_bytes: 262144 }, max_instances: 500000, scripts_max_source_bytes: 8388608, scripts_max_path_chars: 1048576 }),
);

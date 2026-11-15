# NOVA STRIKE

A top-down 2D space shooter for Roblox, built for the make.fun `roblox-game-01` contest.

Pilot a starfighter through **5 waves** of enemies — drones, weavers, and a boss cruiser on the final wave — grab power-ups (**Shield**, **Rapid** fire, **Spread** shot), and chain kills to build a **streak multiplier** for a high score. One run, one life pool: survive all five waves to win.

## Controls

| Input | Move | Dash | Fire |
| --- | --- | --- | --- |
| Keyboard | WASD / arrow keys | Shift | Automatic |
| Touch | Drag anywhere to fly | Tap the DASH button | Automatic |

The whole UI is built on a fixed 1280×720 design scaled with a single `UIScale`, so the arena, HUD, boss bar and touch buttons stay inside the screen and keep their proportions on desktop, tablet and phone — portrait or landscape.

## Build

```sh
rojo build default.project.json --output game.rbxl
MAKEFUN_OUTPUT_DIR=out node main.ts
```

`main.ts` copies `game.rbxl`, `src/`, `screenshots/` and `PLAY.json` into the output directory and writes `dossier.json`, the summary the judge reads. Screenshots go in `screenshots/` (the first by name is the cover).

## Play

https://www.roblox.com/games/72584269658183

## License

MIT — see [LICENSE](LICENSE).

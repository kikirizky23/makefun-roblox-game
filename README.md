# EMBER ARENA

EMBER ARENA is a 2D wave-survival shooter played entirely inside a Roblox
ScreenGui. You are a gold ember knight trapped in a neon arena. Waves of red
Chasers and violet Drifters close in. Move with WASD, aim with the mouse,
click to fire ember bolts, dash with Shift to escape, and grab mint orbs for
points and the occasional heal. Survive all 5 waves to win. Lose all 3 hearts
and the run ends.

## How a run plays

- Menu screen with a start button, then five waves with clear banners
- Wave-clear bonuses, a win screen after wave 5, a loss screen at zero hearts
- Restart any time with R or with the on-screen button
- Best score is saved between runs when the data store is reachable

## Controls

- WASD or arrow keys — move
- Mouse — aim, left click — shoot (F also shoots)
- Left Shift — dash
- R — restart

## Module layout

All game code lives under src, mapped by the Rojo project file:

- src/shared — Config, every constant in one place (palette, layout, tuning, waves)
- src/server — GameState, the single source of truth for the run; Spawner, wave
  composition and spawn points; init, boot, wiring, and the single server loop
- src/client — PlayerController, input plus world rendering; Hud, all interface
  construction and screen state

The server owns score, health, waves, and timing. The client only renders the
snapshots it is sent. Two remote events carry the traffic: one sends state from
server to client, the other sends player actions from client to server.

## Build

Build the place from the Rojo project file:

    rojo build default.project.json --output game.rbxl

Rojo writes the place file game.rbxl from the scripts under src. Do not build
over a place saved by Studio, and do not sync a Studio-saved place back over
these sources. Pick one direction and keep it.

## Screenshots

Screenshots live under screenshots, three images: the play shot first by name
so it is the cover, then the menu shot, then the win shot. Each image is
1280 by 720 and no larger than 256 KiB.

## Play link

PLAY.json holds zeros until the owner publishes the game on Roblox. The real
place and universe identifiers go in only after publishing. Until then the
entry is complete except for the play link.

## License

MIT — see LICENSE.

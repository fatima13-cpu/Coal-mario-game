# Super Mario Engine

A side-scrolling platform game written entirely in **16-bit x86 assembly** (NASM) for DOS.
It runs as a single `MARIO.COM` program in VGA mode 13h (320x200) and is played in **DOSBox**.

> EL2003 - Computer Organization & Assembly Language (COAL) - Semester Project, Fall 2026

Title screen

<!-- Put a screenshot of the title screen in a folder called docs/ with the name title-screen.png, or delete the line above. -->

## Features

- **Two levels**
  - World 1-1: classic daytime level
  - World 1-2: night level with a moonlit sky, twinkling stars, hills and pines. It has wider pits, faster enemies and less time
- **Smooth scrolling camera** over a 60 x 12 tile level (16 x 16 pixel tiles)
- **Small and Super Mario**: pick up a mushroom to grow, take a hit to shrink back (health hearts on the HUD)
- **Enemies**: Goombas and Koopas. Stomp a Koopa to turn it into a shell and kick it away
- **Blocks and items**: `?` blocks with coins, a mushroom block, breakable bricks, pipes, stairs
- **Scoring**: stomp chains (100, 200, 400, ... up to 8000), coins (100 coins = extra life), score pop-ups, time bonus, higher grab on the flag pole = more points
- **Full game flow**: title screen, pause, life-lost card, level complete, game over, game complete
- **Lives and timer**: 3 lives, countdown clock (300 s in World 1-1, 250 s in World 1-2)

---

## Controls

| Key | Action |
|---|---|
| **Left / Right arrow** | Walk |
| **Left Shift** (hold) | Run |
| **Space** | Jump (hold longer = higher jump) |
| **P** | Pause / resume |
| **Esc** | Back to the title screen (on the title screen: exit) |
| **Up / Down, Enter** | Choose START GAME or EXIT in the menu |

### Debug keys (for testing)

| Key | Action |
|---|---|
| **F1** | Set the clock to 5 seconds |
| **F2** | Set coins to 99 |
| **F3** | Switch between World 1-1 and World 1-2 |

---

## How to play

1. Run to the right, jump over pits and enemies, and reach the **flag pole** at the end of each level.
2. **Stomp** enemies by landing on their heads. Touching them from the side hurts you.
3. Hit `?` blocks from below for coins; the mushroom block makes you Super Mario.
4. Pits are lethal. Some of the wider pits need a **running jump** (hold Shift + Space).
5. Finish World 1-1 to continue to World 1-2. Finish World 1-2 to complete the game.

---

## Requirements

- [NASM](https://www.nasm.us/) (to build)
- [DOSBox](https://www.dosbox.com/) (to run the game)

---

## Build and run

In the folder that contains `mario.asm`:

```
nasm mario.asm -f bin -o mario.com -l mario.lst
```

Run it in DOSBox:

```
mount c C:\path\to\this\folder
c:
mario.com
```

`sprites.inc` and `level.inc` must stay next to `mario.asm`: they are pulled in while assembling.

---

## Project structure

```
Coal_Project/
|
|-- mario.asm          main program + game logic
|-- sprites.inc        tiles and sprites artwork
|-- level.inc          World 1-1 map
|-- README.md          project information and instructions
|-- .gitignore         files Git should ignore
|
`-- docs/
    `-- screenshots/   project screenshots
```

---

## How it works (technical overview)

- **Video**: VGA mode 13h. A frame is drawn into an off-screen buffer and copied to video memory once per frame (double buffering, no flicker).
- **Palette**: 16 colours programmed through the VGA DAC. World 1-2 loads a different (night) palette, so the same sprites change their mood without extra art.
- **Input**: custom keyboard handler (INT 09h) with a key-state table, so several keys can be held at once (run + jump + direction).
- **Timing**: custom timer handler (INT 08h) gives a fixed game speed of 30 ticks per second.
- **Physics**: 8.8 fixed-point positions and velocities, gravity, variable-height jumps, tile-based collision against the level map.
- **Text**: the 8x8 font is read from the BIOS ROM and drawn at any scale.
- **Calling convention**: arguments are pushed on the stack, the callee cleans them up (`ret n`) and preserves every register it does not return.

---

### Team Contributions

| Team Member | Responsible For |
|---|---|
| **Fatima** | Main program integration, game structure and overall implementation. **Module 1** (program entry, setup and exit), **Module 2** (VGA video mode and colour palette), **Modules 7 + 8** (keyboard and timer interrupt handlers), **Module 14** (game states, screens and menus: title, pause, level complete, game over), **Module 15** (death, win and restart, flag-pole sequence). Also implemented the Level 1 → Level 2 progression. |
| **Fatima Altaf** | Everything drawn on the screen. Text and numbers (BIOS bitmap font, strings, score numbers), **Module 4** (sprite and tile drawing with screen clipping), **Module 3** (level map loading, tile lookup, map and background drawing), **Module 5** (frame buffer), **Module 6** (camera and scrolling), and rendering (HUD and screen flip). Also implemented the night theme of Level 2 (night palette, moon, stars, hills, pines and lit castle windows). |
| **Tehreem** | Gameplay rules. **Module 9** (player movement and physics: walking, running, variable-height jump, gravity), **Module 10** (collision with tiles and enemies), **Module 11** (enemies: Goombas, Koopas, shells and stomping), **Module 12** (blocks, coins and power-ups: question blocks, bricks and mushrooms), **Module 13** (score, coins, lives and pop-up effects). Also designed the Level 2 map, enemy placement and enemy speeds. |

## Working Together with Git

- Each member uses their own GitHub account.
- Pull the latest changes before starting work.
- Create a separate branch for your task.
- Commit and push your changes with meaningful messages.
- Open a Pull Request for review and merging.
- Coordinate before editing `mario.asm` to avoid conflicts.
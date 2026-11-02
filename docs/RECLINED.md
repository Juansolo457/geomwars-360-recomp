# Plan: Geometry Wars: Reclined (the game plays itself)

An idea from 2026-10-30, written up before any of it exists. Not part of M0-M5 in
[PLAN.md](PLAN.md); it starts once M2 is merged and runs on its own branch and pull requests.
**Every build and run still needs the user's OK.**

## The idea
An idle game made of a recompiled arcade game. The program starts, gets itself into a game of
Evolved and plays. Each game it tries a slightly different way of playing, keeps what scored
and drops what didn't, and goes on, game after game, for hours or days, climbing the high score
and ticking off the achievements. A small overlay shows the generation, the best score so far
and which achievements are left. At any moment the player picks up a pad and the ship is theirs;
put the pad down and Reclined takes over again. It stops, by default, when every achievement is
unlocked and the score has stopped improving, and says so.

The joke is the genre: a twin-stick shooter that would rather you didn't, played like the AFK
games that level up while you make tea. It is also a good test rig: thousands of unattended
games exercise the recomp harder than any smoke script.

## What already exists (and why this is small)
- **An input driver that feeds the game from code.** `port/src/autopilot.cpp` is a
  `rex::input::InputDriver` that returns a pad state per poll from a timed script. Reclined is
  the same driver fed by a policy instead of a file. Run 3 showed the sticks and the trigger
  work through it (+y is up).
- **The game flow is known.** Logo, one START to "Select game mode", START into Evolved, a
  game, "Game over / Continue", back to the menu (run 2, run 3; `tools/autopilot/boot.txt`).
  Restarting is a few presses.
- **Game events reach the host as kernel calls**, so some outcomes need no memory reading:
  `XSessionStart` (a game began), `XSessionWriteStats` + `XSessionEnd` (a game ended; the
  stats buffer carries the score and the leaderboard it goes to), `XamUserWriteProfileSettings`
  (a new high score), the runtime's achievement store (11 entries loaded; unlocks go through it).
- **Every controller drives player 1 already**, so a human pad and the policy share the slot;
  "take over" is a priority rule, not new plumbing.
- **The host has ImGui** (`ui_style.cpp`, `ui_pad.cpp`) for the overlay.
- **The image is 1.1 MB with 1,764 functions**: finding the score, the lives, the ship and the
  enemy table in guest memory is an afternoon with a memory scan, not a reverse-engineering
  project.

## Decisions to make (recommendations in bold)
- **Language.** The policy must answer every input poll (60 Hz) inside the process, so it lives
  in the host app: **C++ in `port/src/reclined/`**, next to the autopilot it extends. No embedded
  scripting runtime and no Rust crate for this: a few hundred lines, no new build dependency,
  Linux-clean. The outer bookkeeping that doesn't need to be in-process (the log of games, the
  stop rule, a summary page) is **a tiny Python script, `tools/reclined.py`**, or nothing at all
  if the host writes the summary itself. Rust stays the option for a later host-layer migration
  (the F.E.A.R. plan), not for this.
- **What a "set of moves" is.** Enemy spawns are random per game, so a recorded tape of stick
  positions does not replay into the same game. What transfers between games is a **policy with
  a handful of parameters** (how far from the nearest enemy to keep, how hard to orbit, when to
  bomb, how long to hold fire for Pacifism...), and a game is **one evaluation of one parameter
  vector**. That is also what makes the file small: **one line per game**, `seed, 12-16 bytes of
  parameters, score, seconds, achievements mask` (about 40 bytes), appended to
  `port/user/reclined.log`. The "best so far" is the best line. No per-frame recording.
- **How it gets better.** **A (1+λ) evolution strategy**: keep the best vector, play a game with
  a mutated copy, replace the best if the mutant scored more. Simple, stateless between games,
  and visibly climbs in the overlay. Random restarts every N games so it does not sit on a local
  optimum. Nothing learned per frame (no neural net, no RL loop): the parameter space is tiny
  and a game is the unit of feedback.
- **What the policy sees.** Three tiers, start at the lowest that works:
  1. **Blind** (nothing from memory): a fixed orbit pattern with aim sweep. Scores hundreds.
  2. **HUD only** (score, lives, bombs, multiplier read from guest memory): lets the policy
     restart, bomb when a life goes, and measure itself. Enough for the restart loop and the
     log.
  3. **World** (the ship's position and the enemy table): keep away from the nearest, aim at the
     nearest, bomb when surrounded. This is where scores reach the tens of thousands. The
     entity table is one array in `.data`/heap; the memory scan finds it from the ship's
     position changing with the stick.
- **Speed.** Real time first: a game of a weak policy is 60-120 s, a strong one longer, so a
  few hundred games a night. **Turbo** (run the guest clock faster than real time, skip presents
  when no one is watching) is a later step and may not be free: the game's step may be tied to
  the vblank or to the wall clock; measure before promising. Headless runs (`--headless`) for
  overnight batches are already in the host.
- **Taking over.** Any input on a physical pad beyond the dead zone **mutes the policy for 3 s**
  (renewed by each input); the overlay shows "yours" while muted and the game logs that game as
  `human`, excluded from the evolution. Pressing the Reclined overlay's own key (BACK held 1 s)
  toggles it off entirely.
- **Stop rule.** All achievements unlocked **and** no new best in the last 200 games: the
  overlay says "Reclined is done" and the policy idles on the menu. A flag keeps going forever.
- **Achievements.** The game's twelve (from the image strings: survive 60 s without firing,
  score thresholds, a multiplier threshold, a bomb count, ...) split into "come with score"
  and "need a behaviour". The second kind get their own policy mode with its own parameters
  (Pacifism: hold fire and dodge for 60 s), scheduled when the score policies plateau. The
  unlock is read from the runtime's achievement store, not inferred.
- **Retro.** Evolved first. Retro is a second arena with the same loop; a second leaderboard in
  the log.

## Milestones
| # | Milestone | Done when |
|---|---|---|
| R0 | **Memory map** | Score, lives, bombs, multiplier, game state (menu / playing / game over), the ship's x,y and the enemy table found in guest memory on this XEX hash, documented in FINDINGS.md with how each was found (`tools/memscan.py`: snapshot the guest arena at known HUD values and diff). The `XSessionWriteStats` buffer layout (the score field) read from one hook. |
| R1 | **The loop** | `--reclined` starts the game, plays a blind policy, detects game over, restarts, appends a line per game to `reclined.log`; runs 30 games unattended without a crash; the log's scores plotted by `tools/reclined.py`. |
| R2 | **It learns** | Tier-3 policy with 12-16 parameters, (1+λ) evolution, the best score climbing over 200 games (a chart in the PR); the parameter vector and its meaning documented. |
| R3 | **Overlay and takeover** | The ImGui overlay (generation, games, best, last, achievements n/12, "yours" while muted); a human pad takes over and hands back; the whole thing off by default and on with `--reclined`. |
| R4 | **Achievements and the stop** | The twelve achievements tracked from the store; behaviour modes for the ones that need them; the stop rule; an overnight run that ends by itself. |
| R5 | **Turbo and Retro** | Faster-than-real-time games if the engine allows it (measured); Retro's arena; a README section and a short clip. |

Each milestone is a pull request (`master` is locked; CodeRabbit reviews). R0 is read-only
analysis plus one hook and needs one or two runs; R1 is the first thing to show.

## Risks and open questions
- **Determinism.** If a game's RNG is seeded from the wall clock, the same parameters score
  differently game to game; the evolution needs a few games per vector or a noise-tolerant
  acceptance rule. Measure the variance in R1.
- **The entity table's layout** may be a linked structure rather than an array; tier 2 (HUD only)
  still gives the loop and the log, tier 3 waits.
- **Turbo** may break audio pacing or the game's own timers; it is last for that reason.
- **Achievement persistence** in the runtime's store across restarts is unverified (the smoke
  runs use a fresh user directory); check in R0.
- **Headless for hours**: memory growth in the runtime or the Vulkan backend shows up only in
  long runs; R1's 30 games are the first look, an overnight run the second.
- **Keep it out of the normal game's way**: nothing in `port/src/reclined/` runs unless
  `--reclined` is given; the ordinary build and the Linux build must not change behaviour.

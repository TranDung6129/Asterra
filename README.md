# RIFTBOUND

Local hot-seat physics arena prototype, built from the supplied design guide.

## Run

Open `project.godot` with Godot 4.6 or later and press **F6/F5**, or run:

```bash
godot --path . --editor
```

## Controls

- Click **anywhere** on the title screen to begin.
- On your turn, click any living hero in your team, then **pull the cursor back from them and release** to launch.
- Press **Space** while aiming to use Bront, Momo, or Vex's active skill.
- Press **R** to restart a match.

## Included MVP systems

- 1v1 local hot-seat, five hero squads and free hero selection every turn
- drag-to-aim launch, elastic wall collisions, bounce pads, impact damage and knockouts
- Bront, Niva, Kitsu, Momo and Vex with distinct physics-focused passives/skills
- Heart, Shield, Dash, Power Core and Chaos Orb pickups
- stable-motion turn resolution, ten-second simulation failsafe and squad/HP HUD

This is deliberately local-first: online matchmaking, progression, monetization and final character art remain outside the prototype scope stated in the GDD.

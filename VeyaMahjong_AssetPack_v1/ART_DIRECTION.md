# Art direction — Veya Mahjong

Modern colorful casual Mahjong, lightweight 2D, premium through consistency instead of expensive effects.

## Mood
Warm porcelain tiles, rounded cream cards, sea-blue/teal backgrounds, cherry blossom pink, violet accents, soft gold reward moments. Never obscure match symbols with ornaments.

## Do
- Preserve clear Chinese character glyphs and strong visual differences among bamboo/circle/character suits.
- Keep interface uncluttered in gameplay; use large and forgiving hit boxes.
- Prefer 2D sprite atlases and low shader budgets, original backgrounds and independent decor sprites.
- Use limited tap animations (90ms) and match transitions (220ms), optional particles.
- Keep premium visual language via spacing, soft shading, pleasant transitions, no 3D.

## Avoid
- Busy backgrounds behind tile stacks; intense glitter; animation loops on every decor element.
- Using moodboard composites as in-game sprites (they contain text baked in / inconsistent scales).
- Fixed-position UI assuming every screen has 1080×1920 safe zone.
- Dependent texts embedded into button PNGs; all dynamic labels should be drawn by the game.

## Brand colors
`#765AC7`, `#49BDB7`, `#F4A3C7`, `#F4C568`, `#FFF8EC`, `#153D56`.

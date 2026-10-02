# Raccoon animation trial — brief v14

Only idle, run and shoot are included for the first in-engine review requested by the brief.

- idle/run: 4×2 frames, 3072×1024; shoot: 2×2 frames, 1536×1024.
- Cell size: 768×512. Reading order: left to right, then second row.
- Facing right; mirror in code for left.
- Feet aligned at y=487; 24 pixels of empty bottom margin. Background #FF00FF.
- No weapon painted in frames. raccoon_grip.json uses cell-local [grip_x, grip_y, support_x, support_y] per frame, visually placed on the two gloves.
- Identity based on source/assets/player/raccoon_body.png: gray raccoon, olive scarf, brown outfit, orange buckles.

PNG decoding and dimensions checked. Animation timing, loop continuity, weapon placement and grip coordinates need in-engine review. Keep the existing body/arm as fallback. Remaining animations and other heroes follow after approval of this trial.

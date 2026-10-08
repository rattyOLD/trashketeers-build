class_name PhysicsLayers
extends RefCounted
## Битовые маски слоёв. Имена слоёв 1–8 в Project Settings → Layer Names → 2D Physics
## должны совпадать с порядком ниже.

const WORLD := 1 << 0
const PLAYER := 1 << 1
const ENEMY := 1 << 2
const OBSTACLE := 1 << 3
const PLAYER_BULLET := 1 << 4
const ENEMY_BULLET := 1 << 5
const SHIELD := 1 << 6
## Декор, который останавливает персонажей, но не пули (кристаллы Алтаря).
const PROP := 1 << 7

## Рельеф (кислотная протока): держит наземных врагов (идут по мостам); герой может пройти вброд, пули и летуны — над ним.
const TERRAIN := 1 << 8

## Тела, о которые пуля гарантированно разбивается, не нанося урона.
const BULLET_BLOCKERS := WORLD | SHIELD

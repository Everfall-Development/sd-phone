# Everfall map tiles

The phone uses the shared Everfall map tile service:

```text
https://files.coolgingerginger.me/tiles/{z}/{x}/{y}.png
```

The map uses the same simple CRS as MDT, Spawn, Administration, Bus Job, and
Gangs. Keep the GTA-to-map transform in `data.ts` unchanged when adding or
updating tile coverage:

- map origin `[-119.43, 58.84]`
- scale `1.421 / 100` map units per GTA unit
- bounds latitude `-192..0`, longitude `0..128`
- zoom levels `z2..z7`
- 256px PNG tiles

Pins, live-location dots, route lines, and shared-location previews all use the
same transform. Public phone payloads remain GTA `{ x, y }` coordinates.

## Tile health check

Use `/maptiles` in the client to probe the center tile at every supported zoom
level. The result is printed to the F8 console. A failed probe means the shared
tile service or its network path should be checked before native acceptance.

## Alignment check

Open Maps and compare the live location dot against known landmarks such as
Legion Square `(195, -930)` and LSIA `(-1037, -2738)`. The map calibration
commands remain available for development checks, but normal use must not need
per-resource projection bounds.

Build the web package with:

```text
cd web
pnpm run build
```

The game serves the generated `web/build/index.html`; browser rendering is
only renderer QA. Native map, waypoint, focus, and safe-zone behavior still
require in-game acceptance.

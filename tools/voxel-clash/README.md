# Voxel Clash · The Floating Kingdoms

A real-time, two-player strategy game rendered with the repository’s Three.js r160. The same scene and controls run inside Telegram’s native HTML bubble through its Metal renderer and in a browser through WebGL. A server owns the simulation, validates every action, and pushes snapshots through WebSockets. The Telegram conversation is a local mock; multiplayer networking is real.

## CEO demo

1. Build and run the `Telegram` Debug scheme in `Telegram-Mac.xcworkspace` with Xcode 27. With the `dev` app-configuration flag enabled, open **Voxel Clash** at the top of the chat list. Any signed-in account can play.
2. Choose **Match → Create match**, then **Copy invitation**. Share the link with anyone you want to play with. For a local rehearsal, `/rival` opens another signed-in account in a second window.
3. Your rival can open the link in a browser, or open Voxel Clash on their own dev-enabled Telegram account and choose **Match → Join link** with the invitation on the clipboard. Pasting the invitation into the local game chat also joins it.
4. Choose **Copy spectator link** on either player. Open it in a browser to follow the same battle live without a player seat. Spectators can orbit and zoom, but cannot change the game.
5. Build a cottage or windmill, select **Command army → Capture**, then select **Rival citadel → Attack**. Both native windows and the browser receive the same changes immediately.
6. The host can choose **Match → Rematch** to reset the battle while keeping player sessions and both links.

For a solo rehearsal, choose **Practice** while the rival seat is empty. Clockwork builds and commands armies. A person following the invitation can take over its seat. Opening the mock chat for the first time creates a private room for that account; later openings resume its saved match. **Create match** creates a separate private room.

Mock chats stay in the list after switching chats, including compact layouts. Their contents are retained for the account window’s lifetime. Match credentials survive app restarts, and the Railway volume preserves private rooms across redeployments. `/rival` uses Telegram’s existing account windows; copying the app is unnecessary.

## Play

Two floating kingdoms compete for the Sky Crystal on a neutral bridge. Capturing it costs three knights and generates one crown per second. Reach **80 crowns**, destroy the rival citadel, or lead on crowns when the six-minute clock expires. Citadel health breaks a timed tie. Build and upgrade an economy, increase army capacity with cottages, defend with towers and ramparts, and choose between attacking the city and controlling the crystal.

Click a plot in the 3D scene. Click and drag horizontally to orbit or vertically to tilt the camera. A drag keeps the selected plot unchanged; a simple click selects it. **Next plot**, **Rival citadel**, and **Sky Crystal** select useful targets. Arrow keys or WASD move selection. The ↶/↷ and −/+ controls orbit and zoom; **Dusk/Dawn** changes the lighting. Economy, Fortifications, and Command army expose the corresponding actions. Construction, windmills, the crystal, marching knights, meteors, shields, and impacts animate in the scene.

| Building | Gold | Benefit at level 1 |
| --- | ---: | --- |
| Cottage | 45 | +2 gold/sec, +4 army capacity |
| Windmill | 60 | +3 food/sec |
| Crystal mine | 80 | +2 energy/sec |
| Barracks | 100 | Recruits knights using food |
| Watchtower | 110 | Reduces nearby incoming damage by 12 |
| Rampart | 25 | Reduces nearby incoming damage by 4 |

Every kingdom starts with a citadel, cottage, windmill, barracks, 280 gold, 90 food, 60 energy, and 12 knights. A citadel adds income and army capacity. Upgrade buildings to level 3, or repair damaged buildings. Attacks send five knights for 20 gold; Skystrike costs 80 energy; Shield costs 60 energy and protects for 12 seconds. Armies travel before damage resolves. Combat actions have a short cooldown. All currencies are game counters.

The local game chat accepts commands without adding chat messages:

| Command | Action |
| --- | --- |
| `/create`, `/invite`, `/spectate` | Create a private room; copy player or spectator links |
| `/join URL`, `/watch URL` | Enter a linked room |
| `/rival` | Open another signed-in account’s window |
| `/practice` | Start a match against Clockwork |
| `/build house D7` | Build; kinds: house, farm, quarry, barracks, tower, wall |
| `/upgrade D7`, `/repair D7` | Improve or repair a selected building |
| `/claim`, `/train`, `/shield` | Capture the crystal, train five knights, shield the kingdom |
| `/attack L7`, `/meteor L7` | Attack or cast Skystrike on an enemy building |
| `/newworld` | Host starts a rematch |

Coordinates are A1–N14. The host’s grass plots are columns B–F; the rival’s are I–M. The outer ring is sky. G7/H7/G8/H8 form the neutral bridge. Citadels start at C8 and L7.

## Backend and persistence

The only deployed service is **voxel-clash** in Railway project **tg-bubble-html**, at `https://voxel-clash-production.up.railway.app`. `/health` reports version 2 and WebSocket transport. Port 3000 is configured on the service and domain. The `/data` Railway volume stores `matches-v2.json` through atomic replacement; graceful shutdown also saves state.

Private rooms have separate random invitation and spectator capabilities. Player sessions use bearer tokens; browser WebSockets send the token through a subprotocol rather than the URL. Spectator snapshots omit the invitation and player credentials. Spectator actions are rejected by the server. Reconnection reuses credentials, and action identifiers prevent duplicate spending after a lost acknowledgement. Payload sizes, action frequency, and snapshot buffering are bounded. Player seats follow invitation capabilities and random client identities, independent of commander names. This is demo authentication, not Telegram-signed identity.

Only a commander name and a random local client ID go to Railway. Telegram credentials, account IDs, and chat contents are not transmitted. The native bridge is restricted to the fixed demo HTTPS host; the HTML sandbox does not gain general network access. A browser invitation includes **Open in Telegram**, handled by the app’s `tg://voxelclash` route only when the current account has `dev == 1` and that app is registered for Telegram links. The same flag gates the mock-chat list. Both entry points require this flag in every build configuration.

Use Node 22 or later:

```sh
npm ci
npm test
npm start
```

`DATA_DIR` selects the state directory (default `/tmp/voxel-clash`); `PORT` defaults to 3000. For local browser links, set `PUBLIC_URL=http://127.0.0.1:3000`. `RAILWAY_VOLUME_MOUNT_PATH` takes precedence over `DATA_DIR` on Railway.

`npm test` covers game rules, ownership, upgrades, shields, moving armies, victory, practice, room isolation, persistence, WebSocket push, and spectator restrictions. `npm run smoke` checks the deployed API and live transport using a new disposable private room, without resetting an existing demo. Set `VOXEL_DEMO_URL` to check a local server.

Deploy from this directory:

```sh
railway up --project 2e82dfe8-1795-4d6b-a6da-453b0107eece --environment production --service voxel-clash --detach --path-as-root .
```

The demo intentionally runs as a single authoritative process with a persistent volume. It is ready for the CEO demonstration; public launch would require account authentication, multi-instance coordination, and operational monitoring.

## Sources

Edit `public/game.js` and `public/style.css`, then run **`npm run pack`** to regenerate `packages/HTMLBubbles/Tests/HTMLBubblesTests/Fixtures/multiplayer/voxel-clash.html`. `public/bridge.js` provides browser sessions and WebSockets; `HTMLMultiplayerDemoClient.swift` supplies the native equivalent. `engine.mjs` contains deterministic game rules, `store.mjs` persistence, and `api.mjs` HTTP/WebSocket transport.

`public/assets/three.js` is copied from the repository’s existing HTMLBubbles library. Three.js is MIT licensed, copyright 2010–2023 Three.js Authors; see `THIRD_PARTY_NOTICES.md`.

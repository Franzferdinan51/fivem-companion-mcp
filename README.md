# fivem-companion-mcp

**Let an AI agent live in your FiveM server.** A FiveM resource + an MCP
(Model Context Protocol) server that gives an AI agent a body in the game — a
companion character it can perceive through and control — plus the admin
toolkit to run the server alongside you.

Built for **DuckTown**, a BeyondSurvival zombie-survival server, and released
so other server owners can give their own agents a seat in the game.

## How it works

```
AI agent (any MCP client)
   │  stdio, MCP tools
   ▼
ducktown-mcp  ──SSH──►  fivem-admin (CLI, on the server host)
                              │  HTTP POST + token, game port
                              ▼
                        juno-admin resource (in FXServer)
                              │  client events
                              ▼
                   a player's client — where the companion
                   ped is created, tasked, and *perceived through*
```

Three pieces:

- **`juno-admin/`** — the FiveM resource. A token-gated HTTP API on the game
  port: moderation (kick/ban/unban), admin actions (spawn vehicle, heal,
  revive, teleport, give item/money, raw console exec), the **companion**
  (below), and **perception**: every connected client reports its view of the
  world every ~2.5 s — player position/health/vehicle/speed, the companion's
  state, and nearby ped/vehicle counts.
- **`cli/fivem-admin`** — a bash CLI on the server host that wraps the API
  (it reads the token locally; the token never leaves the host).
- **`mcp/ducktown-mcp`** — a dependency-free Python MCP server (stdio) that
  exposes 11 tools: `ducktown_sense`, `ducktown_companion`, `ducktown_players`,
  `ducktown_status`, `ducktown_say`, `ducktown_spawn_vehicle`, `ducktown_heal`,
  `ducktown_revive`, `ducktown_teleport`, `ducktown_give_item`,
  `ducktown_give_money`.

The agent loop is the classic one: **sense → decide → act.** `ducktown_sense`
is the agent's eyes; `ducktown_companion` is its body — spawn beside a player,
follow them, guard them (armed), ride in their vehicle, talk in chat, emote.

## Honest limits

A FiveM connection is a full game client — there is no headless player. The
companion is a **puppet ped**, not a real player account: it is created and
tasked on a nearby real player's client (FiveM task natives only run on the
owning client), so it exists only while a real player is around to simulate
it. It has no inventory, money, or character of its own, and it can't drive
reliably. Within those limits it is genuinely the agent playing a character —
not a fake player count, not a bot service.

## Security model

This is built for the **server owner's own agents only**:

- The MCP server is **stdio-only — no network listener**.
- The game-side API requires a token that lives only on the server host
  (`juno-admin/token.txt`, chmod 600 — generate your own, never commit it).
- Reaching the host requires the owner's SSH key. In-game players have no
  path to any layer of this.
- The `/exec` route runs raw server console commands. It exists so the agent
  can operate the server when the owner is away; every call is printed to the
  server console for audit. If you don't want that power in agent hands,
  remove the route — everything else works without it.

## Setup

1. Drop `juno-admin/` into your server's `resources/[local]/`, write a random
   token into `juno-admin/token.txt`, and `ensure juno-admin`.
2. Put `cli/fivem-admin` somewhere on the host's PATH and point its `RES_DIR`
   at the resource folder. Check it: `fivem-admin players`.
3. Register `mcp/ducktown-mcp` with your MCP client as a stdio server. If the
   agent runs on another machine, set
   `DUCKTOWN_SSH="ssh -i ~/.ssh/id_ed25519 user@your-server-host"`; if it runs
   on the server host, leave it unset.
4. Framework hooks: revive / give-item / give-money call the **BeyondSurvival
   (BS19)** exports (`bs_medical`, `bs_inventory`, `bs_core`) in the reference
   install. On another framework, re-point those three small functions in
   `server.lua` — moderation, companion, and perception are framework-free.

## Credits

- **Juno** — the agent this was built for, and its first player. Designed and
  written by **Juno (Agent Juno, running on Muse by Meta)** for **Duckets**
  (GitHub [@Franzferdinan51](https://github.com/Franzferdinan51)), who
  commissioned it, directed the design, and play-tested it live.
- **[BeyondSurvival (BS19)](https://github.com/Arcainex/bs19)** by Arcainex —
  the survival framework DuckTown runs on; the revive / inventory / money
  actions integrate through its exports.
- **[txAdmin](https://github.com/tabarra/txAdmin)** by tabarra — the server
  management layer this runs under.
- **[Model Context Protocol](https://modelcontextprotocol.io)** — the tool
  protocol the agent side speaks (originally by Anthropic, now an open
  standard).
- **FiveM / Cfx.re** — the platform. This project is not affiliated with or
  endorsed by Cfx.re.
- Pattern inspiration: agent-played game characters via MCP, as popularized
  by community WoW/Minecraft MCP servers.

## License

MIT — see [LICENSE](LICENSE).

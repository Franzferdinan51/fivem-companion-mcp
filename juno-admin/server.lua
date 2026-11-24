-- juno-admin: moderation + AI companion control for a FiveM server.
-- Bans persist in bans.json inside this resource. API token in token.txt (same folder).
-- HTTP API (POST, JSON body, every call needs {"token": "..."}):
--   /juno-admin/players {}                       -> [{id,name,ping}]
--   /juno-admin/kick    {id, reason}             -> drops the player
--   /juno-admin/ban     {id, reason}             -> records identifiers+tokens, drops the player
--   /juno-admin/unban   {match}                  -> removes bans whose name contains match or an identifier equals match
--   /juno-admin/bans    {}                       -> [{name, reason, date, identifiers}]
--   /juno-admin/say     {message}                -> chat broadcast attempt + console print
-- Admin actions (v1.1.0) — target a player by {"id": n} or {"name": "partial"}:
--   /juno-admin/spawnveh {model}                 -> spawns the vehicle at the player, warps them in
--   /juno-admin/heal     {}                      -> full health via the client helper
--   /juno-admin/revive   {}                      -> bs_medical Revive export
--   /juno-admin/tp       {x,y,z} or {to}         -> teleport to coords or to another player
--   /juno-admin/giveitem {item, count}           -> bs_inventory GiveItem
--   /juno-admin/givemoney {account, amount}      -> bs_core AddMoney (account cash|bank)
--   /juno-admin/companion {action, model?, text?, emote?}
--       -> Juno's in-game body on that player's client: spawn|despawn|follow|guard|ride|come|say|emote
--   /juno-admin/exec     {command}               -> runs a raw server console command (full admin;
--                                                   so the agent can run
--                                                   the server when the owner is not around). Every call is
--                                                   printed to the server console for audit.
-- Console commands (txAdmin Live Console / server console): juno_kick, juno_ban, juno_unban, juno_bans, juno_players

local RES = GetCurrentResourceName()

local function loadJsonFile(name, fallback)
    local raw = LoadResourceFile(RES, name)
    if not raw or raw == '' then return fallback end
    local ok, data = pcall(json.decode, raw)
    if ok and data then return data end
    return fallback
end

local function saveBans()
    SaveResourceFile(RES, 'bans.json', json.encode(Bans), -1)
end

Bans = loadJsonFile('bans.json', {})
local tokenRaw = LoadResourceFile(RES, 'token.txt') or ''
local ApiToken = tokenRaw:gsub('%s+', '')
if ApiToken == '' then
    print('[juno-admin] WARNING: token.txt missing/empty - HTTP API disabled until a token is written and the resource is restarted.')
else
    print(('[juno-admin] loaded: %d ban(s), HTTP API armed.'):format(#Bans))
end

local function playerIdentifiers(src)
    local ids = {}
    for _, id in ipairs(GetPlayerIdentifiers(src)) do ids[#ids + 1] = id end
    local tokens = {}
    local n = GetNumPlayerTokens(src)
    for i = 0, n - 1 do tokens[#tokens + 1] = GetPlayerToken(src, i) end
    return ids, tokens
end

local function findBan(ids, tokens)
    for _, ban in ipairs(Bans) do
        for _, bid in ipairs(ban.identifiers or {}) do
            for _, id in ipairs(ids) do
                if bid == id then return ban end
            end
        end
        for _, bt in ipairs(ban.tokens or {}) do
            for _, t in ipairs(tokens) do
                if bt == t then return ban end
            end
        end
    end
    return nil
end

local function doKick(src, reason)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return false, 'no such player' end
    DropPlayer(src, reason or 'Kicked by an admin.')
    return true, 'kicked'
end

local function doBan(src, reason)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return false, 'no such player' end
    local name = GetPlayerName(src)
    local ids, tokens = playerIdentifiers(src)
    Bans[#Bans + 1] = {
        name = name,
        reason = reason or 'Banned by an admin.',
        date = os.date('%Y-%m-%d %H:%M:%S'),
        identifiers = ids,
        tokens = tokens
    }
    saveBans()
    DropPlayer(src, 'You are banned from this server. Reason: ' .. (reason or 'Banned by an admin.'))
    print(('[juno-admin] banned %s (%d identifiers, %d tokens)'):format(name, #ids, #tokens))
    return true, 'banned ' .. name
end

local function doUnban(match)
    if not match or match == '' then return false, 'empty match' end
    local lower = match:lower()
    local removed = 0
    for i = #Bans, 1, -1 do
        local ban = Bans[i]
        local hit = (ban.name and ban.name:lower():find(lower, 1, true)) and true or false
        if not hit then
            for _, id in ipairs(ban.identifiers or {}) do
                if id == match then hit = true break end
            end
        end
        if hit then
            table.remove(Bans, i)
            removed = removed + 1
        end
    end
    if removed > 0 then saveBans() end
    return removed > 0, ('removed %d ban(s)'):format(removed)
end

-- Ban enforcement on connect
AddEventHandler('playerConnecting', function(_, _, deferrals)
    local src = source
    deferrals.defer()
    Wait(0)
    local ids, tokens = playerIdentifiers(src)
    local ban = findBan(ids, tokens)
    if ban then
        deferrals.done(('You are banned from this server. Reason: %s (banned %s)'):format(ban.reason or '', ban.date or ''))
    else
        deferrals.done()
    end
end)

-- Console commands (restricted: server console / txAdmin live console)
RegisterCommand('juno_players', function()
    for _, id in ipairs(GetPlayers()) do
        print(('[juno-admin] [%s] %s (ping %s)'):format(id, GetPlayerName(id), GetPlayerPing(id)))
    end
end, true)

RegisterCommand('juno_kick', function(_, args)
    local ok, msg = doKick(args[1], table.concat(args, ' ', 2))
    print('[juno-admin] kick: ' .. msg)
end, true)

RegisterCommand('juno_ban', function(_, args)
    local ok, msg = doBan(args[1], table.concat(args, ' ', 2))
    print('[juno-admin] ban: ' .. msg)
end, true)

RegisterCommand('juno_unban', function(_, args)
    local ok, msg = doUnban(args[1] or '')
    print('[juno-admin] unban: ' .. msg)
end, true)

RegisterCommand('juno_bans', function()
    for _, ban in ipairs(Bans) do
        print(('[juno-admin] %s | %s | %s'):format(ban.name, ban.date or '?', ban.reason or ''))
    end
    print(('[juno-admin] %d ban(s) total'):format(#Bans))
end, true)

-- Admin actions ------------------------------------------------------------
local function resolvePlayer(data)
    if data.id then
        local src = tonumber(data.id)
        if src and GetPlayerName(src) then return src end
        return nil
    end
    if data.name and data.name ~= '' then
        local asId = tonumber(data.name)
        if asId and GetPlayerName(asId) then return asId end
        local needle = tostring(data.name):lower()
        for _, id in ipairs(GetPlayers()) do
            local n = GetPlayerName(id)
            if n and n:lower():find(needle, 1, true) then return tonumber(id) end
        end
    end
    return nil
end

local function doSpawnVeh(src, model, livery)
    if not model or model == '' then return false, 'no model given' end
    TriggerClientEvent('juno-admin:spawnVeh', src, model, tonumber(livery) or -1)
    return true, 'spawning ' .. model
end

local function doHeal(src)
    TriggerClientEvent('juno-admin:heal', src)
    return true, 'heal sent'
end

local function doRevive(src)
    if GetResourceState('bs_medical') == 'started' then
        local ok, res = pcall(function() return exports.bs_medical:Revive(src) end)
        if ok then return true, 'revive: ' .. tostring(res) end
        return false, 'bs_medical Revive errored'
    end
    return false, 'bs_medical not running'
end

local function doTp(src, data)
    local x, y, z = tonumber(data.x), tonumber(data.y), tonumber(data.z)
    if not (x and y and z) and data.to then
        local other = resolvePlayer({ id = data.to, name = data.to })
        if not other then return false, 'tp target not found' end
        local ped = GetPlayerPed(other)
        if ped == 0 then return false, 'tp target has no ped' end
        local c = GetEntityCoords(ped)
        x, y, z = c.x, c.y, c.z
    end
    if not (x and y and z) then return false, 'no coords or target' end
    TriggerClientEvent('juno-admin:tp', src, x, y, z)
    return true, ('teleported to %.1f, %.1f, %.1f'):format(x, y, z)
end

local function doGiveItem(src, item, count)
    if not item or item == '' then return false, 'no item given' end
    if GetResourceState('bs_inventory') ~= 'started' then return false, 'bs_inventory not running' end
    local given = exports.bs_inventory:GiveItem(src, item, tonumber(count) or 1)
    return given == true, given == true and 'gave ' .. item or 'give failed (unknown item or no space)'
end

local function doGiveWeapon(src, data)
    local weapon = tostring(data.weapon or '')
    if weapon == '' then return false, 'no weapon given' end
    TriggerClientEvent('juno-admin:giveweapon', src, weapon, tonumber(data.ammo) or 250)
    return true, 'gave weapon ' .. weapon
end

local COMPANION_ACTIONS = {
    spawn = true, despawn = true, follow = true, guard = true,
    ride = true, come = true, say = true, emote = true,
}

local function doCompanion(src, data)
    local action = tostring(data.action or '')
    if not COMPANION_ACTIONS[action] then return false, 'unknown companion action' end
    TriggerClientEvent('juno-admin:companion', src, action, {
        model = data.model, text = data.text, emote = data.emote,
    })
    return true, 'companion: ' .. action
end

local function doGiveMoney(src, account, amount)
    account = account == 'bank' and 'bank' or 'cash'
    amount = tonumber(amount) or 0
    if amount == 0 then return false, 'no amount' end
    exports.bs_core:AddMoney(src, account, amount, 'juno-admin')
    return true, ('gave $%d (%s)'):format(amount, account)
end

-- Perception: clients report what they see every ~2.5s (see client.lua).
-- /sense returns the freshest report for a player, so Juno and the owner's other
-- bots can perceive the world through the MCP server. Players in-game have no
-- access to any of this: the API is token-gated and the token never leaves the server host.
local Reports = {}

RegisterNetEvent('juno-admin:report', function(report)
    if type(report) == 'table' then
        Reports[source] = { at = os.time(), data = report }
    end
end)

AddEventHandler('playerDropped', function()
    Reports[source] = nil
end)

local function doSense(src)
    local r = Reports[src]
    if not r then
        TriggerClientEvent('juno-admin:sense', src)
        return false, 'no report yet - asked the client, try again in a few seconds'
    end
    return true, r
end

-- HTTP API
local function reply(res, code, tbl)
    res.writeHead(code, { ['Content-Type'] = 'application/json' })
    res.send(json.encode(tbl))
end

SetHttpHandler(function(req, res)
    if req.method ~= 'POST' then return reply(res, 405, { error = 'POST only' }) end
    req.setDataHandler(function(body)
        local ok, data = pcall(json.decode, body or '')
        if not ok or type(data) ~= 'table' then return reply(res, 400, { error = 'bad json' }) end
        if ApiToken == '' or data.token ~= ApiToken then
            print('[juno-admin] rejected API call to ' .. tostring(req.path) .. ' (bad token)')
            return reply(res, 403, { error = 'bad token' })
        end
        local path = req.path
        if path == '/players' then
            local out = {}
            for _, id in ipairs(GetPlayers()) do
                out[#out + 1] = { id = tonumber(id), name = GetPlayerName(id), ping = GetPlayerPing(id) }
            end
            return reply(res, 200, { players = out })
        elseif path == '/kick' then
            local okk, msg = doKick(data.id, data.reason)
            return reply(res, okk and 200 or 404, { ok = okk, result = msg })
        elseif path == '/ban' then
            local okk, msg = doBan(data.id, data.reason)
            return reply(res, okk and 200 or 404, { ok = okk, result = msg })
        elseif path == '/unban' then
            local okk, msg = doUnban(data.match)
            return reply(res, 200, { ok = okk, result = msg })
        elseif path == '/bans' then
            local out = {}
            for _, ban in ipairs(Bans) do
                out[#out + 1] = { name = ban.name, reason = ban.reason, date = ban.date, identifiers = ban.identifiers }
            end
            return reply(res, 200, { bans = out })
        elseif path == '/say' then
            print('[juno-admin] announce: ' .. tostring(data.message or ''))
            TriggerClientEvent('chat:addMessage', -1, { args = { 'Server', tostring(data.message or '') } })
            return reply(res, 200, { ok = true })
        elseif path == '/exec' then
            local cmd = tostring(data.command or '')
            if cmd == '' then return reply(res, 400, { ok = false, result = 'no command' }) end
            print('[juno-admin] exec: ' .. cmd)
            ExecuteCommand(cmd)
            return reply(res, 200, { ok = true, result = 'executed: ' .. cmd })
        elseif path == '/livery' then
            local src = resolvePlayer(data)
            if not src then return reply(res, 404, { ok = false, result = 'no such player' }) end
            TriggerClientEvent('juno-admin:livery', src, tonumber(data.livery) or -1)
            return reply(res, 200, { ok = true, result = 'livery applied: ' .. tostring(data.livery) })
        elseif path == '/spawnveh' or path == '/heal' or path == '/revive' or path == '/tp'
            or path == '/giveitem' or path == '/givemoney' or path == '/companion'
            or path == '/giveweapon' then
            local src = resolvePlayer(data)
            if not src then return reply(res, 404, { ok = false, result = 'no such player' }) end
            local okk, msg
            if path == '/spawnveh' then okk, msg = doSpawnVeh(src, data.model, data.livery)
            elseif path == '/heal' then okk, msg = doHeal(src)
            elseif path == '/revive' then okk, msg = doRevive(src)
            elseif path == '/tp' then okk, msg = doTp(src, data)
            elseif path == '/giveitem' then okk, msg = doGiveItem(src, data.item, data.count)
            elseif path == '/giveweapon' then okk, msg = doGiveWeapon(src, data)
            elseif path == '/givemoney' then okk, msg = doGiveMoney(src, data.account, data.amount)
            elseif path == '/companion' then okk, msg = doCompanion(src, data) end
            print(('[juno-admin] %s -> %s (%s): %s'):format(path, GetPlayerName(src) or '?', src, tostring(msg)))
            return reply(res, okk and 200 or 400, { ok = okk, result = msg })
        elseif path == '/sense' then
            local src = resolvePlayer(data)
            if not src then return reply(res, 404, { ok = false, result = 'no such player' }) end
            local good, r = doSense(src)
            if not good then return reply(res, 202, { ok = false, result = r }) end
            return reply(res, 200, { ok = true, player = GetPlayerName(src), ageSeconds = os.time() - r.at, sense = r.data })
        end
        return reply(res, 404, { error = 'unknown route' })
    end)
end)

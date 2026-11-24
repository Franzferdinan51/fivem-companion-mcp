-- juno-admin client helper: ped-level actions the server side cannot do alone.
-- These events are only ever fired by the juno-admin server resource.

RegisterNetEvent('juno-admin:spawnVeh', function(model, livery)
    livery = tonumber(livery) or -1
    local hash = GetHashKey(model)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        TriggerEvent('chat:addMessage', { args = { 'Juno', 'unknown vehicle model: ' .. tostring(model) } })
        return
    end
    RequestModel(hash)
    local tries = 0
    while not HasModelLoaded(hash) and tries < 100 do
        Wait(50)
        tries = tries + 1
    end
    if not HasModelLoaded(hash) then return end
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local veh = CreateVehicle(hash, coords.x + 2.0, coords.y + 2.0, coords.z + 0.5, GetEntityHeading(ped), true, false)
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleEngineOn(veh, true, true, false)
    SetPedIntoVehicle(ped, veh, -1)
    SetModelAsNoLongerNeeded(hash)
    if livery >= 0 then
        -- Apply AFTER the player is seated: same-frame-as-create mod calls get
        -- silently dropped on some models (seen live on the Scramjet).
        CreateThread(function()
            Wait(300)
            SetVehicleModKit(veh, 0)
            SetVehicleMod(veh, 48, livery, false)
            SetVehicleLivery(veh, livery)
        end)
    end
end)

RegisterNetEvent('juno-admin:livery', function(livery)
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh == 0 then return end
    livery = tonumber(livery) or -1
    if livery < 0 then return end
    SetVehicleModKit(veh, 0)
    SetVehicleMod(veh, 48, livery, false)
    SetVehicleLivery(veh, livery)
end)

RegisterNetEvent('juno-admin:heal', function()
    local ped = PlayerPedId()
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
    ClearPedWetness(ped)
end)

RegisterNetEvent('juno-admin:tp', function(x, y, z)
    local ped = PlayerPedId()
    SetEntityCoords(ped, x + 0.0, y + 0.0, z + 0.0, false, false, false, true)
end)

-- juno-companion ------------------------------------------------------------
-- A ped body for Juno, created and driven on this client (FiveM tasks only run
-- on the client that owns the ped). The server routes the operator's requests here
-- through the juno-admin bridge. One companion, bound to this player.
local Companion = { ped = nil, mode = 'idle', bubble = nil, bubbleUntil = 0 }

local SCENARIOS = {
    sit = 'PROP_HUMAN_SEAT_CHAIR_MP_PLAYER',
    lean = 'WORLD_HUMAN_LEANING',
    smoke = 'WORLD_HUMAN_SMOKING',
    guard = 'WORLD_HUMAN_GUARD_STAND',
    cheer = 'WORLD_HUMAN_CHEERING',
    clipboard = 'WORLD_HUMAN_CLIPBOARD',
    drink = 'WORLD_HUMAN_DRINKING',
    coffee = 'WORLD_HUMAN_AA_COFFEE',
    phone = 'WORLD_HUMAN_STAND_MOBILE',
    music = 'WORLD_HUMAN_MUSICIAN',
}

local function companionAlive()
    return Companion.ped and DoesEntityExist(Companion.ped)
end

local function deleteCompanion()
    if companionAlive() then DeleteEntity(Companion.ped) end
    Companion.ped = nil
    Companion.mode = 'idle'
end

local function spawnCompanion(model)
    deleteCompanion()
    local hash = GetHashKey(model or 'a_m_m_business_01')
    if not IsModelInCdimage(hash) or not IsModelAPed(hash) then return end
    RequestModel(hash)
    local tries = 0
    while not HasModelLoaded(hash) and tries < 100 do Wait(50) tries = tries + 1 end
    if not HasModelLoaded(hash) then return end
    local me = PlayerPedId()
    local c = GetEntityCoords(me)
    local ped = CreatePed(4, hash, c.x + 1.5, c.y + 1.5, c.z, GetEntityHeading(me), true, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetPedRelationshipGroupHash(ped, GetPedRelationshipGroupHash(me))
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetEntityInvincible(ped, true)
    SetPedCanRagdoll(ped, false)
    Companion.ped = ped
    Companion.mode = 'idle'
    SetModelAsNoLongerNeeded(hash)
end

local function companionFollow()
    if not companionAlive() then return end
    ClearPedTasks(Companion.ped)
    TaskFollowToOffsetOfEntity(Companion.ped, PlayerPedId(), 1.2, -1.2, 0.0, 2.4, -1, 2.0, true)
    Companion.mode = 'follow'
end

local function companionGuard()
    if not companionAlive() then return end
    local ped = Companion.ped
    GiveWeaponToPed(ped, GetHashKey('WEAPON_CARBINERIFLE'), 250, false, true)
    SetPedCombatAttributes(ped, 46, true)
    SetPedCombatAttributes(ped, 5, true)
    SetPedCombatRange(ped, 2)
    SetPedFleeAttributes(ped, 0, false)
    companionFollow()
    Companion.mode = 'guard'
end

local function companionRide()
    if not companionAlive() then return end
    local me = PlayerPedId()
    local veh = GetVehiclePedIsIn(me, false)
    if veh == 0 then
        local c = GetEntityCoords(me)
        veh = GetClosestVehicle(c.x, c.y, c.z, 9.0, 0, 71)
    end
    if veh == 0 then return end
    ClearPedTasks(Companion.ped)
    TaskEnterVehicle(Companion.ped, veh, -1, 0, 2.0, 1, 0)
    Companion.mode = 'ride'
end

RegisterNetEvent('juno-admin:companion', function(action, data)
    data = data or {}
    if action == 'spawn' then spawnCompanion(data.model)
    elseif action == 'despawn' then deleteCompanion()
    elseif action == 'follow' then companionFollow()
    elseif action == 'guard' then companionGuard()
    elseif action == 'ride' then companionRide()
    elseif action == 'come' then
        if companionAlive() then
            local c = GetEntityCoords(PlayerPedId())
            SetEntityCoords(Companion.ped, c.x + 1.5, c.y + 1.5, c.z, false, false, false, true)
            if Companion.mode == 'follow' or Companion.mode == 'guard' then companionFollow() end
        end
    elseif action == 'say' then
        local text = tostring(data.text or '')
        TriggerEvent('chat:addMessage', { color = { 255, 170, 0 }, args = { 'Juno', text } })
        Companion.bubble = text
        Companion.bubbleUntil = GetGameTimer() + 6000
    elseif action == 'emote' then
        if companionAlive() then
            local name = tostring(data.emote or ''):lower()
            if name == 'stop' then
                ClearPedTasks(Companion.ped)
                Companion.mode = 'idle'
            else
                local scenario = SCENARIOS[name] or name
                ClearPedTasks(Companion.ped)
                TaskStartScenarioInPlace(Companion.ped, scenario, 0, true)
                Companion.mode = 'emote'
            end
        end
    end
end)

-- Perception reporting: every ~2.5s tell the server what this client sees, so
-- Juno (or any of the owner's bots, via the MCP server) can perceive the world:
-- player state, companion state, and what's nearby. Also answers on demand.
local function buildReport()
    local me = PlayerPedId()
    local mc = GetEntityCoords(me)
    local veh = GetVehiclePedIsIn(me, false)
    local report = {
        player = {
            x = math.floor(mc.x * 10) / 10, y = math.floor(mc.y * 10) / 10, z = math.floor(mc.z * 10) / 10,
            heading = math.floor(GetEntityHeading(me)),
            health = GetEntityHealth(me), maxHealth = GetEntityMaxHealth(me),
            inVehicle = veh ~= 0,
            vehicle = veh ~= 0 and GetDisplayNameFromVehicleModel(GetEntityModel(veh)) or nil,
            speed = math.floor(GetEntitySpeed(me) * 2.237), -- mph
        },
        companion = nil,
        nearby = { peds = 0, vehicles = 0, closestPed = nil },
    }
    if companionAlive() then
        local ped = Companion.ped
        local cc = GetEntityCoords(ped)
        local cveh = GetVehiclePedIsIn(ped, false)
        report.companion = {
            x = math.floor(cc.x * 10) / 10, y = math.floor(cc.y * 10) / 10, z = math.floor(cc.z * 10) / 10,
            mode = Companion.mode,
            health = GetEntityHealth(ped),
            inVehicle = cveh ~= 0,
            distance = math.floor(#(mc - cc) * 10) / 10,
        }
    end
    local peds = GetGamePool('CPed')
    local closest = nil
    local pedCount = 0
    for _, p in ipairs(peds) do
        if p ~= me and p ~= Companion.ped and not IsPedAPlayer(p) then
            local d = #(mc - GetEntityCoords(p))
            if d <= 60.0 then
                pedCount = pedCount + 1
                if not closest or d < closest then closest = d end
            end
        end
    end
    report.nearby.peds = pedCount
    report.nearby.closestPed = closest and (math.floor(closest * 10) / 10) or nil
    local vehs = GetGamePool('CVehicle')
    local vCount = 0
    for _, v in ipairs(vehs) do
        if #(mc - GetEntityCoords(v)) <= 60.0 then vCount = vCount + 1 end
    end
    report.nearby.vehicles = vCount
    return report
end

RegisterNetEvent('juno-admin:sense', function()
    TriggerServerEvent('juno-admin:report', buildReport())
end)

CreateThread(function()
    while true do
        Wait(2500)
        if NetworkIsPlayerActive(PlayerId()) then
            TriggerServerEvent('juno-admin:report', buildReport())
        end
    end
end)

-- Name tag + speech bubble over the companion's head.
CreateThread(function()
    while true do
        Wait(0)
        if companionAlive() then
            local ped = Companion.ped
            local pc = GetEntityCoords(PlayerPedId())
            local cc = GetEntityCoords(ped)
            if #(pc - cc) < 30.0 then
                local label = 'Juno'
                if GetGameTimer() < Companion.bubbleUntil and Companion.bubble then
                    label = Companion.bubble
                end
                SetDrawOrigin(cc.x, cc.y, cc.z + 1.05, 0)
                SetTextFont(4)
                SetTextScale(0.35, 0.35)
                SetTextColour(255, 170, 0, 215)
                SetTextCentre(true)
                SetTextEntry('STRING')
                AddTextComponentString(label)
                DrawText(0.0, 0.0)
                ClearDrawOrigin()
            else
                Wait(500)
            end
        else
            Wait(1000)
        end
    end
end)

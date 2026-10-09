-- Rayfield Gen2: features from this conversation, excluding the example GUI.
-- Saved automation toggles resume when this script runs. Client requests remain subject to server validation.
-- This uses the user's external loader; it is not a standard Studio LocalScript.

local LOBBY_PLACE_ID = 117949143041402
local function inLobbyPlace() return game.PlaceId == LOBBY_PLACE_ID end

local CONFIG = {
    ScriptURL = "", -- Raw HTTPS URL serving this entire Lua file
    HostUsername = "ILY_Byeol", -- Actual username, not DisplayName
    RoomName = "ILY_Byeol_Room", -- Exact lobby identifier expected by the server
    BuyInterval = 5, -- Seconds after each complete purchase pass
    JoinDelay = 1.5,
    StartDelay = 5,
    UltimateInterval = 5,
    UltimateSellDelay = 2,
    LeaveMinute = 5, -- Every hour at xx:05, device local time
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
assert(player, "Run this on the client.")

local env = (getgenv and getgenv()) or _G
local previous = env.ConversationAutomation
if previous and previous.stop then previous.stop() end

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()
local window = Rayfield:CreateWindow({
    name = "AM",
    subtitle = "Shop • Lobby • Hourly Leave",
    sidebarLayout = true,
})

local session = { alive = true }
env.ConversationAutomation = session
local state = { gems = false, coins = false, lobby = false, leave = false, antiAfk = false, autoExecute = false }
local versions = { gems = 0, coins = 0, lobby = 0 }
local controls = {}
local characters = {
    { name = "JoGo (Six-eye)", sell = true, enabled = false, version = 0 },
    { name = "Yuto (Pure Love)", sell = false, enabled = false, version = 0 },
    { name = "Elforia (Frozen Empress)", sell = false, enabled = false, version = 0 },
}
local ultimateStatus
local ultimateControls = {}
local autoExecuteControl
local teleportConnection
local leaveControl
local antiAfkControl
local antiAfkVersion = 0
local releaseSpace = function() end
local configControls, itemControls, currencyControls = {}, {}, {}
local HttpService = game:GetService("HttpService")
local saveFolder = "GameAutomationSettings"
local savePath = saveFolder .. "/" .. tostring(player.UserId) .. ".json"
local savedCurrencies = { gems = false, coins = false }
local selectedItems = {}
local defaults = {}
for key, value in pairs(CONFIG) do defaults[key] = value end
local saveStatus
local ready = false
local applying = false
local dirty = false
local changeVersion = 0
local saveSettings -- assigned after the item list exists
local function queueSave()
    if not ready or applying then return end
    dirty = true
    changeVersion = changeVersion + 1
    local token = changeVersion
    task.delay(0.75, function()
        if session.alive and token == changeVersion and dirty then saveSettings() end
    end)
end
local shopStatus, lobbyStatus, leaveStatus
local lobbyBusy = false
local buyBusy = false

local function alive()
    return session.alive and not window.unloaded
end

local function status(control, message)
    if alive() and control then control:Set(message) end
    print("[Automation] " .. message)
end

local function waitWhile(seconds, allowed)
    local deadline = os.clock() + seconds
    repeat
        if not alive() or not allowed() then return false end
        task.wait(math.min(0.1, math.max(0, deadline - os.clock())))
    until os.clock() >= deadline
    return alive() and allowed()
end

-- Resolve only when needed: missing game-specific remotes cannot freeze the GUI.
local function remote(folderName, name, className)
    local folder = ReplicatedStorage:FindFirstChild(folderName)
    local object = folder and folder:FindFirstChild(name)
    assert(object and object:IsA(className), folderName .. "." .. name .. " unavailable")
    return object
end

local function toggle(tab, name, callback)
    local control = tab:CreateToggle({
        name = name, value = false, forgetState = true,
        callback = function(value)
            if alive() then callback(value); queueSave() end
        end,
    })
    table.insert(controls, control)
    return control
end

local home = window:CreateTab({ name = "Home", icon = 93364949241311, forgetState = true })
local shop = window:CreateTab({ name = "Auto Buy", forgetState = true })
local lobby = window:CreateTab({ name = "Lobby", forgetState = true })
local leave = window:CreateTab({ name = "Hourly Leave", forgetState = true })

home:CreateText({ name = "Getting started", text =
    "Auto Buy: select items, then turn on Gems, Coins, or both. " ..
    "Lobby: enter the host username and room identifier, then enable on each client. " ..
    "Hourly Leave: enable to send one leave request each hour at the chosen minute. " ..
    "Settings and saved ON/OFF states load automatically; enabled features resume. Requests already sent cannot be cancelled." })

local function disableAll()
    state.gems, state.coins, state.lobby, state.leave, state.antiAfk = false, false, false, false, false
    antiAfkVersion = antiAfkVersion + 1
    releaseSpace()
    state.autoExecute = false
    for key in pairs(versions) do versions[key] = versions[key] + 1 end
    for _, character in ipairs(characters) do
        character.enabled = false
        character.version = character.version + 1
    end
    if ultimateStatus then status(ultimateStatus, "Auto Ultimate OFF; pending sales cancelled") end
    for _, control in ipairs(controls) do control:Set(false, true) end
end

home:CreateButton({ name = "Turn everything OFF", callback = function()
    disableAll()
    -- Item selections are also cleared below by resetting their state.
    if session.clearItems then session.clearItems() end
    queueSave()
    status(shopStatus, "Auto Buy OFF")
    status(lobbyStatus, "Lobby OFF; pending start/join cancelled")
    status(leaveStatus, "Hourly Leave OFF")
end })

session.stop = function()
    if ready and dirty then saveSettings() end
    if teleportConnection then teleportConnection:Disconnect() end
    session.alive = false
    state.gems, state.coins, state.lobby, state.leave, state.antiAfk = false, false, false, false, false
    antiAfkVersion = antiAfkVersion + 1
    releaseSpace()
    if window.Unload then pcall(function() window:Unload() end) end
end

-- AUTO BUY
shop:CreateText({ name = "Shop location", text = "Required PlaceId: " .. LOBBY_PLACE_ID
    .. " / Current: " .. tostring(game.PlaceId)
    .. (inLobbyPlace() and " — shop enabled here" or " — buying idle here") })
shop:CreateSection({ name = "Currencies" })
shop:CreateText({ text = "Selected items are requested once per enabled currency each pass. Both currencies can be spent. Coins only work for items the server allows." })
shopStatus = shop:CreateText({ name = "Shop status", text = "OFF — select items and a currency" })
for _, currency in ipairs({ "Gems", "Coins" }) do
    local key = currency:lower()
    currencyControls[key] = toggle(shop, "Auto Buy with " .. currency, function(value)
        state[key] = value
        savedCurrencies[key] = value
        queueSave()
        versions[key] = versions[key] + 1
        status(shopStatus, currency .. " purchases " .. (value and "ON" or "OFF"))
    end)
end

configControls.BuyInterval = shop:CreateSlider({ name = "Buy interval", range = {1, 60}, increment = 1,
    value = CONFIG.BuyInterval, suffix = " sec", forgetState = true,
    callback = function(value) CONFIG.BuyInterval = value; queueSave() end })

local items = {
    { id = "StatReroll", amount = 10 },
    { id = "StatRerollAll", amount = 10 },
    { id = "Trait", amount = 3 },
    { id = "RareShard", amount = 10 },
    { id = "EpicShard", amount = 7 },
    { id = "LegendShard", amount = 5 },
    { id = "MythicShard", amount = 3 },
}
session.clearItems = function()
    for _, item in ipairs(items) do item.enabled = false; selectedItems[item.id] = false end
end
local stockControls, stockMessages = {}, {}
shop:CreateText({ name = "Stock checks", text = "Reads GemsShop.Main and Main.MainFrame.GoldShop item TextLabel. Assumes Inventory: remaining/maximum. Zero stock is skipped. Missing/unreadable labels are reported as unknown and use the original request amount. GUI stock may be stale until the shop opens." })
shop:CreateSection({ name = "Items — original quantities" })
for _, item in ipairs(items) do
    item.enabled = false
    itemControls[item.id] = toggle(shop, item.id .. " × " .. item.amount, function(value)
        item.enabled = value
        selectedItems[item.id] = value
        queueSave()
    end)
    stockMessages[item.id] = { Gems = "not checked", Coins = "not checked" }
    stockControls[item.id] = shop:CreateText({ name = item.id .. " stock", text = "Gems: not checked | Coins: not checked" })
end

local function readStock(itemId, currency)
    local gui = player:FindFirstChild("PlayerGui")
    local list
    if currency == "Coins" then
        local main = gui and gui:FindFirstChild("Main")
        local frame = main and main:FindFirstChild("MainFrame")
        local goldShop = frame and frame:FindFirstChild("GoldShop")
        list = goldShop and goldShop:FindFirstChild("ScrollingFrame")
    elseif currency == "Gems" then
        local gemsShop = gui and gui:FindFirstChild("GemsShop")
        local main = gemsShop and gemsShop:FindFirstChild("Main")
        list = main and main:FindFirstChild("ScrollingFrame")
    end
    local entry = list and list:FindFirstChild(itemId)
    local label = entry and entry:FindFirstChild("TextLabel")
    if not label or not (label:IsA("TextLabel") or label:IsA("TextButton")) then
        return nil, "label missing"
    end
    local plain = label.Text:gsub("<[^>]*>", "")
    local remaining, maximum = plain:match("(%d+)%s*/%s*(%d+)")
    remaining, maximum = tonumber(remaining), tonumber(maximum)
    if not remaining or not maximum or remaining > maximum then
        return nil, "unreadable stock text"
    end
    return remaining
end

local function showStock(itemId, currency, message)
    stockMessages[itemId][currency] = message
    if alive() then
        stockControls[itemId]:Set("Gems: " .. stockMessages[itemId].Gems
            .. " | Coins: " .. stockMessages[itemId].Coins)
    end
end

-- Serialize background and pre-lobby purchase passes.
-- A yielding BuyItem call must return before creation/join can proceed.
local function purchasePass(allowed)
    if not inLobbyPlace() then return false, "Not in the shop/lobby place" end
    while buyBusy do
        if not waitWhile(0.1, allowed) then return false, "Cancelled" end
    end
    if not alive() or not allowed() then return false, "Cancelled" end
    buyBusy = true
    local passVersions = { gems = versions.gems, coins = versions.coins }
    local failed, attempted = false, 0
    local ok, err = pcall(function()
        for _, item in ipairs(items) do
            for _, currency in ipairs({ "Gems", "Coins" }) do
                if not alive() or not allowed() or not inLobbyPlace() then return end
                local key = currency:lower()
                if item.enabled and state[key] and versions[key] == passVersions[key] then
                    local before, reason = readStock(item.id, currency)
                    if before == 0 then
                        showStock(item.id, currency, "0 remaining — skipped")
                    else
                        local amount = before and math.min(item.amount, before) or item.amount
                        showStock(item.id, currency, before and (before .. " remaining; requesting " .. amount)
                            or ("unknown (" .. reason .. "); requesting " .. amount))
                        attempted = attempted + 1
                        local requestOK, result = pcall(function()
                            return remote("Remotes", "BuyItem", "RemoteFunction")
                                :InvokeServer(item.id, amount, currency)
                        end)
                        if not requestOK or result == false then failed = true end
                        if not alive() or not allowed() then return end
                        -- Allow up to one second for replicated GUI stock to update.
                        local after = readStock(item.id, currency)
                        if requestOK and result ~= false and before ~= nil then
                            local deadline = os.clock() + 1
                            while after == before and os.clock() < deadline do
                                if not waitWhile(0.1, allowed) then return end
                                after = readStock(item.id, currency)
                            end
                        end
                        if not requestOK then
                            showStock(item.id, currency, "request error: " .. tostring(result))
                        elseif result == false then
                            showStock(item.id, currency, "request rejected; stock " .. tostring(after or "unknown"))
                        elseif before and after and after < before then
                            showStock(item.id, currency, "stock " .. before .. " → " .. after
                                .. (after == 0 and " — sold out" or " remaining"))
                        else
                            showStock(item.id, currency, "stock " .. tostring(after or "unknown")
                                .. "; request returned " .. tostring(result) .. " (purchase unconfirmed)")
                        end
                        status(shopStatus, "Checked " .. item.id .. " / " .. currency)
                        if not waitWhile(0.2, allowed) then return end
                    end
                end
            end
        end
    end)
    buyBusy = false
    if not alive() or not allowed() then return false, "Cancelled" end
    if not ok then return false, tostring(err) end
    if failed then
        status(shopStatus, "Purchase pass finished with rejected/error responses; see individual item status. Continuing lobby setup.")
    end
    return true, attempted
end

task.spawn(function()
    while alive() do
        if inLobbyPlace() and (state.gems or state.coins) and not lobbyBusy then
            purchasePass(function() return not lobbyBusy and (state.gems or state.coins) end)
            waitWhile(CONFIG.BuyInterval, function()
                return not lobbyBusy and (state.gems or state.coins)
            end)
        else
            task.wait(0.2)
        end
    end
end)

-- LOBBY: host creates once; guests retry explicit join failures while enabled.
local rewards = {
    Items = {
        { Chance = 40, Min = 1, Max = 5, Id = "CursedFragment" },
        { Chance = 100, Min = 1, Max = 1, Id = "SukunaEvo" },
        { Chance = 5, Min = 1, Max = 1, Id = "YutaEvo" },
        { Chance = 100, Min = 1, Max = 2, Id = "Fruit_3" },
    },
    Gems = 40, Coins = 20,
    Units = {},
}
for _, entry in ipairs({ {"Normal", 0.0025}, {"Hard", 0.05}, {"Nightmare", 0.25} }) do
    table.insert(rewards.Units, {
        PityMax = 2, Id = "unit_005", ShinyChance = 100,
        Difficulty = {entry[1]}, IsBlack = true, Chance = entry[2],
        Max = 1, PityMin = 1, Min = 1,
    })
end

lobby:CreateSection({ name = "Host and room" })
lobby:CreateText({ text = "First completes a purchase pass for selected items with enabled currencies. Host then creates/configures, waits 5 seconds, and starts. Other clients wait 1.5 seconds and retry failed joins every 1.5 seconds while ON. Delays begin on each client; no membership check. Edit settings while OFF, then enable." })
configControls.HostUsername = lobby:CreateInput({ name = "Host username", value = CONFIG.HostUsername, forgetState = true,
    callback = function(value) CONFIG.HostUsername = tostring(value):match("^%s*(.-)%s*$"); queueSave() end })
configControls.RoomName = lobby:CreateInput({ name = "Room identifier", value = CONFIG.RoomName, forgetState = true,
    callback = function(value) CONFIG.RoomName = tostring(value):match("^%s*(.-)%s*$"); queueSave() end })
configControls.JoinDelay = lobby:CreateSlider({ name = "Join delay", range = {0, 10}, increment = 0.1,
    value = CONFIG.JoinDelay, suffix = " sec", forgetState = true,
    callback = function(value) CONFIG.JoinDelay = value; queueSave() end })
configControls.StartDelay = lobby:CreateSlider({ name = "Host start delay", range = {1, 60}, increment = 1,
    value = CONFIG.StartDelay, suffix = " sec", forgetState = true,
    callback = function(value) CONFIG.StartDelay = value; queueSave() end })
lobbyStatus = lobby:CreateText({ name = "Lobby status", text = "OFF" })
local lobbyControl

lobbyControl = toggle(lobby, "Enable create / join / delayed start", function(value)
    state.lobby = value
    versions.lobby = versions.lobby + 1
    local token = versions.lobby
    if not value then
        status(lobbyStatus, "OFF — pending lobby actions cancelled")
        return
    end
    if not inLobbyPlace() then
        status(lobbyStatus, "ON — lobby actions idle here; required PlaceId: " .. LOBBY_PLACE_ID)
        return
    end
    local function reject(message)
        state.lobby = false
        if lobbyControl then lobbyControl:Set(false, true) end
        status(lobbyStatus, message)
    end
    if lobbyBusy then
        reject("Previous lobby request is still pending. Try again once it returns.")
        return
    end
    local host, room = CONFIG.HostUsername, CONFIG.RoomName
    local isHost = player.Name:lower() == host:lower()
    if host == "" or host == "XXX" or (not isHost and (room == "" or room:lower() == "xxx_room")) then
        reject("Enter the real host username and room identifier first.")
        return
    end
    local joinDelay, startDelay = CONFIG.JoinDelay, CONFIG.StartDelay
    local function active() return state.lobby and versions.lobby == token and inLobbyPlace() end
    lobbyBusy = true
    task.spawn(function()
        local ok, err = pcall(function()
            if not alive() or not active() then return end
            status(lobbyStatus, "Buying selected items before lobby setup...")
            local bought, detail = purchasePass(active)
            if not alive() or not active() then return end
            if not bought then
                status(lobbyStatus, "Lobby paused, still ON: " .. tostring(detail)
                    .. ". Fix shop settings, then toggle lobby OFF/ON to retry.")
                return
            end
            status(lobbyStatus, "Purchase pass finished (" .. detail .. " requests); proceeding")
            if isHost then
                status(lobbyStatus, "Requesting lobby creation...")
                local result = remote("Remotes", "RequestJoinLobby", "RemoteFunction"):InvokeServer("Create")
                if not alive() or not active() then return end
                if result == false then error("Server returned false for Create") end
                remote("Remotes", "UpdateLobbySettings", "RemoteEvent"):FireServer(
                    "Tokyo Jujutsu High (Event)", 1, rewards, "Nightmare", "CursedAcademy", "Event")
                status(lobbyStatus, "Settings sent; starting in " .. startDelay .. " seconds")
                if not waitWhile(startDelay, active) then return end
                remote("Remotes", "TeleportRequest", "RemoteEvent"):FireServer(
                    97246719761307, "Event", "CursedAcademy", 1, "Nightmare")
                status(lobbyStatus, "Start request sent; toggle OFF/ON for another attempt")
            else
                status(lobbyStatus, "Joining in " .. joinDelay .. " seconds...")
                if not waitWhile(joinDelay, active) then return end
                while alive() and active() do
                    local joinOK, result = pcall(function()
                        return remote("Remotes", "RequestJoinLobby", "RemoteFunction")
                            :InvokeServer("Join", room)
                    end)
                    if not alive() or not active() then return end
                    if joinOK and result ~= false then
                        -- The response format is unknown. A non-false return ends retries,
                        -- but does not prove membership. Keep the toggle ON.
                        status(lobbyStatus, "Join request returned: " .. tostring(result)
                            .. "; toggle remains ON (membership not verified)")
                        return
                    end
                    status(lobbyStatus, "Join failed: " .. tostring(result)
                        .. "; still ON, retrying in 1.5 seconds")
                    if not waitWhile(1.5, active) then return end
                end
            end
        end)
        lobbyBusy = false
        if not ok and alive() and active() then
            status(lobbyStatus, "Lobby error: " .. tostring(err)
                .. "; toggle remains ON. Toggle OFF/ON to try again.")
        end
    end)
end)

-- HOURLY LEAVE: once per local calendar hour while inside the chosen minute.
leave:CreateText({ text = "Default: xx:05 every hour using this device's local clock. Enabling during that minute triggers immediately. Leaving/teleporting ends this script; it does not automatically reload." })
leaveStatus = leave:CreateText({ name = "Leave status", text = "OFF" })
configControls.LeaveMinute = leave:CreateSlider({ name = "Minute each hour", range = {0, 59}, increment = 1,
    value = CONFIG.LeaveMinute, forgetState = true,
    callback = function(value) CONFIG.LeaveMinute = value; queueSave() end })
leaveControl = toggle(leave, "Hourly leave ON / OFF", function(value)
    state.leave = value
    status(leaveStatus, value and string.format("ON — scheduled for xx:%02d", CONFIG.LeaveMinute) or "OFF")
end)

local lastTriggeredHour
task.spawn(function()
    while alive() do
        if state.leave then
            local now = os.date("*t")
            local hour = string.format("%04d-%02d-%02d-%02d", now.year, now.month, now.day, now.hour)
            if now.min == CONFIG.LeaveMinute and hour ~= lastTriggeredHour then
                lastTriggeredHour = hour
                local ok, err = pcall(function()
                    remote("GameEvents", "LeaveGameRequest", "RemoteEvent"):FireServer()
                end)
                status(leaveStatus, ok and ("Leave request sent at " .. os.date("%H:%M:%S"))
                    or ("Leave error: " .. tostring(err)))
            end
        end
        task.wait(0.5)
    end
end)


-- AUTO ULTIMATE: use the supplied DisplayName matching; only JoGo may sell.
local ultimate = window:CreateTab({ name = "Auto Ultimate", forgetState = true })
ultimate:CreateText({ text = "Activate matching units every 5 seconds. JoGo sells 2 seconds after the ultimate request; Yuto and Elforia never sell. OFF cancels pending sales. Timing and ON/OFF settings save per account and resume on load." })
ultimateStatus = ultimate:CreateText({ name = "Ultimate status", text = "OFF" })
configControls.UltimateInterval = ultimate:CreateSlider({ name = "Ultimate interval",
    range = {1, 60}, increment = 1, value = CONFIG.UltimateInterval, suffix = " sec", forgetState = true,
    callback = function(value) CONFIG.UltimateInterval = value; queueSave() end })
configControls.UltimateSellDelay = ultimate:CreateSlider({ name = "JoGo sell delay",
    range = {0.5, 10}, increment = 0.5, value = CONFIG.UltimateSellDelay, suffix = " sec", forgetState = true,
    callback = function(value) CONFIG.UltimateSellDelay = value; queueSave() end })
for _, character in ipairs(characters) do
    ultimateControls[character.name] = toggle(ultimate, character.name .. (character.sell and " + Sell" or " — Ultimate only"), function(value)
        character.enabled = value
        character.version = character.version + 1
        status(ultimateStatus, character.name .. (value and " ON" or " OFF — pending sale cancelled"))
    end)
end

local function unitDisplayName(unit)
    local attribute = unit:GetAttribute("DisplayName")
    if type(attribute) == "string" then return attribute end
    local value = unit:FindFirstChild("DisplayName")
    if value and value:IsA("StringValue") then return value.Value end
    return nil
end
local pendingSales = {}
local function activateUltimate(unit, character, units)
    if pendingSales[unit] or not alive() or not character.enabled then return end
    local ok, err = pcall(function()
        remote("GameEvents", "UseUltimateEvent", "RemoteEvent"):FireServer(unit)
    end)
    if not ok then status(ultimateStatus, "Ultimate request failed: " .. tostring(err)); return end
    status(ultimateStatus, "Ultimate requested: " .. character.name)
    if not character.sell then return end
    local token = character.version
    pendingSales[unit] = true
    task.delay(CONFIG.UltimateSellDelay, function()
        local sellOK, sellError = pcall(function()
            if alive() and character.enabled and character.version == token
                and unit.Parent == units and unitDisplayName(unit) == character.name then
                remote("GameEvents", "SellUnitRequest", "RemoteEvent"):FireServer(unit)
                status(ultimateStatus, "Sell requested: " .. character.name)
            end
        end)
        pendingSales[unit] = nil
        if not sellOK and alive() then status(ultimateStatus, "Sell request failed: " .. tostring(sellError)) end
    end)
end

-- Stop the standalone GUI's worker through its existing Destroying handler.
local playerGui = player:FindFirstChild("PlayerGui")
local oldUltimateGui = playerGui and playerGui:FindFirstChild("AutoUltimateGui")
if oldUltimateGui then oldUltimateGui:Destroy() end

task.spawn(function()
    while alive() do
        local anyEnabled = false
        for _, character in ipairs(characters) do
            if character.enabled then anyEnabled = true; break end
        end
        if anyEnabled then
            local map = workspace:FindFirstChild("CursedAcademy")
            local units = map and map:FindFirstChild("PlayerFolder")
            if units then
                for _, unit in ipairs(units:GetChildren()) do
                    local displayName = unitDisplayName(unit)
                    for _, character in ipairs(characters) do
                        if character.enabled and displayName == character.name then
                            activateUltimate(unit, character, units)
                            break
                        end
                    end
                end
            else
                status(ultimateStatus, "Waiting for CursedAcademy.PlayerFolder; toggles stay ON")
            end
            waitWhile(CONFIG.UltimateInterval, function() return true end)
        else
            task.wait(0.2)
        end
    end
end)

-- ANTI AFK: user's virtual Space input, independent of PlaceId.
local antiAfk = window:CreateTab({ name = "Anti AFK", forgetState = true })
antiAfk:CreateText({ text = "Sends Space every 10 seconds, holding it for 0.1 seconds. Skips while typing. Uses CreateVirtualInput when available. ON/OFF saves per account. Preventing the game's idle kick is not guaranteed." })
local afkStatus = antiAfk:CreateText({ name = "Anti AFK status", text = "OFF" })
local inputService = game:GetService("UserInputService")
local virtualInput
local spaceHeld = false
releaseSpace = function()
    if not spaceHeld or not virtualInput then return end
    local ok, err = pcall(function()
        virtualInput:SendKey(false, Enum.KeyCode.Space, false)
    end)
    if ok then spaceHeld = false
    elseif alive() then status(afkStatus, "Space release failed; will retry: " .. tostring(err)) end
end
antiAfkControl = toggle(antiAfk, "Anti AFK ON / OFF", function(value)
    state.antiAfk = value
    antiAfkVersion = antiAfkVersion + 1
    if not value then releaseSpace() end
    status(afkStatus, value and "ON — Space every 10 seconds" or "OFF")
end)
task.spawn(function()
    while alive() do
        -- Retry an unsuccessful key release even after OFF.
        if spaceHeld then releaseSpace() end
        if state.antiAfk then
            local token = antiAfkVersion
            local function active() return state.antiAfk and antiAfkVersion == token end
            if waitWhile(10, active) then
                if inputService:GetFocusedTextBox() then
                    status(afkStatus, "Skipped — typing in a text box")
                else
                    local ok, err = pcall(function()
                        if not virtualInput then virtualInput = inputService:CreateVirtualInput() end
                        assert(virtualInput, "Virtual input unavailable in this environment")
                        if not alive() or not active() then return end
                        spaceHeld = true
                        virtualInput:SendKey(true, Enum.KeyCode.Space, false)
                        waitWhile(0.1, active)
                    end)
                    releaseSpace()
                    if alive() and active() then
                        status(afkStatus, ok and "Space input sent" or ("Input unavailable/blocked: " .. tostring(err)))
                    end
                end
            end
        else
            task.wait(0.2)
        end
    end
    releaseSpace()
end)

-- PER-ACCOUNT LOCAL SETTINGS (Volt workspace).
-- Only allowlisted settings are decoded. No code is loaded from JSON.
local function filesAvailable()
    return type(isfolder) == "function" and type(makefolder) == "function"
        and type(isfile) == "function" and type(readfile) == "function"
        and type(writefile) == "function"
end

local function saveMessage(message)
    status(saveStatus, message)
end

local function validateSettings(data)
    assert(type(data) == "table" and data.version == 1, "Unsupported settings format")
    assert(data.userId == tostring(player.UserId), "Settings belong to another account")
    assert(type(data.config) == "table", "Missing settings")
    local result = { config = {}, items = {}, currencies = {}, automation = {}, ultimate = {} }
    local bounds = {
        BuyInterval = {1, 60, 1}, JoinDelay = {0, 10, 0.1},
        UltimateInterval = {1, 60, 1}, UltimateSellDelay = {0.5, 10, 0.5},
        StartDelay = {1, 60, 1}, LeaveMinute = {0, 59, 1},
    }
    for key, fallback in pairs(defaults) do
        local value = data.config[key]
        if bounds[key] then
            local limits = bounds[key]
            if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
                value = fallback
            end
            value = math.max(limits[1], math.min(limits[2], value))
            value = math.floor(value / limits[3] + 0.5) * limits[3]
        elseif type(value) ~= "string" or #value > (key == "ScriptURL" and 2048 or 200) then
            value = fallback
        end
        result.config[key] = value
    end
    for _, item in ipairs(items) do
        result.items[item.id] = type(data.items) == "table" and data.items[item.id] == true
    end
    for _, key in ipairs({"gems", "coins"}) do
        result.currencies[key] = type(data.currencies) == "table" and data.currencies[key] == true
    end
    local automation = type(data.automation) == "table" and data.automation or {}
    for _, key in ipairs({"gems", "coins", "lobby", "leave", "antiAfk", "autoExecute"}) do
        result.automation[key] = automation[key] == true
    end
    -- Older files stored currency preferences, but not lobby/ultimate states.
    if data.automation == nil then
        result.automation.gems = result.currencies.gems
        result.automation.coins = result.currencies.coins
    end
    for _, character in ipairs(characters) do
        result.ultimate[character.name] = type(data.ultimate) == "table"
            and data.ultimate[character.name] == true
    end
    return result
end

saveSettings = function()
    if not filesAvailable() then
        saveMessage("File saving unavailable in this environment")
        return false
    end
    local ok, err = pcall(function()
        if not isfolder(saveFolder) then makefolder(saveFolder) end
        local ultimateStates = {}
        for _, character in ipairs(characters) do
            ultimateStates[character.name] = character.enabled
        end
        local data = { version = 1, userId = tostring(player.UserId),
            config = CONFIG, items = selectedItems, currencies = savedCurrencies,
            automation = { gems = state.gems, coins = state.coins,
                lobby = state.lobby, leave = state.leave, antiAfk = state.antiAfk, autoExecute = state.autoExecute },
            ultimate = ultimateStates }
        writefile(savePath, HttpService:JSONEncode(data))
    end)
    if ok then
        dirty = false
        changeVersion = changeVersion + 1
        saveMessage("Saved for " .. player.Name .. " at " .. os.date("%H:%M:%S"))
    else
        saveMessage("Save failed: " .. tostring(err))
    end
    return ok
end

local function loadSettings()
    if not filesAvailable() then saveMessage("File saving unavailable in this environment"); return end
    -- Read and validate completely before changing controls or cancelling automation.
    local ok, data = pcall(function()
        if not isfile(savePath) then return nil end
        return validateSettings(HttpService:JSONDecode(readfile(savePath)))
    end)
    if not ok then
        saveMessage("Could not load settings; existing file left unchanged: " .. tostring(data))
        return
    end
    if not data then saveMessage("No saved settings yet — changes will save automatically"); return end
    applying = true
    disableAll()
    for key, value in pairs(data.config) do
        CONFIG[key] = value
        configControls[key]:Set(value, true)
    end
    for _, item in ipairs(items) do
        item.enabled = data.items[item.id]
        selectedItems[item.id] = item.enabled
        itemControls[item.id]:Set(item.enabled, true)
    end
    savedCurrencies = data.currencies
    -- Restore inputs and item selections before activating any automation.
    currencyControls.gems:Set(data.automation.gems)
    currencyControls.coins:Set(data.automation.coins)
    for _, character in ipairs(characters) do
        ultimateControls[character.name]:Set(data.ultimate[character.name])
    end
    leaveControl:Set(data.automation.leave)
    antiAfkControl:Set(data.automation.antiAfk)
    autoExecuteControl:Set(data.automation.autoExecute)
    -- Lobby last: its purchase pass now sees restored items and currencies.
    lobbyControl:Set(data.automation.lobby)
    applying = false
    dirty = false
    changeVersion = changeVersion + 1
    saveMessage("Loaded settings and ON/OFF states for " .. player.Name)

end

local settings = window:CreateTab({ name = "Settings", forgetState = true })
settings:CreateText({ name = "Per-account saving", text =
    "Changes save automatically after 0.75 seconds. Each UserId has its own JSON file. " ..
    "Loading restores items, delays, host, room, minute and currency preferences. " ..
    "Saved ON toggles resume buying, lobby actions, hourly leave, ultimates and Anti AFK when loaded. " ..
    "On another device, copy the GameAutomationSettings folder into Volt's workspace." })
settings:CreateText({ name = "This account", text = player.Name .. " / " .. tostring(player.UserId)
    .. "\nFile: " .. savePath })
saveStatus = settings:CreateText({ name = "Save status", text = "Loading..." })
settings:CreateButton({ name = "Save settings now", callback = function() saveSettings() end })
settings:CreateButton({ name = "Reload saved settings and ON/OFF states", callback = loadSettings })
settings:CreateButton({ name = "Enable buying with saved currencies", callback = function()
    -- Explicit user action: applying saved preferences can spend in-game currency.
    local gems, coins = savedCurrencies.gems, savedCurrencies.coins
    currencyControls.gems:Set(gems)
    currencyControls.coins:Set(coins)
end })
settings:CreateSection({ name = "Loader and auto-execute" })
settings:CreateText({ text = "Paste a raw HTTPS link serving this full Lua file. Auto-execute resumes after an in-game teleport/rejoin while Volt remains active. Closing Roblox and joining again requires running the loader or configuring Volt Autoexec separately." })
local loaderStatus = settings:CreateText({ name = "Loader status", text = "Set your raw script URL" })
local function validURL(url)
    return type(url) == "string" and url:match("^https://[^%s]+$") ~= nil
end
configControls.ScriptURL = settings:CreateInput({ name = "Raw script URL", value = CONFIG.ScriptURL,
    placeholder = "https://your-host/your-script.lua", forgetState = true,
    callback = function(value)
        CONFIG.ScriptURL = tostring(value):match("^%s*(.-)%s*$")
        queueSave()
    end })
autoExecuteControl = toggle(settings, "Auto-execute after teleport / rejoin", function(value)
    state.autoExecute = value
    status(loaderStatus, value and "ON — will queue on teleport; a valid raw URL is required" or "OFF")
    -- Persist immediately so already-queued code also observes OFF.
    if ready and not applying then saveSettings() end
end)
settings:CreateButton({ name = "Copy one-line loader", callback = function()
    if not validURL(CONFIG.ScriptURL) then status(loaderStatus, "Enter a valid raw HTTPS script URL first"); return end
    local code = "loadstring(game:HttpGet(" .. string.format("%q", CONFIG.ScriptURL) .. "))()"
    if type(setclipboard) == "function" then
        local ok, err = pcall(setclipboard, code)
        status(loaderStatus, ok and "Loader copied" or ("Copy failed: " .. tostring(err)))
    else
        print(code)
        status(loaderStatus, "Clipboard unavailable; loader printed to console")
    end
end })

-- The queued loader reads the latest per-account toggle before fetching anything.
-- It never clears the global teleport queue belonging to other scripts.
local queued = false
if player.OnTeleport then
    teleportConnection = player.OnTeleport:Connect(function(teleportState)
        if teleportState == Enum.TeleportState.Failed then queued = false; return end
        if not alive() or not state.autoExecute or queued then return end
        if teleportState ~= Enum.TeleportState.Started
            and teleportState ~= Enum.TeleportState.InProgress then return end
        local queue = queueonteleport or queue_on_teleport or queueteleport
        if type(queue) ~= "function" then status(loaderStatus, "Teleport queue unavailable"); return end
        if not validURL(CONFIG.ScriptURL) then status(loaderStatus, "Cannot queue: set the raw HTTPS script URL"); return end
        if not saveSettings() then status(loaderStatus, "Cannot queue: settings could not be saved"); return end
        local code = string.format([[
            local ok, err = pcall(function()
                if not game:IsLoaded() then game.Loaded:Wait() end
                local players = game:GetService("Players")
                while not players.LocalPlayer do task.wait(0.1) end
                if type(isfile) ~= "function" or type(readfile) ~= "function" or not isfile(%q) then return end
                local data = game:GetService("HttpService"):JSONDecode(readfile(%q))
                if data.userId ~= tostring(players.LocalPlayer.UserId) then return end
                if type(data.automation) ~= "table" or data.automation.autoExecute ~= true then return end
                local url = type(data.config) == "table" and data.config.ScriptURL
                if type(url) ~= "string" or not url:match("^https://[^%%s]+$") then return end
                local env = (getgenv and getgenv()) or _G
                local current = env.ConversationAutomation
                if current and current.alive then return end
                local code, compileError = loadstring(game:HttpGet(url))
                assert(code, compileError)
                code()
            end)
            if not ok then warn("[AM auto-execute] " .. tostring(err)) end
        ]], savePath, savePath)
        local ok, err = pcall(queue, code)
        queued = ok
        status(loaderStatus, ok and "Loader queued for destination" or ("Queue failed: " .. tostring(err)))
    end)
else
    status(loaderStatus, "Teleport event unavailable in this environment")
end
loadSettings()
ready = true

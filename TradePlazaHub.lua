--[[
==================================================================================
    TRADE PLAZA HUB  v2   --  script client (executor / LocalScript)
==================================================================================
    * Teleport LENT et sur (glisse progressive, altitude de croisiere, mode
      marche) pour ne plus se faire renvoyer en arriere ni mourir
    * Scanner de BRAINROTS dans la base d'un joueur (nom, mutation, revenu/s)
    * Envoi de trade et de messages bases sur la CAPTURE des vrais appels du
      jeu : plus besoin de deviner les arguments des remotes
    * Traducteur du chat de trade (entrant + sortant) avec repli hors-ligne

    Utilisation
      Executor : coller le script, ou
                 loadstring(game:HttpGet("<lien raw>"))()
      In-game  : LocalScript dans StarterPlayer > StarterPlayerScripts

    Touche menu : RightControl (modifiable dans CONFIG.Keybind)
==================================================================================
]]

local GENV = (getgenv and getgenv()) or _G
if GENV.TradePlazaHub and GENV.TradePlazaHub.Unload then
    pcall(GENV.TradePlazaHub.Unload)
end
print("[TPH] chargement...")

----------------------------------------------------------------------------------
-- SERVICES
----------------------------------------------------------------------------------
local Players           = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local UserInputService   = game:GetService("UserInputService")
local RunService         = game:GetService("RunService")
local TweenService       = game:GetService("TweenService")
local StarterGui         = game:GetService("StarterGui")
local HttpService        = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

local unpack = unpack or table.unpack

----------------------------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------------------------
local CONFIG = {
    Keybind           = Enum.KeyCode.RightControl,

    -- teleport
    TPMode            = "lent",   -- lent | instant | marche
    TPSpeed           = 70,       -- studs par seconde en mode lent
    TPAltitude        = 25,       -- hauteur de croisiere au dessus du sol
    TPNoclip          = true,
    TPFaceTarget      = true,

    -- traduction
    TranslateTo       = "fr",
    SendAs            = "en",
    TranslateIncoming = true,
    TranslateOutgoing = false,
    ShowOriginal      = true,
    PatchChatGui      = true,

    -- divers
    SpyActive         = true,
    ArgMode           = "auto",    -- auto | player | userid | name
    RemotePaths       = {},        -- ex : { Invite = "ReplicatedStorage.Remotes.TradeService.Invite" }
}

if type(GENV.TradePlazaHubConfig) == "table" then
    for k, v in pairs(GENV.TradePlazaHubConfig) do CONFIG[k] = v end
end

local LANGS = {
    "fr","en","es","pt","pt-BR","de","it","nl","pl","tr","ru","uk","ar",
    "id","ms","vi","th","fil","ja","ko","zh-CN","hi","ro","sv",
}

----------------------------------------------------------------------------------
-- ENVIRONNEMENT (executor ou simple LocalScript)
----------------------------------------------------------------------------------
local Env = {}
Env.request        = (syn and syn.request) or (http and http.request)
                     or (fluxus and fluxus.request) or http_request or request
Env.clipboard      = setclipboard or toclipboard or (syn and syn.write_clipboard)
Env.gethui         = gethui
Env.hookmetamethod = hookmetamethod
Env.getnamecall    = getnamecallmethod
Env.checkcaller    = checkcaller
Env.isExecutor     = (Env.request ~= nil) or (Env.hookmetamethod ~= nil)

local function spawnTask(fn)
    if task and task.spawn then return task.spawn(fn) end
    return coroutine.wrap(fn)()
end

local function waitFor(t)
    if task and task.wait then return task.wait(t) end
    return wait(t)
end

----------------------------------------------------------------------------------
-- UTILITAIRES
----------------------------------------------------------------------------------
local Util = {}

function Util.trim(s)
    return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Util.lower(s)
    return string.lower(tostring(s))
end

function Util.comma(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out, k = s, 0
    repeat
        out, k = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1 %2")
    until k == 0
    return out
end

-- "$1.25M/s" -> 1250000
function Util.parseNumber(txt)
    if not txt then return nil end
    local clean = string.gsub(tostring(txt), "[%s,]", "")
    local num, suffix = string.match(clean, "([%d%.]+)%s*([KkMmBbTt]?)")
    local value = tonumber(num)
    if not value then return nil end
    suffix = string.lower(suffix or "")
    if suffix == "k" then value = value * 1e3
    elseif suffix == "m" then value = value * 1e6
    elseif suffix == "b" then value = value * 1e9
    elseif suffix == "t" then value = value * 1e12 end
    return value
end

function Util.short(n)
    n = tonumber(n) or 0
    if n >= 1e12 then return string.format("%.2fT", n / 1e12) end
    if n >= 1e9  then return string.format("%.2fB", n / 1e9)  end
    if n >= 1e6  then return string.format("%.2fM", n / 1e6)  end
    if n >= 1e3  then return string.format("%.2fK", n / 1e3)  end
    return tostring(math.floor(n))
end

function Util.urlEncode(s)
    s = tostring(s)
    s = string.gsub(s, "\n", "\r\n")
    s = string.gsub(s, "([^%w%-%_%.%~ ])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return (string.gsub(s, " ", "+"))
end

function Util.httpGet(url)
    if Env.request then
        local ok, res = pcall(Env.request, { Url = url, Method = "GET" })
        if ok and type(res) == "table" and res.Body then return res.Body end
    end
    local ok2, body = pcall(function() return game:HttpGetAsync(url) end)
    if ok2 and body then return body end
    local ok3, body3 = pcall(function() return game:HttpGet(url) end)
    if ok3 and body3 then return body3 end
    return nil
end

function Util.copy(text)
    if Env.clipboard then return (pcall(Env.clipboard, text)) end
    return false
end

function Util.dottedPath(path)
    local node = game
    for part in string.gmatch(path, "[^%.]+") do
        if node == game and part == "ReplicatedStorage" then
            node = ReplicatedStorage
        elseif node == game and (part == "Workspace" or part == "workspace") then
            node = workspace
        else
            node = node:FindFirstChild(part)
        end
        if not node then return nil end
    end
    return node
end

----------------------------------------------------------------------------------
-- MAID / ETAT / LOGS
----------------------------------------------------------------------------------
local Maid = { conns = {}, insts = {} }

function Maid.conn(c) table.insert(Maid.conns, c) return c end
function Maid.inst(i) table.insert(Maid.insts, i) return i end
function Maid.clean()
    for _, c in ipairs(Maid.conns) do pcall(function() c:Disconnect() end) end
    for _, i in ipairs(Maid.insts) do pcall(function() i:Destroy() end) end
    Maid.conns, Maid.insts = {}, {}
end

local State = {
    Unloaded   = false,
    Travelling = false,
    Cancel     = false,
    LastPos    = nil,
    Logs       = {},
    ChatLog    = {},
    Plot       = nil,
    PlotOwner  = nil,
}

local UI    -- interface, remplie plus bas
local Spy   -- capture des appels du jeu
local Hook  -- hook __namecall unique

local function log(fmt, ...)
    local ok, msg = pcall(string.format, tostring(fmt), ...)
    if not ok then msg = tostring(fmt) end
    msg = os.date("%H:%M:%S") .. "  " .. msg
    table.insert(State.Logs, msg)
    if #State.Logs > 200 then table.remove(State.Logs, 1) end
    if UI and UI.pushLog then pcall(UI.pushLog, msg) end
    print("[TPH] " .. msg)
end

local function notify(title, text, dur)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title or "Trade Plaza Hub", Text = tostring(text), Duration = dur or 4,
        })
    end)
end

----------------------------------------------------------------------------------
-- REMOTES
----------------------------------------------------------------------------------
local Remotes = { cache = {}, found = {} }

local function isRemote(inst)
    return inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction")
        or inst.ClassName == "UnreliableRemoteEvent"
end

local function searchRoots()
    local roots = { ReplicatedStorage }
    local rf = game:FindFirstChild("ReplicatedFirst")
    if rf then table.insert(roots, rf) end
    table.insert(roots, workspace)
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if pg then table.insert(roots, pg) end
    return roots
end

local function scoreRemote(inst, wanted)
    local name, full = Util.lower(inst.Name), Util.lower(inst:GetFullName())
    local score = 0
    if name == wanted then score = 10
    elseif string.find(name, "/" .. wanted, 1, true) then score = 8
    elseif string.find(name, wanted, 1, true) then score = 4
    else return 0 end
    if string.find(full, "tradeservice", 1, true) then score = score + 6 end
    if string.find(full, "trade", 1, true) then score = score + 3 end
    return score
end

function Remotes:Find(name)
    local cached = self.cache[name]
    if cached and cached.Parent then return cached end

    local forced = CONFIG.RemotePaths and CONFIG.RemotePaths[name]
    if forced then
        local node = Util.dottedPath(forced)
        if node and isRemote(node) then self.cache[name] = node return node end
    end

    local wanted = Util.lower(name)
    local best, bestScore = nil, 0
    for _, root in ipairs(searchRoots()) do
        local ok, list = pcall(function() return root:GetDescendants() end)
        if ok then
            for _, d in ipairs(list) do
                local okIs, remote = pcall(isRemote, d)
                if okIs and remote then
                    local s = scoreRemote(d, wanted)
                    if s > bestScore then best, bestScore = d, s end
                end
            end
        end
    end
    if best then
        self.cache[name] = best
        log("remote '%s' -> %s", name, best:GetFullName())
    end
    return best
end

function Remotes:Scan()
    local out = {}
    for _, root in ipairs(searchRoots()) do
        local ok, list = pcall(function() return root:GetDescendants() end)
        if ok then
            for _, d in ipairs(list) do
                local okIs, remote = pcall(isRemote, d)
                if okIs and remote and string.find(Util.lower(d:GetFullName()), "trade", 1, true) then
                    table.insert(out, d)
                end
            end
        end
    end
    table.sort(out, function(a, b) return a:GetFullName() < b:GetFullName() end)
    self.found = out
    return out
end

-- InvokeServer peut ne jamais repondre : thread separe + delai maxi
local function callRemote(remote, args, n, timeout)
    local finished, success, result = false, false, nil
    spawnTask(function()
        local ok, res
        if remote:IsA("RemoteFunction") then
            ok, res = pcall(function() return remote:InvokeServer(unpack(args, 1, n)) end)
        else
            ok, res = pcall(function() remote:FireServer(unpack(args, 1, n)) end)
        end
        finished, success, result = true, ok, res
    end)
    local waited = 0
    while not finished and waited < (timeout or 5) do
        waited = waited + RunService.Heartbeat:Wait()
    end
    if not finished then return "timeout", nil end
    return success and "ok" or "error", result
end

----------------------------------------------------------------------------------
-- JOUEURS
----------------------------------------------------------------------------------
local PlayerUtil = {}

function PlayerUtil.byQuery(query)
    query = Util.trim(query or "")
    if query == "" then return nil, "entree vide" end

    local asId = tonumber(query)
    if asId then
        for _, p in ipairs(Players:GetPlayers()) do
            if p.UserId == asId then return p end
        end
        local ok, name = pcall(function() return Players:GetNameFromUserIdAsync(asId) end)
        return nil, ok and (name .. " n'est pas dans ce serveur") or ("id inconnu : " .. asId)
    end

    local q = Util.lower(query)
    for _, p in ipairs(Players:GetPlayers()) do
        if Util.lower(p.Name) == q or Util.lower(p.DisplayName) == q then return p end
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if string.find(Util.lower(p.Name), q, 1, true)
        or string.find(Util.lower(p.DisplayName), q, 1, true) then return p end
    end
    return nil, "aucun joueur nomme '" .. query .. "'"
end

function PlayerUtil.userIdOf(query)
    local plr = PlayerUtil.byQuery(query)
    if plr then return plr.UserId end
    local asId = tonumber(query)
    if asId then return asId end
    local ok, id = pcall(function() return Players:GetUserIdFromNameAsync(query) end)
    return ok and id or nil
end

----------------------------------------------------------------------------------
-- PLOTS / BASES
----------------------------------------------------------------------------------
local Plots = {}

local OWNER_KEYS = {
    "Owner", "OwnerId", "OwnerID", "OwnerUserId", "UserId", "UserID",
    "Player", "PlayerId", "PlayerName", "OwnerName", "Occupant",
}
local CONTAINER_NAMES = {
    "plots", "plot", "bases", "base", "playerplots", "playerbases", "islands", "tycoons",
}

function Plots:Containers()
    local out = {}
    for _, child in ipairs(workspace:GetChildren()) do
        local n = Util.lower(child.Name)
        for _, want in ipairs(CONTAINER_NAMES) do
            if n == want then table.insert(out, child) break end
        end
    end
    if #out == 0 then
        for _, child in ipairs(workspace:GetChildren()) do
            if child:IsA("Folder") or child:IsA("Model") then
                for _, sub in ipairs(child:GetChildren()) do
                    local n = Util.lower(sub.Name)
                    for _, want in ipairs(CONTAINER_NAMES) do
                        if n == want then table.insert(out, sub) break end
                    end
                end
            end
        end
    end
    return out
end

function Plots:OwnerOf(model)
    for _, key in ipairs(OWNER_KEYS) do
        local ok, val = pcall(function() return model:GetAttribute(key) end)
        if ok and val ~= nil then
            if type(val) == "number" then
                for _, p in ipairs(Players:GetPlayers()) do
                    if p.UserId == val then return p end
                end
            elseif type(val) == "string" then
                local plr = PlayerUtil.byQuery(val)
                if plr then return plr end
            end
        end
    end
    for _, d in ipairs(model:GetChildren()) do
        for _, key in ipairs(OWNER_KEYS) do
            if d.Name == key then
                if d:IsA("ObjectValue") and d.Value and d.Value:IsA("Player") then
                    return d.Value
                elseif d:IsA("IntValue") or d:IsA("NumberValue") then
                    for _, p in ipairs(Players:GetPlayers()) do
                        if p.UserId == d.Value then return p end
                    end
                elseif d:IsA("StringValue") then
                    local plr = PlayerUtil.byQuery(d.Value)
                    if plr then return plr end
                end
            end
        end
    end
    local asId = tonumber(model.Name)
    if asId then
        for _, p in ipairs(Players:GetPlayers()) do
            if p.UserId == asId then return p end
        end
    end
    local ok, list = pcall(function() return model:GetDescendants() end)
    if ok then
        for _, d in ipairs(list) do
            if d:IsA("TextLabel") or d:IsA("TextBox") then
                local txt = Util.lower(d.Text or "")
                if txt ~= "" then
                    for _, p in ipairs(Players:GetPlayers()) do
                        if string.find(txt, Util.lower(p.Name), 1, true)
                        or string.find(txt, Util.lower(p.DisplayName), 1, true) then return p end
                    end
                end
            end
        end
    end
    return nil
end

local function pivotOf(model)
    local ok, cf = pcall(function() return model:GetPivot() end)
    if ok and cf then return cf end
    if model:IsA("BasePart") then return model.CFrame end
    if model:IsA("Model") and model.PrimaryPart then return model.PrimaryPart.CFrame end
    local part = model:FindFirstChildWhichIsA("BasePart", true)
    return part and part.CFrame or nil
end
Plots.pivotOf = pivotOf

function Plots:All()
    local out = {}
    for _, container in ipairs(self:Containers()) do
        for _, model in ipairs(container:GetChildren()) do
            if model:IsA("Model") or model:IsA("Folder") then
                local owner = self:OwnerOf(model)
                table.insert(out, {
                    model = model, owner = owner,
                    ownerName = owner and owner.Name or nil,
                    cframe = pivotOf(model),
                })
            end
        end
    end
    return out
end

function Plots:ForPlayer(player)
    for _, entry in ipairs(self:All()) do
        if entry.owner == player then return entry.model, entry.cframe end
    end
    local char = player and player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root then
        for _, entry in ipairs(self:All()) do
            if entry.cframe and (entry.cframe.Position - root.Position).Magnitude < 200 then
                return entry.model, entry.cframe
            end
        end
    end
    return nil, nil
end

----------------------------------------------------------------------------------
-- TELEPORT  (lent = glisse progressive, pour ne pas se faire renvoyer / mourir)
----------------------------------------------------------------------------------
local TP = {}

function TP.root()
    local char = LocalPlayer.Character
    return char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart) or nil
end

function TP.humanoid()
    local char = LocalPlayer.Character
    return char and char:FindFirstChildWhichIsA("Humanoid") or nil
end

local noclipConn
local function setNoclip(on)
    if noclipConn then noclipConn:Disconnect() noclipConn = nil end
    if not on then return end
    noclipConn = Maid.conn(RunService.Stepped:Connect(function()
        local char = LocalPlayer.Character
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                pcall(function() part.CanCollide = false end)
            end
        end
    end))
end

local function killVelocity(root)
    pcall(function() root.AssemblyLinearVelocity = Vector3.new(0, 0, 0) end)
    pcall(function() root.Velocity = Vector3.new(0, 0, 0) end)
    pcall(function() root.RotVelocity = Vector3.new(0, 0, 0) end)
end

-- avance vers un point a vitesse constante, une frame a la fois
function TP.moveTowards(target, speed)
    local hum = TP.humanoid()
    local guard = 0
    while true do
        if State.Unloaded or State.Cancel then return false, "annule" end
        local root = TP.root()
        if not root then return false, "personnage perdu (mort ou respawn)" end

        local delta = target - root.Position
        local dist = delta.Magnitude
        if dist < 2 then
            root.CFrame = CFrame.new(target) * (root.CFrame - root.CFrame.Position)
            killVelocity(root)
            return true
        end

        local dt = RunService.Heartbeat:Wait()
        guard = guard + dt
        if guard > 90 then return false, "trajet trop long" end

        local step = math.min(dist, math.max(4, speed) * dt)
        local nextPos = root.Position + delta.Unit * step
        if CONFIG.TPFaceTarget and dist > 4 then
            root.CFrame = CFrame.new(nextPos, target)
        else
            root.CFrame = CFrame.new(nextPos) * (root.CFrame - root.CFrame.Position)
        end
        killVelocity(root)
        if hum and hum.Parent then
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.Freefall) end)
        end
    end
end

-- monte, traverse en altitude, redescend : evite murs, vide et degats de chute
function TP.glideTo(goalCF)
    local root = TP.root()
    if not root then return false, "personnage introuvable" end

    local startPos = root.Position
    local goalPos  = goalCF.Position + Vector3.new(0, 4, 0)
    local cruise   = math.max(startPos.Y, goalPos.Y) + math.max(0, CONFIG.TPAltitude)
    local speed    = math.max(8, CONFIG.TPSpeed)

    local waypoints = {
        Vector3.new(startPos.X, cruise, startPos.Z),
        Vector3.new(goalPos.X,  cruise, goalPos.Z),
        goalPos,
    }

    if CONFIG.TPNoclip then setNoclip(true) end
    for _, wp in ipairs(waypoints) do
        local ok, err = TP.moveTowards(wp, speed)
        if not ok then
            setNoclip(false)
            return false, err
        end
    end
    setNoclip(false)

    -- petite pause immobile : le serveur revalide la position sans rubberband
    local final = TP.root()
    if final then
        for _ = 1, 6 do
            killVelocity(final)
            RunService.Heartbeat:Wait()
        end
    end
    return true
end

-- le personnage marche vraiment : 100% accepte par le serveur, mais lent
function TP.walkTo(goalCF)
    local hum = TP.humanoid()
    if not hum then return false, "humanoid introuvable" end
    local target = goalCF.Position
    local elapsed = 0
    while true do
        if State.Unloaded or State.Cancel then return false, "annule" end
        local root = TP.root()
        if not root then return false, "personnage perdu" end
        if (root.Position - target).Magnitude < 8 then return true end
        hum:MoveTo(target)
        elapsed = elapsed + RunService.Heartbeat:Wait()
        if elapsed > 120 then return false, "marche trop longue (obstacle ?)" end
    end
end

function TP.travel(goalCF)
    if State.Travelling then return false, "deplacement deja en cours" end
    local root = TP.root()
    if not root then return false, "personnage introuvable" end
    if typeof(goalCF) == "Vector3" then goalCF = CFrame.new(goalCF) end
    if typeof(goalCF) ~= "CFrame" then return false, "destination invalide" end

    State.Travelling, State.Cancel = true, false
    State.LastPos = root.CFrame

    local ok, err
    if CONFIG.TPMode == "instant" then
        pcall(function() root.CFrame = goalCF + Vector3.new(0, 4, 0) end)
        ok = true
    elseif CONFIG.TPMode == "marche" then
        ok, err = TP.walkTo(goalCF)
    else
        ok, err = TP.glideTo(goalCF)
    end

    State.Travelling = false
    return ok, err
end

function TP.stop()
    State.Cancel = true
    setNoclip(false)
end

function TP.back()
    if not State.LastPos then return false, "aucune position sauvegardee" end
    return TP.travel(State.LastPos)
end

function TP.toPlayer(player)
    local char = player.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
    if not root then return false, "ce joueur n'a pas de personnage charge" end
    return TP.travel(root.CFrame * CFrame.new(0, 0, 5))
end

function TP.toBase(player)
    local model, cf = Plots:ForPlayer(player)
    if not model or not cf then return false, "base introuvable pour " .. player.Name end
    State.Plot, State.PlotOwner = model, player.Name
    return TP.travel(cf)
end

----------------------------------------------------------------------------------
-- INSPECTEUR DE BASE  (brainrots + objets)
----------------------------------------------------------------------------------
local Inspector = {}

local GENERIC_NAMES = {
    plotblock = true, plotsign = true, part = true, model = true, item = true,
    block = true, meshpart = true, union = true, folder = true, handle = true,
    main = true, purchase = true, purchases = true, object = true, base = true,
    primary = true, podium = true, spawn = true, floor = true, hitbox = true,
}
local RARITIES = {
    "common", "uncommon", "rare", "epic", "legendary", "mythic", "godly",
    "brainrot god", "secret", "limited", "exclusive", "og",
}
local MUTATIONS = {
    "gold", "golden", "diamond", "rainbow", "lava", "bloodrot", "celestial",
    "candy", "galaxy", "galaxy 4090", "nuclear", "radioactive", "ice", "fire",
    "crystal", "glitch", "zombie", "concert", "tung", "rain", "snow", "taco",
}

local function guiTexts(model)
    local texts = {}
    local ok, list = pcall(function() return model:GetDescendants() end)
    if not ok then return texts end
    for _, d in ipairs(list) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            local t = Util.trim(d.Text or "")
            if t ~= "" and #t < 60 then table.insert(texts, t) end
        end
    end
    return texts
end

local function attributesOf(inst)
    local ok, attrs = pcall(function() return inst:GetAttributes() end)
    return (ok and attrs) or {}
end

-- lit un brainrot / objet pose : nom, mutation, rarete, revenu par seconde
local function readEntity(model)
    local info = { model = model, name = nil, income = 0, rarity = nil, mutation = nil }

    for k, v in pairs(attributesOf(model)) do
        local lk = Util.lower(k)
        if type(v) == "string" and v ~= "" then
            if lk == "animal" or lk == "brainrot" or lk == "itemname"
            or lk == "displayname" or lk == "petname" or lk == "name" then
                info.name = info.name or v
            elseif lk == "mutation" or lk == "variant" or lk == "skin" then
                info.mutation = info.mutation or v
            elseif lk == "rarity" or lk == "tier" then
                info.rarity = info.rarity or v
            end
        elseif type(v) == "number" and v > 0 then
            if lk == "income" or lk == "generation" or lk == "persecond"
            or lk == "money" or lk == "value" or lk == "price" or lk == "worth" then
                if v > info.income then info.income = v end
            end
        end
    end

    for _, t in ipairs(guiTexts(model)) do
        local lt = Util.lower(t)
        if string.find(lt, "/s", 1, true) or string.find(t, "%$") then
            local n = Util.parseNumber(t)
            if n and n > info.income then info.income = n end
        else
            local tagged = false
            for _, r in ipairs(RARITIES) do
                if lt == r then info.rarity = info.rarity or t tagged = true end
            end
            for _, m in ipairs(MUTATIONS) do
                if lt == m then info.mutation = info.mutation or t tagged = true end
            end
            if not tagged and not info.name and #t >= 3 and not tonumber(t) then
                info.name = t
            end
        end
    end

    if not info.name then
        local n = model.Name
        if GENERIC_NAMES[Util.lower(n)] then
            for _, c in ipairs(model:GetChildren()) do
                if (c:IsA("Model") or c:IsA("BasePart"))
                   and not GENERIC_NAMES[Util.lower(c.Name)] then n = c.Name break end
            end
            if GENERIC_NAMES[Util.lower(n)] then
                for _, c in ipairs(model:GetChildren()) do
                    if c:IsA("StringValue") and c.Value ~= "" then n = c.Value break end
                end
            end
        end
        info.name = n
    end
    return info
end

-- un modele est un "brainrot" s'il est anime, s'il affiche un revenu,
-- ou s'il est pose dans un dossier d'achats / sur un socle
local function isEntityModel(model)
    if not model:IsA("Model") then return false end
    if model:FindFirstChildWhichIsA("Humanoid") then return true end
    if model:FindFirstChildWhichIsA("AnimationController") then return true end

    local parentName = Util.lower(model.Parent and model.Parent.Name or "")
    if parentName == "purchases" or parentName == "animals" or parentName == "pets"
    or parentName == "brainrots" or parentName == "items" then return true end

    for _, d in ipairs(model:GetChildren()) do
        if d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
            for _, t in ipairs(guiTexts(d)) do
                if string.find(t, "%$") or string.find(Util.lower(t), "/s", 1, true) then
                    return true
                end
            end
        end
    end
    return false
end

-- liste les brainrots d'une base, groupes par nom + mutation
function Inspector.brainrots(plot)
    if not plot then return {}, 0, 0 end

    local candidates, chosen = {}, {}
    local ok, list = pcall(function() return plot:GetDescendants() end)
    if not ok then return {}, 0, 0 end

    for _, d in ipairs(list) do
        if d:IsA("Model") and isEntityModel(d) then candidates[d] = true end
    end
    -- on garde le modele le plus haut : pas les sous-modeles d'un meme brainrot
    for model in pairs(candidates) do
        local nested = false
        local parent = model.Parent
        while parent and parent ~= plot do
            if candidates[parent] then nested = true break end
            parent = parent.Parent
        end
        if not nested then table.insert(chosen, model) end
    end

    local buckets, order, total = {}, {}, 0
    for _, model in ipairs(chosen) do
        local info = readEntity(model)
        local key = Util.lower((info.name or "?") .. "|" .. (info.mutation or ""))
        local b = buckets[key]
        if not b then
            b = { name = info.name or model.Name, mutation = info.mutation,
                  rarity = info.rarity, income = info.income, count = 0, total = 0 }
            buckets[key] = b
            table.insert(order, b)
        end
        b.count = b.count + 1
        if info.income > b.income then b.income = info.income end
        b.total = b.total + info.income
        total = total + info.income
    end

    table.sort(order, function(a, b)
        if a.total == b.total then return a.count > b.count end
        return a.total > b.total
    end)
    return order, total, #chosen
end

-- liste brute de tout ce qui est pose (repli quand rien n'est reconnu)
function Inspector.items(plot)
    if not plot then return {} end
    local buckets, order = {}, {}
    local ok, list = pcall(function() return plot:GetDescendants() end)
    if not ok then return {} end

    local function add(inst)
        local info = readEntity(inst)
        local key = Util.lower(info.name)
        local b = buckets[key]
        if not b then
            b = { name = info.name, count = 0, income = info.income }
            buckets[key] = b
            table.insert(order, b)
        end
        b.count = b.count + 1
    end

    local found = false
    for _, d in ipairs(list) do
        if (d:IsA("Folder") or d:IsA("Model")) and Util.lower(d.Name) == "purchases" then
            for _, item in ipairs(d:GetChildren()) do add(item) found = true end
        end
    end
    if not found then
        for _, d in ipairs(list) do
            if d:IsA("Model") and d.Parent ~= plot then add(d) end
        end
    end

    table.sort(order, function(a, b) return a.count > b.count end)
    return order
end

function Inspector.dump(plot, maxLines)
    if not plot then return "aucune base selectionnee" end
    maxLines = maxLines or 400
    local lines = { plot:GetFullName() }
    local function walk(inst, depth)
        if #lines >= maxLines or depth > 5 then return end
        for _, child in ipairs(inst:GetChildren()) do
            if #lines >= maxLines then return end
            local attrs = ""
            local t = attributesOf(child)
            local parts = {}
            for k, v in pairs(t) do table.insert(parts, k .. "=" .. tostring(v)) end
            if #parts > 0 then attrs = "  {" .. table.concat(parts, ", ") .. "}" end
            local extra = ""
            if child:IsA("TextLabel") then extra = '  "' .. tostring(child.Text) .. '"' end
            table.insert(lines, string.rep("   ", depth) .. child.ClassName .. " "
                .. child.Name .. extra .. attrs)
            walk(child, depth + 1)
        end
    end
    walk(plot, 1)
    return table.concat(lines, "\n")
end

----------------------------------------------------------------------------------
-- TRADE
----------------------------------------------------------------------------------
local Trade = {}
local INVITE_NAMES = { "Invite", "SendRequest", "TradeRequest", "RequestTrade", "SendTradeRequest" }

local function argShapes(player, userId)
    return {
        { label = "player", n = 1, args = { player } },
        { label = "userid", n = 1, args = { userId } },
        { label = "name",   n = 1, args = { player and player.Name } },
        { label = "table",  n = 1, args = { { Player = player, UserId = userId } } },
    }
end

function Trade.invite(query)
    local player, err = PlayerUtil.byQuery(query)
    local userId = (player and player.UserId) or tonumber(query) or PlayerUtil.userIdOf(query)
    if not player and not userId then return false, err or "joueur introuvable" end
    local who = player and player.Name or tostring(userId)

    -- 1) rejouer l'appel capture sur le vrai bouton du jeu : signature exacte
    local template = Spy and Spy.templates and Spy.templates.invite
    if template then
        local ok, res = Spy.replay(template, { target = player, userId = userId })
        if ok then return true, "trade envoye a " .. who .. " (appel capture)" end
        log("replay invite en echec : %s", tostring(res))
    end

    -- 2) sinon : chaque remote candidat x chaque forme d'argument
    local tried = {}
    for _, remoteName in ipairs(INVITE_NAMES) do
        local remote = Remotes:Find(remoteName)
        if remote then
            for _, shape in ipairs(argShapes(player, userId)) do
                local skip = (CONFIG.ArgMode ~= "auto" and shape.label ~= CONFIG.ArgMode)
                if not skip and shape.args[1] ~= nil then
                    local status, res = callRemote(remote, shape.args, shape.n, 5)
                    log("%s[%s] -> %s (%s)", remoteName, shape.label, status, tostring(res))
                    table.insert(tried, remoteName .. ":" .. shape.label .. "=" .. status)
                    if status == "ok" and res ~= false then
                        CONFIG.ArgMode = shape.label
                        return true, string.format("trade envoye a %s (%s / %s)",
                            who, remoteName, shape.label)
                    end
                end
            end
            break
        end
    end

    if #tried == 0 then
        return false, "aucun remote d'invitation trouve - onglet Spy : clique une fois sur le vrai bouton de trade"
    end
    return false, "refuse par le serveur [" .. table.concat(tried, " ") .. "] - passe par l'onglet Spy"
end

function Trade.simple(remoteName)
    local remote = Remotes:Find(remoteName)
    if not remote then return false, "remote '" .. remoteName .. "' introuvable" end
    local status, res = callRemote(remote, {}, 0, 5)
    if status == "ok" then return true, remoteName .. " envoye" end
    return false, remoteName .. " : " .. status .. " " .. tostring(res)
end

----------------------------------------------------------------------------------
-- TRADUCTEUR
----------------------------------------------------------------------------------
local Translator = { cache = {} }

local PHRASEBOOK = {
    { fr = "salut, tu veux trade ?",   en = "hey, wanna trade?" },
    { fr = "combien tu veux ?",        en = "how much do you want?" },
    { fr = "c'est trop peu",           en = "that's too low" },
    { fr = "ajoute un truc",           en = "add something" },
    { fr = "j'accepte",                en = "i accept" },
    { fr = "non merci",                en = "no thanks" },
    { fr = "attends une seconde",      en = "wait a second" },
    { fr = "montre moi ta base",       en = "show me your base" },
    { fr = "c'est quoi la valeur ?",   en = "what is the value?" },
    { fr = "deal ?",                   en = "deal?" },
    { fr = "envoie en premier",        en = "you go first" },
    { fr = "merci beaucoup",           en = "thank you very much" },
}
Translator.phrases = PHRASEBOOK

function Translator.raw(text, target, source)
    local key = tostring(target) .. "|" .. text
    if Translator.cache[key] then return Translator.cache[key], "cache" end

    local url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl="
        .. (source or "auto") .. "&tl=" .. tostring(target) .. "&dt=t&q=" .. Util.urlEncode(text)
    local body = Util.httpGet(url)
    if not body then return nil, "pas de fonction HTTP dans cet executor" end

    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok or type(data) ~= "table" or type(data[1]) ~= "table" then
        return nil, "reponse illisible"
    end
    local parts = {}
    for _, seg in ipairs(data[1]) do
        if type(seg) == "table" and type(seg[1]) == "string" then table.insert(parts, seg[1]) end
    end
    local out = table.concat(parts)
    if out == "" then return nil, "traduction vide" end
    Translator.cache[key] = out
    return out, (type(data[3]) == "string" and data[3] or "?")
end

local function phrasebookLookup(text, target)
    local key = Util.lower(Util.trim(text))
    for _, phrase in ipairs(PHRASEBOOK) do
        if Util.lower(phrase.fr) == key or Util.lower(phrase.en) == key then
            return (target == "fr") and phrase.fr or phrase.en
        end
    end
    return nil
end

function Translator.translate(text, target)
    text = Util.trim(text)
    if text == "" then return nil, "texte vide" end
    target = target or CONFIG.TranslateTo
    local out, info = Translator.raw(text, target)
    if out then return out, info end
    local offline = phrasebookLookup(text, target)
    if offline then return offline, "hors-ligne" end
    return nil, info or "traduction indisponible"
end

----------------------------------------------------------------------------------
-- CHAT DE TRADE
----------------------------------------------------------------------------------
local Chat = { remote = nil, patched = {} }

local function pushChat(who, original, translated)
    local entry = { who = who, original = original, translated = translated, at = os.date("%H:%M") }
    table.insert(State.ChatLog, entry)
    if #State.ChatLog > 100 then table.remove(State.ChatLog, 1) end
    if UI and UI.pushChat then pcall(UI.pushChat, entry) end
end

function Chat.getRemote()
    if Chat.remote and Chat.remote.Parent then return Chat.remote end
    Chat.remote = Remotes:Find("SendChatMessage") or Remotes:Find("ChatMessage")
        or Remotes:Find("SendMessage") or Remotes:Find("Chat")
    return Chat.remote
end

function Chat.send(text, translateTo)
    text = Util.trim(text or "")
    if text == "" then return false, "message vide" end

    local final = text
    if translateTo and translateTo ~= "" then
        local out = Translator.translate(text, translateTo)
        if out then final = out end
    end

    -- rejoue l'appel capture (conserve les arguments en plus : id de trade, canal...)
    local template = Spy and Spy.templates and Spy.templates.chat
    if template then
        local ok, res = Spy.replay(template, { message = final })
        if ok then
            pushChat("moi", text, (final ~= text) and final or nil)
            return true, final
        end
        log("replay chat en echec : %s", tostring(res))
    end

    local remote = Chat.getRemote()
    if not remote then
        return false, "remote de chat introuvable - onglet Spy : envoie un vrai message une fois"
    end
    local status, res = callRemote(remote, { final }, 1, 5)
    if status ~= "ok" then return false, "echec envoi (" .. status .. ") " .. tostring(res) end
    pushChat("moi", text, (final ~= text) and final or nil)
    return true, final
end

local function extractMessage(...)
    local args, sender, message = { ... }, nil, nil
    for _, v in ipairs(args) do
        if typeof(v) == "Instance" and v:IsA("Player") then
            sender = v
        elseif type(v) == "string" and #v > 0 then
            if not message or #v > #message then message = v end
        elseif type(v) == "table" then
            if type(v.Message) == "string" then message = v.Message end
            if typeof(v.Player) == "Instance" then sender = v.Player end
        end
    end
    return sender, message
end

function Chat.hookIncoming()
    local remote = Chat.getRemote()
    if not remote or not remote:IsA("RemoteEvent") then return end
    Maid.conn(remote.OnClientEvent:Connect(function(...)
        if State.Unloaded or not CONFIG.TranslateIncoming then return end
        local sender, message = extractMessage(...)
        if not message or sender == LocalPlayer then return end
        spawnTask(function()
            local out = Translator.translate(message, CONFIG.TranslateTo)
            pushChat(sender and sender.Name or "eux", message, out)
            if out and out ~= message then notify(sender and sender.Name or "Trade", out, 6) end
        end)
    end))
    log("chat : ecoute de %s", remote:GetFullName())
end

local function looksLikeTradeChat(inst)
    local full = Util.lower(inst:GetFullName())
    return string.find(full, "trade", 1, true) and string.find(full, "chat", 1, true)
end

function Chat.patchGui()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return end

    local function handle(label)
        if not (CONFIG.PatchChatGui and CONFIG.TranslateIncoming) then return end
        if not label:IsA("TextLabel") or Chat.patched[label] then return end
        if not looksLikeTradeChat(label) then return end
        local original = Util.trim(label.Text or "")
        if #original < 2 then return end
        Chat.patched[label] = true
        spawnTask(function()
            local out, detected = Translator.translate(original, CONFIG.TranslateTo)
            if not out or out == original or State.Unloaded or not label.Parent then return end
            label.Text = CONFIG.ShowOriginal and (original .. "  |  " .. out) or out
            pushChat("chat/" .. tostring(detected), original, out)
        end)
    end

    Maid.conn(pg.DescendantAdded:Connect(function(d)
        if State.Unloaded or not d:IsA("TextLabel") then return end
        spawnTask(function() waitFor(0.15) handle(d) end)
    end))
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("TextLabel") then handle(d) end
    end
end

----------------------------------------------------------------------------------
-- SPY : capture les vrais appels du jeu, le hub les rejoue
----------------------------------------------------------------------------------
Spy = { records = {}, templates = {}, active = CONFIG.SpyActive, max = 50 }

local function describeArg(v)
    local t = typeof(v)
    if t == "Instance" then return string.format("%s(%s)", v.ClassName, v.Name) end
    if t == "string" then return '"' .. v .. '"' end
    if t == "table" then
        local parts = {}
        for k, val in pairs(v) do
            table.insert(parts, tostring(k) .. "=" ..
                (typeof(val) == "Instance" and val.Name or tostring(val)))
            if #parts >= 5 then break end
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(v)
end

function Spy.signature(rec)
    local parts = {}
    for i = 1, rec.n do table.insert(parts, describeArg(rec.args[i])) end
    return string.format("%s %s(%s)", rec.method == "InvokeServer" and "RF" or "RE",
        rec.name, table.concat(parts, ", "))
end

local function analyseRecord(rec)
    for i = 1, rec.n do
        local v = rec.args[i]
        if typeof(v) == "Instance" and v:IsA("Player") then
            if not rec.targetIndex then rec.targetIndex, rec.targetKind = i, "player" end
        elseif type(v) == "number" then
            if not rec.targetIndex then
                for _, plr in ipairs(Players:GetPlayers()) do
                    if plr.UserId == v then rec.targetIndex, rec.targetKind = i, "userid" break end
                end
            end
        elseif type(v) == "string" then
            local asPlayer = nil
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr.Name == v then asPlayer = plr break end
            end
            if asPlayer and not rec.targetIndex then
                rec.targetIndex, rec.targetKind = i, "name"
            elseif not rec.stringIndex then
                rec.stringIndex = i
            end
        end
    end
    return rec
end

function Spy.record(remote, method, args, n)
    local rec = {
        remote = remote, name = remote.Name, path = remote:GetFullName(),
        method = method, args = args, n = n, at = os.date("%H:%M:%S"),
    }
    analyseRecord(rec)
    table.insert(Spy.records, rec)
    if #Spy.records > Spy.max then table.remove(Spy.records, 1) end

    local lname = Util.lower(rec.name)
    if rec.targetIndex and (string.find(lname, "invite", 1, true)
       or string.find(lname, "request", 1, true)) then
        Spy.templates.invite = rec
        log("SPY : modele TRADE capture -> %s", Spy.signature(rec))
    elseif rec.stringIndex and (string.find(lname, "chat", 1, true)
       or string.find(lname, "message", 1, true)) then
        Spy.templates.chat = rec
        log("SPY : modele CHAT capture -> %s", Spy.signature(rec))
    else
        log("SPY : %s", Spy.signature(rec))
    end
    if UI and UI.pushSpy then pcall(UI.pushSpy, rec) end
    return rec
end

function Spy.replay(rec, subs)
    if not rec or not rec.remote or not rec.remote.Parent then
        return false, "modele invalide"
    end
    subs = subs or {}
    local args = {}
    for i = 1, rec.n do args[i] = rec.args[i] end

    if rec.targetIndex then
        if rec.targetKind == "player" and subs.target then
            args[rec.targetIndex] = subs.target
        elseif rec.targetKind == "userid" and subs.userId then
            args[rec.targetIndex] = subs.userId
        elseif rec.targetKind == "name" and subs.target then
            args[rec.targetIndex] = subs.target.Name
        end
    end
    if subs.message and rec.stringIndex then args[rec.stringIndex] = subs.message end

    local status, res = callRemote(rec.remote, args, rec.n, 5)
    if status == "ok" then return true, res end
    return false, status .. " " .. tostring(res)
end

Hook = { installed = false }

function Hook.install()
    if Hook.installed then return true end
    if not (Env.hookmetamethod and Env.getnamecall) then
        log("hook indisponible : ton executor n'expose pas hookmetamethod")
        return false, "hookmetamethod indisponible"
    end

    local old
    old = Env.hookmetamethod(game, "__namecall", function(self, ...)
        local okMethod, method = pcall(Env.getnamecall)
        if not okMethod or State.Unloaded then return old(self, ...) end
        if method ~= "FireServer" and method ~= "InvokeServer" then return old(self, ...) end

        local mine = Env.checkcaller and Env.checkcaller()
        if typeof(self) == "Instance" and not mine then
            local okName, full = pcall(function() return Util.lower(self:GetFullName()) end)

            if Spy.active and okName and string.find(full, "trade", 1, true) then
                pcall(Spy.record, self, method, { ... }, select("#", ...))
            end

            if CONFIG.TranslateOutgoing and self == Chat.remote then
                local n, args = select("#", ...), { ... }
                for i = 1, n do
                    if type(args[i]) == "string" and Util.trim(args[i]) ~= "" then
                        local original = args[i]
                        spawnTask(function()
                            local out = Translator.translate(original, CONFIG.SendAs) or original
                            args[i] = out
                            pcall(function() return old(self, unpack(args, 1, n)) end)
                            pushChat("moi", original, (out ~= original) and out or nil)
                        end)
                        return
                    end
                end
            end
        end
        return old(self, ...)
    end)

    Hook.installed = true
    log("hook __namecall installe (spy + traduction sortante)")
    return true
end

----------------------------------------------------------------------------------
-- INTERFACE : theme + composants
----------------------------------------------------------------------------------
local THEME = {
    bg      = Color3.fromRGB(13, 14, 20),
    surface = Color3.fromRGB(19, 21, 29),
    card    = Color3.fromRGB(25, 27, 37),
    cardHi  = Color3.fromRGB(33, 36, 49),
    line    = Color3.fromRGB(44, 47, 63),
    text    = Color3.fromRGB(238, 240, 248),
    sub     = Color3.fromRGB(138, 144, 168),
    accent  = Color3.fromRGB(139, 108, 255),
    accent2 = Color3.fromRGB(0, 214, 190),
    good    = Color3.fromRGB(78, 216, 148),
    warn    = Color3.fromRGB(255, 190, 92),
    bad     = Color3.fromRGB(255, 96, 112),
}

UI = { pages = {}, tabs = {} }

local function mk(class, props)
    local ok, inst = pcall(Instance.new, class)
    if not ok or not inst then inst = Instance.new("Frame") end
    local parent
    for k, v in pairs(props or {}) do
        if k == "Parent" then parent = v
        else
            if not pcall(function() inst[k] = v end) then
                warn(string.format("[TPH] propriete ignoree : %s.%s", class, tostring(k)))
            end
        end
    end
    if parent then pcall(function() inst.Parent = parent end) end
    return inst
end

local function corner(inst, r)
    mk("UICorner", { CornerRadius = UDim.new(0, r or 8), Parent = inst })
    return inst
end

local function stroke(inst, color, thickness, transparency)
    return mk("UIStroke", {
        Color = color or THEME.line, Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = inst,
    })
end

local function pad(inst, all, top, bottom, left, right)
    return mk("UIPadding", {
        PaddingTop = UDim.new(0, top or all or 0),
        PaddingBottom = UDim.new(0, bottom or all or 0),
        PaddingLeft = UDim.new(0, left or all or 0),
        PaddingRight = UDim.new(0, right or all or 0),
        Parent = inst,
    })
end

local function listLayout(inst, padding, horizontal)
    return mk("UIListLayout", {
        FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
        Padding = UDim.new(0, padding or 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = inst,
    })
end

local function tween(inst, props, time, style)
    local ok, t = pcall(function()
        return TweenService:Create(inst,
            TweenInfo.new(time or 0.16, style or Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
            props)
    end)
    if ok and t then t:Play() return t end
end

local function guiParent()
    if Env.gethui then
        local ok, hui = pcall(Env.gethui)
        if ok and hui then return hui end
    end
    local ok, coreGui = pcall(function() return game:GetService("CoreGui") end)
    if ok and coreGui then
        local safe = pcall(function()
            local probe = Instance.new("ScreenGui")
            probe.Parent = coreGui
            probe:Destroy()
        end)
        if safe then return coreGui end
    end
    return LocalPlayer:WaitForChild("PlayerGui")
end

----------------------------------------------------------------------------------
-- FENETRE
----------------------------------------------------------------------------------
local screen = mk("ScreenGui", {
    Name = "TPH_" .. tostring(math.random(100000, 999999)),
    ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 9999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    Parent = guiParent(),
})
Maid.inst(screen)
if syn and syn.protect_gui then pcall(syn.protect_gui, screen) end

local WIN_W, WIN_H = 700, 470

local window = corner(mk("Frame", {
    Name = "Window",
    Size = UDim2.new(0, WIN_W, 0, WIN_H),
    Position = UDim2.new(0.5, -WIN_W / 2, 0.5, -WIN_H / 2),
    BackgroundColor3 = THEME.bg,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Parent = screen,
}), 14)
stroke(window, THEME.line, 1.5)

-- barre de titre
local titleBar = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 46),
    BackgroundColor3 = THEME.surface,
    BorderSizePixel = 0,
    Parent = window,
})
mk("UIGradient", {
    Color = ColorSequence.new(THEME.surface, THEME.card),
    Rotation = 90, Parent = titleBar,
})

corner(mk("Frame", {
    Size = UDim2.new(0, 10, 0, 10),
    Position = UDim2.new(0, 18, 0.5, -5),
    BackgroundColor3 = THEME.accent,
    BorderSizePixel = 0, Parent = titleBar,
}), 5)

mk("TextLabel", {
    Size = UDim2.new(0, 260, 1, 0), Position = UDim2.new(0, 36, 0, 0),
    BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
    Text = "TRADE PLAZA HUB", TextSize = 13, TextColor3 = THEME.text,
    TextXAlignment = Enum.TextXAlignment.Left, Parent = titleBar,
})

local versionPill = corner(mk("Frame", {
    Size = UDim2.new(0, 30, 0, 18), Position = UDim2.new(0, 172, 0.5, -9),
    BackgroundColor3 = THEME.card, BorderSizePixel = 0, Parent = titleBar,
}), 9)
stroke(versionPill, THEME.accent, 1, 0.4)
mk("TextLabel", {
    Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold, Text = "v2", TextSize = 10,
    TextColor3 = THEME.accent, Parent = versionPill,
})

local function circleButton(offsetX, color, symbol, callback)
    local b = corner(mk("TextButton", {
        Size = UDim2.new(0, 22, 0, 22), Position = UDim2.new(1, offsetX, 0.5, -11),
        BackgroundColor3 = THEME.card, AutoButtonColor = false,
        Font = Enum.Font.GothamBold, Text = symbol, TextSize = 12,
        TextColor3 = color, BorderSizePixel = 0, Parent = titleBar,
    }), 11)
    Maid.conn(b.MouseEnter:Connect(function() tween(b, { BackgroundColor3 = color }, 0.15) tween(b, { TextColor3 = THEME.bg }, 0.15) end))
    Maid.conn(b.MouseLeave:Connect(function() tween(b, { BackgroundColor3 = THEME.card }, 0.15) tween(b, { TextColor3 = color }, 0.15) end))
    Maid.conn(b.MouseButton1Click:Connect(callback))
    return b
end

-- corps : barre laterale + contenu
local bodyFrame = mk("Frame", {
    Size = UDim2.new(1, 0, 1, -46 - 28), Position = UDim2.new(0, 0, 0, 46),
    BackgroundTransparency = 1, Parent = window,
})

local sidebar = mk("Frame", {
    Size = UDim2.new(0, 152, 1, 0), BackgroundColor3 = THEME.surface,
    BorderSizePixel = 0, Parent = bodyFrame,
})
listLayout(sidebar, 4)
pad(sidebar, 10)

local contentArea = mk("Frame", {
    Size = UDim2.new(1, -152, 1, 0), Position = UDim2.new(0, 152, 0, 0),
    BackgroundTransparency = 1, Parent = bodyFrame,
})

-- barre de statut
local statusBar = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 28), Position = UDim2.new(0, 0, 1, -28),
    BackgroundColor3 = THEME.surface, BorderSizePixel = 0, Parent = window,
})
local statusDot = corner(mk("Frame", {
    Size = UDim2.new(0, 7, 0, 7), Position = UDim2.new(0, 16, 0.5, -3.5),
    BackgroundColor3 = THEME.sub, BorderSizePixel = 0, Parent = statusBar,
}), 4)
local statusText = mk("TextLabel", {
    Size = UDim2.new(1, -40, 1, 0), Position = UDim2.new(0, 30, 0, 0),
    BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = "initialisation...",
    TextSize = 11, TextColor3 = THEME.sub, TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd, Parent = statusBar,
})

local function setStatus(text, color)
    statusText.Text = tostring(text)
    tween(statusText, { TextColor3 = color or THEME.sub }, 0.2)
    tween(statusDot, { BackgroundColor3 = color or THEME.sub }, 0.2)
end

--// deplacement de la fenetre
do
    local dragging, dragStart, startPos = false, nil, nil
    Maid.conn(titleBar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, i.Position, window.Position
        end
    end))
    Maid.conn(UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
        or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            window.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                        startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    Maid.conn(UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end))
end

----------------------------------------------------------------------------------
-- COMPOSANTS
----------------------------------------------------------------------------------
local function addTab(name)
    local page = mk("ScrollingFrame", {
        Name = name, Size = UDim2.new(1, -20, 1, -16),
        Position = UDim2.new(0, 12, 0, 8), BackgroundTransparency = 1,
        BorderSizePixel = 0, ScrollBarThickness = 3,
        ScrollBarImageColor3 = THEME.accent, CanvasSize = UDim2.new(),
        Visible = false, Parent = contentArea,
    })
    local layout = listLayout(page, 10)
    Maid.conn(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        page.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 14)
    end))

    local tab = corner(mk("TextButton", {
        Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = THEME.card,
        BackgroundTransparency = 1, AutoButtonColor = false,
        Font = Enum.Font.GothamMedium, Text = "", TextSize = 12,
        BorderSizePixel = 0, Parent = sidebar,
    }), 8)
    local mark = corner(mk("Frame", {
        Size = UDim2.new(0, 3, 0, 0), Position = UDim2.new(0, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = THEME.accent,
        BorderSizePixel = 0, Parent = tab,
    }), 2)
    local tabLabel = mk("TextLabel", {
        Size = UDim2.new(1, -14, 1, 0), Position = UDim2.new(0, 14, 0, 0),
        BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, Text = name,
        TextSize = 12, TextColor3 = THEME.sub,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = tab,
    })

    UI.pages[name] = page
    UI.tabs[name] = { button = tab, label = tabLabel, mark = mark }

    Maid.conn(tab.MouseEnter:Connect(function()
        if not page.Visible then tween(tab, { BackgroundTransparency = 0.5 }, 0.15) end
    end))
    Maid.conn(tab.MouseLeave:Connect(function()
        if not page.Visible then tween(tab, { BackgroundTransparency = 1 }, 0.15) end
    end))
    Maid.conn(tab.MouseButton1Click:Connect(function() UI.select(name) end))
    return page
end

function UI.select(name)
    for tabName, page in pairs(UI.pages) do
        local active = (tabName == name)
        page.Visible = active
        local t = UI.tabs[tabName]
        tween(t.button, { BackgroundTransparency = active and 0 or 1 }, 0.16)
        tween(t.label, { TextColor3 = active and THEME.text or THEME.sub }, 0.16)
        tween(t.mark, { Size = UDim2.new(0, 3, 0, active and 18 or 0) }, 0.18)
    end
end

-- carte : bloc titre + contenu
local function card(page, title, subtitle)
    local holder = corner(mk("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = THEME.card, BorderSizePixel = 0, Parent = page,
    }), 12)
    stroke(holder, THEME.line, 1, 0.35)
    pad(holder, 14)
    listLayout(holder, 8)

    if title then
        local head = mk("Frame", {
            Size = UDim2.new(1, 0, 0, subtitle and 32 or 16),
            BackgroundTransparency = 1, Parent = holder,
        })
        mk("TextLabel", {
            Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold, Text = string.upper(title), TextSize = 11,
            TextColor3 = THEME.accent, TextXAlignment = Enum.TextXAlignment.Left,
            Parent = head,
        })
        if subtitle then
            mk("TextLabel", {
                Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, 17),
                BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = subtitle,
                TextSize = 11, TextColor3 = THEME.sub,
                TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
                Parent = head,
            })
        end
    end
    return holder
end

local function note(parent, text, color)
    return mk("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = text,
        TextSize = 11, TextColor3 = color or THEME.sub,
        TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Parent = parent,
    })
end

local function rowOf(parent, height)
    local frame = mk("Frame", {
        Size = UDim2.new(1, 0, 0, height or 32), BackgroundTransparency = 1, Parent = parent,
    })
    listLayout(frame, 6, true)
    return frame
end

local function btn(parent, opts)
    local style = opts.style or "ghost"
    local base  = (style == "primary" and THEME.accent)
        or (style == "danger" and THEME.bad) or THEME.cardHi
    local textColor = (style == "primary" or style == "danger") and THEME.bg or THEME.text
    local hover = (style == "primary" and THEME.accent2)
        or (style == "danger" and Color3.fromRGB(255, 140, 150)) or THEME.line

    local b = corner(mk("TextButton", {
        Size = opts.width and UDim2.new(0, opts.width, 0, opts.height or 32)
                          or UDim2.new(1, 0, 0, opts.height or 32),
        BackgroundColor3 = base, AutoButtonColor = false,
        Font = Enum.Font.GothamMedium, Text = opts.text, TextSize = 12,
        TextColor3 = textColor, BorderSizePixel = 0, Parent = parent,
    }), 8)
    if style == "ghost" then stroke(b, THEME.line, 1, 0.4) end

    local baseSize = b.Size
    local pressedSize = baseSize - UDim2.new(0, 0, 0, 2)
    Maid.conn(b.MouseEnter:Connect(function() tween(b, { BackgroundColor3 = hover }, 0.14) end))
    Maid.conn(b.MouseLeave:Connect(function()
        tween(b, { BackgroundColor3 = base, Size = baseSize }, 0.14)
    end))
    Maid.conn(b.MouseButton1Down:Connect(function() tween(b, { Size = pressedSize }, 0.08) end))
    Maid.conn(b.MouseButton1Up:Connect(function() tween(b, { Size = baseSize }, 0.08) end))
    Maid.conn(b.MouseButton1Click:Connect(function()
        spawnTask(function()
            local ok, err = pcall(opts.callback)
            if not ok then log("erreur bouton '%s' : %s", tostring(opts.text), tostring(err)) end
        end)
    end))
    return b
end

local function field(parent, placeholder, onEnter, width)
    local box = corner(mk("TextBox", {
        Size = width and UDim2.new(0, width, 0, 34) or UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = THEME.surface, Font = Enum.Font.Gotham,
        PlaceholderText = placeholder, PlaceholderColor3 = THEME.sub, Text = "",
        TextSize = 12, TextColor3 = THEME.text, ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left, BorderSizePixel = 0, Parent = parent,
    }), 8)
    local st = stroke(box, THEME.line, 1, 0.2)
    pad(box, nil, 0, 0, 10, 10)
    Maid.conn(box.Focused:Connect(function() tween(st, { Color = THEME.accent, Transparency = 0 }, 0.15) end))
    Maid.conn(box.FocusLost:Connect(function(enter)
        tween(st, { Color = THEME.line, Transparency = 0.2 }, 0.15)
        if enter and onEnter then spawnTask(function() pcall(onEnter, box.Text, box) end) end
    end))
    return box
end

local function switch(parent, text, key, callback)
    local holder = corner(mk("TextButton", {
        Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = THEME.surface,
        AutoButtonColor = false, Text = "", BorderSizePixel = 0, Parent = parent,
    }), 8)
    mk("TextLabel", {
        Size = UDim2.new(1, -70, 1, 0), Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = text, TextSize = 12,
        TextColor3 = THEME.text, TextXAlignment = Enum.TextXAlignment.Left, Parent = holder,
    })
    local track = corner(mk("Frame", {
        Size = UDim2.new(0, 42, 0, 20), Position = UDim2.new(1, -54, 0.5, -10),
        BackgroundColor3 = CONFIG[key] and THEME.accent or THEME.line,
        BorderSizePixel = 0, Parent = holder,
    }), 10)
    local knob = corner(mk("Frame", {
        Size = UDim2.new(0, 16, 0, 16),
        Position = CONFIG[key] and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8),
        BackgroundColor3 = THEME.text, BorderSizePixel = 0, Parent = track,
    }), 8)

    Maid.conn(holder.MouseButton1Click:Connect(function()
        CONFIG[key] = not CONFIG[key]
        tween(track, { BackgroundColor3 = CONFIG[key] and THEME.accent or THEME.line }, 0.18)
        tween(knob, { Position = CONFIG[key] and UDim2.new(1, -18, 0.5, -8)
                                             or UDim2.new(0, 2, 0.5, -8) }, 0.18,
              Enum.EasingStyle.Back)
        if callback then spawnTask(function() pcall(callback, CONFIG[key]) end) end
    end))
    return holder
end

-- ligne de choix (ex : mode de teleport, langue)
local function chips(parent, values, key, callback)
    local holder = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Parent = parent,
    })
    listLayout(holder, 6, true)
    local buttons, labels = {}, {}
    local function refresh()
        for value, b in pairs(buttons) do
            local active = (CONFIG[key] == value)
            tween(b, { BackgroundColor3 = active and THEME.accent or THEME.surface }, 0.15)
            tween(labels[value], { TextColor3 = active and THEME.bg or THEME.sub }, 0.15)
        end
    end
    for _, value in ipairs(values) do
        local b = corner(mk("TextButton", {
            Size = UDim2.new(0, math.max(56, #tostring(value) * 9 + 22), 1, 0),
            BackgroundColor3 = THEME.surface, AutoButtonColor = false, Text = "",
            BorderSizePixel = 0, Parent = holder,
        }), 8)
        local lbl = mk("TextLabel", {
            Name = "Label", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
            Font = Enum.Font.GothamMedium, Text = tostring(value), TextSize = 11,
            TextColor3 = THEME.sub, Parent = b,
        })
        buttons[value], labels[value] = b, lbl
        Maid.conn(b.MouseButton1Click:Connect(function()
            CONFIG[key] = value
            refresh()
            if callback then spawnTask(function() pcall(callback, value) end) end
        end))
    end
    refresh()
    return holder
end

-- curseur de reglage (vitesse du teleport, altitude...)
local function slider(parent, text, key, minVal, maxVal, suffix)
    local holder = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1, Parent = parent,
    })
    local label = mk("TextLabel", {
        Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Font = Enum.Font.Gotham,
        Text = text, TextSize = 11, TextColor3 = THEME.sub,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = holder,
    })
    local valueLabel = mk("TextLabel", {
        Size = UDim2.new(0, 90, 0, 16), Position = UDim2.new(1, -90, 0, 0),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
        Text = tostring(CONFIG[key]) .. (suffix or ""), TextSize = 11,
        TextColor3 = THEME.accent2, TextXAlignment = Enum.TextXAlignment.Right, Parent = holder,
    })
    local bar = corner(mk("Frame", {
        Size = UDim2.new(1, 0, 0, 8), Position = UDim2.new(0, 0, 0, 26),
        BackgroundColor3 = THEME.surface, BorderSizePixel = 0, Parent = holder,
    }), 4)
    local alpha = (CONFIG[key] - minVal) / math.max(1, (maxVal - minVal))
    local fill = corner(mk("Frame", {
        Size = UDim2.new(alpha, 0, 1, 0), BackgroundColor3 = THEME.accent,
        BorderSizePixel = 0, Parent = bar,
    }), 4)
    local knob = corner(mk("Frame", {
        Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(alpha, -7, 0.5, -7),
        BackgroundColor3 = THEME.text, BorderSizePixel = 0, Parent = bar,
    }), 7)

    local dragging = false
    local function apply(x)
        local rel = math.clamp((x - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X), 0, 1)
        local value = math.floor(minVal + (maxVal - minVal) * rel + 0.5)
        CONFIG[key] = value
        valueLabel.Text = tostring(value) .. (suffix or "")
        fill.Size = UDim2.new(rel, 0, 1, 0)
        knob.Position = UDim2.new(rel, -7, 0.5, -7)
    end
    Maid.conn(bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true apply(i.Position.X)
        end
    end))
    Maid.conn(UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
        or i.UserInputType == Enum.UserInputType.Touch) then apply(i.Position.X) end
    end))
    Maid.conn(UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end))
    return holder
end

local function panel(parent, height)
    local holder = corner(mk("Frame", {
        Size = UDim2.new(1, 0, 0, height or 150), BackgroundColor3 = THEME.surface,
        BorderSizePixel = 0, Parent = parent,
    }), 8)
    local scroll = mk("ScrollingFrame", {
        Size = UDim2.new(1, -10, 1, -10), Position = UDim2.new(0, 5, 0, 5),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
        ScrollBarImageColor3 = THEME.accent, CanvasSize = UDim2.new(), Parent = holder,
    })
    local layout = listLayout(scroll, 4)
    Maid.conn(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 8)
    end))
    return scroll
end

local function textLine(scroll, text, color, font)
    return mk("TextLabel", {
        Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, Font = font or Enum.Font.Code, Text = text,
        TextSize = 11, TextColor3 = color or THEME.sub,
        TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Parent = scroll,
    })
end

-- ligne de liste avec des boutons a droite
local function entryRow(scroll, text, subtext, actions)
    local row = corner(mk("Frame", {
        Size = UDim2.new(1, -6, 0, 34), BackgroundColor3 = THEME.card,
        BackgroundTransparency = 0.35, BorderSizePixel = 0, Parent = scroll,
    }), 6)
    local width = 0
    for _, a in ipairs(actions or {}) do width = width + (a.width or 54) + 4 end

    mk("TextLabel", {
        Size = UDim2.new(1, -width - 20, 0, subtext and 14 or 34),
        Position = UDim2.new(0, 10, 0, subtext and 4 or 0),
        BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, Text = text,
        TextSize = 11, TextColor3 = THEME.text, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
    })
    if subtext then
        mk("TextLabel", {
            Size = UDim2.new(1, -width - 20, 0, 12), Position = UDim2.new(0, 10, 0, 18),
            BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = subtext,
            TextSize = 10, TextColor3 = THEME.sub, TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
        })
    end
    if actions and #actions > 0 then
        local holder = mk("Frame", {
            Size = UDim2.new(0, width, 1, -8), Position = UDim2.new(1, -width - 6, 0, 4),
            BackgroundTransparency = 1, Parent = row,
        })
        listLayout(holder, 4, true)
        for _, a in ipairs(actions) do
            btn(holder, { text = a.text, width = a.width or 54, height = 26,
                          style = a.style or "ghost", callback = a.callback })
        end
    end
    return row
end

local function clearChildren(scroll)
    for _, child in ipairs(scroll:GetChildren()) do
        if not child:IsA("UIListLayout") then child:Destroy() end
    end
end

-- bouton qui fait defiler une liste de valeurs (langues)
local function cycleButton(parent, prefix, values, key, width, callback)
    local index = 1
    for i, v in ipairs(values) do
        if v == CONFIG[key] then index = i break end
    end
    local b
    b = btn(parent, {
        text = prefix .. " " .. tostring(CONFIG[key]), width = width, style = "ghost",
        callback = function()
            index = index % #values + 1
            CONFIG[key] = values[index]
            b.Text = prefix .. " " .. tostring(CONFIG[key])
            if callback then pcall(callback, CONFIG[key]) end
        end,
    })
    return b
end

local inspectBase   -- defini dans l'onglet Base
local refreshPlayers

----------------------------------------------------------------------------------
-- ONGLET : TELEPORT
----------------------------------------------------------------------------------
local pageTP = addTab("Teleport")

local cardDest = card(pageTP, "Destination", "pseudo ou UserId du joueur")
local tpField = field(cardDest, "ex : Hugosousbdv  ou  1234567890")
local rowDest = rowOf(cardDest)
btn(rowDest, { text = "Aller a sa base", width = 150, style = "primary", callback = function()
    local plr, err = PlayerUtil.byQuery(tpField.Text)
    if not plr then setStatus(err or "joueur introuvable", THEME.bad) return end
    setStatus("deplacement vers la base de " .. plr.Name .. "...", THEME.warn)
    local ok, e = TP.toBase(plr)
    setStatus(ok and ("arrive a la base de " .. plr.Name) or tostring(e), ok and THEME.good or THEME.bad)
    if ok then inspectBase(plr) end
end })
btn(rowDest, { text = "Aller au joueur", width = 140, callback = function()
    local plr, err = PlayerUtil.byQuery(tpField.Text)
    if not plr then setStatus(err or "joueur introuvable", THEME.bad) return end
    setStatus("deplacement vers " .. plr.Name .. "...", THEME.warn)
    local ok, e = TP.toPlayer(plr)
    setStatus(ok and ("arrive sur " .. plr.Name) or tostring(e), ok and THEME.good or THEME.bad)
end })
btn(rowDest, { text = "Retour", width = 90, callback = function()
    local ok, e = TP.back()
    setStatus(ok and "retour effectue" or tostring(e), ok and THEME.good or THEME.bad)
end })
btn(rowDest, { text = "Stop", width = 70, style = "danger", callback = function()
    TP.stop()
    setStatus("deplacement arrete", THEME.warn)
end })

local cardMode = card(pageTP, "Mode de deplacement",
    "lent = glisse progressive (recommande, evite le retour en arriere et la mort) | marche = le perso marche vraiment | instant = brutal")
chips(cardMode, { "lent", "marche", "instant" }, "TPMode")
slider(cardMode, "Vitesse du deplacement", "TPSpeed", 20, 250, " studs/s")
slider(cardMode, "Altitude de croisiere", "TPAltitude", 0, 120, " studs")
switch(cardMode, "Traverser les murs pendant le trajet", "TPNoclip")
switch(cardMode, "Regarder vers la destination", "TPFaceTarget")
note(cardMode, "Si tu te fais encore renvoyer en arriere : baisse la vitesse vers 40-60 studs/s. Si tu meurs a l'arrivee : monte l'altitude.", THEME.warn)

local cardPlayers = card(pageTP, "Joueurs du serveur")
local playersPanel = panel(cardPlayers, 170)
btn(cardPlayers, { text = "Rafraichir la liste", callback = function()
    refreshPlayers()
    setStatus("liste rafraichie", THEME.good)
end })

refreshPlayers = function()
    clearChildren(playersPanel)
    local list = Players:GetPlayers()
    local shown = 0
    for _, plr in ipairs(list) do
        if plr ~= LocalPlayer then
            shown = shown + 1
            entryRow(playersPanel, plr.DisplayName ~= plr.Name
                    and (plr.DisplayName .. "  (@" .. plr.Name .. ")") or plr.Name,
                "UserId " .. plr.UserId, {
                { text = "Base", width = 52, callback = function()
                    setStatus("deplacement vers la base de " .. plr.Name .. "...", THEME.warn)
                    local ok, e = TP.toBase(plr)
                    setStatus(ok and ("arrive chez " .. plr.Name) or tostring(e),
                        ok and THEME.good or THEME.bad)
                end },
                { text = "Voir", width = 50, callback = function() inspectBase(plr) end },
                { text = "Trade", width = 56, style = "primary", callback = function()
                    local ok, msg = Trade.invite(tostring(plr.UserId))
                    setStatus(msg, ok and THEME.good or THEME.bad)
                end },
            })
        end
    end
    if shown == 0 then textLine(playersPanel, "aucun autre joueur dans le serveur", THEME.sub) end
end

----------------------------------------------------------------------------------
-- ONGLET : TRADE
----------------------------------------------------------------------------------
local pageTrade = addTab("Trade")

local cardInvite = card(pageTrade, "Envoyer une demande de trade")
local inviteInfo = note(cardInvite, "remote : recherche en cours...", THEME.sub)
local tradeField = field(cardInvite, "pseudo ou UserId...", function(text)
    local ok, msg = Trade.invite(text)
    setStatus(msg, ok and THEME.good or THEME.bad)
end)
local rowInvite = rowOf(cardInvite)
btn(rowInvite, { text = "Envoyer le trade", width = 160, style = "primary", callback = function()
    setStatus("envoi en cours...", THEME.warn)
    local ok, msg = Trade.invite(tradeField.Text)
    setStatus(msg, ok and THEME.good or THEME.bad)
end })
btn(rowInvite, { text = "Joueur le plus proche", width = 180, callback = function()
    local root = TP.root()
    if not root then setStatus("pas de personnage", THEME.bad) return end
    local best, bestDist
    for _, plr in ipairs(Players:GetPlayers()) do
        local char = plr.Character
        local r = char and char:FindFirstChild("HumanoidRootPart")
        if plr ~= LocalPlayer and r then
            local d = (r.Position - root.Position).Magnitude
            if not bestDist or d < bestDist then best, bestDist = plr, d end
        end
    end
    if not best then setStatus("personne a proximite", THEME.bad) return end
    local ok, msg = Trade.invite(tostring(best.UserId))
    setStatus(msg, ok and THEME.good or THEME.bad)
end })

local cardActions = card(pageTrade, "Actions rapides", "envoyees telles quelles au serveur")
local rowActions = rowOf(cardActions)
for _, action in ipairs({ "Accept", "Ready", "Decline", "Cancel" }) do
    btn(rowActions, { text = action, width = 96,
        style = (action == "Cancel" or action == "Decline") and "danger" or "ghost",
        callback = function()
            local ok, msg = Trade.simple(action)
            setStatus(msg, ok and THEME.good or THEME.bad)
        end })
end

local cardFormat = card(pageTrade, "Format des arguments",
    "laisse sur auto : le hub teste chaque format et retient celui qui marche")
chips(cardFormat, { "auto", "player", "userid", "name" }, "ArgMode")
note(cardFormat, "Si rien ne marche : va dans l'onglet Spy, clique UNE fois sur le vrai bouton de trade du jeu, puis reessaie ici. Le hub rejouera exactement le meme appel avec ta cible.", THEME.warn)

----------------------------------------------------------------------------------
-- ONGLET : CHAT
----------------------------------------------------------------------------------
local pageChat = addTab("Chat")

local cardTrad = card(pageChat, "Traducteur")
local rowLangs = rowOf(cardTrad)
cycleButton(rowLangs, "Je lis en :", LANGS, "TranslateTo", 170)
cycleButton(rowLangs, "J'ecris en :", LANGS, "SendAs", 170)
switch(cardTrad, "Traduire les messages recus", "TranslateIncoming")
switch(cardTrad, "Traduire ce que je tape dans le jeu", "TranslateOutgoing", function(on)
    if on then Hook.install() end
end)
switch(cardTrad, "Garder le texte original a cote", "ShowOriginal")
switch(cardTrad, "Reecrire les bulles du chat du jeu", "PatchChatGui")

local cardConv = card(pageChat, "Conversation")
local chatPanel = panel(cardConv, 160)
local chatField = field(cardConv, "ton message (tape en francais)...")
local rowSend = rowOf(cardConv)
btn(rowSend, { text = "Traduire et envoyer", width = 180, style = "primary", callback = function()
    local ok, msg = Chat.send(chatField.Text, CONFIG.SendAs)
    if ok then chatField.Text = "" end
    setStatus(ok and ("envoye : " .. tostring(msg)) or tostring(msg), ok and THEME.good or THEME.bad)
end })
btn(rowSend, { text = "Envoyer brut", width = 130, callback = function()
    local ok, msg = Chat.send(chatField.Text, nil)
    if ok then chatField.Text = "" end
    setStatus(ok and "envoye" or tostring(msg), ok and THEME.good or THEME.bad)
end })
btn(rowSend, { text = "Test", width = 70, callback = function()
    local out, err = Translator.translate("salut, tu veux trade ?", CONFIG.SendAs)
    setStatus(out or ("traduction KO : " .. tostring(err)), out and THEME.good or THEME.bad)
end })

local cardPhrases = card(pageChat, "Phrases rapides", "fonctionnent meme sans traduction en ligne")
for i = 1, #Translator.phrases, 2 do
    local row = rowOf(cardPhrases, 30)
    for j = i, math.min(i + 1, #Translator.phrases) do
        local phrase = Translator.phrases[j]
        btn(row, { text = phrase.fr, width = 232, height = 30, callback = function()
            local ok, msg = Chat.send(phrase.fr, CONFIG.SendAs)
            setStatus(ok and ("envoye : " .. tostring(msg)) or tostring(msg),
                ok and THEME.good or THEME.bad)
        end })
    end
end

function UI.pushChat(entry)
    textLine(chatPanel, string.format("[%s] %s : %s", entry.at, entry.who, entry.original), THEME.sub)
    if entry.translated and entry.translated ~= entry.original then
        textLine(chatPanel, "      -> " .. entry.translated, THEME.accent2)
    end
    local children = chatPanel:GetChildren()
    if #children > 120 then
        for i = 1, 20 do
            local c = children[i]
            if c and not c:IsA("UIListLayout") then c:Destroy() end
        end
    end
end

----------------------------------------------------------------------------------
-- ONGLET : BASE (scanner de brainrots)
----------------------------------------------------------------------------------
local pageBase = addTab("Base")

local cardScan = card(pageBase, "Scanner une base")
local baseField = field(cardScan, "pseudo ou UserId...")
local rowScan = rowOf(cardScan)
btn(rowScan, { text = "Scanner sa base", width = 150, style = "primary", callback = function()
    local plr, err = PlayerUtil.byQuery(baseField.Text)
    if not plr then setStatus(err or "joueur introuvable", THEME.bad) return end
    inspectBase(plr)
end })
btn(rowScan, { text = "Ma base", width = 100, callback = function() inspectBase(LocalPlayer) end })
btn(rowScan, { text = "Re-scanner", width = 110, callback = function()
    if State.Plot then inspectBase(nil, State.Plot, State.PlotOwner)
    else setStatus("scanne d'abord une base", THEME.bad) end
end })

local baseSummary = note(cardScan, "aucune base scannee", THEME.text)

local cardBrainrots = card(pageBase, "Brainrots trouves", "tries par revenu total")
local brainrotPanel = panel(cardBrainrots, 190)

local cardObjects = card(pageBase, "Autres objets poses")
local objectsPanel = panel(cardObjects, 110)
btn(cardObjects, { text = "Copier la structure de la base (pour debug)", callback = function()
    if not State.Plot then setStatus("scanne d'abord une base", THEME.bad) return end
    local dump = Inspector.dump(State.Plot, 400)
    if Util.copy(dump) then setStatus("structure copiee dans le presse-papier", THEME.good)
    else print(dump) setStatus("presse-papier indispo -> envoye dans la console F9", THEME.warn) end
end })

inspectBase = function(player, model, ownerName)
    local plot = model
    ownerName = ownerName or (player and player.Name) or "?"
    if not plot and player then plot = Plots:ForPlayer(player) end
    if not plot then
        setStatus("base introuvable pour " .. ownerName, THEME.bad)
        baseSummary.Text = "base introuvable pour " .. ownerName
        return
    end
    State.Plot, State.PlotOwner = plot, ownerName
    UI.select("Base")

    clearChildren(brainrotPanel)
    clearChildren(objectsPanel)

    local brainrots, totalIncome, count = Inspector.brainrots(plot)
    baseSummary.Text = string.format("Base de %s  -  %d brainrots  -  %d types  -  revenu total $%s/s",
        ownerName, count, #brainrots, Util.short(totalIncome))
    baseSummary.TextColor3 = THEME.text

    if #brainrots == 0 then
        textLine(brainrotPanel, "aucun brainrot reconnu sur cette base", THEME.bad)
        textLine(brainrotPanel, "utilise 'Copier la structure' et envoie-moi le resultat", THEME.sub)
    else
        for _, b in ipairs(brainrots) do
            local tags = {}
            if b.mutation then table.insert(tags, b.mutation) end
            if b.rarity then table.insert(tags, b.rarity) end
            local right = b.income > 0 and ("$" .. Util.short(b.income) .. "/s") or "-"
            entryRow(brainrotPanel,
                string.format("x%d  %s", b.count, b.name),
                (#tags > 0 and (table.concat(tags, " . ") .. "   ") or "") .. right, {})
        end
    end

    local items = Inspector.items(plot)
    if #items == 0 then
        textLine(objectsPanel, "rien d'autre trouve", THEME.sub)
    else
        for i, item in ipairs(items) do
            if i > 40 then break end
            textLine(objectsPanel, string.format("x%-3d %s", item.count, item.name), THEME.sub)
        end
    end
    setStatus("base de " .. ownerName .. " scannee", THEME.good)
end

----------------------------------------------------------------------------------
-- ONGLET : SPY
----------------------------------------------------------------------------------
local pageSpy = addTab("Spy")

local cardSpy = card(pageSpy, "Capture des appels du jeu",
    "1. laisse la capture active   2. dans le jeu, clique une fois sur le VRAI bouton de trade et envoie un VRAI message dans le chat   3. le hub rejoue ensuite ces appels avec ta cible")
switch(cardSpy, "Capture active", "SpyActive", function(on)
    Spy.active = on
    if on then Hook.install() end
end)
local spyTemplates = note(cardSpy, "aucun appel capture pour l'instant", THEME.warn)

local cardSpyList = card(pageSpy, "Appels captures")
local spyPanel = panel(cardSpyList, 200)
btn(cardSpyList, { text = "Vider la capture", style = "danger", callback = function()
    Spy.records, Spy.templates = {}, {}
    clearChildren(spyPanel)
    spyTemplates.Text = "aucun appel capture pour l'instant"
    setStatus("capture videe", THEME.warn)
end })

local function refreshSpy()
    clearChildren(spyPanel)
    if #Spy.records == 0 then
        textLine(spyPanel, Hook.installed and "en attente d'un appel du jeu..."
            or "hook non installe (executor sans hookmetamethod)", THEME.sub)
    end
    for i = #Spy.records, 1, -1 do
        local rec = Spy.records[i]
        entryRow(spyPanel, Spy.signature(rec), rec.at .. "   " .. rec.path, {
            { text = "Trade", width = 56, style = "primary", callback = function()
                Spy.templates.invite = rec
                setStatus("modele de trade defini", THEME.good)
                refreshSpy()
            end },
            { text = "Chat", width = 52, callback = function()
                Spy.templates.chat = rec
                setStatus("modele de chat defini", THEME.good)
                refreshSpy()
            end },
        })
    end
    local parts = {}
    if Spy.templates.invite then
        table.insert(parts, "TRADE : " .. Spy.signature(Spy.templates.invite))
    end
    if Spy.templates.chat then
        table.insert(parts, "CHAT : " .. Spy.signature(Spy.templates.chat))
    end
    spyTemplates.Text = #parts > 0 and table.concat(parts, "\n")
        or "aucun appel capture pour l'instant"
    spyTemplates.TextColor3 = #parts > 0 and THEME.good or THEME.warn
end

function UI.pushSpy()
    refreshSpy()
end

----------------------------------------------------------------------------------
-- ONGLET : CONFIG
----------------------------------------------------------------------------------
local pageConfig = addTab("Config")

local cardInfo = card(pageConfig, "Etat du hub")
local infoNote = note(cardInfo, "...", THEME.text)

local cardRemotes = card(pageConfig, "Remotes lies au trade")
local remotesPanel = panel(cardRemotes, 150)

local function refreshRemotes()
    clearChildren(remotesPanel)
    local found = Remotes:Scan()
    if #found == 0 then
        textLine(remotesPanel, "aucun remote 'trade' trouve", THEME.bad)
        return
    end
    for _, remote in ipairs(found) do
        local full = remote:GetFullName()
        entryRow(remotesPanel, (remote:IsA("RemoteFunction") and "[RF] " or "[RE] ") .. remote.Name,
            full, {
            { text = "copier", width = 60, callback = function()
                if Util.copy(full) then setStatus("chemin copie", THEME.good)
                else print(full) setStatus("copie indispo -> console F9", THEME.warn) end
            end },
        })
    end
    setStatus(#found .. " remotes trouves", THEME.good)
end

local rowCfg = rowOf(cardRemotes)
btn(rowCfg, { text = "Scanner les remotes", width = 170, callback = refreshRemotes })
btn(rowCfg, { text = "Recharger les modules", width = 180, callback = function()
    Remotes.cache, Chat.remote = {}, nil
    Chat.getRemote()
    Chat.hookIncoming()
    Hook.install()
    refreshRemotes()
    setStatus("modules recharges", THEME.good)
end })

local cardLogs = card(pageConfig, "Journal")
local logsPanel = panel(cardLogs, 170)

function UI.pushLog(msg)
    textLine(logsPanel, msg, THEME.sub)
    local children = logsPanel:GetChildren()
    if #children > 150 then
        for i = 1, 40 do
            local c = children[i]
            if c and not c:IsA("UIListLayout") then c:Destroy() end
        end
    end
end

btn(cardLogs, { text = "Fermer le hub", style = "danger", callback = function()
    if GENV.TradePlazaHub and GENV.TradePlazaHub.Unload then GENV.TradePlazaHub.Unload() end
end })

----------------------------------------------------------------------------------
-- BOUTONS FENETRE / RACCOURCI / BOUTON FLOTTANT
----------------------------------------------------------------------------------
local minimized = false

circleButton(-62, THEME.warn, "-", function()
    minimized = not minimized
    bodyFrame.Visible = not minimized
    statusBar.Visible = not minimized
    tween(window, { Size = UDim2.new(0, WIN_W, 0, minimized and 46 or WIN_H) }, 0.2)
end)

circleButton(-32, THEME.bad, "X", function()
    if GENV.TradePlazaHub and GENV.TradePlazaHub.Unload then GENV.TradePlazaHub.Unload() end
end)

-- bouton rond pour rouvrir le hub quand il est cache (utile sans clavier)
local floating = corner(mk("TextButton", {
    Size = UDim2.new(0, 46, 0, 46), Position = UDim2.new(0, 18, 1, -64),
    BackgroundColor3 = THEME.accent, AutoButtonColor = false,
    Font = Enum.Font.GothamBold, Text = "TP", TextSize = 14, TextColor3 = THEME.bg,
    BorderSizePixel = 0, Visible = false, Parent = screen,
}), 23)
stroke(floating, THEME.accent2, 1.5, 0.3)

local function setWindowVisible(visible)
    window.Visible = visible
    floating.Visible = not visible
end

Maid.conn(floating.MouseButton1Click:Connect(function() setWindowVisible(true) end))
Maid.conn(UserInputService.InputBegan:Connect(function(inputObj, processed)
    if processed or State.Unloaded then return end
    if inputObj.KeyCode == CONFIG.Keybind then setWindowVisible(not window.Visible) end
end))

----------------------------------------------------------------------------------
-- UNLOAD
----------------------------------------------------------------------------------
local function unload()
    if State.Unloaded then return end
    State.Unloaded = true
    State.Cancel = true
    setNoclip(false)
    Maid.clean()
    GENV.TradePlazaHub = nil
    print("[TPH] decharge.")
end

GENV.TradePlazaHub = {
    Config = CONFIG, State = State, Remotes = Remotes, Plots = Plots,
    Teleport = TP, Trade = Trade, Chat = Chat, Translator = Translator,
    Inspector = Inspector, Spy = Spy, Hook = Hook, Unload = unload,
}

----------------------------------------------------------------------------------
-- INITIALISATION
----------------------------------------------------------------------------------
UI.select("Teleport")

-- animation d'ouverture
window.Size = UDim2.new(0, WIN_W - 60, 0, WIN_H - 40)
tween(window, { Size = UDim2.new(0, WIN_W, 0, WIN_H) }, 0.35, Enum.EasingStyle.Back)

Maid.conn(Players.PlayerAdded:Connect(function()
    if not State.Unloaded then pcall(refreshPlayers) end
end))
Maid.conn(Players.PlayerRemoving:Connect(function()
    if State.Unloaded then return end
    spawnTask(function() waitFor(0.2) pcall(refreshPlayers) end)
end))
Maid.conn(LocalPlayer.CharacterAdded:Connect(function()
    State.Cancel = true
    State.Travelling = false
end))

local function init()
    log("demarrage (executor : %s)", tostring(Env.isExecutor))

    Hook.install()
    Chat.getRemote()
    Chat.hookIncoming()
    if CONFIG.PatchChatGui then Chat.patchGui() end

    local invite = Remotes:Find("Invite") or Remotes:Find("SendRequest")
    inviteInfo.Text = invite and ("remote : " .. invite:GetFullName())
        or "remote d'invitation introuvable - passe par l'onglet Spy"
    inviteInfo.TextColor3 = invite and THEME.good or THEME.warn

    refreshPlayers()
    refreshRemotes()
    refreshSpy()

    local httpOk = Util.httpGet(
        "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=en&dt=t&q=test") ~= nil

    infoNote.Text = table.concat({
        "Touche du menu          : " .. tostring(CONFIG.Keybind.Name),
        "Executor detecte        : " .. (Env.isExecutor and "oui" or "non"),
        "Hook / spy              : " .. (Hook.installed and "actif" or "indisponible"),
        "Traduction en ligne     : " .. (httpOk and "operationnelle" or "INDISPO (phrases rapides seulement)"),
        "Presse-papier           : " .. (Env.clipboard and "ok" or "indispo"),
        "Remote d'invitation     : " .. (invite and invite:GetFullName() or "introuvable"),
        "Remote de chat          : " .. (Chat.remote and Chat.remote:GetFullName() or "introuvable"),
        "Bases detectees         : " .. tostring(#Plots:All()),
        "API console             : getgenv().TradePlazaHub",
    }, "\n")

    setStatus("pret - " .. tostring(CONFIG.Keybind.Name) .. " pour cacher le menu", THEME.good)
    notify("Trade Plaza Hub v2", "Charge. " .. tostring(CONFIG.Keybind.Name) .. " pour afficher/cacher.", 6)
end

spawnTask(function()
    local ok, err = pcall(init)
    if not ok then
        setStatus("erreur init (console F9)", THEME.bad)
        log("ERREUR INIT : %s", tostring(err))
        warn("[TPH] ERREUR INIT : " .. tostring(err))
    end
end)

print("[TPH] interface construite - touche " .. tostring(CONFIG.Keybind.Name))
return GENV.TradePlazaHub

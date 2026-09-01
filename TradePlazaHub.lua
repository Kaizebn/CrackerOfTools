--[[
==================================================================================
    TRADE PLAZA HUB  v3   --  script client (executor / LocalScript)
==================================================================================
    4 onglets seulement :
      JOUEURS  - liste avec la tete de chaque joueur, TP vers sa base, send trade
      BASE     - scanner de brainrots avec apercu 3D, mutation et revenu/s
      CHAT     - traducteur du chat de trade (entrant + sortant)
      REGLAGES - mode de deplacement, vitesse, langues, journal

    Deplacement : le personnage bouge UNIQUEMENT avec le moteur physique
    (BodyVelocity) ou en marchant. Aucune ecriture de CFrame sur le personnage,
    aucun noclip : rien de ce que les anticheats de position savent detecter.

    Remotes : un seul remote d'invitation et un seul remote de chat sont
    utilises, et chaque envoi passe par un limiteur de debit (pas de rafale,
    donc pas de rate limit serveur).

    Touche menu : RightControl
==================================================================================
]]

local GENV = (getgenv and getgenv()) or _G
if GENV.TradePlazaHub and GENV.TradePlazaHub.Unload then
    pcall(GENV.TradePlazaHub.Unload)
end
print("[TPH] chargement...")

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local StarterGui        = game:GetService("StarterGui")
local HttpService       = game:GetService("HttpService")

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
    Keybind      = Enum.KeyCode.RightControl,

    -- deplacement (aucun mode n'ecrit de CFrame sur le personnage)
    TPMode       = "physique",  -- physique | marche
    TPSpeed      = 45,          -- studs/seconde (45 = a peine plus qu'une course)
    TPAltitude   = 18,          -- hauteur de survol
    TPLandSlow   = true,        -- descente freinee : plus de degats de chute

    -- limiteur d'envoi des remotes (secondes)
    RemoteMinGap   = 0.8,       -- delai minimum entre deux appels, tous remotes confondus
    RemoteCooldown = 1.5,       -- delai minimum entre deux appels du meme remote
    InviteCooldown = 6,         -- delai minimum entre deux invitations de trade
    ChatCooldown   = 2,         -- delai minimum entre deux messages

    -- traduction
    TranslateTo       = "fr",
    SendAs            = "en",
    TranslateIncoming = true,
    ShowOriginal      = true,
    PatchChatGui      = true,

    -- affichage
    ShowAvatars  = true,
    ShowModels   = true,

    ArgMode      = "auto",
    RemotePaths  = {},
}

if type(GENV.TradePlazaHubConfig) == "table" then
    for k, v in pairs(GENV.TradePlazaHubConfig) do CONFIG[k] = v end
end

-- le mode "cframe" a ete supprime : toute valeur inconnue retombe sur "physique"
if CONFIG.TPMode ~= "marche" then CONFIG.TPMode = "physique" end

local LANGS = {
    "fr","en","es","pt","pt-BR","de","it","nl","pl","tr","ru","uk","ar",
    "id","ms","vi","th","fil","ja","ko","zh-CN","hi","ro","sv",
}

----------------------------------------------------------------------------------
-- ENVIRONNEMENT
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

function Util.trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function Util.lower(s) return string.lower(tostring(s)) end

function Util.clamp(v, a, b)
    v = tonumber(v) or a
    if v < a then return a end
    if v > b then return b end
    return v
end

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
    if n >= 1e9  then return string.format("%.2fB", n / 1e9) end
    if n >= 1e6  then return string.format("%.2fM", n / 1e6) end
    if n >= 1e3  then return string.format("%.1fK", n / 1e3) end
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
        if node == game and part == "ReplicatedStorage" then node = ReplicatedStorage
        elseif node == game and (part == "Workspace" or part == "workspace") then node = workspace
        else node = node:FindFirstChild(part) end
        if not node then return nil end
    end
    return node
end

----------------------------------------------------------------------------------
-- MAID / ETAT / LOG
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
    Unloaded = false, Travelling = false, Cancel = false,
    LastPos = nil, Logs = {}, ChatLog = {},
    Plot = nil, PlotOwner = nil,
}

local UI, Spy, Hook

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
local Remotes = { cache = {} }

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

local function allRemotes()
    local out = {}
    for _, root in ipairs(searchRoots()) do
        local ok, list = pcall(function() return root:GetDescendants() end)
        if ok then
            for _, d in ipairs(list) do
                local okIs, remote = pcall(isRemote, d)
                if okIs and remote then table.insert(out, d) end
            end
        end
    end
    return out
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
    for _, d in ipairs(allRemotes()) do
        local n, full = Util.lower(d.Name), Util.lower(d:GetFullName())
        local score = 0
        if n == wanted then score = 10
        elseif string.find(n, "/" .. wanted, 1, true) then score = 8
        elseif string.find(n, wanted, 1, true) then score = 4 end
        if score > 0 then
            if string.find(full, "tradeservice", 1, true) then score = score + 6 end
            if string.find(full, "trade", 1, true) then score = score + 3 end
            if score > bestScore then best, bestScore = d, score end
        end
    end
    if best then
        self.cache[name] = best
        log("remote '%s' -> %s", name, best:GetFullName())
    end
    return best
end

function Remotes:Trade()
    local out = {}
    for _, d in ipairs(allRemotes()) do
        if string.find(Util.lower(d:GetFullName()), "trade", 1, true) then
            table.insert(out, d)
        end
    end
    table.sort(out, function(a, b) return a:GetFullName() < b:GetFullName() end)
    return out
end

----------------------------------------------------------------------------------
-- LIMITEUR DE DEBIT
--   Tout appel serveur du hub passe par ici. Deux verrous : un delai global
--   entre deux appels quels qu'ils soient, et un delai par remote. Un remote
--   appele trop tot n'est pas mis en file d'attente, il est simplement refuse :
--   ca evite la rafale qui declenche le rate limit (voire le kick) du serveur.
----------------------------------------------------------------------------------
local Limiter = { lastGlobal = 0, lastByRemote = {}, lastByAction = {} }

local function now()
    if os and os.clock then return os.clock() end
    return tick()
end

function Limiter:check(remote)
    local t = now()
    local gap = tonumber(CONFIG.RemoteMinGap) or 0.8
    if t - self.lastGlobal < gap then
        return false, string.format("trop rapide, attends %.1fs", gap - (t - self.lastGlobal))
    end
    local key = tostring(remote)
    local cooldown = tonumber(CONFIG.RemoteCooldown) or 1.5
    local last = self.lastByRemote[key] or 0
    if t - last < cooldown then
        return false, string.format("%s en cooldown (%.1fs)", remote.Name, cooldown - (t - last))
    end
    return true
end

function Limiter:stamp(remote)
    local t = now()
    self.lastGlobal = t
    self.lastByRemote[tostring(remote)] = t
end

-- cooldown par action (invitation, chat) en plus du cooldown par remote
function Limiter:action(name, seconds)
    local t = now()
    local last = self.lastByAction[name] or 0
    if t - last < seconds then
        return false, string.format("attends encore %.1fs", seconds - (t - last))
    end
    self.lastByAction[name] = t
    return true
end

-- appel avec delai maxi : un InvokeServer sans reponse ne fige plus le hub
local function callRemote(remote, args, n, timeout)
    local allowed, why = Limiter:check(remote)
    if not allowed then
        log("appel refuse par le limiteur : %s", why)
        return "cooldown", why
    end
    Limiter:stamp(remote)

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
        return nil, "ce joueur n'est pas dans le serveur"
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

function Plots:All()
    local out = {}
    for _, container in ipairs(self:Containers()) do
        for _, model in ipairs(container:GetChildren()) do
            if model:IsA("Model") or model:IsA("Folder") then
                local owner = self:OwnerOf(model)
                table.insert(out, { model = model, owner = owner, cframe = pivotOf(model) })
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
-- DEPLACEMENT
--   mode "physique" : on n'ecrit JAMAIS de CFrame sur le personnage. On pose un
--   BodyVelocity et on laisse le moteur physique deplacer le personnage,
--   exactement comme un joueur qui court ou tombe. Pour le serveur c'est un
--   mouvement continu et legitime : rien a detecter comme teleport, et pas de
--   degat de chute puisque la vitesse de descente reste controlee.
--   mode "marche" : Humanoid:MoveTo, le personnage marche pour de vrai.
--   Le mode "cframe" (ecriture directe de root.CFrame) et le noclip
--   (CanCollide force depuis le client) ont ete supprimes : c'est exactement
--   ce que les anti-teleport reperent.
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

local mover

local function clearMover()
    if mover then pcall(function() mover:Destroy() end) mover = nil end
end

local function makeMover(root)
    clearMover()
    local created
    local ok = pcall(function()
        created = Instance.new("BodyVelocity")
        created.Name = "TPH_Move"
        created.MaxForce = Vector3.new(100000, 100000, 100000)
        created.P = 3000
        created.Velocity = Vector3.new(0, 0, 0)
        created.Parent = root
    end)
    if not ok or not created then return nil end
    mover = created
    return mover
end

local function cleanupTravel()
    clearMover()
    State.Travelling = false
end

-- avance vers un point avec la physique, en freinant a l'approche
local function flySegment(target, speed)
    local guard = 0
    while true do
        if State.Unloaded or State.Cancel then return false, "annule" end
        local root = TP.root()
        if not root then return false, "personnage perdu (mort / respawn)" end

        local delta = target - root.Position
        local dist = delta.Magnitude
        if dist <= 3 then return true end

        local dt = RunService.Heartbeat:Wait()
        guard = guard + dt
        if guard > 75 then return false, "trajet trop long (bloque ?)" end

        local wanted = math.min(speed, math.max(6, dist * 1.4))
        local velocity = delta.Unit * wanted
        if mover and mover.Parent then
            mover.Velocity = velocity
        else
            local ok = pcall(function() root.AssemblyLinearVelocity = velocity end)
            if not ok then pcall(function() root.Velocity = velocity end) end
        end
    end
end

function TP.flyTo(goalCF)
    local root = TP.root()
    if not root then return false, "personnage introuvable" end

    local speed    = Util.clamp(CONFIG.TPSpeed, 10, 250)
    local startPos = root.Position
    local goalPos  = goalCF.Position + Vector3.new(0, 4, 0)
    local cruise   = math.max(startPos.Y, goalPos.Y) + Util.clamp(CONFIG.TPAltitude, 0, 200)

    makeMover(root)

    local waypoints = {
        Vector3.new(startPos.X, cruise, startPos.Z),
        Vector3.new(goalPos.X, cruise, goalPos.Z),
        goalPos,
    }
    for _, point in ipairs(waypoints) do
        local ok, err = flySegment(point, speed)
        if not ok then cleanupTravel() return false, err end
    end

    -- atterrissage freine : la vitesse verticale reste faible, donc aucun degat
    if CONFIG.TPLandSlow and mover and mover.Parent then
        mover.Velocity = Vector3.new(0, -10, 0)
        local t = 0
        while t < 0.4 do t = t + RunService.Heartbeat:Wait() end
    end
    clearMover()

    -- on reste immobile un instant : le serveur revalide la position au calme
    local t2 = 0
    while t2 < 0.25 do t2 = t2 + RunService.Heartbeat:Wait() end
    return true
end

-- le personnage marche vraiment : rien a detecter, mais lent et bloque par les murs
function TP.walkTo(goalCF)
    local hum = TP.humanoid()
    if not hum then return false, "humanoid introuvable" end
    local target, elapsed = goalCF.Position, 0
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
    if State.Travelling then return false, "un deplacement est deja en cours" end
    local root = TP.root()
    if not root then return false, "personnage introuvable" end
    if typeof(goalCF) == "Vector3" then goalCF = CFrame.new(goalCF) end
    if typeof(goalCF) ~= "CFrame" then return false, "destination invalide" end

    State.Travelling, State.Cancel = true, false
    State.LastPos = root.CFrame

    -- si le personnage meurt pendant le trajet on arrete tout proprement
    local hum = TP.humanoid()
    local diedConn
    if hum then
        diedConn = hum.Died:Connect(function()
            State.Cancel = true
            cleanupTravel()
            log("mort pendant le deplacement : essaie une vitesse plus basse")
        end)
    end

    local ok, err
    if CONFIG.TPMode == "marche" then ok, err = TP.walkTo(goalCF)
    else ok, err = TP.flyTo(goalCF) end

    if diedConn then pcall(function() diedConn:Disconnect() end) end
    cleanupTravel()
    return ok, err
end

function TP.stop()
    State.Cancel = true
    cleanupTravel()
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
-- SCANNER DE BASE (brainrots)
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
    "candy", "galaxy", "nuclear", "radioactive", "ice", "fire", "crystal",
    "glitch", "zombie", "concert", "rain", "snow", "taco",
}

local function guiTexts(inst)
    local texts = {}
    local ok, list = pcall(function() return inst:GetDescendants() end)
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

-- retourne la liste groupee (avec le modele pour l'apercu 3D), le revenu total
-- et le nombre d'unites
function Inspector.brainrots(plot)
    if not plot then return {}, 0, 0 end

    local candidates, chosen = {}, {}
    local ok, list = pcall(function() return plot:GetDescendants() end)
    if not ok then return {}, 0, 0 end

    for _, d in ipairs(list) do
        if d:IsA("Model") and isEntityModel(d) then candidates[d] = true end
    end
    for model in pairs(candidates) do
        local nested, parent = false, model.Parent
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
                  rarity = info.rarity, income = info.income, count = 0,
                  total = 0, model = model }
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

function Inspector.dump(plot, maxLines)
    if not plot then return "aucune base selectionnee" end
    maxLines = maxLines or 400
    local lines = { plot:GetFullName() }
    local function walk(inst, depth)
        if #lines >= maxLines or depth > 5 then return end
        for _, child in ipairs(inst:GetChildren()) do
            if #lines >= maxLines then return end
            local parts = {}
            for k, v in pairs(attributesOf(child)) do
                table.insert(parts, k .. "=" .. tostring(v))
            end
            local attrs = #parts > 0 and ("  {" .. table.concat(parts, ", ") .. "}") or ""
            local extra = child:IsA("TextLabel") and ('  "' .. tostring(child.Text) .. '"') or ""
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
local INVITE_WORDS = { "invite", "sendrequest", "traderequest", "requesttrade",
                       "sendtrade", "request", "invitation" }

-- on ne garde que LE remote d'invitation le plus probable : plus de balayage
-- de tous les remotes du jeu, un seul appel part par clic
function Trade.candidates()
    local scored = {}
    for _, remote in ipairs(Remotes:Trade()) do
        local n = Util.lower(remote.Name)
        local score = 0
        if n == "invite" then score = 100
        else
            for i, word in ipairs(INVITE_WORDS) do
                if string.find(n, word, 1, true) then score = 60 - i break end
            end
        end
        if score > 0 then table.insert(scored, { remote = remote, score = score }) end
    end
    if #scored == 0 then
        for _, name in ipairs({ "Invite", "SendRequest", "TradeRequest", "RequestTrade" }) do
            local remote = Remotes:Find(name)
            if remote then table.insert(scored, { remote = remote, score = 10 }) end
        end
    end
    table.sort(scored, function(a, b) return a.score > b.score end)
    local out = {}
    for _, entry in ipairs(scored) do table.insert(out, entry.remote) end
    return out
end

-- une seule forme d'argument est envoyee par clic (jamais les 4 a la suite)
local function argShape(player, userId)
    local mode = CONFIG.ArgMode
    if mode == "userid" and userId then return { userId }, 1, "userid" end
    if mode == "name" and player then return { player.Name }, 1, "name" end
    if mode == "player" and player then return { player }, 1, "player" end
    if player then return { player }, 1, "player" end
    if userId then return { userId }, 1, "userid" end
    return nil
end

function Trade.invite(query)
    local player, err = PlayerUtil.byQuery(query)
    local userId = (player and player.UserId) or tonumber(query) or PlayerUtil.userIdOf(query)
    if not player and not userId then return false, err or "joueur introuvable" end
    local who = player and player.Name or tostring(userId)

    local free, wait = Limiter:action("invite", tonumber(CONFIG.InviteCooldown) or 6)
    if not free then return false, "invitation trop rapprochee : " .. wait end

    -- 1) rejouer l'appel exact que le jeu envoie quand tu cliques sur son bouton
    --    (capture automatique en arriere-plan) : c'est un seul appel, la bonne
    --    signature du premier coup
    local template = Spy and Spy.templates and Spy.templates.invite
    if template then
        local ok, res = Spy.replay(template, { target = player, userId = userId })
        if ok then return true, "trade envoye a " .. who end
        -- on n'enchaine PAS un deuxieme appel derriere un echec : c'est cette
        -- rafale la qui faisait sauter le rate limit. Un clic = un appel.
        return false, "le serveur a refuse l'appel appris (" .. tostring(res) .. ")"
    end

    -- 2) sinon : LE meilleur remote, UN seul appel
    local remote = Trade.candidates()[1]
    if not remote then return false, "aucun remote d'invitation trouve dans ce jeu" end

    local args, n, label = argShape(player, userId)
    if not args then return false, "joueur introuvable" end

    local status, res = callRemote(remote, args, n, 5)
    log("%s[%s] -> %s (%s)", remote.Name, label, status, tostring(res))
    if status == "ok" and res ~= false then
        CONFIG.ArgMode = label
        return true, "trade envoye a " .. who .. " (" .. remote.Name .. ")"
    end
    if status == "cooldown" then return false, "remote en cooldown, reessaie dans un instant" end
    return false, "le serveur a refuse (" .. remote.Name .. ") - ouvre le vrai menu de trade une fois, le hub apprendra l'appel"
end

----------------------------------------------------------------------------------
-- TRADUCTEUR
----------------------------------------------------------------------------------
local Translator = { cache = {} }

local PHRASEBOOK = {
    { fr = "salut, tu veux trade ?",  en = "hey, wanna trade?" },
    { fr = "combien tu veux ?",       en = "how much do you want?" },
    { fr = "c'est trop peu",          en = "that's too low" },
    { fr = "ajoute un truc",          en = "add something" },
    { fr = "j'accepte",               en = "i accept" },
    { fr = "non merci",               en = "no thanks" },
    { fr = "attends une seconde",     en = "wait a second" },
    { fr = "montre moi ta base",      en = "show me your base" },
    { fr = "deal ?",                  en = "deal?" },
    { fr = "envoie en premier",       en = "you go first" },
    { fr = "merci beaucoup",          en = "thank you very much" },
    { fr = "je te fais confiance",    en = "i trust you" },
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

    local free, wait = Limiter:action("chat", tonumber(CONFIG.ChatCooldown) or 2)
    if not free then return false, "message trop rapproche : " .. wait end

    local final = text
    if translateTo and translateTo ~= "" then
        local out = Translator.translate(text, translateTo)
        if out then final = out end
    end

    local template = Spy and Spy.templates and Spy.templates.chat
    if template then
        local ok = Spy.replay(template, { message = final })
        if ok then
            pushChat("moi", text, (final ~= text) and final or nil)
            return true, final
        end
    end

    local remote = Chat.getRemote()
    if not remote then return false, "remote de chat introuvable" end
    local status, res = callRemote(remote, { final }, 1, 5)
    if status ~= "ok" then return false, "echec envoi (" .. status .. ") " .. tostring(res) end
    pushChat("moi", text, (final ~= text) and final or nil)
    return true, final
end

local function extractMessage(...)
    local args, sender, message = { ... }, nil, nil
    for _, v in ipairs(args) do
        if typeof(v) == "Instance" and v:IsA("Player") then sender = v
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
end

function Chat.patchGui()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return end

    local function handle(label)
        if not (CONFIG.PatchChatGui and CONFIG.TranslateIncoming) then return end
        if not label:IsA("TextLabel") or Chat.patched[label] then return end
        local full = Util.lower(label:GetFullName())
        if not (string.find(full, "trade", 1, true) and string.find(full, "chat", 1, true)) then
            return
        end
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
-- APPRENTISSAGE SILENCIEUX DES APPELS DU JEU (aucun onglet, ca tourne tout seul)
--   Quand tu utilises le vrai menu de trade du jeu, on enregistre l'appel exact
--   envoye au serveur. Le bouton "Envoyer le trade" rejoue ensuite ce meme appel
--   avec le joueur de ton choix : la signature est forcement la bonne.
----------------------------------------------------------------------------------
Spy = { templates = {}, records = {}, active = true, max = 20 }

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
    local rec = { remote = remote, name = remote.Name, method = method,
                  args = args, n = n, at = os.date("%H:%M:%S") }
    analyseRecord(rec)
    table.insert(Spy.records, rec)
    if #Spy.records > Spy.max then table.remove(Spy.records, 1) end

    local lname = Util.lower(rec.name)
    if rec.targetIndex and (string.find(lname, "invite", 1, true)
       or string.find(lname, "request", 1, true)) then
        Spy.templates.invite = rec
        log("appel de trade appris : %s (%d arguments)", rec.name, rec.n)
        if UI and UI.setLearned then pcall(UI.setLearned) end
    elseif rec.stringIndex and (string.find(lname, "chat", 1, true)
       or string.find(lname, "message", 1, true)) then
        Spy.templates.chat = rec
        log("appel de chat appris : %s (%d arguments)", rec.name, rec.n)
        if UI and UI.setLearned then pcall(UI.setLearned) end
    end
    return rec
end

function Spy.replay(rec, subs)
    if not rec or not rec.remote or not rec.remote.Parent then return false, "modele invalide" end
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

-- Le hook est en LECTURE SEULE : il note la signature des appels de trade du
-- jeu et laisse toujours passer l'appel d'origine. Il n'intercepte plus, ne
-- reecrit plus et ne renvoie plus d'appel a la place du jeu (ce doublon de
-- remote comptait dans le rate limit, et modifier un message deja parti est de
-- toute facon le travail du serveur, pas du client).
Hook = { installed = false }

function Hook.install()
    if Hook.installed then return true end
    if not (Env.hookmetamethod and Env.getnamecall) then return false end

    local old
    old = Env.hookmetamethod(game, "__namecall", function(self, ...)
        local okMethod, method = pcall(Env.getnamecall)
        if not okMethod or State.Unloaded then return old(self, ...) end
        if method ~= "FireServer" and method ~= "InvokeServer" then return old(self, ...) end

        local mine = Env.checkcaller and Env.checkcaller()
        if Spy.active and typeof(self) == "Instance" and not mine then
            local okName, full = pcall(function() return Util.lower(self:GetFullName()) end)
            if okName and string.find(full, "trade", 1, true) then
                pcall(Spy.record, self, method, { ... }, select("#", ...))
            end
        end
        return old(self, ...)
    end)

    Hook.installed = true
    return true
end

----------------------------------------------------------------------------------
-- INTERFACE : theme + composants
----------------------------------------------------------------------------------
local THEME = {
    bg      = Color3.fromRGB(12, 13, 18),
    surface = Color3.fromRGB(18, 20, 27),
    card    = Color3.fromRGB(24, 26, 35),
    cardHi  = Color3.fromRGB(32, 35, 47),
    line    = Color3.fromRGB(42, 45, 60),
    text    = Color3.fromRGB(240, 242, 250),
    sub     = Color3.fromRGB(134, 141, 165),
    accent  = Color3.fromRGB(139, 108, 255),
    accent2 = Color3.fromRGB(0, 216, 190),
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
        elseif not pcall(function() inst[k] = v end) then
            warn(string.format("[TPH] propriete ignoree : %s.%s", class, tostring(k)))
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
        VerticalAlignment = horizontal and Enum.VerticalAlignment.Center or Enum.VerticalAlignment.Top,
        Parent = inst,
    })
end

local function tween(inst, props, time, style)
    local ok, t = pcall(function()
        return TweenService:Create(inst,
            TweenInfo.new(time or 0.16, style or Enum.EasingStyle.Quart,
                Enum.EasingDirection.Out), props)
    end)
    if ok and t then t:Play() return t end
end

-- tete du joueur (miniature Roblox)
local function avatar(parent, userId, size)
    size = size or 34
    local holder = corner(mk("Frame", {
        Size = UDim2.new(0, size, 0, size), BackgroundColor3 = THEME.cardHi,
        BorderSizePixel = 0, Parent = parent,
    }), size / 2)
    local img = mk("ImageLabel", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Image = "",
        ScaleType = Enum.ScaleType.Fit, Parent = holder,
    })
    corner(img, size / 2)
    if CONFIG.ShowAvatars then
        spawnTask(function()
            local ok, content = pcall(function()
                return Players:GetUserThumbnailAsync(userId,
                    Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
            end)
            if ok and content and img.Parent then img.Image = content end
        end)
    end
    return holder
end

-- apercu 3D d'un brainrot (le vrai modele du jeu, rendu dans un ViewportFrame)
local function modelIcon(parent, model, size)
    size = size or 44
    local holder = corner(mk("Frame", {
        Size = UDim2.new(0, size, 0, size), BackgroundColor3 = THEME.surface,
        BorderSizePixel = 0, ClipsDescendants = true, Parent = parent,
    }), 8)
    stroke(holder, THEME.line, 1, 0.5)

    local fallback = mk("TextLabel", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold, Text = "?", TextSize = 16,
        TextColor3 = THEME.sub, Parent = holder,
    })
    if not (CONFIG.ShowModels and model) then return holder end

    spawnTask(function()
        local ok = pcall(function()
            local viewport = mk("ViewportFrame", {
                Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
                Ambient = Color3.fromRGB(200, 200, 210),
                LightColor = Color3.fromRGB(255, 255, 255),
                Parent = holder,
            })
            pcall(function() model.Archivable = true end)
            local clone = model:Clone()
            for _, d in ipairs(clone:GetDescendants()) do
                if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("BillboardGui")
                or d:IsA("SurfaceGui") or d:IsA("ParticleEmitter") then
                    d:Destroy()
                end
            end
            clone.Parent = viewport

            local camera = Instance.new("Camera")
            camera.Parent = viewport
            viewport.CurrentCamera = camera

            local center, extents = clone:GetBoundingBox()
            local radius = math.max(extents.Magnitude, 4)
            local offset = Vector3.new(radius * 0.75, radius * 0.45, radius * 0.85)
            camera.CFrame = CFrame.new(center.Position + offset, center.Position)
            fallback.Visible = false
        end)
        if not ok and fallback.Parent then fallback.Text = "3D" end
    end)
    return holder
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
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = guiParent(),
})
Maid.inst(screen)
if syn and syn.protect_gui then pcall(syn.protect_gui, screen) end

local WIN_W, WIN_H = 690, 480

local window = corner(mk("Frame", {
    Size = UDim2.new(0, WIN_W, 0, WIN_H),
    Position = UDim2.new(0.5, -WIN_W / 2, 0.5, -WIN_H / 2),
    BackgroundColor3 = THEME.bg, BorderSizePixel = 0,
    ClipsDescendants = true, Parent = screen,
}), 14)
stroke(window, THEME.line, 1.5)

local titleBar = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = THEME.surface,
    BorderSizePixel = 0, Parent = window,
})
mk("UIGradient", { Color = ColorSequence.new(THEME.surface, THEME.card),
    Rotation = 90, Parent = titleBar })

corner(mk("Frame", {
    Size = UDim2.new(0, 10, 0, 10), Position = UDim2.new(0, 18, 0.5, -5),
    BackgroundColor3 = THEME.accent, BorderSizePixel = 0, Parent = titleBar,
}), 5)

mk("TextLabel", {
    Size = UDim2.new(0, 240, 1, 0), Position = UDim2.new(0, 36, 0, 0),
    BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
    Text = "TRADE PLAZA HUB", TextSize = 13, TextColor3 = THEME.text,
    TextXAlignment = Enum.TextXAlignment.Left, Parent = titleBar,
})

local learnedPill = corner(mk("Frame", {
    Size = UDim2.new(0, 122, 0, 20), Position = UDim2.new(0, 176, 0.5, -10),
    BackgroundColor3 = THEME.card, BorderSizePixel = 0, Parent = titleBar,
}), 10)
local learnedStroke = stroke(learnedPill, THEME.warn, 1, 0.3)
local learnedLabel = mk("TextLabel", {
    Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold, Text = "trade non appris", TextSize = 10,
    TextColor3 = THEME.warn, Parent = learnedPill,
})

function UI.setLearned()
    local ok = Spy and Spy.templates and Spy.templates.invite
    learnedLabel.Text = ok and "trade appris" or "trade non appris"
    learnedLabel.TextColor3 = ok and THEME.good or THEME.warn
    learnedStroke.Color = ok and THEME.good or THEME.warn
end

local function circleButton(offsetX, color, symbol, callback)
    local b = corner(mk("TextButton", {
        Size = UDim2.new(0, 22, 0, 22), Position = UDim2.new(1, offsetX, 0.5, -11),
        BackgroundColor3 = THEME.card, AutoButtonColor = false,
        Font = Enum.Font.GothamBold, Text = symbol, TextSize = 12,
        TextColor3 = color, BorderSizePixel = 0, Parent = titleBar,
    }), 11)
    Maid.conn(b.MouseEnter:Connect(function()
        tween(b, { BackgroundColor3 = color }, 0.15)
        tween(b, { TextColor3 = THEME.bg }, 0.15)
    end))
    Maid.conn(b.MouseLeave:Connect(function()
        tween(b, { BackgroundColor3 = THEME.card }, 0.15)
        tween(b, { TextColor3 = color }, 0.15)
    end))
    Maid.conn(b.MouseButton1Click:Connect(callback))
    return b
end

local bodyFrame = mk("Frame", {
    Size = UDim2.new(1, 0, 1, -74), Position = UDim2.new(0, 0, 0, 46),
    BackgroundTransparency = 1, Parent = window,
})

local sidebar = mk("Frame", {
    Size = UDim2.new(0, 148, 1, 0), BackgroundColor3 = THEME.surface,
    BorderSizePixel = 0, Parent = bodyFrame,
})
listLayout(sidebar, 4)
pad(sidebar, 10)

local contentArea = mk("Frame", {
    Size = UDim2.new(1, -148, 1, 0), Position = UDim2.new(0, 148, 0, 0),
    BackgroundTransparency = 1, Parent = bodyFrame,
})

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
        Name = name, Size = UDim2.new(1, -20, 1, -16), Position = UDim2.new(0, 12, 0, 8),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
        ScrollBarImageColor3 = THEME.accent, CanvasSize = UDim2.new(),
        Visible = false, Parent = contentArea,
    })
    local layout = listLayout(page, 10)
    Maid.conn(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        page.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 14)
    end))

    local tab = corner(mk("TextButton", {
        Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = THEME.card,
        BackgroundTransparency = 1, AutoButtonColor = false, Text = "",
        BorderSizePixel = 0, Parent = sidebar,
    }), 8)
    local mark = corner(mk("Frame", {
        Size = UDim2.new(0, 3, 0, 0), Position = UDim2.new(0, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = THEME.accent,
        BorderSizePixel = 0, Parent = tab,
    }), 2)
    local tabLabel = mk("TextLabel", {
        Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 16, 0, 0),
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
        tween(t.mark, { Size = UDim2.new(0, 3, 0, active and 20 or 0) }, 0.18)
    end
end

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
                TextSize = 11, TextColor3 = THEME.sub, TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left, Parent = head,
            })
        end
    end
    return holder
end

local function note(parent, text, color)
    return mk("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = text, TextSize = 11,
        TextColor3 = color or THEME.sub, TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true, Parent = parent,
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
    local base = (style == "primary" and THEME.accent)
        or (style == "danger" and THEME.bad) or THEME.cardHi
    local textColor = (style == "primary" or style == "danger") and THEME.bg or THEME.text
    local hover = (style == "primary" and THEME.accent2)
        or (style == "danger" and Color3.fromRGB(255, 140, 150)) or THEME.line

    local b = corner(mk("TextButton", {
        Size = opts.width and UDim2.new(0, opts.width, 0, opts.height or 32)
                          or UDim2.new(1, 0, 0, opts.height or 32),
        BackgroundColor3 = base, AutoButtonColor = false, Font = Enum.Font.GothamBold,
        Text = opts.text, TextSize = opts.textSize or 12, TextColor3 = textColor,
        BorderSizePixel = 0, Parent = parent,
    }), 8)
    if style == "ghost" then stroke(b, THEME.line, 1, 0.4) end

    Maid.conn(b.MouseEnter:Connect(function() tween(b, { BackgroundColor3 = hover }, 0.14) end))
    Maid.conn(b.MouseLeave:Connect(function() tween(b, { BackgroundColor3 = base }, 0.14) end))
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
    Maid.conn(box.Focused:Connect(function()
        tween(st, { Color = THEME.accent, Transparency = 0 }, 0.15)
    end))
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
        TextColor3 = THEME.text, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = holder,
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
                                             or UDim2.new(0, 2, 0.5, -8) }, 0.18)
        if callback then spawnTask(function() pcall(callback, CONFIG[key]) end) end
    end))
    return holder
end

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
            Size = UDim2.new(0, math.max(64, #tostring(value) * 9 + 24), 1, 0),
            BackgroundColor3 = THEME.surface, AutoButtonColor = false, Text = "",
            BorderSizePixel = 0, Parent = holder,
        }), 8)
        local lbl = mk("TextLabel", {
            Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
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

local function slider(parent, text, key, minVal, maxVal, suffix)
    local holder = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1, Parent = parent,
    })
    mk("TextLabel", {
        Size = UDim2.new(1, -100, 0, 16), BackgroundTransparency = 1,
        Font = Enum.Font.Gotham, Text = text, TextSize = 11, TextColor3 = THEME.sub,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = holder,
    })
    local valueLabel = mk("TextLabel", {
        Size = UDim2.new(0, 96, 0, 16), Position = UDim2.new(1, -96, 0, 0),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
        Text = tostring(CONFIG[key]) .. (suffix or ""), TextSize = 11,
        TextColor3 = THEME.accent2, TextXAlignment = Enum.TextXAlignment.Right, Parent = holder,
    })
    local bar = corner(mk("Frame", {
        Size = UDim2.new(1, 0, 0, 8), Position = UDim2.new(0, 0, 0, 26),
        BackgroundColor3 = THEME.surface, BorderSizePixel = 0, Parent = holder,
    }), 4)
    local ratio = (CONFIG[key] - minVal) / math.max(1, maxVal - minVal)
    local fill = corner(mk("Frame", {
        Size = UDim2.new(ratio, 0, 1, 0), BackgroundColor3 = THEME.accent,
        BorderSizePixel = 0, Parent = bar,
    }), 4)
    local knob = corner(mk("Frame", {
        Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(ratio, -7, 0.5, -7),
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
    local function setValue(value)
        local rel = math.clamp((value - minVal) / math.max(1, maxVal - minVal), 0, 1)
        CONFIG[key] = value
        valueLabel.Text = tostring(value) .. (suffix or "")
        fill.Size = UDim2.new(rel, 0, 1, 0)
        knob.Position = UDim2.new(rel, -7, 0.5, -7)
    end
    Maid.conn(bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then dragging = true apply(i.Position.X) end
    end))
    Maid.conn(UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
        or i.UserInputType == Enum.UserInputType.Touch) then apply(i.Position.X) end
    end))
    Maid.conn(UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end))
    return holder, setValue
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
    local layout = listLayout(scroll, 5)
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

local function clearChildren(scroll)
    for _, child in ipairs(scroll:GetChildren()) do
        if not child:IsA("UIListLayout") then child:Destroy() end
    end
end

-- petite etiquette coloree (mutation, rarete)
local function tag(parent, text, color)
    local holder = corner(mk("Frame", {
        Size = UDim2.new(0, math.max(38, #text * 7 + 14), 0, 18),
        BackgroundColor3 = color, BackgroundTransparency = 0.78,
        BorderSizePixel = 0, Parent = parent,
    }), 9)
    stroke(holder, color, 1, 0.55)
    mk("TextLabel", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold, Text = text, TextSize = 10, TextColor3 = color,
        Parent = holder,
    })
    return holder
end

local function cycleButton(parent, prefix, values, key, width)
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
        end,
    })
    return b
end

local scanBase, refreshPlayers

----------------------------------------------------------------------------------
-- ONGLET : JOUEURS
----------------------------------------------------------------------------------
local pagePlayers = addTab("Joueurs")

local cardTarget = card(pagePlayers, "Cible")
local targetField = field(cardTarget, "pseudo ou UserId...")
local rowTarget = rowOf(cardTarget, 36)
btn(rowTarget, { text = "ENVOYER LE TRADE", width = 200, height = 36, style = "primary",
    callback = function()
        setStatus("envoi de la demande...", THEME.warn)
        local ok, msg = Trade.invite(targetField.Text)
        setStatus(msg, ok and THEME.good or THEME.bad)
        if ok then notify("Trade", msg, 4) end
    end })
btn(rowTarget, { text = "Aller a sa base", width = 140, height = 36, callback = function()
    local plr, err = PlayerUtil.byQuery(targetField.Text)
    if not plr then setStatus(err or "joueur introuvable", THEME.bad) return end
    setStatus("deplacement vers " .. plr.Name .. "...", THEME.warn)
    local ok, e = TP.toBase(plr)
    setStatus(ok and ("arrive chez " .. plr.Name) or tostring(e), ok and THEME.good or THEME.bad)
end })
btn(rowTarget, { text = "Retour", width = 84, height = 36, callback = function()
    local ok, e = TP.back()
    setStatus(ok and "retour effectue" or tostring(e), ok and THEME.good or THEME.bad)
end })
btn(rowTarget, { text = "Stop", width = 66, height = 36, style = "danger", callback = function()
    TP.stop()
    setStatus("deplacement arrete", THEME.warn)
end })

local cardList = card(pagePlayers, "Joueurs du serveur")
local playersPanel = panel(cardList, 250)
btn(cardList, { text = "Rafraichir", callback = function()
    refreshPlayers()
    setStatus("liste rafraichie", THEME.good)
end })

local function playerRow(scroll, plr)
    local row = corner(mk("Frame", {
        Size = UDim2.new(1, -6, 0, 48), BackgroundColor3 = THEME.card,
        BackgroundTransparency = 0.2, BorderSizePixel = 0, Parent = scroll,
    }), 8)
    stroke(row, THEME.line, 1, 0.65)

    local head = avatar(row, plr.UserId, 34)
    head.Position = UDim2.new(0, 8, 0.5, -17)

    mk("TextLabel", {
        Size = UDim2.new(1, -210, 0, 15), Position = UDim2.new(0, 50, 0, 8),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
        Text = plr.DisplayName ~= "" and plr.DisplayName or plr.Name, TextSize = 12,
        TextColor3 = THEME.text, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
    })
    mk("TextLabel", {
        Size = UDim2.new(1, -210, 0, 13), Position = UDim2.new(0, 50, 0, 25),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham,
        Text = "@" .. plr.Name .. "   -   " .. plr.UserId, TextSize = 10,
        TextColor3 = THEME.sub, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
    })

    local actions = mk("Frame", {
        Size = UDim2.new(0, 196, 0, 30), Position = UDim2.new(1, -204, 0.5, -15),
        BackgroundTransparency = 1, Parent = row,
    })
    listLayout(actions, 5, true)
    btn(actions, { text = "Base", width = 56, height = 30, callback = function()
        setStatus("deplacement vers la base de " .. plr.Name .. "...", THEME.warn)
        local ok, e = TP.toBase(plr)
        setStatus(ok and ("arrive chez " .. plr.Name) or tostring(e),
            ok and THEME.good or THEME.bad)
    end })
    btn(actions, { text = "Voir", width = 52, height = 30, callback = function()
        scanBase(plr)
    end })
    btn(actions, { text = "TRADE", width = 74, height = 30, style = "primary",
        callback = function()
            setStatus("envoi de la demande a " .. plr.Name .. "...", THEME.warn)
            local ok, msg = Trade.invite(tostring(plr.UserId))
            setStatus(msg, ok and THEME.good or THEME.bad)
        end })
    return row
end

refreshPlayers = function()
    clearChildren(playersPanel)
    local shown = 0
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            shown = shown + 1
            playerRow(playersPanel, plr)
        end
    end
    if shown == 0 then
        textLine(playersPanel, "aucun autre joueur dans le serveur", THEME.sub, Enum.Font.Gotham)
    end
end

----------------------------------------------------------------------------------
-- ONGLET : BASE
----------------------------------------------------------------------------------
local pageBase = addTab("Base")

local cardScan = card(pageBase, "Scanner une base")
local baseField = field(cardScan, "pseudo ou UserId...")
local rowScan = rowOf(cardScan)
btn(rowScan, { text = "Scanner sa base", width = 150, style = "primary", callback = function()
    local plr, err = PlayerUtil.byQuery(baseField.Text)
    if not plr then setStatus(err or "joueur introuvable", THEME.bad) return end
    scanBase(plr)
end })
btn(rowScan, { text = "Ma base", width = 96, callback = function() scanBase(LocalPlayer) end })
btn(rowScan, { text = "Copier la structure", width = 160, callback = function()
    if not State.Plot then setStatus("scanne d'abord une base", THEME.bad) return end
    local dump = Inspector.dump(State.Plot, 400)
    if Util.copy(dump) then setStatus("structure copiee", THEME.good)
    else print(dump) setStatus("presse-papier indispo -> console F9", THEME.warn) end
end })
local baseSummary = note(cardScan, "aucune base scannee", THEME.text)

local cardBrainrots = card(pageBase, "Brainrots")
local brainrotPanel = panel(cardBrainrots, 260)

local function brainrotRow(scroll, entry)
    local row = corner(mk("Frame", {
        Size = UDim2.new(1, -6, 0, 58), BackgroundColor3 = THEME.card,
        BackgroundTransparency = 0.2, BorderSizePixel = 0, Parent = scroll,
    }), 8)
    stroke(row, THEME.line, 1, 0.65)

    local icon = modelIcon(row, entry.model, 44)
    icon.Position = UDim2.new(0, 7, 0.5, -22)

    mk("TextLabel", {
        Size = UDim2.new(1, -200, 0, 16), Position = UDim2.new(0, 60, 0, 8),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = entry.name,
        TextSize = 12, TextColor3 = THEME.text, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
    })

    local tags = mk("Frame", {
        Size = UDim2.new(1, -200, 0, 18), Position = UDim2.new(0, 60, 0, 30),
        BackgroundTransparency = 1, Parent = row,
    })
    listLayout(tags, 5, true)
    tag(tags, "x" .. entry.count, THEME.sub)
    if entry.mutation then tag(tags, entry.mutation, THEME.warn) end
    if entry.rarity then tag(tags, entry.rarity, THEME.accent) end

    mk("TextLabel", {
        Size = UDim2.new(0, 130, 0, 18), Position = UDim2.new(1, -138, 0, 11),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
        Text = entry.income > 0 and ("$" .. Util.short(entry.income) .. "/s") or "-",
        TextSize = 13, TextColor3 = THEME.accent2,
        TextXAlignment = Enum.TextXAlignment.Right, Parent = row,
    })
    if entry.count > 1 and entry.total > 0 then
        mk("TextLabel", {
            Size = UDim2.new(0, 130, 0, 14), Position = UDim2.new(1, -138, 0, 30),
            BackgroundTransparency = 1, Font = Enum.Font.Gotham,
            Text = "total $" .. Util.short(entry.total) .. "/s", TextSize = 10,
            TextColor3 = THEME.sub, TextXAlignment = Enum.TextXAlignment.Right, Parent = row,
        })
    end
    return row
end

scanBase = function(player, model, ownerName)
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

    local list, total, count = Inspector.brainrots(plot)
    baseSummary.Text = string.format("Base de %s   -   %d brainrots   -   %d types   -   revenu total $%s/s",
        ownerName, count, #list, Util.short(total))

    if #list == 0 then
        textLine(brainrotPanel, "aucun brainrot reconnu sur cette base", THEME.bad, Enum.Font.Gotham)
        textLine(brainrotPanel, "clique sur 'Copier la structure' et envoie-moi le resultat",
            THEME.sub, Enum.Font.Gotham)
    else
        for i, entry in ipairs(list) do
            if i > 60 then break end
            brainrotRow(brainrotPanel, entry)
        end
    end
    setStatus("base de " .. ownerName .. " scannee : " .. count .. " brainrots", THEME.good)
end

----------------------------------------------------------------------------------
-- ONGLET : CHAT
----------------------------------------------------------------------------------
local pageChat = addTab("Chat")

local cardTrad = card(pageChat, "Traducteur")
local rowLangs = rowOf(cardTrad)
cycleButton(rowLangs, "Je lis en :", LANGS, "TranslateTo", 168)
cycleButton(rowLangs, "J'ecris en :", LANGS, "SendAs", 168)
switch(cardTrad, "Traduire les messages recus", "TranslateIncoming")
switch(cardTrad, "Garder le texte original a cote", "ShowOriginal")
note(cardTrad, "Pour ecrire traduit, passe par le champ ci-dessous : le hub n'intercepte plus le chat du jeu (ca renvoyait un second remote pour un seul message).", THEME.sub)

local cardConv = card(pageChat, "Conversation")
local chatPanel = panel(cardConv, 170)
local chatField = field(cardConv, "ton message en francais...")
local rowSend = rowOf(cardConv)
btn(rowSend, { text = "Traduire et envoyer", width = 190, style = "primary", callback = function()
    local ok, msg = Chat.send(chatField.Text, CONFIG.SendAs)
    if ok then chatField.Text = "" end
    setStatus(ok and ("envoye : " .. tostring(msg)) or tostring(msg),
        ok and THEME.good or THEME.bad)
end })
btn(rowSend, { text = "Envoyer brut", width = 130, callback = function()
    local ok, msg = Chat.send(chatField.Text, nil)
    if ok then chatField.Text = "" end
    setStatus(ok and "envoye" or tostring(msg), ok and THEME.good or THEME.bad)
end })

local cardPhrases = card(pageChat, "Phrases rapides")
for i = 1, #Translator.phrases, 2 do
    local row = rowOf(cardPhrases, 30)
    for j = i, math.min(i + 1, #Translator.phrases) do
        local phrase = Translator.phrases[j]
        btn(row, { text = phrase.fr, width = 228, height = 30, textSize = 11,
            callback = function()
                local ok, msg = Chat.send(phrase.fr, CONFIG.SendAs)
                setStatus(ok and ("envoye : " .. tostring(msg)) or tostring(msg),
                    ok and THEME.good or THEME.bad)
            end })
    end
end

function UI.pushChat(entry)
    textLine(chatPanel, string.format("[%s] %s : %s", entry.at, entry.who, entry.original),
        THEME.sub, Enum.Font.Gotham)
    if entry.translated and entry.translated ~= entry.original then
        textLine(chatPanel, "      -> " .. entry.translated, THEME.accent2, Enum.Font.GothamMedium)
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
-- ONGLET : REGLAGES
----------------------------------------------------------------------------------
local pageSettings = addTab("Reglages")

local cardMove = card(pageSettings, "Deplacement",
    "aucun mode n'ecrit de CFrame sur le personnage : rien a voir pour un anti-teleport")
chips(cardMove, { "physique", "marche" }, "TPMode")
local speedSlider, setSpeed = slider(cardMove, "Vitesse", "TPSpeed", 16, 250, " studs/s")
local rowPresets = rowOf(cardMove, 28)
btn(rowPresets, { text = "Discret 25", width = 118, height = 28, callback = function() setSpeed(25) end })
btn(rowPresets, { text = "Normal 45", width = 118, height = 28, callback = function() setSpeed(45) end })
btn(rowPresets, { text = "Rapide 90", width = 118, height = 28, callback = function() setSpeed(90) end })
slider(cardMove, "Altitude de survol", "TPAltitude", 0, 120, " studs")
switch(cardMove, "Atterrissage freine (anti degats de chute)", "TPLandSlow")
note(cardMove, "Le mode CFrame et le noclip ont ete retires : ce sont eux qui declenchaient l'anti-teleport. Tu es renvoye en arriere ? Descends la vitesse a 25-45.", THEME.warn)

local cardLimit = card(pageSettings, "Limiteur de remotes",
    "un seul appel serveur a la fois, jamais de rafale")
slider(cardLimit, "Delai entre deux invitations", "InviteCooldown", 1, 30, " s")
slider(cardLimit, "Delai entre deux messages", "ChatCooldown", 1, 15, " s")
note(cardLimit, "Un envoi refuse n'est pas mis en file d'attente : il est annule. Monte ces delais si le serveur te repond mal.", THEME.sub)

local cardDisplay = card(pageSettings, "Affichage")
switch(cardDisplay, "Tete des joueurs", "ShowAvatars")
switch(cardDisplay, "Apercu 3D des brainrots", "ShowModels")

local cardState = card(pageSettings, "Etat")
local infoNote = note(cardState, "...", THEME.text)
local rowState = rowOf(cardState)
btn(rowState, { text = "Recharger les modules", width = 190, callback = function()
    Remotes.cache, Chat.remote = {}, nil
    Chat.getRemote()
    Chat.hookIncoming()
    Hook.install()
    refreshPlayers()
    setStatus("modules recharges", THEME.good)
end })
btn(rowState, { text = "Fermer le hub", width = 150, style = "danger", callback = function()
    if GENV.TradePlazaHub and GENV.TradePlazaHub.Unload then GENV.TradePlazaHub.Unload() end
end })

local cardLogs = card(pageSettings, "Journal")
local logsPanel = panel(cardLogs, 150)

function UI.pushLog(msg)
    textLine(logsPanel, msg, THEME.sub)
    local children = logsPanel:GetChildren()
    if #children > 140 then
        for i = 1, 40 do
            local c = children[i]
            if c and not c:IsA("UIListLayout") then c:Destroy() end
        end
    end
end

----------------------------------------------------------------------------------
-- BOUTONS FENETRE / RACCOURCI / UNLOAD
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

local floating = corner(mk("TextButton", {
    Size = UDim2.new(0, 46, 0, 46), Position = UDim2.new(0, 18, 1, -64),
    BackgroundColor3 = THEME.accent, AutoButtonColor = false, Font = Enum.Font.GothamBold,
    Text = "TP", TextSize = 14, TextColor3 = THEME.bg, BorderSizePixel = 0,
    Visible = false, Parent = screen,
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

local function unload()
    if State.Unloaded then return end
    State.Unloaded, State.Cancel = true, true
    clearMover()
    Maid.clean()
    GENV.TradePlazaHub = nil
    print("[TPH] decharge.")
end

GENV.TradePlazaHub = {
    Config = CONFIG, State = State, Remotes = Remotes, Plots = Plots, Teleport = TP,
    Trade = Trade, Chat = Chat, Translator = Translator, Inspector = Inspector,
    Spy = Spy, Hook = Hook, Limiter = Limiter, Unload = unload,
}

----------------------------------------------------------------------------------
-- INITIALISATION
----------------------------------------------------------------------------------
UI.select("Joueurs")
UI.setLearned()

window.Size = UDim2.new(0, WIN_W - 50, 0, WIN_H - 34)
tween(window, { Size = UDim2.new(0, WIN_W, 0, WIN_H) }, 0.3, Enum.EasingStyle.Back)

Maid.conn(Players.PlayerAdded:Connect(function()
    if not State.Unloaded then pcall(refreshPlayers) end
end))
Maid.conn(Players.PlayerRemoving:Connect(function()
    if State.Unloaded then return end
    spawnTask(function() waitFor(0.2) pcall(refreshPlayers) end)
end))
Maid.conn(LocalPlayer.CharacterAdded:Connect(function()
    State.Cancel, State.Travelling = true, false
    clearMover()
end))

local function init()
    log("demarrage (executor : %s)", tostring(Env.isExecutor))
    Hook.install()
    Chat.getRemote()
    Chat.hookIncoming()
    if CONFIG.PatchChatGui then Chat.patchGui() end

    refreshPlayers()

    local candidates = Trade.candidates()
    local httpOk = Util.httpGet(
        "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=en&dt=t&q=test") ~= nil

    infoNote.Text = table.concat({
        "Touche du menu       : " .. tostring(CONFIG.Keybind.Name),
        "Executor detecte     : " .. (Env.isExecutor and "oui" or "non"),
        "Apprentissage trade  : " .. (Hook.installed and "actif" or "indisponible (hookmetamethod absent)"),
        "Remotes de trade     : " .. tostring(#candidates)
            .. (candidates[1] and ("  (" .. candidates[1].Name .. ")") or ""),
        "Remote de chat       : " .. (Chat.remote and Chat.remote.Name or "introuvable"),
        "Limiteur remotes     : " .. string.format("%.1fs global / %.1fs par remote",
            tonumber(CONFIG.RemoteMinGap) or 0.8, tonumber(CONFIG.RemoteCooldown) or 1.5),
        "Mode de deplacement  : " .. tostring(CONFIG.TPMode) .. " (CFrame retire)",
        "Traduction en ligne  : " .. (httpOk and "operationnelle" or "indispo (phrases rapides seulement)"),
        "Bases detectees      : " .. tostring(#Plots:All()),
        "API console          : getgenv().TradePlazaHub",
    }, "\n")

    setStatus("pret - " .. tostring(CONFIG.Keybind.Name) .. " pour cacher", THEME.good)
    notify("Trade Plaza Hub v3", "Charge. " .. tostring(CONFIG.Keybind.Name) .. " pour afficher/cacher.", 5)
end

spawnTask(function()
    local ok, err = pcall(init)
    if not ok then
        setStatus("erreur init (console F9)", THEME.bad)
        log("ERREUR INIT : %s", tostring(err))
        warn("[TPH] ERREUR INIT : " .. tostring(err))
    end
end)

print("[TPH] pret - touche " .. tostring(CONFIG.Keybind.Name))
return GENV.TradePlazaHub

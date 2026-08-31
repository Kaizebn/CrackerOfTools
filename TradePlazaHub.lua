--[[
==================================================================================
    TRADE PLAZA HUB  --  script client (executor / LocalScript)
==================================================================================
    Fonctionnalites :
      * Teleport vers la base (plot) de n'importe quel joueur du serveur
      * Envoi de demande de trade par pseudo OU par UserId
      * Traducteur integre pour le mini-chat de trade (entrant + sortant)
      * Inspecteur de base : voir tout ce que le joueur a pose sur son plot
      * Onglet Remotes : liste les remotes TradeService detectes + dump structure

    Utilisation :
      1) Executor  : loadstring(game:HttpGet("<url du raw>"))()
                     ou simple copier/coller dans l'executor.
      2) In-game   : poser ce fichier comme LocalScript dans
                     StarterPlayer > StarterPlayerScripts.
         (les fonctions d'executor - request, gethui, hookmetamethod - sont
          optionnelles, le script se rabat automatiquement sur des equivalents)

    Touche par defaut pour afficher/cacher : RightControl (Ctrl droit)

    Config surchargeable avant le chargement :
      _G.TradePlazaHubConfig = { TranslateTo = "en", Keybind = Enum.KeyCode.F4 }
==================================================================================
]]

--// Rechargement propre si deja lance
if _G.TradePlazaHub and _G.TradePlazaHub.Unload then
    pcall(_G.TradePlazaHub.Unload)
end

----------------------------------------------------------------------------------
-- SERVICES
----------------------------------------------------------------------------------
local Players          = game:GetService("Players")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local StarterGui       = game:GetService("StarterGui")
local HttpService      = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

----------------------------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------------------------
local CONFIG = {
    Keybind            = Enum.KeyCode.RightControl,
    TranslateTo        = "fr",     -- langue d'affichage des messages recus
    SendAs             = "en",     -- langue dans laquelle on traduit ce qu'on envoie
    TranslateIncoming  = true,
    TranslateOutgoing  = false,    -- traduit automatiquement ce que TU envoies
    ShowOriginal       = true,     -- garde le texte original a cote de la traduction
    PatchChatGui       = true,     -- reecrit directement les TextLabel du chat de trade
    SteppedTeleport    = true,     -- teleport par paliers (evite le fling / le rubberband)
    StepStuds          = 14,
    NoclipOnTeleport   = true,
    TeleportOffset     = Vector3.new(0, 5, 0),
    ArgMode            = "auto",   -- auto | player | userid | name
    RemotePaths        = {},       -- ex: { Invite = "ReplicatedStorage.Remotes.TradeService.Invite" }
}

if type(_G.TradePlazaHubConfig) == "table" then
    for k, v in pairs(_G.TradePlazaHubConfig) do CONFIG[k] = v end
end

local LANGS = {
    "fr","en","es","pt","pt-BR","de","it","nl","pl","tr","ru","uk","ar",
    "id","ms","vi","th","fil","ja","ko","zh-CN","zh-TW","hi","ro","sv"
}

----------------------------------------------------------------------------------
-- ENVIRONNEMENT (executor ou pas)
----------------------------------------------------------------------------------
local Env = {}
Env.request = (syn and syn.request)
    or (http and http.request)
    or (fluxus and fluxus.request)
    or rawget(getfenv(), "http_request")
    or rawget(getfenv(), "request")

Env.clipboard = rawget(getfenv(), "setclipboard")
    or rawget(getfenv(), "toclipboard")
    or (syn and syn.write_clipboard)

Env.gethui        = rawget(getfenv(), "gethui")
Env.hookmetamethod= rawget(getfenv(), "hookmetamethod")
Env.getnamecall   = rawget(getfenv(), "getnamecallmethod")
Env.checkcaller   = rawget(getfenv(), "checkcaller")
Env.isExecutor    = (Env.request ~= nil) or (Env.hookmetamethod ~= nil)

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
local unpack = unpack or table.unpack

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

function Util.parseNumber(txt)
    if not txt then return nil end
    local clean = string.gsub(tostring(txt), "[%s,]", "")
    local num, suffix = string.match(clean, "([%d%.]+)%s*([KkMmBb]?)")
    if not num then return nil end
    local value = tonumber(num)
    if not value then return nil end
    suffix = string.lower(suffix or "")
    if suffix == "k" then value = value * 1e3
    elseif suffix == "m" then value = value * 1e6
    elseif suffix == "b" then value = value * 1e9 end
    return value
end

function Util.urlEncode(s)
    s = tostring(s)
    s = string.gsub(s, "\n", "\r\n")
    s = string.gsub(s, "([^%w%-%_%.%~ ])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    s = string.gsub(s, " ", "+")
    return s
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
    if Env.clipboard then
        local ok = pcall(Env.clipboard, text)
        if ok then return true end
    end
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
-- MAID (nettoyage au unload)
----------------------------------------------------------------------------------
local Maid = { conns = {}, insts = {} }

function Maid.conn(c)
    table.insert(Maid.conns, c)
    return c
end

function Maid.inst(i)
    table.insert(Maid.insts, i)
    return i
end

function Maid.clean()
    for _, c in ipairs(Maid.conns) do pcall(function() c:Disconnect() end) end
    for _, i in ipairs(Maid.insts) do pcall(function() i:Destroy() end) end
    Maid.conns, Maid.insts = {}, {}
end

----------------------------------------------------------------------------------
-- ETAT GLOBAL + LOGS
----------------------------------------------------------------------------------
local State = {
    Unloaded    = false,
    LastPos     = nil,      -- CFrame avant le dernier teleport
    Noclip      = false,
    Logs        = {},
    ChatLog     = {},
    PriceMap    = {},
    SelectedPlot= nil,
}

local UI  -- rempli plus bas (declare ici pour que les modules puissent logger)

local function log(fmt, ...)
    local ok, msg = pcall(string.format, tostring(fmt), ...)
    if not ok then msg = tostring(fmt) end
    msg = string.format("[%s] %s", os.date("%H:%M:%S"), msg)
    table.insert(State.Logs, msg)
    if #State.Logs > 200 then table.remove(State.Logs, 1) end
    if UI and UI.pushLog then UI.pushLog(msg) end
    print("[TradePlazaHub] " .. msg)
end

local function notify(title, text, dur)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title    = title or "Trade Plaza Hub",
            Text     = tostring(text),
            Duration = dur or 4,
        })
    end)
end

----------------------------------------------------------------------------------
-- MODULE : RESOLUTION DES REMOTES
--   Le jeu expose des remotes du style "RF/TradeService/Invite" ou
--   ReplicatedStorage > ... > TradeService > Invite. On cherche les deux formes.
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

-- score : plus c'est haut, plus le remote colle a ce qu'on cherche
local function scoreRemote(inst, wanted)
    local name = Util.lower(inst.Name)
    local full = Util.lower(inst:GetFullName())
    local score = 0
    if name == wanted then
        score = score + 10
    elseif string.find(name, "/" .. wanted, 1, true) then
        score = score + 8
    elseif string.find(name, wanted, 1, true) then
        score = score + 4
    else
        return 0
    end
    if string.find(full, "tradeservice", 1, true) then score = score + 6 end
    if string.find(full, "trade", 1, true) then score = score + 3 end
    return score
end

function Remotes:Find(name)
    local cached = self.cache[name]
    if cached and cached.Parent then return cached end

    -- 1) chemin force par la config
    local forced = CONFIG.RemotePaths and CONFIG.RemotePaths[name]
    if forced then
        local node = Util.dottedPath(forced)
        if node and isRemote(node) then
            self.cache[name] = node
            return node
        end
    end

    -- 2) recherche par score
    local wanted = Util.lower(name)
    local best, bestScore = nil, 0
    for _, root in ipairs(searchRoots()) do
        local ok, descendants = pcall(function() return root:GetDescendants() end)
        if ok then
            for _, d in ipairs(descendants) do
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
        log("Remote '%s' -> %s", name, best:GetFullName())
    end
    return best
end

-- liste tous les remotes qui ressemblent a du TradeService (onglet Remotes)
function Remotes:Scan()
    local out = {}
    for _, root in ipairs(searchRoots()) do
        local ok, descendants = pcall(function() return root:GetDescendants() end)
        if ok then
            for _, d in ipairs(descendants) do
                local okIs, remote = pcall(isRemote, d)
                if okIs and remote then
                    local full = Util.lower(d:GetFullName())
                    if string.find(full, "trade", 1, true) then
                        table.insert(out, d)
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a:GetFullName() < b:GetFullName() end)
    self.found = out
    return out
end

-- envoie sur un remote quel que soit son type
function Remotes:Send(remote, ...)
    if not remote then return false, "remote introuvable" end
    if remote:IsA("RemoteFunction") then
        local ok, res = pcall(function(...) return remote:InvokeServer(...) end, ...)
        return ok, res
    end
    local ok, err = pcall(function(...) remote:FireServer(...) end, ...)
    return ok, err
end

----------------------------------------------------------------------------------
-- MODULE : JOUEURS
----------------------------------------------------------------------------------
local PlayerUtil = {}

function PlayerUtil.byQuery(query)
    query = Util.trim(query)
    if query == "" then return nil, "entree vide" end

    -- UserId direct
    local asId = tonumber(query)
    if asId then
        for _, p in ipairs(Players:GetPlayers()) do
            if p.UserId == asId then return p end
        end
        local ok, name = pcall(function() return Players:GetNameFromUserIdAsync(asId) end)
        return nil, ok and ("le joueur " .. name .. " n'est pas dans ce serveur")
                        or ("aucun joueur avec l'id " .. asId)
    end

    -- pseudo / display name (exact puis partiel)
    local q = Util.lower(query)
    for _, p in ipairs(Players:GetPlayers()) do
        if Util.lower(p.Name) == q or Util.lower(p.DisplayName) == q then return p end
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if string.find(Util.lower(p.Name), q, 1, true)
        or string.find(Util.lower(p.DisplayName), q, 1, true) then
            return p
        end
    end
    return nil, "aucun joueur trouve pour '" .. query .. "'"
end

function PlayerUtil.userIdOf(query)
    local plr = PlayerUtil.byQuery(query)
    if plr then return plr.UserId end
    local asId = tonumber(query)
    if asId then return asId end
    local ok, id = pcall(function() return Players:GetUserIdFromNameAsync(query) end)
    if ok then return id end
    return nil
end

----------------------------------------------------------------------------------
-- MODULE : PLOTS / BASES
----------------------------------------------------------------------------------
local Plots = { cache = {} }

local OWNER_KEYS = {
    "Owner", "OwnerId", "OwnerID", "OwnerUserId", "UserId", "UserID",
    "Player", "PlayerId", "PlayerName", "OwnerName", "Occupant",
}
local CONTAINER_NAMES = {
    "plots", "plot", "bases", "base", "playerplots", "playerbases",
    "islands", "tycoons", "houses",
}
local IGNORED_ITEMS = {
    plotblock = true, plotsign = true, baseplate = true, floor = true,
    walls = true, wall = true, spawn = true, spawnlocation = true,
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
        -- recherche plus profonde (jusqu'a 3 niveaux)
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

-- essaie de trouver a qui appartient un plot
function Plots:OwnerOf(model)
    -- 1) attributs
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

    -- 2) Value objects
    for _, d in ipairs(model:GetChildren()) do
        local n = d.Name
        for _, key in ipairs(OWNER_KEYS) do
            if n == key then
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

    -- 3) le nom du modele est un UserId
    local asId = tonumber(model.Name)
    if asId then
        for _, p in ipairs(Players:GetPlayers()) do
            if p.UserId == asId then return p end
        end
    end

    -- 4) le panneau (PlotSign) affiche le pseudo du proprio
    local ok, descendants = pcall(function() return model:GetDescendants() end)
    if ok then
        for _, d in ipairs(descendants) do
            if d:IsA("TextLabel") or d:IsA("TextBox") then
                local txt = Util.lower(d.Text or "")
                if txt ~= "" then
                    for _, p in ipairs(Players:GetPlayers()) do
                        if string.find(txt, Util.lower(p.Name), 1, true)
                        or string.find(txt, Util.lower(p.DisplayName), 1, true) then
                            return p
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- position centrale d'un plot
local function pivotOf(model)
    local ok, cf = pcall(function() return model:GetPivot() end)
    if ok and cf then return cf end
    if model:IsA("Model") then
        local ok2, cf2 = pcall(function() return model:GetBoundingBox() end)
        if ok2 and cf2 then return cf2 end
        if model.PrimaryPart then return model.PrimaryPart.CFrame end
    elseif model:IsA("BasePart") then
        return model.CFrame
    end
    local part = model:FindFirstChildWhichIsA("BasePart", true)
    if part then return part.CFrame end
    return nil
end
Plots.pivotOf = pivotOf

-- liste { model, owner, ownerName, cframe }
function Plots:All()
    local out = {}
    for _, container in ipairs(self:Containers()) do
        for _, model in ipairs(container:GetChildren()) do
            if model:IsA("Model") or model:IsA("Folder") then
                local owner = self:OwnerOf(model)
                table.insert(out, {
                    model     = model,
                    owner     = owner,
                    ownerName = owner and owner.Name or "?",
                    cframe    = pivotOf(model),
                })
            end
        end
    end
    return out
end

-- plot d'un joueur precis (avec repli sur "le joueur est physiquement dessus")
function Plots:ForPlayer(player)
    for _, entry in ipairs(self:All()) do
        if entry.owner == player then return entry.model, entry.cframe end
    end
    local char = player.Character
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
-- MODULE : TELEPORT
----------------------------------------------------------------------------------
local TP = {}

function TP.root()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
end

local function setNoclip(on)
    State.Noclip = on
    local char = LocalPlayer.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide ~= (not on) then
            pcall(function() part.CanCollide = not on end)
        end
    end
end

function TP.to(target)
    local root = TP.root()
    if not root then return false, "personnage introuvable" end

    local goal
    if typeof(target) == "CFrame" then goal = target
    elseif typeof(target) == "Vector3" then goal = CFrame.new(target)
    else return false, "cible invalide" end
    goal = goal + CONFIG.TeleportOffset

    State.LastPos = root.CFrame

    if not CONFIG.SteppedTeleport then
        root.CFrame = goal
        return true
    end

    if CONFIG.NoclipOnTeleport then setNoclip(true) end

    local start = root.CFrame
    local dist  = (goal.Position - start.Position).Magnitude
    local steps = math.max(1, math.ceil(dist / math.max(1, CONFIG.StepStuds)))
    for i = 1, steps do
        if State.Unloaded then break end
        local alpha = i / steps
        local r = TP.root()
        if not r then break end
        r.CFrame = CFrame.new(start.Position:Lerp(goal.Position, alpha)) * (goal - goal.Position)
        RunService.Heartbeat:Wait()
    end

    local r = TP.root()
    if r then r.CFrame = goal end
    if CONFIG.NoclipOnTeleport then setNoclip(false) end
    return true
end

function TP.back()
    if not State.LastPos then return false, "aucune position sauvegardee" end
    local saved = State.LastPos
    local ok, err = TP.to(saved)
    return ok, err
end

function TP.toPlayer(player)
    local char = player.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
    if not root then return false, "le joueur n'a pas de personnage charge" end
    return TP.to(root.CFrame * CFrame.new(0, 0, 4))
end

function TP.toBase(player)
    local model, cf = Plots:ForPlayer(player)
    if not model or not cf then
        return false, "base introuvable pour " .. player.Name
    end
    State.SelectedPlot = model
    return TP.to(cf)
end

----------------------------------------------------------------------------------
-- MODULE : INSPECTEUR DE BASE
--   Structure observee : Bases > FirstFloor/SecondFloor/... > Purchases > <items>
--   On regarde en priorite les dossiers "Purchases", sinon on prend tous les
--   modeles poses qui ne sont pas de la structure (PlotBlock, PlotSign, ...).
----------------------------------------------------------------------------------
local Inspector = {}

local VALUE_KEYS = { "Value", "Price", "Cost", "Worth", "Coins", "Cash" }
local NAME_KEYS  = { "ItemName", "Item", "DisplayName", "Name" }

local function itemNameOf(inst)
    for _, key in ipairs(NAME_KEYS) do
        local ok, val = pcall(function() return inst:GetAttribute(key) end)
        if ok and type(val) == "string" and val ~= "" then return val end
    end
    local sv = inst:FindFirstChild("ItemName") or inst:FindFirstChild("Item")
    if sv and sv:IsA("StringValue") and sv.Value ~= "" then return sv.Value end
    return inst.Name
end

local function itemValueOf(inst, name)
    for _, key in ipairs(VALUE_KEYS) do
        local ok, val = pcall(function() return inst:GetAttribute(key) end)
        if ok and tonumber(val) then return tonumber(val) end
    end
    for _, key in ipairs(VALUE_KEYS) do
        local nv = inst:FindFirstChild(key)
        if nv and (nv:IsA("IntValue") or nv:IsA("NumberValue")) then return nv.Value end
        if nv and nv:IsA("StringValue") then
            local parsed = Util.parseNumber(nv.Value)
            if parsed then return parsed end
        end
    end
    local mapped = State.PriceMap[Util.lower(name or inst.Name)]
    if mapped then return mapped end
    return 0
end

-- construit une table prix a partir du shop du joueur local (CoinsShop, etc.)
function Inspector.buildPriceMap()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return 0 end
    local count = 0
    local ok, descendants = pcall(function() return pg:GetDescendants() end)
    if not ok then return 0 end
    for _, d in ipairs(descendants) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            local price = Util.parseNumber(d.Text)
            local looksLikePrice = price and price > 0
                and string.find(d.Text, "%d")
                and (string.find(d.Text, "%$") or string.find(Util.lower(d.Name), "price")
                     or string.find(Util.lower(d.Name), "cost") or string.find(Util.lower(d.Name), "value"))
            if looksLikePrice then
                -- on remonte jusqu'au conteneur qui porte le nom de l'item
                local holder = d.Parent
                for _ = 1, 3 do
                    if not holder or holder == pg then break end
                    local hn = Util.lower(holder.Name)
                    if hn ~= "iteminformation" and hn ~= "content" and hn ~= "items"
                       and hn ~= "frame" and hn ~= "container" then
                        State.PriceMap[hn] = price
                        count = count + 1
                        break
                    end
                    holder = holder.Parent
                end
            end
        end
    end
    log("Table de prix construite depuis le shop : %d entrees", count)
    return count
end

-- retourne une liste triee { name, count, value, total }
function Inspector.scan(model)
    if not model then return {}, 0, 0 end
    local buckets, order = {}, {}
    local total, items = 0, 0

    local function addItem(inst)
        local name = itemNameOf(inst)
        local key  = Util.lower(name)
        local val  = itemValueOf(inst, name)
        local b = buckets[key]
        if not b then
            b = { name = name, count = 0, value = val, total = 0 }
            buckets[key] = b
            table.insert(order, b)
        end
        b.count = b.count + 1
        if val > 0 and b.value == 0 then b.value = val end
        b.total = b.total + val
        total = total + val
        items = items + 1
    end

    -- 1) dossiers "Purchases"
    local ok, descendants = pcall(function() return model:GetDescendants() end)
    if not ok then return {}, 0, 0 end

    local foundPurchases = false
    for _, d in ipairs(descendants) do
        if (d:IsA("Folder") or d:IsA("Model")) and Util.lower(d.Name) == "purchases" then
            foundPurchases = true
            for _, item in ipairs(d:GetChildren()) do
                addItem(item)
            end
        end
    end

    -- 2) repli : tous les modeles poses hors structure
    if not foundPurchases then
        for _, d in ipairs(descendants) do
            if d:IsA("Model") and not IGNORED_ITEMS[Util.lower(d.Name)] then
                local parentName = Util.lower(d.Parent and d.Parent.Name or "")
                if parentName ~= "" and not string.find(parentName, "accessor", 1, true) then
                    addItem(d)
                end
            end
        end
    end

    table.sort(order, function(a, b)
        if a.total == b.total then return a.count > b.count end
        return a.total > b.total
    end)
    return order, total, items
end

-- dump texte de la structure du plot (pratique pour adapter le script au jeu)
function Inspector.dump(model, maxLines)
    if not model then return "aucun plot selectionne" end
    maxLines = maxLines or 400
    local lines = { model:GetFullName() }
    local function walk(inst, depth)
        if #lines >= maxLines or depth > 5 then return end
        for _, child in ipairs(inst:GetChildren()) do
            if #lines >= maxLines then return end
            local attrs = ""
            local ok, t = pcall(function() return child:GetAttributes() end)
            if ok and t then
                local parts = {}
                for k, v in pairs(t) do table.insert(parts, k .. "=" .. tostring(v)) end
                if #parts > 0 then attrs = "  {" .. table.concat(parts, ", ") .. "}" end
            end
            table.insert(lines, string.rep("  ", depth) .. child.ClassName .. " " .. child.Name .. attrs)
            walk(child, depth + 1)
        end
    end
    walk(model, 1)
    return table.concat(lines, "\n")
end

----------------------------------------------------------------------------------
-- MODULE : TRADE
----------------------------------------------------------------------------------
local Trade = {}

local function argShapes(player, userId)
    return {
        { label = "player", args = { player } },
        { label = "userid", args = { userId } },
        { label = "name",   args = { player and player.Name } },
        { label = "table",  args = { { Player = player, UserId = userId } } },
    }
end

function Trade.invite(query)
    local remote = Remotes:Find("Invite")
    if not remote then
        return false, "remote 'Invite' introuvable (mets le chemin dans CONFIG.RemotePaths)"
    end

    local player, err = PlayerUtil.byQuery(query)
    local userId = player and player.UserId or tonumber(query) or PlayerUtil.userIdOf(query)
    if not player and not userId then
        return false, err or "joueur introuvable"
    end

    local shapes = argShapes(player, userId)

    -- mode force par la config
    if CONFIG.ArgMode ~= "auto" then
        for _, shape in ipairs(shapes) do
            if shape.label == CONFIG.ArgMode then
                if shape.args[1] == nil then return false, "argument indisponible pour ce mode" end
                local ok, res = Remotes:Send(remote, unpack(shape.args))
                if ok then
                    return true, string.format("trade envoye a %s (mode %s)",
                        player and player.Name or tostring(userId), shape.label)
                end
                return false, "echec : " .. tostring(res)
            end
        end
    end

    -- mode auto : on essaie chaque forme d'argument jusqu'a ce que ca passe
    local lastErr
    for _, shape in ipairs(shapes) do
        if shape.args[1] ~= nil then
            local ok, res = Remotes:Send(remote, unpack(shape.args))
            if ok and res ~= false then
                CONFIG.ArgMode = shape.label   -- on retient ce qui marche
                return true, string.format("trade envoye a %s (mode %s)",
                    player and player.Name or tostring(userId), shape.label)
            end
            lastErr = res
        end
    end
    return false, "aucune forme d'argument acceptee : " .. tostring(lastErr)
end

-- boutons annexes si les remotes existent (Accept / Decline / Ready / Cancel)
function Trade.simple(remoteName)
    local remote = Remotes:Find(remoteName)
    if not remote then return false, "remote '" .. remoteName .. "' introuvable" end
    local ok, res = Remotes:Send(remote)
    if ok then return true, remoteName .. " envoye" end
    return false, "echec " .. remoteName .. " : " .. tostring(res)
end

----------------------------------------------------------------------------------
-- MODULE : TRADUCTEUR
----------------------------------------------------------------------------------
local Translator = { cache = {}, available = true }

function Translator.raw(text, target, source)
    local key = tostring(target) .. "|" .. text
    if Translator.cache[key] then return Translator.cache[key] end

    local url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl="
        .. (source or "auto") .. "&tl=" .. tostring(target) .. "&dt=t&q=" .. Util.urlEncode(text)

    local body = Util.httpGet(url)
    if not body then
        Translator.available = false
        return nil, "requetes HTTP indisponibles (executor sans 'request' / HttpGet)"
    end

    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok or type(data) ~= "table" or type(data[1]) ~= "table" then
        return nil, "reponse de traduction illisible"
    end

    local parts = {}
    for _, seg in ipairs(data[1]) do
        if type(seg) == "table" and type(seg[1]) == "string" then
            table.insert(parts, seg[1])
        end
    end
    local out = table.concat(parts)
    local detected = type(data[3]) == "string" and data[3] or "?"
    if out == "" then return nil, "traduction vide" end

    Translator.cache[key] = out
    return out, detected
end

function Translator.translate(text, target)
    text = Util.trim(text)
    if text == "" then return nil, "texte vide" end
    return Translator.raw(text, target or CONFIG.TranslateTo)
end

----------------------------------------------------------------------------------
-- MODULE : CHAT DE TRADE
----------------------------------------------------------------------------------
local Chat = { remote = nil, hooked = false, patched = {} }

local function pushChat(who, original, translated)
    local entry = { who = who, original = original, translated = translated, at = os.date("%H:%M") }
    table.insert(State.ChatLog, entry)
    if #State.ChatLog > 100 then table.remove(State.ChatLog, 1) end
    if UI and UI.pushChat then UI.pushChat(entry) end
end

function Chat.getRemote()
    if Chat.remote and Chat.remote.Parent then return Chat.remote end
    Chat.remote = Remotes:Find("SendChatMessage") or Remotes:Find("ChatMessage") or Remotes:Find("Chat")
    return Chat.remote
end

-- envoie un message (traduit si demande)
function Chat.send(text, translateTo)
    local remote = Chat.getRemote()
    if not remote then return false, "remote de chat introuvable" end
    text = Util.trim(text)
    if text == "" then return false, "message vide" end

    local final = text
    if translateTo and translateTo ~= "" then
        local out = Translator.translate(text, translateTo)
        if out then final = out end
    end

    local ok, err = Remotes:Send(remote, final)
    if not ok then return false, "echec envoi : " .. tostring(err) end
    pushChat("moi", text, final ~= text and final or nil)
    return true, final
end

-- extrait le message texte des arguments d'un remote de chat
local function extractMessage(...)
    local args = { ... }
    local sender, message
    for _, v in ipairs(args) do
        if typeof(v) == "Instance" and v:IsA("Player") then
            sender = v
        elseif type(v) == "string" and #v > 0 then
            if not message or #v > #message then message = v end
        elseif type(v) == "table" then
            if type(v.Message) == "string" then message = v.Message end
            if typeof(v.Player) == "Instance" then sender = v.Player end
            if type(v.Sender) == "string" and not sender then
                sender = PlayerUtil.byQuery(v.Sender)
            end
        end
    end
    return sender, message
end

-- ecoute les messages recus
function Chat.hookIncoming()
    local remote = Chat.getRemote()
    if not remote or not remote:IsA("RemoteEvent") then
        log("chat : pas de RemoteEvent a ecouter (lecture GUI seulement)")
        return
    end
    Maid.conn(remote.OnClientEvent:Connect(function(...)
        if State.Unloaded or not CONFIG.TranslateIncoming then return end
        local sender, message = extractMessage(...)
        if not message then return end
        if sender == LocalPlayer then return end
        spawnTask(function()
            local out = Translator.translate(message, CONFIG.TranslateTo)
            pushChat(sender and sender.Name or "eux", message, out)
            if out and out ~= message then
                notify(sender and sender.Name or "Trade", out, 6)
            end
        end)
    end))
    log("chat : ecoute de %s", remote:GetFullName())
end

-- reecrit directement les bulles de chat affichees par le jeu
local function looksLikeTradeChat(inst)
    local full = Util.lower(inst:GetFullName())
    return string.find(full, "trade", 1, true) and string.find(full, "chat", 1, true)
end

function Chat.patchGui()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return end

    local function handleLabel(label)
        if not CONFIG.PatchChatGui or not CONFIG.TranslateIncoming then return end
        if not label:IsA("TextLabel") then return end
        if Chat.patched[label] then return end
        if not looksLikeTradeChat(label) then return end
        local original = Util.trim(label.Text)
        if original == "" or #original < 2 then return end
        Chat.patched[label] = true
        spawnTask(function()
            local out, detected = Translator.translate(original, CONFIG.TranslateTo)
            if not out or out == original or State.Unloaded then return end
            if not label.Parent then return end
            if CONFIG.ShowOriginal then
                label.Text = original .. "  |  " .. out
            else
                label.Text = out
            end
            pushChat("chat(" .. tostring(detected) .. ")", original, out)
        end)
    end

    Maid.conn(pg.DescendantAdded:Connect(function(d)
        if State.Unloaded then return end
        if d:IsA("TextLabel") then
            spawnTask(function()
                waitFor(0.15)
                handleLabel(d)
            end)
        end
    end))

    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("TextLabel") then handleLabel(d) end
    end
    log("chat : patch GUI actif")
end

-- traduit automatiquement ce que TU tapes dans le chat du jeu (executor requis)
function Chat.hookOutgoing()
    if Chat.hooked then return end
    if not (Env.hookmetamethod and Env.getnamecall) then
        log("chat sortant : hookmetamethod indisponible, utilise la barre d'envoi du hub")
        return
    end
    local old
    old = Env.hookmetamethod(game, "__namecall", function(self, ...)
        local ok, method = pcall(Env.getnamecall)
        if ok and not State.Unloaded and CONFIG.TranslateOutgoing
           and (method == "FireServer" or method == "InvokeServer")
           and self == Chat.remote
           and not (Env.checkcaller and Env.checkcaller()) then
            local args = { ... }
            for i, v in ipairs(args) do
                if type(v) == "string" and Util.trim(v) ~= "" then
                    local original = v
                    spawnTask(function()
                        local out = Translator.translate(original, CONFIG.SendAs) or original
                        args[i] = out
                        pcall(function() old(self, unpack(args)) end)
                        pushChat("moi", original, out ~= original and out or nil)
                    end)
                    return
                end
            end
        end
        return old(self, ...)
    end)
    Chat.hooked = true
    log("chat sortant : hook actif (traduction vers %s)", CONFIG.SendAs)
end

----------------------------------------------------------------------------------
-- INTERFACE : petite lib maison
----------------------------------------------------------------------------------
local THEME = {
    bg        = Color3.fromRGB(18, 18, 22),
    panel     = Color3.fromRGB(26, 26, 32),
    panel2    = Color3.fromRGB(34, 34, 42),
    accent    = Color3.fromRGB(120, 90, 255),
    accent2   = Color3.fromRGB(90, 200, 160),
    text      = Color3.fromRGB(236, 236, 240),
    dim       = Color3.fromRGB(150, 150, 165),
    danger    = Color3.fromRGB(230, 90, 90),
    ok        = Color3.fromRGB(110, 210, 140),
}

UI = { pages = {}, tabs = {}, lists = {} }

local function mk(class, props)
    local inst = Instance.new(class)
    local parent = nil
    for k, v in pairs(props or {}) do
        if k == "Parent" then parent = v else inst[k] = v end
    end
    if parent then inst.Parent = parent end
    return inst
end

local function corner(inst, r)
    mk("UICorner", { CornerRadius = UDim.new(0, r or 6), Parent = inst })
    return inst
end

local function stroke(inst, color, thickness)
    mk("UIStroke", {
        Color = color or THEME.panel2,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = inst,
    })
    return inst
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
-- FENETRE PRINCIPALE
----------------------------------------------------------------------------------
local screen = mk("ScreenGui", {
    Name = "TPH_" .. tostring(math.random(100000, 999999)),
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 999,
    Parent = guiParent(),
})
Maid.inst(screen)
if syn and syn.protect_gui then pcall(syn.protect_gui, screen) end

local window = corner(mk("Frame", {
    Name = "Window",
    Size = UDim2.new(0, 640, 0, 430),
    Position = UDim2.new(0.5, -320, 0.5, -215),
    BackgroundColor3 = THEME.bg,
    BorderSizePixel = 0,
    Parent = screen,
}), 10)
stroke(window, THEME.panel2, 1.4)

local titleBar = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 38),
    BackgroundColor3 = THEME.panel,
    BorderSizePixel = 0,
    Parent = window,
})
corner(titleBar, 10)
mk("Frame", {   -- masque le bas arrondi de la barre de titre
    Size = UDim2.new(1, 0, 0, 12),
    Position = UDim2.new(0, 0, 1, -12),
    BackgroundColor3 = THEME.panel,
    BorderSizePixel = 0,
    Parent = titleBar,
})

mk("TextLabel", {
    Size = UDim2.new(0.6, 0, 1, 0),
    Position = UDim2.new(0, 14, 0, 0),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    Text = "TRADE PLAZA HUB",
    TextSize = 14,
    TextColor3 = THEME.text,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = titleBar,
})

local statusLabel = mk("TextLabel", {
    Size = UDim2.new(0, 260, 1, 0),
    Position = UDim2.new(1, -330, 0, 0),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    Text = "init...",
    TextSize = 11,
    TextColor3 = THEME.dim,
    TextXAlignment = Enum.TextXAlignment.Right,
    Parent = titleBar,
})

local function setStatus(text, color)
    statusLabel.Text = tostring(text)
    statusLabel.TextColor3 = color or THEME.dim
end

local function titleButton(text, color, offset, callback)
    local btn = corner(mk("TextButton", {
        Size = UDim2.new(0, 26, 0, 22),
        Position = UDim2.new(1, offset, 0.5, -11),
        BackgroundColor3 = THEME.panel2,
        AutoButtonColor = true,
        Font = Enum.Font.GothamBold,
        Text = text,
        TextSize = 13,
        TextColor3 = color,
        BorderSizePixel = 0,
        Parent = titleBar,
    }), 6)
    Maid.conn(btn.MouseButton1Click:Connect(callback))
    return btn
end

local body = mk("Frame", {
    Size = UDim2.new(1, 0, 1, -38),
    Position = UDim2.new(0, 0, 0, 38),
    BackgroundTransparency = 1,
    Parent = window,
})

local tabStrip = mk("Frame", {
    Size = UDim2.new(0, 140, 1, 0),
    BackgroundColor3 = THEME.panel,
    BorderSizePixel = 0,
    Parent = body,
})
mk("UIListLayout", {
    Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder,
    Parent = tabStrip,
})
mk("UIPadding", {
    PaddingTop = UDim.new(0, 8),
    PaddingLeft = UDim.new(0, 8),
    PaddingRight = UDim.new(0, 8),
    Parent = tabStrip,
})

local content = mk("Frame", {
    Size = UDim2.new(1, -140, 1, 0),
    Position = UDim2.new(0, 140, 0, 0),
    BackgroundTransparency = 1,
    Parent = body,
})

--// drag
do
    local dragging, dragStart, startPos = false, nil, nil
    Maid.conn(titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, input.Position, window.Position
        end
    end))
    Maid.conn(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            window.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end))
    Maid.conn(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end

----------------------------------------------------------------------------------
-- COMPOSANTS
----------------------------------------------------------------------------------
local function addTab(name)
    local page = mk("ScrollingFrame", {
        Name = name,
        Size = UDim2.new(1, -16, 1, -16),
        Position = UDim2.new(0, 8, 0, 8),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = THEME.accent,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = false,
        Parent = content,
    })
    mk("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = page,
    })

    local btn = corner(mk("TextButton", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = THEME.panel2,
        BackgroundTransparency = 0.35,
        AutoButtonColor = false,
        Font = Enum.Font.Gotham,
        Text = name,
        TextSize = 12,
        TextColor3 = THEME.dim,
        BorderSizePixel = 0,
        Parent = tabStrip,
    }), 6)

    UI.pages[name] = page
    UI.tabs[name] = btn

    Maid.conn(btn.MouseButton1Click:Connect(function()
        for tabName, p in pairs(UI.pages) do
            p.Visible = (tabName == name)
            local b = UI.tabs[tabName]
            b.BackgroundTransparency = (tabName == name) and 0 or 0.35
            b.TextColor3 = (tabName == name) and THEME.text or THEME.dim
        end
    end))
    return page
end

local function section(page, text)
    local lbl = mk("TextLabel", {
        Size = UDim2.new(1, -6, 0, 20),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        Text = string.upper(text),
        TextSize = 11,
        TextColor3 = THEME.accent,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = page,
    })
    return lbl
end

local function label(page, text, color)
    return mk("TextLabel", {
        Size = UDim2.new(1, -6, 0, 18),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = text,
        TextSize = 11,
        TextColor3 = color or THEME.dim,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = page,
    })
end

local function button(parent, text, callback, width, color)
    local btn = corner(mk("TextButton", {
        Size = width and UDim2.new(0, width, 0, 28) or UDim2.new(1, -6, 0, 28),
        BackgroundColor3 = color or THEME.panel2,
        AutoButtonColor = true,
        Font = Enum.Font.GothamMedium,
        Text = text,
        TextSize = 12,
        TextColor3 = THEME.text,
        BorderSizePixel = 0,
        Parent = parent,
    }), 6)
    Maid.conn(btn.MouseButton1Click:Connect(function()
        spawnTask(function()
            local ok, err = pcall(callback)
            if not ok then log("erreur bouton '%s' : %s", text, tostring(err)) end
        end)
    end))
    return btn
end

local function row(page, height)
    local frame = mk("Frame", {
        Size = UDim2.new(1, -6, 0, height or 28),
        BackgroundTransparency = 1,
        Parent = page,
    })
    mk("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = frame,
    })
    return frame
end

local function input(page, placeholder, onEnter)
    local box = corner(mk("TextBox", {
        Size = UDim2.new(1, -6, 0, 30),
        BackgroundColor3 = THEME.panel,
        Font = Enum.Font.Gotham,
        PlaceholderText = placeholder,
        PlaceholderColor3 = THEME.dim,
        Text = "",
        TextSize = 12,
        TextColor3 = THEME.text,
        ClearTextOnFocus = false,
        BorderSizePixel = 0,
        Parent = page,
    }), 6)
    stroke(box, THEME.panel2)
    mk("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = box })
    if onEnter then
        Maid.conn(box.FocusLost:Connect(function(enterPressed)
            if enterPressed then
                spawnTask(function() pcall(onEnter, box.Text, box) end)
            end
        end))
    end
    return box
end

local function toggle(page, text, key, callback)
    local holder = corner(mk("TextButton", {
        Size = UDim2.new(1, -6, 0, 28),
        BackgroundColor3 = THEME.panel,
        AutoButtonColor = false,
        Font = Enum.Font.Gotham,
        Text = "",
        BorderSizePixel = 0,
        Parent = page,
    }), 6)
    mk("TextLabel", {
        Size = UDim2.new(1, -60, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = text,
        TextSize = 12,
        TextColor3 = THEME.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = holder,
    })
    local pill = corner(mk("Frame", {
        Size = UDim2.new(0, 40, 0, 18),
        Position = UDim2.new(1, -50, 0.5, -9),
        BackgroundColor3 = CONFIG[key] and THEME.accent2 or THEME.panel2,
        BorderSizePixel = 0,
        Parent = holder,
    }), 9)
    local knob = corner(mk("Frame", {
        Size = UDim2.new(0, 14, 0, 14),
        Position = CONFIG[key] and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7),
        BackgroundColor3 = THEME.text,
        BorderSizePixel = 0,
        Parent = pill,
    }), 7)

    Maid.conn(holder.MouseButton1Click:Connect(function()
        CONFIG[key] = not CONFIG[key]
        pill.BackgroundColor3 = CONFIG[key] and THEME.accent2 or THEME.panel2
        knob.Position = CONFIG[key] and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
        if callback then
            spawnTask(function() pcall(callback, CONFIG[key]) end)
        end
    end))
    return holder
end

-- bouton qui fait defiler une liste de valeurs (langues, modes...)
local function cycler(parent, prefix, values, key, width, callback)
    local index = 1
    for i, v in ipairs(values) do
        if v == CONFIG[key] then index = i break end
    end
    local btn
    btn = button(parent, prefix .. " : " .. tostring(CONFIG[key]), function()
        index = index % #values + 1
        CONFIG[key] = values[index]
        btn.Text = prefix .. " : " .. tostring(CONFIG[key])
        if callback then pcall(callback, CONFIG[key]) end
    end, width)
    return btn
end

-- zone de liste scrollable reutilisable
local function listBox(page, height)
    local holder = corner(mk("Frame", {
        Size = UDim2.new(1, -6, 0, height or 150),
        BackgroundColor3 = THEME.panel,
        BorderSizePixel = 0,
        Parent = page,
    }), 6)
    stroke(holder, THEME.panel2)
    local scroll = mk("ScrollingFrame", {
        Size = UDim2.new(1, -8, 1, -8),
        Position = UDim2.new(0, 4, 0, 4),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = THEME.accent,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = holder,
    })
    mk("UIListLayout", {
        Padding = UDim.new(0, 3),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = scroll,
    })
    return scroll
end

local function listLine(scroll, text, color)
    return mk("TextLabel", {
        Size = UDim2.new(1, -8, 0, 16),
        BackgroundTransparency = 1,
        Font = Enum.Font.Code,
        Text = text,
        TextSize = 11,
        TextColor3 = color or THEME.dim,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = scroll,
    })
end

local function clearChildren(scroll)
    for _, child in ipairs(scroll:GetChildren()) do
        if not child:IsA("UIListLayout") then child:Destroy() end
    end
end

----------------------------------------------------------------------------------
-- ONGLET : TELEPORT
----------------------------------------------------------------------------------
local pageTP = addTab("Teleport")

section(pageTP, "cible")
local tpInput = input(pageTP, "pseudo ou UserId...", nil)

local rowTP = row(pageTP)
button(rowTP, "TP a sa base", function()
    local plr, err = PlayerUtil.byQuery(tpInput.Text)
    if not plr then setStatus(err or "joueur introuvable", THEME.danger) log(err or "joueur introuvable") return end
    local ok, e = TP.toBase(plr)
    if ok then setStatus("TP -> base de " .. plr.Name, THEME.ok) log("TP base de %s", plr.Name)
    else setStatus(e, THEME.danger) log(tostring(e)) end
end, 130, THEME.accent)

button(rowTP, "TP au joueur", function()
    local plr, err = PlayerUtil.byQuery(tpInput.Text)
    if not plr then setStatus(err or "joueur introuvable", THEME.danger) return end
    local ok, e = TP.toPlayer(plr)
    setStatus(ok and ("TP -> " .. plr.Name) or tostring(e), ok and THEME.ok or THEME.danger)
end, 120)

button(rowTP, "Retour", function()
    local ok, e = TP.back()
    setStatus(ok and "retour a la position precedente" or tostring(e), ok and THEME.ok or THEME.danger)
end, 90)

toggle(pageTP, "Teleport par paliers (anti-fling)", "SteppedTeleport")
toggle(pageTP, "Noclip pendant le teleport", "NoclipOnTeleport")

section(pageTP, "joueurs du serveur")
local playersScroll = listBox(pageTP, 150)

section(pageTP, "plots detectes")
local plotsScroll = listBox(pageTP, 120)

local function smallButton(parent, text, width, color, callback)
    local btn = corner(mk("TextButton", {
        Size = UDim2.new(0, width, 1, 0),
        BackgroundColor3 = color or THEME.panel2,
        AutoButtonColor = true,
        Font = Enum.Font.Gotham,
        Text = text,
        TextSize = 11,
        TextColor3 = THEME.text,
        BorderSizePixel = 0,
        Parent = parent,
    }), 5)
    Maid.conn(btn.MouseButton1Click:Connect(function()
        spawnTask(function()
            local ok, err = pcall(callback)
            if not ok then log("erreur : %s", tostring(err)) end
        end)
    end))
    return btn
end

local inspectPlayer  -- defini dans l'onglet Base, utilise ici

local function refreshPlayers()
    clearChildren(playersScroll)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local line = mk("Frame", {
                Size = UDim2.new(1, -8, 0, 24),
                BackgroundTransparency = 1,
                Parent = playersScroll,
            })
            mk("TextLabel", {
                Size = UDim2.new(1, -250, 1, 0),
                BackgroundTransparency = 1,
                Font = Enum.Font.Gotham,
                Text = plr.Name .. "  (" .. plr.UserId .. ")",
                TextSize = 11,
                TextColor3 = THEME.text,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = line,
            })
            local btns = mk("Frame", {
                Size = UDim2.new(0, 244, 1, 0),
                Position = UDim2.new(1, -244, 0, 0),
                BackgroundTransparency = 1,
                Parent = line,
            })
            mk("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                Padding = UDim.new(0, 4),
                HorizontalAlignment = Enum.HorizontalAlignment.Right,
                SortOrder = Enum.SortOrder.LayoutOrder,
                Parent = btns,
            })
            smallButton(btns, "Base", 52, nil, function()
                local ok, e = TP.toBase(plr)
                setStatus(ok and ("TP -> base de " .. plr.Name) or tostring(e), ok and THEME.ok or THEME.danger)
            end)
            smallButton(btns, "Joueur", 58, nil, function()
                local ok, e = TP.toPlayer(plr)
                setStatus(ok and ("TP -> " .. plr.Name) or tostring(e), ok and THEME.ok or THEME.danger)
            end)
            smallButton(btns, "Voir", 50, nil, function()
                if inspectPlayer then inspectPlayer(plr) end
            end)
            smallButton(btns, "Trade", 56, THEME.accent, function()
                local ok, msg = Trade.invite(tostring(plr.UserId))
                setStatus(msg, ok and THEME.ok or THEME.danger)
                log("%s", tostring(msg))
            end)
        end
    end
end

local function refreshPlots()
    clearChildren(plotsScroll)
    local all = Plots:All()
    if #all == 0 then
        listLine(plotsScroll, "aucun conteneur de plots trouve dans workspace", THEME.danger)
        return
    end
    for _, entry in ipairs(all) do
        local line = mk("Frame", {
            Size = UDim2.new(1, -8, 0, 22),
            BackgroundTransparency = 1,
            Parent = plotsScroll,
        })
        local who = entry.owner and entry.owner.Name or "libre / inconnu"
        mk("TextLabel", {
            Size = UDim2.new(1, -110, 1, 0),
            BackgroundTransparency = 1,
            Font = Enum.Font.Code,
            Text = who .. "  <- " .. string.sub(entry.model.Name, 1, 22),
            TextSize = 11,
            TextColor3 = entry.owner and THEME.text or THEME.dim,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = line,
        })
        local btns = mk("Frame", {
            Size = UDim2.new(0, 104, 1, 0),
            Position = UDim2.new(1, -104, 0, 0),
            BackgroundTransparency = 1,
            Parent = line,
        })
        mk("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 4),
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Parent = btns,
        })
        smallButton(btns, "TP", 44, nil, function()
            if not entry.cframe then setStatus("plot sans position", THEME.danger) return end
            TP.to(entry.cframe)
            State.SelectedPlot = entry.model
            setStatus("TP -> plot " .. who, THEME.ok)
        end)
        smallButton(btns, "Voir", 52, nil, function()
            State.SelectedPlot = entry.model
            if inspectPlayer then inspectPlayer(entry.owner, entry.model) end
        end)
    end
end

button(pageTP, "Rafraichir joueurs + plots", function()
    refreshPlayers()
    refreshPlots()
    setStatus("listes rafraichies", THEME.ok)
end)

----------------------------------------------------------------------------------
-- ONGLET : TRADE
----------------------------------------------------------------------------------
local pageTrade = addTab("Trade")

section(pageTrade, "envoyer une demande")
local remoteLabel = label(pageTrade, "remote Invite : recherche...")
local tradeInput = input(pageTrade, "pseudo ou UserId du joueur...", function(text)
    local ok, msg = Trade.invite(text)
    setStatus(msg, ok and THEME.ok or THEME.danger)
    log("%s", tostring(msg))
end)

button(pageTrade, "Envoyer la demande de trade", function()
    local ok, msg = Trade.invite(tradeInput.Text)
    setStatus(msg, ok and THEME.ok or THEME.danger)
    log("%s", tostring(msg))
end, nil, THEME.accent)

button(pageTrade, "Trade le joueur le plus proche", function()
    local root = TP.root()
    if not root then setStatus("pas de personnage", THEME.danger) return end
    local best, bestDist
    for _, plr in ipairs(Players:GetPlayers()) do
        local char = plr.Character
        local r = char and char:FindFirstChild("HumanoidRootPart")
        if plr ~= LocalPlayer and r then
            local d = (r.Position - root.Position).Magnitude
            if not bestDist or d < bestDist then best, bestDist = plr, d end
        end
    end
    if not best then setStatus("aucun joueur a proximite", THEME.danger) return end
    local ok, msg = Trade.invite(tostring(best.UserId))
    setStatus(msg, ok and THEME.ok or THEME.danger)
    log("plus proche = %s (%.0f studs) : %s", best.Name, bestDist, tostring(msg))
end)

cycler(pageTrade, "Format d'argument", { "auto", "player", "userid", "name" }, "ArgMode")

section(pageTrade, "actions rapides")
local rowTrade = row(pageTrade)
button(rowTrade, "Accept", function()
    local ok, msg = Trade.simple("Accept")
    setStatus(msg, ok and THEME.ok or THEME.danger)
end, 90, THEME.accent2)
button(rowTrade, "Ready", function()
    local ok, msg = Trade.simple("Ready")
    setStatus(msg, ok and THEME.ok or THEME.danger)
end, 90)
button(rowTrade, "Decline", function()
    local ok, msg = Trade.simple("Decline")
    setStatus(msg, ok and THEME.ok or THEME.danger)
end, 90)
button(rowTrade, "Cancel", function()
    local ok, msg = Trade.simple("Cancel")
    setStatus(msg, ok and THEME.ok or THEME.danger)
end, 90, THEME.danger)

label(pageTrade, "Si le trade ne part pas : va dans l'onglet Remotes, copie le chemin exact du remote et mets-le dans CONFIG.RemotePaths.Invite.")

----------------------------------------------------------------------------------
-- ONGLET : CHAT / TRADUCTEUR
----------------------------------------------------------------------------------
local pageChat = addTab("Chat")

section(pageChat, "options")
toggle(pageChat, "Traduire les messages recus", "TranslateIncoming")
toggle(pageChat, "Traduire mes messages (hook)", "TranslateOutgoing", function(on)
    if on then Chat.hookOutgoing() end
end)
toggle(pageChat, "Garder le texte original", "ShowOriginal")
toggle(pageChat, "Reecrire les bulles du chat du jeu", "PatchChatGui")

local rowLang = row(pageChat)
cycler(rowLang, "Je lis en", LANGS, "TranslateTo", 180)
cycler(rowLang, "J'ecris en", LANGS, "SendAs", 180)

section(pageChat, "conversation")
local chatScroll = listBox(pageChat, 150)

local chatInput = input(pageChat, "message a envoyer...", nil)
local rowSend = row(pageChat)
button(rowSend, "Traduire & envoyer", function()
    local ok, msg = Chat.send(chatInput.Text, CONFIG.SendAs)
    if ok then chatInput.Text = "" end
    setStatus(ok and ("envoye : " .. tostring(msg)) or tostring(msg), ok and THEME.ok or THEME.danger)
end, 160, THEME.accent)
button(rowSend, "Envoyer tel quel", function()
    local ok, msg = Chat.send(chatInput.Text, nil)
    if ok then chatInput.Text = "" end
    setStatus(ok and "envoye" or tostring(msg), ok and THEME.ok or THEME.danger)
end, 140)
button(rowSend, "Test", function()
    local out, err = Translator.translate("bonjour, tu veux trade ?", CONFIG.SendAs)
    setStatus(out or ("traduction KO : " .. tostring(err)), out and THEME.ok or THEME.danger)
    log("test traduction -> %s", tostring(out or err))
end, 70)

function UI.pushChat(entry)
    local text = string.format("[%s] %s : %s", entry.at, entry.who, entry.original)
    listLine(chatScroll, text, THEME.dim)
    if entry.translated and entry.translated ~= entry.original then
        listLine(chatScroll, "        -> " .. entry.translated, THEME.accent2)
    end
    local children = chatScroll:GetChildren()
    if #children > 120 then
        for i = 1, 20 do
            local c = children[i]
            if c and not c:IsA("UIListLayout") then c:Destroy() end
        end
    end
end

----------------------------------------------------------------------------------
-- ONGLET : BASE (inspecteur)
----------------------------------------------------------------------------------
local pageBase = addTab("Base")

section(pageBase, "inspecter une base")
local baseInput = input(pageBase, "pseudo ou UserId...", nil)
local baseSummary = label(pageBase, "aucune base scannee", THEME.text)
local baseScroll = listBox(pageBase, 190)

local function renderInventory(model, ownerName)
    clearChildren(baseScroll)
    local items, total, count = Inspector.scan(model)
    if #items == 0 then
        listLine(baseScroll, "rien trouve sur ce plot (essaie le dump pour voir la structure)", THEME.danger)
        baseSummary.Text = "base de " .. ownerName .. " : vide ou structure inconnue"
        return
    end
    baseSummary.Text = string.format("base de %s  |  %d objets  |  %d types  |  valeur ~ %s",
        ownerName, count, #items, Util.comma(total))
    for _, item in ipairs(items) do
        local line = string.format("x%-3d  %-28s  %s", item.count, string.sub(item.name, 1, 28),
            item.total > 0 and Util.comma(item.total) or "-")
        listLine(baseScroll, line, item.total > 0 and THEME.text or THEME.dim)
    end
end

inspectPlayer = function(player, model)
    local target = model
    local ownerName = player and player.Name or "inconnu"
    if not target and player then
        target = Plots:ForPlayer(player)
    end
    if not target then
        setStatus("base introuvable pour " .. ownerName, THEME.danger)
        baseSummary.Text = "base introuvable pour " .. ownerName
        return
    end
    State.SelectedPlot = target
    for name, page in pairs(UI.pages) do
        page.Visible = (name == "Base")
        UI.tabs[name].BackgroundTransparency = (name == "Base") and 0 or 0.35
        UI.tabs[name].TextColor3 = (name == "Base") and THEME.text or THEME.dim
    end
    renderInventory(target, ownerName)
    setStatus("base de " .. ownerName .. " scannee", THEME.ok)
end

local rowBase = row(pageBase)
button(rowBase, "Scanner sa base", function()
    local plr, err = PlayerUtil.byQuery(baseInput.Text)
    if not plr then setStatus(err or "joueur introuvable", THEME.danger) return end
    inspectPlayer(plr)
end, 150, THEME.accent)
button(rowBase, "Ma base", function()
    inspectPlayer(LocalPlayer)
end, 90)
button(rowBase, "Table de prix (shop)", function()
    local n = Inspector.buildPriceMap()
    setStatus("prix charges : " .. n .. " entrees", THEME.ok)
end, 160)

button(pageBase, "Copier la structure du plot (dump)", function()
    if not State.SelectedPlot then setStatus("scanne d'abord une base", THEME.danger) return end
    local dump = Inspector.dump(State.SelectedPlot, 400)
    if Util.copy(dump) then
        setStatus("structure copiee dans le presse-papier", THEME.ok)
    else
        log("%s", dump)
        setStatus("presse-papier indispo -> dump envoye dans la console (F9)", THEME.dim)
    end
end)

----------------------------------------------------------------------------------
-- ONGLET : REMOTES
----------------------------------------------------------------------------------
local pageRemotes = addTab("Remotes")

section(pageRemotes, "remotes lies au trade")
local remotesScroll = listBox(pageRemotes, 250)

local function refreshRemotes()
    clearChildren(remotesScroll)
    local found = Remotes:Scan()
    if #found == 0 then
        listLine(remotesScroll, "aucun remote 'trade' trouve", THEME.danger)
        return
    end
    for _, remote in ipairs(found) do
        local full = remote:GetFullName()
        local line = mk("Frame", {
            Size = UDim2.new(1, -8, 0, 20),
            BackgroundTransparency = 1,
            Parent = remotesScroll,
        })
        mk("TextLabel", {
            Size = UDim2.new(1, -60, 1, 0),
            BackgroundTransparency = 1,
            Font = Enum.Font.Code,
            Text = (remote:IsA("RemoteFunction") and "[RF] " or "[RE] ") .. full,
            TextSize = 10,
            TextColor3 = THEME.text,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = line,
        })
        smallButton(line, "copier", 54, nil, function()
            if Util.copy(full) then
                setStatus("chemin copie", THEME.ok)
            else
                log("%s", full)
                setStatus("presse-papier indispo, voir console", THEME.dim)
            end
        end).Position = UDim2.new(1, -54, 0, 0)
    end
    setStatus(#found .. " remotes trouves", THEME.ok)
end

button(pageRemotes, "Scanner les remotes", refreshRemotes, nil, THEME.accent)
button(pageRemotes, "Vider le cache des remotes", function()
    Remotes.cache = {}
    Chat.remote = nil
    setStatus("cache vide", THEME.ok)
end)

----------------------------------------------------------------------------------
-- ONGLET : INFOS / LOGS
----------------------------------------------------------------------------------
local pageInfo = addTab("Infos")

section(pageInfo, "etat")
local infoLabel = label(pageInfo, "...", THEME.text)

section(pageInfo, "logs")
local logsScroll = listBox(pageInfo, 190)

function UI.pushLog(msg)
    listLine(logsScroll, msg, THEME.dim)
    local children = logsScroll:GetChildren()
    if #children > 160 then
        for i = 1, 40 do
            local c = children[i]
            if c and not c:IsA("UIListLayout") then c:Destroy() end
        end
    end
end

button(pageInfo, "Recharger les modules (remotes + chat)", function()
    Remotes.cache = {}
    Chat.remote = nil
    Chat.getRemote()
    Chat.hookIncoming()
    refreshRemotes()
    setStatus("modules recharges", THEME.ok)
end)

button(pageInfo, "Fermer le hub (unload)", function()
    if _G.TradePlazaHub and _G.TradePlazaHub.Unload then _G.TradePlazaHub.Unload() end
end, nil, THEME.danger)

----------------------------------------------------------------------------------
-- BOUTONS DE LA BARRE DE TITRE + RACCOURCI
----------------------------------------------------------------------------------
local minimized = false
titleButton("-", THEME.text, -62, function()
    minimized = not minimized
    body.Visible = not minimized
    window.Size = minimized and UDim2.new(0, 640, 0, 38) or UDim2.new(0, 640, 0, 430)
end)

titleButton("X", THEME.danger, -32, function()
    if _G.TradePlazaHub and _G.TradePlazaHub.Unload then _G.TradePlazaHub.Unload() end
end)

Maid.conn(UserInputService.InputBegan:Connect(function(inputObj, processed)
    if processed or State.Unloaded then return end
    if inputObj.KeyCode == CONFIG.Keybind then
        window.Visible = not window.Visible
    end
end))

----------------------------------------------------------------------------------
-- UNLOAD
----------------------------------------------------------------------------------
local function unload()
    if State.Unloaded then return end
    State.Unloaded = true
    setNoclip(false)
    Maid.clean()
    _G.TradePlazaHub = nil
    print("[TradePlazaHub] decharge.")
end

_G.TradePlazaHub = {
    Config    = CONFIG,
    State     = State,
    Remotes   = Remotes,
    Plots     = Plots,
    Teleport  = TP,
    Trade     = Trade,
    Chat      = Chat,
    Translator= Translator,
    Inspector = Inspector,
    Unload    = unload,
}

----------------------------------------------------------------------------------
-- INITIALISATION
----------------------------------------------------------------------------------
UI.tabs["Teleport"].BackgroundTransparency = 0
UI.tabs["Teleport"].TextColor3 = THEME.text
UI.pages["Teleport"].Visible = true

Maid.conn(Players.PlayerAdded:Connect(function()
    if not State.Unloaded then refreshPlayers() end
end))
Maid.conn(Players.PlayerRemoving:Connect(function()
    if not State.Unloaded then
        spawnTask(function() waitFor(0.2) refreshPlayers() end)
    end
end))

spawnTask(function()
    log("demarrage (executor: %s)", tostring(Env.isExecutor))

    local invite = Remotes:Find("Invite")
    remoteLabel.Text = invite and ("remote Invite : " .. invite:GetFullName())
                              or "remote Invite : INTROUVABLE - va dans l'onglet Remotes"
    remoteLabel.TextColor3 = invite and THEME.ok or THEME.danger

    Chat.getRemote()
    Chat.hookIncoming()
    if CONFIG.PatchChatGui then Chat.patchGui() end
    if CONFIG.TranslateOutgoing then Chat.hookOutgoing() end

    refreshPlayers()
    refreshPlots()
    refreshRemotes()

    local httpOk = Util.httpGet("https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=en&dt=t&q=test") ~= nil
    infoLabel.Text = table.concat({
        "Touche du menu : " .. tostring(CONFIG.Keybind.Name),
        "Executor detecte : " .. (Env.isExecutor and "oui" or "non"),
        "Traduction HTTP : " .. (httpOk and "operationnelle" or "INDISPO (pas de fonction request)"),
        "Presse-papier : " .. (Env.clipboard and "ok" or "indispo"),
        "Hook chat sortant : " .. ((Env.hookmetamethod and Env.getnamecall) and "possible" or "indispo"),
        "Remote Invite : " .. (invite and invite:GetFullName() or "introuvable"),
        "Remote Chat : " .. (Chat.remote and Chat.remote:GetFullName() or "introuvable"),
        "API console : _G.TradePlazaHub",
    }, "\n")
    infoLabel.TextColor3 = THEME.text

    setStatus("pret - " .. tostring(CONFIG.Keybind.Name) .. " pour cacher", THEME.ok)
    notify("Trade Plaza Hub", "Charge. " .. tostring(CONFIG.Keybind.Name) .. " pour afficher/cacher.", 6)
end)

return _G.TradePlazaHub

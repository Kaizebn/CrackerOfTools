--[[
==================================================================================
    TRADE PLAZA HUB  v3   --  script client (executor / LocalScript)
==================================================================================
    VERSION LECTURE SEULE
    ---------------------
    Ce hub ne touche a rien. Il n'envoie AUCUN appel au serveur, ne deplace
    pas le personnage et n'installe aucun hook. Il lit ce qui est deja charge
    chez toi et l'affiche. Rien la-dedans ne peut declencher un anti-cheat.

    Ce qui a ete retire, et pourquoi :
      - deplacement (vol BodyVelocity, marche auto, CFrame, noclip)
        -> le serveur compare ta position d'une frame a l'autre avec ta
           WalkSpeed : peu importe COMMENT tu bouges, la trajectoire est
           impossible et c'est ca qui fait kick.
      - invitation de trade, envoi de chat (FireServer / InvokeServer)
        -> un remote appele avec des arguments que le serveur n'attend pas
           fait kick, meme a un seul appel.
      - hookmetamethod sur __namecall
        -> detectable cote client, quoi qu'on en fasse.

    4 onglets :
      JOUEURS  - liste avec la tete de chaque joueur
      BASE     - scanner de brainrots avec apercu 3D, mutation et revenu/s
      CHAT     - traducteur du chat (lecture) + traduction a coller toi-meme
      REGLAGES - langues, affichage, journal

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

----------------------------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------------------------
local CONFIG = {
    Keybind      = Enum.KeyCode.RightControl,

    -- traduction
    TranslateTo       = "fr",
    SendAs            = "en",
    TranslateIncoming = true,
    PatchChatGui      = true,
    TranslateButtons  = false,  -- les boutons du jeu (Deal?, Last Offer...) sont
                                -- de l'interface, pas des messages : on les laisse

    -- Chemin exact du cadre de chat, relatif a PlayerGui. Renseigne pour
    -- Trade Live Trade : PlayerGui.TradeLiveTrade.TradeLiveTrade.Chat
    -- (contient NormalChat/ChatBox et RestrictedChat). Tout ce qui est dans
    -- ce cadre est traite comme du chat, sans heuristique.
    -- Mets "" pour revenir a la detection par mot-cle.
    ChatGuiPath       = "TradeLiveTrade.TradeLiveTrade.Chat",

    -- affichage
    ShowAvatars  = true,
    ShowModels   = true,
    ModelSize    = 110,         -- taille de l'apercu 3D des brainrots (px)

    -- decor de la base pris a tort pour un brainrot : compare en minuscules,
    -- en sous-chaine. Ajoute-en si le scanner ramene encore du mobilier.
    IgnoreNames  = { "lock base", "base lock", "unlock", "lock", "locked",
                     "buy plot", "buy base", "claim", "empty", "vide" },

    RemotePaths  = {},
}

if type(GENV.TradePlazaHubConfig) == "table" then
    for k, v in pairs(GENV.TradePlazaHubConfig) do CONFIG[k] = v end
end

local LANGS = {
    "fr","en","es","pt","pt-BR","de","it","nl","pl","tr","ru","uk","ar",
    "id","ms","vi","th","fil","ja","ko","zh-CN","hi","ro","sv",
}

local LANG_NAMES = {
    fr = "Francais", en = "English", es = "Espanol", pt = "Portugues",
    ["pt-BR"] = "Portugues BR", de = "Deutsch", it = "Italiano",
    nl = "Nederlands", pl = "Polski", tr = "Turkce", ru = "Russe",
    uk = "Ukrainien", ar = "Arabe", id = "Indonesien", ms = "Malais",
    vi = "Vietnamien", th = "Thai", fil = "Filipino", ja = "Japonais",
    ko = "Coreen", ["zh-CN"] = "Chinois", hi = "Hindi", ro = "Roumain",
    sv = "Suedois", auto = "auto-detect",
}

local function langName(code)
    code = tostring(code or "")
    return LANG_NAMES[code] or (code ~= "" and code or "auto-detect")
end

-- un fournisseur peut renvoyer autre chose qu'une langue ("?", un nom de
-- service...) : on n'affiche que ce qui ressemble vraiment a un code langue
local function isLangCode(code)
    code = tostring(code or "")
    if LANG_NAMES[code] then return true end
    return string.match(code, "^%a%a$") ~= nil
        or string.match(code, "^%a%a%-%a%a$") ~= nil
end

----------------------------------------------------------------------------------
-- ENVIRONNEMENT
----------------------------------------------------------------------------------
local Env = {}
Env.request        = (syn and syn.request) or (http and http.request)
                     or (fluxus and fluxus.request) or http_request or request
Env.clipboard      = setclipboard or toclipboard or (syn and syn.write_clipboard)
Env.gethui         = gethui
Env.isExecutor     = (Env.request ~= nil) or (gethui ~= nil)

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

-- retourne : corps, code HTTP (nil si inconnu). Un 429 de Google renvoie une
-- page HTML : on ne la prend pas pour du JSON, on passe au fournisseur suivant.
function Util.httpGet(url)
    if Env.request then
        local ok, res = pcall(Env.request, { Url = url, Method = "GET" })
        if ok and type(res) == "table" and res.Body then
            local code = tonumber(res.StatusCode or res.Status) or 200
            if code >= 200 and code < 300 then return res.Body, code end
            return nil, code
        end
    end
    local ok2, body = pcall(function() return game:HttpGetAsync(url) end)
    if ok2 and body then return body, nil end
    local ok3, body3 = pcall(function() return game:HttpGet(url) end)
    if ok3 and body3 then return body3, nil end
    return nil, nil
end

function Util.clock()
    if os and os.clock then return os.clock() end
    return tick()
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
    Unloaded = false, Logs = {}, ChatLog = {},
    Plot = nil, PlotOwner = nil,
}

local UI

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
-- REMOTES (LECTURE SEULE)
--   On localise un remote uniquement pour ECOUTER ce que le serveur nous
--   envoie (OnClientEvent). Aucun FireServer / InvokeServer nulle part dans
--   ce fichier : rien ne part vers le serveur.
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

-- rang de rarete : plus le nombre est grand, plus c'est rare. Sert au tri
-- (les plus rares en premier) et a la couleur du contour de la vignette.
local RARITY_RANK = {}
for i, r in ipairs(RARITIES) do RARITY_RANK[r] = i end

local function rarityRank(name)
    if not name then return 0 end
    return RARITY_RANK[Util.lower(Util.trim(name))] or 0
end
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

-- "Lock Base", "Unlock", les panneaux d'achat : ce sont des elements de decor
-- que isEntityModel prend pour des entites parce qu'ils ont un BillboardGui
-- avec un prix. On les jette sur le nom.
function Inspector.isIgnored(name)
    local n = Util.lower(Util.trim(name or ""))
    if n == "" then return true end
    for _, word in ipairs(CONFIG.IgnoreNames or {}) do
        if string.find(n, Util.lower(word), 1, true) then return true end
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

    local buckets, order, total, kept = {}, {}, 0, 0
    for _, model in ipairs(chosen) do
        local info = readEntity(model)
        if not Inspector.isIgnored(info.name) then
            kept = kept + 1
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
    end

    -- les plus rares en tete, puis le meilleur revenu, puis la quantite
    table.sort(order, function(a, b)
        local ra, rb = rarityRank(a.rarity), rarityRank(b.rarity)
        if ra ~= rb then return ra > rb end
        if a.total ~= b.total then return a.total > b.total end
        return a.count > b.count
    end)
    return order, total, kept
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
-- TRADUCTEUR
----------------------------------------------------------------------------------
local Translator = { cache = {}, pausedUntil = 0 }

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

local function decode(body)
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if ok then return data end
    return nil
end

-- Trois fournisseurs essayes dans l'ordre. Google finit par renvoyer du 429
-- (page HTML) quand on traduit beaucoup de messages a la suite : c'est ca qui
-- donnait "reponse illisible". Les deux suivants prennent alors le relais.
function Translator.providers(text, target, source)
    local q  = Util.urlEncode(text)
    local sl = (source and source ~= "") and source or "auto"
    local tl = tostring(target)
    return {
        {
            name = "google-gtx",
            url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl="
                .. sl .. "&tl=" .. tl .. "&dt=t&q=" .. q,
            parse = function(body)
                local data = decode(body)
                if type(data) == "table" and type(data[1]) == "table" then
                    local parts = {}
                    for _, seg in ipairs(data[1]) do
                        if type(seg) == "table" and type(seg[1]) == "string" then
                            table.insert(parts, seg[1])
                        end
                    end
                    if #parts > 0 then
                        return table.concat(parts),
                               (type(data[3]) == "string" and data[3]) or "?"
                    end
                end
                -- repli sans JSON : la premiere chaine du tableau suffit
                local first = string.match(body, '^%[%[%["(.-)"')
                if first then return first, "?" end
                return nil
            end,
        },
        {
            name = "google-dj",
            url = "https://clients5.google.com/translate_a/single?dj=1&dt=t&sl="
                .. sl .. "&tl=" .. tl .. "&q=" .. q,
            parse = function(body)
                local data = decode(body)
                if type(data) ~= "table" or type(data.sentences) ~= "table" then return nil end
                local parts = {}
                for _, seg in ipairs(data.sentences) do
                    if type(seg) == "table" and type(seg.trans) == "string" then
                        table.insert(parts, seg.trans)
                    end
                end
                if #parts == 0 then return nil end
                return table.concat(parts), (type(data.src) == "string" and data.src) or "?"
            end,
        },
        {
            name = "mymemory",
            url = "https://api.mymemory.translated.net/get?q=" .. q .. "&langpair="
                .. ((sl ~= "auto") and sl or "en") .. "%7C" .. tl,
            parse = function(body)
                local data = decode(body)
                if type(data) ~= "table" or type(data.responseData) ~= "table" then return nil end
                local out = data.responseData.translatedText
                if type(out) ~= "string" or out == "" then return nil end
                -- ce fournisseur ne detecte pas la langue : "?" et pas son nom,
                -- sinon l'indicateur affichait "mymemory" comme langue
                return out, "?"
            end,
        },
    }
end

function Translator.raw(text, target, source)
    local key = tostring(target) .. "|" .. text
    local hit = Translator.cache[key]
    -- le cache garde aussi la langue detectee, sinon elle etait perdue des le
    -- deuxieme passage sur le meme message
    if hit then return hit.out, hit.src end

    -- si les trois fournisseurs viennent d'echouer, on ne relance pas trois
    -- requetes par message pendant 30 s : on passe direct au phrasebook
    if Util.clock() < Translator.pausedUntil then
        return nil, "traduction en pause (echecs repetes)"
    end

    local lastErr = "aucun fournisseur n'a repondu"
    for _, provider in ipairs(Translator.providers(text, target, source)) do
        local body, code = Util.httpGet(provider.url)
        if body then
            local okParse, out, detected = pcall(provider.parse, body)
            if okParse and out and out ~= "" then
                Translator.cache[key] = { out = out, src = detected or "?" }
                return out, detected or "?"
            end
            lastErr = provider.name .. " : reponse illisible"
            log("traduction %s illisible : %s", provider.name,
                string.sub(tostring(body), 1, 120))
        else
            lastErr = provider.name .. " : HTTP " .. tostring(code or "pas de reponse")
            log("traduction %s : %s", provider.name, lastErr)
        end
    end
    Translator.pausedUntil = Util.clock() + 30
    return nil, lastErr
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
local Chat = { remote = nil, rootInst = nil, seen = {}, written = {},
               boxes = {}, listened = {} }

local function pushChat(who, original, translated)
    local entry = { who = who, original = original, translated = translated, at = os.date("%H:%M") }
    table.insert(State.ChatLog, entry)
    if #State.ChatLog > 100 then table.remove(State.ChatLog, 1) end
    if UI and UI.pushChat then pcall(UI.pushChat, entry) end
end

-- uniquement pour s'y ABONNER (OnClientEvent), jamais pour y envoyer
function Chat.getRemote()
    if Chat.remote and Chat.remote.Parent then return Chat.remote end
    Chat.remote = Remotes:Find("SendChatMessage") or Remotes:Find("ChatMessage")
        or Remotes:Find("SendMessage") or Remotes:Find("Chat")
    return Chat.remote
end

-- La zone de saisie du chat du jeu ("Type Here..."), cherchee dans le cadre
-- de chat. On prend celle dont le placeholder ou le nom ressemble a une
-- entree de texte, sinon la premiere TextBox trouvee.
function Chat.inputBox()
    local root = Chat.root()
    if not root then return nil end
    local ok, list = pcall(function() return root:GetDescendants() end)
    if not ok then return nil end
    local fallback
    for _, d in ipairs(list) do
        if d:IsA("TextBox") then
            local ph = Util.lower(tostring(d.PlaceholderText or ""))
            local nm = Util.lower(d.Name)
            if string.find(ph, "type", 1, true) or string.find(ph, "here", 1, true)
            or string.find(nm, "input", 1, true) or string.find(nm, "box", 1, true) then
                return d
            end
            fallback = fallback or d
        end
    end
    return fallback
end

-- Langue dans laquelle ta reponse est ecrite : celle detectee chez l'autre
-- si on la connait, sinon celle choisie dans "Repli :".
function Chat.replyLang()
    local d = State.LastDetected
    if d and d ~= "" and d ~= "?" then return d, true end
    return CONFIG.SendAs, false
end

-- Traduit ton texte vers la langue choisie et l'ECRIT dans la zone de saisie
-- du chat du jeu. C'est une ecriture locale sur une TextBox : aucun remote
-- n'est appele, c'est toi qui appuies sur Entree pour envoyer.
-- retourne : ok, texte final, ecrit dans le jeu ?, copie dans le presse-papier ?
function Chat.compose(text, translateTo)
    text = Util.trim(text or "")
    if text == "" then return false, "message vide" end

    local final = text
    if translateTo and translateTo ~= "" then
        local out, info = Translator.translate(text, translateTo)
        if out then
            final = out
        else
            -- on garde quand meme une trace de ce que tu voulais dire
            pushChat("a envoyer (non traduit)", text, nil)
            return false, "traduction impossible (" .. tostring(info) .. ")"
        end
    end

    local box, written = Chat.inputBox(), false
    if box then
        -- focus d'abord : si la TextBox a ClearTextOnFocus, elle se vide
        -- avant qu'on ecrive et pas apres
        pcall(function() box:CaptureFocus() end)
        written = pcall(function() box.Text = final end)
        pcall(function() box.CursorPosition = #final + 1 end)
    end

    pushChat("a envoyer", text, (final ~= text) and final or nil)
    return true, final, written, Util.copy(final)
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

-- On s'abonne a TOUS les remotes de chat trouves, pas seulement au premier :
-- ce jeu en a deux (TradeService/SendChatMessage et ChatService/ChatMessage)
-- et les messages du Trade Chat ne passent pas forcement par le meme que le
-- chat general. Abonnement seul : OnClientEvent est ce que le serveur nous
-- envoie, rien ne part dans l'autre sens.
function Chat.hookIncoming()
    local names = {}
    for _, d in ipairs(allRemotes()) do
        local okName, full = pcall(function() return Util.lower(d:GetFullName()) end)
        if okName and d:IsA("RemoteEvent") and not Chat.listened[d]
        and (string.find(full, "chatmessage", 1, true)
          or string.find(full, "chatservice", 1, true)
          or string.find(full, "sendmessage", 1, true)) then
            Chat.listened[d] = true
            Chat.remote = Chat.remote or d
            table.insert(names, d:GetFullName())
            Maid.conn(d.OnClientEvent:Connect(function(...)
                if State.Unloaded or not CONFIG.TranslateIncoming then return end
                local sender, message = extractMessage(...)
                if not message or sender == LocalPlayer then return end
                spawnTask(function()
                    local out = Translator.translate(message, CONFIG.TranslateTo)
                    pushChat(sender and sender.Name or "eux", message, out)
                    if out and out ~= message then
                        notify(sender and sender.Name or "Trade", out, 6)
                    end
                end)
            end))
        end
    end
    for _, n in ipairs(names) do log("chat ecoute : %s", n) end
    return names
end

-- mots d'interface a ne pas traduire (boutons, entetes, placeholders)
local UI_WORDS = {
    send = true, sent = true, accept = true, accepted = true, decline = true,
    cancel = true, close = true, trade = true, chat = true, ok = true,
    yes = true, no = true, ready = true, waiting = true, back = true,
    ["trade chat"] = true, ["type here..."] = true, ["type here"] = true,
    ["normal chat"] = true, ["restricted chat"] = true, ["live trade"] = true,
    -- boutons de phrases toutes faites du jeu : ce sont des commandes, pas
    -- des messages, et ils polluaient la conversation a chaque ouverture
    ["deal?"] = true, ["deal ?"] = true, ["no thanks"] = true,
    ["last offer"] = true, ["fair trade"] = true, ["add more"] = true,
    ["ajouter plus"] = true, ["derniere offre"] = true, ["non merci"] = true,
    ["first"] = true, ["you first"] = true, ["me first"] = true,
    ["waiting..."] = true, ["not in a trade"] = true, clear = true,
}

-- "\u{1F4B0} Deal?" -> "deal?" : on enleve les emoji et symboles de tete
-- avant de comparer, sinon aucun libelle du jeu ne correspondait
local function coreText(t)
    return Util.lower(Util.trim((string.gsub(tostring(t or ""), "^[^%w]+", ""))))
end

-- Cadre de chat cible. On resout CONFIG.ChatGuiPath sous PlayerGui : pour ce
-- jeu c'est PlayerGui.TradeLiveTrade.TradeLiveTrade.Chat, qui contient
-- NormalChat (avec ChatBox) et RestrictedChat. Quand ce cadre est trouve,
-- TOUT ce qu'il contient est traite comme du chat, sans heuristique de nom :
-- c'est ce qui garantit que chaque message ecrit par quelqu'un est detecte.
-- Si le chemin n'existe pas, on retombe sur la detection par mot-cle.
function Chat.root()
    if Chat.rootInst and Chat.rootInst.Parent then return Chat.rootInst, true end
    Chat.rootInst = nil
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil, false end
    local path = Util.trim(CONFIG.ChatGuiPath or "")
    if path ~= "" then
        local node = pg
        for part in string.gmatch(path, "[^%.]+") do
            node = node and node:FindFirstChild(part)
        end
        if node then
            Chat.rootInst = node
            return node, true
        end
    end
    return pg, false
end

local function onChatPath(inst)
    local root, exact = Chat.root()
    if exact and root then
        local ok, inside = pcall(function() return inst:IsDescendantOf(root) end)
        if ok and inside then return true end
        return false
    end
    local ok2, full = pcall(function() return Util.lower(inst:GetFullName()) end)
    if not ok2 then return false end
    return string.find(full, "chat", 1, true) ~= nil
        or string.find(full, "trade", 1, true) ~= nil
end

-- certains jeux affichent les messages en RichText : on enleve les balises
-- avant de traduire, sinon Google traduit le balisage
local function plainText(obj)
    local ok, t = pcall(function() return obj.Text end)
    if not ok or type(t) ~= "string" then return "" end
    local rich = false
    pcall(function() rich = obj.RichText end)
    if rich and string.find(t, "<", 1, true) then
        t = string.gsub(t, "<[^<>]->", "")
    end
    return Util.trim(t)
end

-- un caractere suffit : dans ce jeu un message peut etre juste "P"
local function looksLikeMessage(text)
    local t = Util.trim(text or "")
    if #t < 1 or #t > 240 then return false end
    if tonumber(t) then return false end
    if UI_WORDS[Util.lower(t)] then return false end
    if UI_WORDS[coreText(t)] then return false end
    return true
end

-- traduit un TextLabel ou un TextButton et se rebranche sur ses changements
-- de texte : les jeux reutilisent les memes lignes quand le chat defile
local function handleText(obj)
    if State.Unloaded then return end
    if not (CONFIG.PatchChatGui and CONFIG.TranslateIncoming) then return end
    local original = plainText(obj)
    if not looksLikeMessage(original) then return end
    if Chat.written[obj] == original then return end   -- notre propre ecriture
    if Chat.seen[obj] == original then return end      -- deja traite
    Chat.seen[obj] = original

    spawnTask(function()
        local out, detected = Translator.translate(original, CONFIG.TranslateTo)
        if State.Unloaded then return end

        -- Le message apparait dans le hub MEME quand la traduction echoue.
        -- Avant, un message que le traducteur refusait disparaissait
        -- completement : c'est pour ca que "Oui" ne s'affichait nulle part.
        if out then
            if UI and UI.setDetected then pcall(UI.setDetected, detected) end
            pushChat("chat/" .. tostring(detected), original,
                (out ~= original) and out or nil)
        else
            pushChat("chat (non traduit)", original, nil)
            log("traduction indisponible pour \"%s\" : %s", original, tostring(detected))
        end

        if not out or out == original then return end
        if not obj.Parent then return end
        -- on remplace par la seule traduction : le "original | traduction"
        -- doublait la longueur des lignes pour rien
        Chat.written[obj] = out
        pcall(function() obj.Text = out end)
    end)
end

-- ce que TU tapes dans le chat du jeu : on le lit dans la TextBox et on
-- l'affiche dans l'onglet Chat du hub. Lecture pure, rien n'est envoye.
local function watchBox(box)
    if Chat.boxes[box] then return end
    Chat.boxes[box] = true
    local lastTyped = ""
    Maid.conn(box:GetPropertyChangedSignal("Text"):Connect(function()
        local t = Util.trim(box.Text or "")
        if t ~= "" then lastTyped = t end
    end))
    Maid.conn(box.FocusLost:Connect(function(enter)
        if State.Unloaded or not enter then return end
        local txt = Util.trim(box.Text or "")
        if txt == "" then txt = lastTyped end
        lastTyped = ""
        if not looksLikeMessage(txt) then return end
        spawnTask(function()
            local out = Translator.translate(txt, CONFIG.TranslateTo)
            pushChat("moi", txt, (out and out ~= txt) and out or nil)
        end)
    end))
end

-- Les messages du chat sont des TextLabel. Les TextButton sont les phrases
-- toutes faites du jeu (Deal?, Last Offer, Fair Trade...) : on ne les traduit
-- pas, sinon elles remplissaient la conversation a chaque ouverture du chat.
local function isTextDisplay(inst)
    if inst:IsA("TextLabel") then return true end
    return CONFIG.TranslateButtons and inst:IsA("TextButton") or false
end

local function handleAny(inst)
    if not onChatPath(inst) then return end
    if inst:IsA("TextButton") and not CONFIG.TranslateButtons then return end
    if isTextDisplay(inst) then
        if Chat.seen[inst] == nil then
            Maid.conn(inst:GetPropertyChangedSignal("Text"):Connect(function()
                handleText(inst)
            end))
        end
        handleText(inst)
    elseif inst:IsA("TextBox") then
        watchBox(inst)
        -- la zone de saisie affiche aussi le texte de l'autre dans certains
        -- jeux : on la traite en lecture comme un label
        handleText(inst)
    end
end

local function isTextThing(inst)
    return inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox")
end

function Chat.patchGui()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return end

    -- on ecoute PlayerGui en entier : le cadre de chat peut etre cree apres
    -- le chargement du hub, et onChatPath filtre a l'arrivee
    Maid.conn(pg.DescendantAdded:Connect(function(d)
        if State.Unloaded or not isTextThing(d) then return end
        spawnTask(function() waitFor(0.15) pcall(handleAny, d) end)
    end))
    for _, d in ipairs(pg:GetDescendants()) do
        if isTextThing(d) then pcall(handleAny, d) end
    end

    local root, exact = Chat.root()
    if exact and root then
        log("cadre de chat trouve : %s", root:GetFullName())
    else
        log("cadre de chat '%s' introuvable - detection par mot-cle",
            tostring(CONFIG.ChatGuiPath))
    end
end

-- relance un balayage complet (bouton "Rescanner le chat")
-- retourne : elements de chat trouves, chemin du cadre, chemin exact ?
function Chat.rescan()
    Chat.seen, Chat.written, Chat.rootInst = {}, {}, nil
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return 0, "PlayerGui absent", false end
    local root, exact = Chat.root()
    local n = 0
    for _, d in ipairs(pg:GetDescendants()) do
        if isTextThing(d) then
            if onChatPath(d) then n = n + 1 end
            pcall(handleAny, d)
        end
    end
    Chat.hookIncoming()
    return n, (root and root:GetFullName() or "?"), exact
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
    size = size or tonumber(CONFIG.ModelSize) or 110
    local holder = corner(mk("Frame", {
        Size = UDim2.new(0, size, 0, size), BackgroundColor3 = THEME.surface,
        BorderSizePixel = 0, ClipsDescendants = true, Parent = parent,
    }), 8)
    stroke(holder, THEME.line, 1, 0.5)

    local fallback = mk("TextLabel", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold, Text = "?",
        TextSize = math.max(14, math.floor(size / 3)),
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
            -- cadrage serre : le modele remplit la vignette au lieu de flotter
            local offset = Vector3.new(radius * 0.52, radius * 0.30, radius * 0.60)
            camera.FieldOfView = 45
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

local WIN_W, WIN_H = 560, 400

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

local modePill = corner(mk("Frame", {
    Size = UDim2.new(0, 104, 0, 20), Position = UDim2.new(0, 176, 0.5, -10),
    BackgroundColor3 = THEME.card, BorderSizePixel = 0, Parent = titleBar,
}), 10)
stroke(modePill, THEME.good, 1, 0.3)
mk("TextLabel", {
    Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold, Text = "lecture seule", TextSize = 10,
    TextColor3 = THEME.good, Parent = modePill,
})

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
    Size = UDim2.new(0, 112, 1, 0), BackgroundColor3 = THEME.surface,
    BorderSizePixel = 0, Parent = bodyFrame,
})
listLayout(sidebar, 4)
pad(sidebar, 10)

local contentArea = mk("Frame", {
    Size = UDim2.new(1, -112, 1, 0), Position = UDim2.new(0, 112, 0, 0),
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

local function slider(parent, text, key, minVal, maxVal, suffix, onChange)
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
        or i.UserInputType == Enum.UserInputType.Touch then
            local was = dragging
            dragging = false
            -- on ne previent qu'au relachement, pas a chaque frame du drag
            if was and onChange then
                spawnTask(function() pcall(onChange, CONFIG[key]) end)
            end
        end
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

-- meme chose, mais les elements se suivent HORIZONTALEMENT et le panneau
-- defile de gauche a droite. Retourne le scroll et son cadre, pour pouvoir
-- ajuster la hauteur selon la taille des vignettes.
local function hpanel(parent, height)
    local holder = corner(mk("Frame", {
        Size = UDim2.new(1, 0, 0, height or 180), BackgroundColor3 = THEME.surface,
        BorderSizePixel = 0, Parent = parent,
    }), 8)
    local scroll = mk("ScrollingFrame", {
        Size = UDim2.new(1, -10, 1, -10), Position = UDim2.new(0, 5, 0, 5),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
        ScrollBarImageColor3 = THEME.accent, CanvasSize = UDim2.new(),
        ScrollingDirection = Enum.ScrollingDirection.X, Parent = holder,
    })
    local layout = listLayout(scroll, 8, true)
    Maid.conn(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scroll.CanvasSize = UDim2.new(0, layout.AbsoluteContentSize.X + 10, 0, 0)
    end))
    return scroll, holder
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

local function cycleButton(parent, prefix, values, key, width, fmt, onChange)
    fmt = fmt or tostring
    local index = 1
    for i, v in ipairs(values) do
        if v == CONFIG[key] then index = i break end
    end
    local b
    b = btn(parent, {
        text = prefix .. " " .. fmt(CONFIG[key]), width = width, style = "ghost",
        callback = function()
            index = index % #values + 1
            CONFIG[key] = values[index]
            b.Text = prefix .. " " .. fmt(CONFIG[key])
            if onChange then onChange(CONFIG[key]) end
        end,
    })
    return b
end

local scanBase, refreshPlayers

----------------------------------------------------------------------------------
-- ONGLET : JOUEURS  (la liste, et la base du joueur choisi juste en dessous)
----------------------------------------------------------------------------------
local pagePlayers = addTab("Joueurs")

local cardList = card(pagePlayers, "Joueurs du serveur",
    "VOIR LA BASE affiche ses brainrots juste en dessous")
local playersPanel = panel(cardList, 186)
btn(cardList, { text = "Rafraichir", callback = function()
    refreshPlayers()
    setStatus("liste rafraichie", THEME.good)
end })

local cardBase = card(pagePlayers, "Base")
local baseSummary = note(cardBase, "aucune base affichee", THEME.text)
local rowBase = rowOf(cardBase)
btn(rowBase, { text = "Ma base", width = 110, style = "primary",
    callback = function() scanBase(LocalPlayer) end })
btn(rowBase, { text = "Copier la structure", width = 160, callback = function()
    if not State.Plot then setStatus("affiche d'abord une base", THEME.bad) return end
    local dump = Inspector.dump(State.Plot, 400)
    if Util.copy(dump) then setStatus("structure copiee", THEME.good)
    else print(dump) setStatus("presse-papier indispo -> console F9", THEME.warn) end
end })
local brainrotPanel, brainrotHolder = hpanel(cardBase, 190)

local function playerRow(scroll, plr)
    local row = corner(mk("Frame", {
        Size = UDim2.new(1, -6, 0, 48), BackgroundColor3 = THEME.card,
        BackgroundTransparency = 0.2, BorderSizePixel = 0, Parent = scroll,
    }), 8)
    stroke(row, THEME.line, 1, 0.65)

    local head = avatar(row, plr.UserId, 34)
    head.Position = UDim2.new(0, 8, 0.5, -17)

    mk("TextLabel", {
        Size = UDim2.new(1, -190, 0, 15), Position = UDim2.new(0, 50, 0, 8),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
        Text = plr.DisplayName ~= "" and plr.DisplayName or plr.Name, TextSize = 12,
        TextColor3 = THEME.text, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
    })
    mk("TextLabel", {
        Size = UDim2.new(1, -190, 0, 13), Position = UDim2.new(0, 50, 0, 25),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham,
        Text = "@" .. plr.Name .. "   -   " .. plr.UserId, TextSize = 10,
        TextColor3 = THEME.sub, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
    })

    local see = btn(row, { text = "VOIR LA BASE", width = 126, height = 30,
        style = "primary", callback = function() scanBase(plr) end })
    see.Position = UDim2.new(1, -134, 0.5, -15)
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

-- couleur de contour par rarete : on repere la piece rare d'un coup d'oeil
local RARITY_COLORS = {
    common = Color3.fromRGB(150, 155, 170), uncommon = Color3.fromRGB(110, 205, 130),
    rare = Color3.fromRGB(90, 160, 255), epic = Color3.fromRGB(180, 110, 255),
    legendary = Color3.fromRGB(255, 190, 80), mythic = Color3.fromRGB(255, 110, 140),
    godly = Color3.fromRGB(255, 90, 90), ["brainrot god"] = Color3.fromRGB(255, 60, 200),
    secret = Color3.fromRGB(235, 235, 255), limited = Color3.fromRGB(0, 216, 190),
    exclusive = Color3.fromRGB(255, 140, 0), og = Color3.fromRGB(255, 215, 0),
}

local function rarityColor(name)
    if not name then return THEME.line end
    return RARITY_COLORS[Util.lower(Util.trim(name))] or THEME.line
end

-- une vignette = le modele 3D en haut, le nom, la rarete et le revenu dessous.
-- Elles se suivent horizontalement, la plus rare en premier.
local function brainrotTile(scroll, entry)
    local size = math.floor(Util.clamp(CONFIG.ModelSize, 48, 260))
    local col  = rarityColor(entry.rarity)

    local tile = corner(mk("Frame", {
        Size = UDim2.new(0, size + 16, 0, size + 64), BackgroundColor3 = THEME.card,
        BackgroundTransparency = 0.15, BorderSizePixel = 0, Parent = scroll,
    }), 10)
    stroke(tile, col, 1.5, 0.3)

    local icon = modelIcon(tile, entry.model, size)
    icon.Position = UDim2.new(0, 8, 0, 8)

    if entry.count > 1 then
        local badge = corner(mk("Frame", {
            Size = UDim2.new(0, 32, 0, 18), Position = UDim2.new(0, 12, 0, 12),
            BackgroundColor3 = THEME.bg, BackgroundTransparency = 0.12,
            BorderSizePixel = 0, ZIndex = 5, Parent = tile,
        }), 9)
        mk("TextLabel", {
            Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, ZIndex = 6,
            Font = Enum.Font.GothamBold, Text = "x" .. entry.count, TextSize = 11,
            TextColor3 = THEME.text, Parent = badge,
        })
    end

    mk("TextLabel", {
        Size = UDim2.new(1, -12, 0, 15), Position = UDim2.new(0, 6, 0, size + 12),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = entry.name,
        TextSize = 12, TextColor3 = THEME.text,
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = tile,
    })
    mk("TextLabel", {
        Size = UDim2.new(1, -12, 0, 13), Position = UDim2.new(0, 6, 0, size + 28),
        BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
        Text = entry.mutation or entry.rarity or "-", TextSize = 10, TextColor3 = col,
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = tile,
    })
    mk("TextLabel", {
        Size = UDim2.new(1, -12, 0, 16), Position = UDim2.new(0, 6, 0, size + 43),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
        Text = entry.total > 0 and ("$" .. Util.short(entry.total) .. "/s") or "-",
        TextSize = 13, TextColor3 = THEME.accent2, Parent = tile,
    })
    return tile
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
    clearChildren(brainrotPanel)
    brainrotHolder.Size = UDim2.new(1, 0, 0,
        math.floor(Util.clamp(CONFIG.ModelSize, 48, 260)) + 84)

    local list, total, count = Inspector.brainrots(plot)
    baseSummary.Text = string.format(
        "Base de %s   -   %d brainrots   -   %d types   -   revenu total $%s/s",
        ownerName, count, #list, Util.short(total))

    if #list == 0 then
        textLine(brainrotPanel, "aucun brainrot reconnu sur cette base", THEME.bad, Enum.Font.Gotham)
        textLine(brainrotPanel, "clique sur 'Copier la structure' et envoie-moi le resultat",
            THEME.sub, Enum.Font.Gotham)
    else
        for i, entry in ipairs(list) do
            if i > 60 then break end
            brainrotTile(brainrotPanel, entry)
        end
    end
    setStatus("base de " .. ownerName .. " : " .. count .. " brainrots", THEME.good)
end

-- re-affiche la base courante (apres un changement de taille de vignette)
local function redrawBase()
    if State.Plot then scanBase(nil, State.Plot, State.PlotOwner) end
end

----------------------------------------------------------------------------------
-- ONGLET : CHAT
----------------------------------------------------------------------------------
local pageChat = addTab("Chat")

local cardTrad = card(pageChat, "Traducteur",
    "la langue de l'autre est detectee toute seule")
local refreshLangNote

local rowLangs = rowOf(cardTrad)
cycleButton(rowLangs, "Je lis :", LANGS, "TranslateTo", 168, langName)
cycleButton(rowLangs, "Repli :", LANGS, "SendAs", 168, langName, function()
    refreshLangNote()
end)

local detectNote = note(cardTrad, "langue detectee : en attente d'un message", THEME.accent2)

refreshLangNote = function()
    local lang, fromDetection = Chat.replyLang()
    detectNote.Text = "langue detectee : "
        .. (State.LastDetected and langName(State.LastDetected) or "en attente")
        .. "     ->     ta reponse partira en " .. langName(lang)
        .. (fromDetection and " (detecte)" or " (repli)")
end

-- appele par le traducteur des qu'un fournisseur nous rend la langue source
function UI.setDetected(code)
    local c = Util.trim(tostring(code or ""))
    if c == "" or c == "?" or c == "cache" or c == "hors-ligne" then return end
    if not isLangCode(c) then return end
    -- tes propres messages passent aussi dans le chat : si la langue detectee
    -- est celle que tu lis, c'est probablement toi, pas ton interlocuteur.
    -- On ne s'en sert pas comme langue de reponse.
    if c == CONFIG.TranslateTo then return end
    State.LastDetected = c
    refreshLangNote()
end

refreshLangNote()

switch(cardTrad, "Traduire les messages recus", "TranslateIncoming")

local chatDiag = note(cardTrad, "cadre de chat : pas encore scanne", THEME.sub)
btn(cardTrad, { text = "Rescanner le chat du jeu", callback = function()
    local n, where, exact = Chat.rescan()
    chatDiag.Text = (exact and "cadre trouve : " or "detection par mot-cle : ")
        .. tostring(where) .. "   -   " .. tostring(n) .. " element(s) de texte"
    setStatus(n > 0 and (n .. " element(s) de chat trouve(s), traduction relancee")
        or "aucun chat trouve - ouvre le Trade Chat dans le jeu puis reclique",
        n > 0 and THEME.good or THEME.warn)
end })

local cardConv = card(pageChat, "Conversation",
    "tape dans ta langue : le hub traduit et ecrit dans le chat du jeu")
local chatPanel = panel(cardConv, 150)

local sendReply
local chatField = field(cardConv, "type in your language...   (Entree pour envoyer)",
    function(text) if sendReply then sendReply(text) end end)
local rowSend = rowOf(cardConv, 36)

-- traduit vers la langue detectee chez l'autre (repli sur "Repli :") puis
-- ecrit dans la zone de saisie du chat du jeu
sendReply = function(text)
    local lang, fromDetection = Chat.replyLang()
    local ok, msg, written, copied = Chat.compose(text, lang)
    if not ok then setStatus(tostring(msg), THEME.bad) return end
    chatField.Text = ""
    local how = " [" .. langName(lang) .. (fromDetection and " detecte]" or " repli]")
    if written then
        setStatus("ecrit dans le chat" .. how .. " : " .. tostring(msg), THEME.good)
    elseif copied then
        setStatus("zone de saisie introuvable, copie" .. how .. " : " .. tostring(msg), THEME.warn)
    else
        setStatus("traduit" .. how .. " : " .. tostring(msg), THEME.warn)
    end
end

btn(rowSend, { text = "ECRIRE DANS LE CHAT", width = 214, height = 36, style = "primary",
    callback = function() sendReply(chatField.Text) end })
btn(rowSend, { text = "Effacer", width = 104, height = 36, callback = function()
    chatField.Text = ""
    clearChildren(chatPanel)
    setStatus("conversation effacee", THEME.sub)
end })

-- une seule ligne par message, celle qui compte : la traduction. Le doublon
-- en gris avec le texte d'origine rendait la conversation illisible.
function UI.pushChat(entry)
    local shown = entry.translated or entry.original
    if not shown or shown == "" then return end
    textLine(chatPanel, string.format("[%s]  %s", entry.at, shown),
        THEME.accent2, Enum.Font.GothamMedium)
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

local cardDisplay = card(pageSettings, "Affichage")
switch(cardDisplay, "Tete des joueurs", "ShowAvatars")
switch(cardDisplay, "Apercu 3D des brainrots", "ShowModels")
slider(cardDisplay, "Taille de l'apercu 3D", "ModelSize", 48, 220, " px", function()
    redrawBase()
end)
note(cardDisplay, "La taille s'applique au relachement du curseur : la base affichee est redessinee toute seule.", THEME.sub)

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
    State.Unloaded = true
    Maid.clean()
    GENV.TradePlazaHub = nil
    print("[TPH] decharge.")
end

GENV.TradePlazaHub = {
    Config = CONFIG, State = State, Remotes = Remotes, Plots = Plots,
    Chat = Chat, Translator = Translator, Inspector = Inspector, Unload = unload,
}

----------------------------------------------------------------------------------
-- INITIALISATION
----------------------------------------------------------------------------------
UI.select("Joueurs")

window.Size = UDim2.new(0, WIN_W - 50, 0, WIN_H - 34)
tween(window, { Size = UDim2.new(0, WIN_W, 0, WIN_H) }, 0.3, Enum.EasingStyle.Back)

Maid.conn(Players.PlayerAdded:Connect(function()
    if not State.Unloaded then pcall(refreshPlayers) end
end))
Maid.conn(Players.PlayerRemoving:Connect(function()
    if State.Unloaded then return end
    spawnTask(function() waitFor(0.2) pcall(refreshPlayers) end)
end))
local function init()
    log("demarrage lecture seule (executor : %s)", tostring(Env.isExecutor))
    Chat.getRemote()
    local chatRemotes = #Chat.hookIncoming()
    if CONFIG.PatchChatGui then Chat.patchGui() end

    refreshPlayers()

    local httpOk = Util.httpGet(
        "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=en&dt=t&q=test") ~= nil

    local root, exact = Chat.root()
    log("chat : %s%s   |   %d remote(s) ecoute(s)   |   traduction en ligne : %s",
        exact and "" or "[mot-cle] ",
        root and root:GetFullName() or "PlayerGui absent",
        chatRemotes, httpOk and "ok" or "indisponible")

    setStatus(httpOk and ("pret - " .. tostring(CONFIG.Keybind.Name) .. " pour cacher")
        or "pret, mais la traduction en ligne ne repond pas", httpOk and THEME.good or THEME.warn)
    notify("Trade Plaza Hub", "Charge. " .. tostring(CONFIG.Keybind.Name) .. " pour afficher/cacher.", 5)
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

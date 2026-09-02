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

    Fenetre en format portrait (380 x 660), onglets en bas comme dans une
    app mobile. Les icones sont dessinees avec des Frames (cercles,
    rectangles arrondis, rotations) : aucun caractere special, donc rien
    qui casse selon la police du client.

      JOUEURS  - la liste du serveur, puis la base du joueur choisi
      CHAT     - la langue detectee, la conversation traduite, la saisie
      REGLAGES - langues, police des messages, avatars, taille des apercus

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
local TextService       = game:GetService("TextService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

--==================================================================================
--   R E G L A G E S   R A P I D E S      <-- c'est ici que tu changes tout
--==================================================================================
local MA_LANGUE    = "fr"            -- la langue que tu lis et dans laquelle tu ecris
local LANGUE_REPLI = "en"            -- si la langue de l'autre n'est pas detectee
local POLICE_CHAT  = "FredokaOne"    -- style des messages (liste dans Reglages)
local TOUCHE_MENU  = "RightControl"  -- touche qui ouvre et ferme le hub
--==================================================================================

local function keyFromName(name)
    local ok, key = pcall(function() return Enum.KeyCode[name] end)
    if ok and key then return key end
    return Enum.KeyCode.RightControl
end

----------------------------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------------------------
local CONFIG = {
    Keybind      = keyFromName(TOUCHE_MENU),

    -- traduction
    TranslateTo       = MA_LANGUE,
    SendAs            = LANGUE_REPLI,
    TranslateIncoming = true,
    PatchChatGui      = true,
    AutoSend          = true,   -- Entree envoie directement dans le chat du jeu
                                -- au lieu de laisser le texte dans la zone
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
    ChatFont     = POLICE_CHAT,   -- police des messages (onglet Reglages)
    ModelSize    = 140,         -- taille de l'apercu 3D des brainrots (px)

    -- Brainrots epingles en tete de la base, du meilleur au moins bon.
    -- Le tri normal (rarete, puis revenu) ne suffit pas : deux pieces
    -- "Secret" ne valent pas la meme chose, et c'est le nom qui tranche.
    -- Tout ce qui est dans cette liste passe devant le reste ; le dernier
    -- de la liste est le seuil (ici Dragon Cannelloni).
    --
    -- Le jeu sort de nouveaux brainrots en permanence : cette liste est un
    -- point de depart, complete-la et reordonne-la comme tu veux. La casse,
    -- les accents et les espaces en trop n'ont pas d'importance.
    TopBrainrots = {
        "garama and madundung",
        "la grande combinasion",
        "nuclearo dinossauro",
        "graipuss medussi",
        "los tralaleritos",
        "chimpanzini spiderini",
        "la vacca saturno saturnita",
        "dragon cannelloni",
    },

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

-- polices proposees pour les messages
local CHAT_FONTS = {
    "FredokaOne", "GothamBold", "Nunito", "Ubuntu", "Oswald",
    "Michroma", "Bangers", "PermanentMarker", "Arimo",
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

----------------------------------------------------------------------------------
-- ANIMATION
--   Une seule connexion Heartbeat pour TOUT ce qui bouge en continu. Chaque
--   effet est une fonction : elle renvoie false quand son element a disparu,
--   et elle est retiree de la liste. Rien ne tourne dans le vide.
----------------------------------------------------------------------------------
local Pulse = { items = {}, conn = nil, t = 0 }

function Pulse.add(fn)
    table.insert(Pulse.items, fn)
    if not Pulse.conn then
        Pulse.conn = Maid.conn(RunService.Heartbeat:Connect(function(dt)
            if State.Unloaded then return end
            Pulse.t = Pulse.t + dt
            for i = #Pulse.items, 1, -1 do
                local ok, keep = pcall(Pulse.items[i], Pulse.t, dt)
                if not ok or keep == false then table.remove(Pulse.items, i) end
            end
        end))
    end
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

-- rang des brainrots epingles (CONFIG.TopBrainrots). Le premier de la liste
-- a le plus grand nombre, tout ce qui n'y figure pas vaut 0 et passe apres.
local TOP_RANK = {}
do
    local list = CONFIG.TopBrainrots or {}
    for i, name in ipairs(list) do
        TOP_RANK[Util.lower(Util.trim(name))] = #list - i + 1
    end
end

local function topRank(name)
    if not name then return 0 end
    return TOP_RANK[Util.lower(Util.trim(name))] or 0
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

    -- d'abord les brainrots epingles dans l'ordre de CONFIG.TopBrainrots,
    -- puis les plus rares, puis le meilleur revenu, puis la quantite
    table.sort(order, function(a, b)
        local ta, tb = topRank(a.name), topRank(b.name)
        if ta ~= tb then return ta > tb end
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

-- Un service peut repondre 200 avec un message d'erreur en guise de
-- traduction. On ne laisse pas passer ca dans le chat.
local function looksBogus(out)
    local l = Util.lower(out)
    return string.find(l, "please select two distinct", 1, true) ~= nil
        or string.find(l, "invalid language pair", 1, true) ~= nil
        or string.find(l, "query length limit", 1, true) ~= nil
        or string.find(l, "mymemory warning", 1, true) ~= nil
end

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
            -- Troisieme endpoint Google, chemin different des deux premiers :
            -- il repond souvent quand les autres sont limites.
            -- MyMemory a ete retire : c'est une MEMOIRE de traduction, elle
            -- renvoie des phrases deja soumises par des humains. "How are you
            -- today" en ressortait en "je m'appelle Shane", et un langpair
            -- en|en donnait "PLEASE SELECT TWO DISTINCT LANGUAGES".
            name = "google-dict",
            url = "https://clients5.google.com/translate_a/t?client=dict-chrome-ex&sl="
                .. sl .. "&tl=" .. tl .. "&q=" .. q,
            parse = function(body)
                local data = decode(body)
                if type(data) == "table" then
                    if type(data[1]) == "string" then return data[1], "?" end
                    if type(data[1]) == "table" then
                        local first = data[1]
                        if type(first[1]) == "string" then
                            return first[1],
                                (type(first[2]) == "string" and first[2]) or "?"
                        end
                    end
                end
                local m = string.match(body, '^%[%s*"(.-)"')
                if m then return m, "?" end
                return nil
            end,
        },
    }
end

function Translator.raw(text, target, source)
    -- source connue et identique a la cible : aucun appel reseau, et surtout
    -- pas de langpair du type "en|en" que certains services refusent
    if source and source ~= "" and source ~= "auto" and source == target then
        return text, source
    end
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
            if okParse and out and out ~= "" and not looksBogus(out) then
                Translator.cache[key] = { out = out, src = detected or "?" }
                return out, detected or "?"
            end
            if okParse and out and looksBogus(out) then
                log("traduction %s rejetee (message de service) : %s",
                    provider.name, string.sub(out, 1, 60))
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
-- TRADUCTION DE L'INTERFACE
--
-- Les libelles du script sont ecrits en francais. Quand tu changes "Ma
-- langue", ils passent par le meme traducteur que le chat.
--
-- Un par un, et pas en une seule requete : les trois fournisseurs Google
-- recollent les segments bout a bout SANS separateur (voir les parse()
-- ci-dessus), donc un envoi groupe reviendrait avec un pave impossible a
-- redecouper. On les enchaine donc en tache de fond, avec une petite pause
-- entre chaque pour ne pas se faire limiter. Le cache du traducteur rend
-- tous les changements suivants instantanes.
----------------------------------------------------------------------------------
local I18N = { items = {}, gen = 0, source = "fr" }

-- enregistre un texte fixe de l'interface, en gardant l'original francais
function I18N.add(inst, prop)
    prop = prop or "Text"
    local ok, src = pcall(function() return inst[prop] end)
    if not ok or type(src) ~= "string" or Util.trim(src) == "" then return end
    I18N.items[#I18N.items + 1] = { inst = inst, prop = prop, src = src }
end

-- Passe une fois sur toute la fenetre. A appeler AVANT que le moindre
-- contenu dynamique existe : un pseudo de joueur ou un nom de brainrot ne
-- doit jamais partir au traducteur. `skip` contient les conteneurs a ignorer.
function I18N.scan(root, skip)
    skip = skip or {}
    local ok, list = pcall(function() return root:GetDescendants() end)
    if not ok then return end
    for _, d in ipairs(list) do
        local ignored, p = false, d
        while p and p ~= root do
            if skip[p] then ignored = true break end
            p = p.Parent
        end
        if not ignored and not d:GetAttribute("TPH_Dynamic") then
            if d:IsA("TextButton") or d:IsA("TextLabel") then
                I18N.add(d, "Text")
            elseif d:IsA("TextBox") then
                I18N.add(d, "PlaceholderText")
            end
        end
    end
end

function I18N.apply(target)
    I18N.gen = I18N.gen + 1
    local gen = I18N.gen

    -- retour au francais : on repose les originaux, aucun appel reseau
    if not target or target == I18N.source then
        for _, it in ipairs(I18N.items) do
            pcall(function() it.inst[it.prop] = it.src end)
        end
        return
    end

    spawnTask(function()
        local done = {}
        for _, it in ipairs(I18N.items) do
            -- une autre langue a ete choisie entre-temps : on abandonne
            if State.Unloaded or I18N.gen ~= gen then return end
            if it.inst.Parent then
                local out = done[it.src]
                if out == nil then
                    out = Translator.raw(it.src, target, I18N.source) or false
                    done[it.src] = out
                    waitFor(0.05)
                end
                if out then pcall(function() it.inst[it.prop] = out end) end
            end
        end
    end)
end

----------------------------------------------------------------------------------
-- CHAT DE TRADE
----------------------------------------------------------------------------------
local Chat = { remote = nil, rootInst = nil, seen = {}, written = {},
               boxes = {}, listened = {} }

-- entry = { who, userId, original, translated, mine }
-- Un meme message peut arriver deux fois : une par le remote de chat, une par
-- le label du jeu. On ignore le doublon s'il tombe dans les 4 secondes.
local recentChat = {}

local function pushChat(entry)
    -- On enregistre l'original ET la traduction. Ton propre message revient
    -- par le chat du jeu dans l'autre langue : sans les deux cles, il
    -- s'affichait une deuxieme fois.
    local a = tostring(entry.original or "")
    local b = tostring(entry.translated or "")
    local now = Util.clock()
    if (a ~= "" and recentChat[a] and (now - recentChat[a]) < 6)
    or (b ~= "" and recentChat[b] and (now - recentChat[b]) < 6) then return end
    if a ~= "" then recentChat[a] = now end
    if b ~= "" then recentChat[b] = now end
    entry.at = os.date("%H:%M")
    table.insert(State.ChatLog, entry)
    if #State.ChatLog > 120 then table.remove(State.ChatLog, 1) end
    if UI and UI.pushChat then pcall(UI.pushChat, entry) end
end

local function meEntry(original, translated)
    return {
        who = (LocalPlayer.DisplayName ~= "" and LocalPlayer.DisplayName) or LocalPlayer.Name,
        userId = LocalPlayer.UserId, original = original, translated = translated,
        mine = true,
    }
end

-- recherche stricte : pas de correspondance partielle, sinon "a" trouverait
-- n'importe quel joueur dont le nom contient un "a"
local function exactPlayer(name)
    local n = Util.lower(Util.trim(name or ""))
    if n == "" then return nil end
    for _, plr in ipairs(Players:GetPlayers()) do
        if Util.lower(plr.Name) == n or Util.lower(plr.DisplayName) == n then return plr end
    end
    return nil
end

-- Qui a ecrit ce message ? On remonte de trois crans dans la ligne du chat et
-- on cherche soit une image d'avatar (l'UserId est dans l'URL), soit un label
-- qui porte le pseudo d'un joueur present.
-- un joueur reconnu depuis un element d'interface : soit son UserId dans
-- l'URL d'une miniature, soit son pseudo ecrit en clair
local function playerFromGui(d, skip)
    if d == skip then return nil end
    if d:IsA("ImageLabel") or d:IsA("ImageButton") then
        -- l'UserId apparait sous plusieurs formes selon le jeu :
        -- rbxthumb://type=AvatarHeadShot&id=123, ?userId=123, ...
        local img = tostring(d.Image or "")
        for id in string.gmatch(img, "(%d%d%d%d%d%d+)") do
            for _, plr in ipairs(Players:GetPlayers()) do
                if tostring(plr.UserId) == id then return plr end
            end
        end
    elseif d:IsA("TextLabel") or d:IsA("TextButton") then
        return exactPlayer(d.Text)
    end
    return nil
end

-- On reste dans LA ligne du message : son parent et un niveau en dessous.
-- Remonter plus haut ramenait le conteneur de tout le chat, donc l'avatar
-- d'une AUTRE ligne : chaque message se retrouvait attribue au mauvais
-- joueur, et ceux attribues a soi-meme etaient purement ignores.
local function senderOf(obj)
    local row = obj.Parent
    if not row then return nil end
    local ok, kids = pcall(function() return row:GetChildren() end)
    if not ok then return nil end
    for _, d in ipairs(kids) do
        local plr = playerFromGui(d, obj)
        if plr then return plr end
        local ok2, subs = pcall(function() return d:GetChildren() end)
        if ok2 then
            for _, sub in ipairs(subs) do
                local p2 = playerFromGui(sub, obj)
                if p2 then return p2 end
            end
        end
    end
    return nil
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
            pushChat(meEntry(text, nil))
            return false, "traduction impossible (" .. tostring(info) .. ")"
        end
    end

    local box, written, sent = Chat.inputBox(), false, false
    if box then
        -- focus d'abord : si la TextBox a ClearTextOnFocus, elle se vide
        -- avant qu'on ecrive et pas apres
        pcall(function() box:CaptureFocus() end)
        written = pcall(function() box.Text = final end)
        pcall(function() box.CursorPosition = #final + 1 end)

        if written and CONFIG.AutoSend then
            -- ReleaseFocus(true) declenche FocusLost avec enterPressed = true.
            -- C'est le CODE DU JEU qui envoie alors le message, avec ses
            -- propres arguments : le hub n'appelle toujours aucun remote.
            pcall(function() box:ReleaseFocus(true) end)
            local waited = 0
            while waited < 0.15 do waited = waited + RunService.Heartbeat:Wait() end
            -- si le jeu a vide la zone, c'est qu'il a pris le message
            sent = (Util.trim(box.Text or "") ~= final)
        end
    end

    pushChat(meEntry(text, (final ~= text) and final or nil))
    return true, final, written, Util.copy(final), sent
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
                    pushChat({
                        who = sender and ((sender.DisplayName ~= "" and sender.DisplayName)
                              or sender.Name) or "joueur",
                        userId = sender and sender.UserId or nil,
                        original = message, translated = out,
                    })
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

-- Dans un trade il n'y a que deux joueurs. Quand la ligne du chat ne porte ni
-- pseudo lisible ni avatar exploitable (beaucoup de jeux affichent une
-- miniature dont l'URL ne contient plus l'UserId), on balaye toute la fenetre
-- de trade a la recherche d'un joueur present : c'est forcement l'autre.
function Chat.otherTrader()
    local now = Util.clock()
    if Chat.trader and Chat.trader.Parent and Chat.traderAt
    and (now - Chat.traderAt) < 5 then
        return Chat.trader
    end
    Chat.traderAt, Chat.trader = now, nil

    local root = Chat.root()
    if not root then return nil end
    local top = root
    while top and top.Parent and not top:IsA("ScreenGui") do top = top.Parent end
    top = top or root

    local ok, list = pcall(function() return top:GetDescendants() end)
    if not ok then return nil end

    for _, d in ipairs(list) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            local plr = exactPlayer(d.Text)
            if plr and plr ~= LocalPlayer then Chat.trader = plr break end
        elseif d:IsA("ImageLabel") or d:IsA("ImageButton") then
            local img = tostring(d.Image or "")
            for id in string.gmatch(img, "(%d%d%d%d%d%d+)") do
                for _, plr in ipairs(Players:GetPlayers()) do
                    if tostring(plr.UserId) == id and plr ~= LocalPlayer then
                        Chat.trader = plr
                    end
                end
            end
            if Chat.trader then break end
        end
    end
    return Chat.trader
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

-- Traduit un message du chat du jeu et se rebranche sur ses changements de
-- texte : les jeux reutilisent les memes lignes quand le chat defile.
--   silent = on traduit dans le jeu mais on n'ajoute RIEN a la conversation
--   du hub. Sert au balayage de depart : la conversation demarre vide et ne
--   se remplit qu'avec ce qui est dit apres.
local function handleText(obj, silent)
    if State.Unloaded then return end
    if not (CONFIG.PatchChatGui and CONFIG.TranslateIncoming) then return end
    local original = plainText(obj)
    if not looksLikeMessage(original) then return end
    if Chat.written[obj] == original then return end   -- notre propre ecriture
    if Chat.seen[obj] == original then return end      -- deja traite
    Chat.seen[obj] = original

    -- "Pseudo: message" : on isole l'auteur et on ne traduit que son texte
    local prefix, body, sender = "", original, nil
    local who, rest = string.match(original, "^([%w_%. ]-)%s*:%s*(.+)$")
    if who and rest then
        local plr = exactPlayer(who)
        if plr then
            sender, body = plr, Util.trim(rest)
            prefix = string.sub(original, 1, #original - #rest)
        end
    end
    if not sender then sender = senderOf(obj) end
    if not sender then sender = Chat.otherTrader() end

    spawnTask(function()
        local out, detected = Translator.translate(body, CONFIG.TranslateTo)
        if State.Unloaded then return end

        -- Le message apparait dans le hub MEME quand la traduction echoue.
        -- Un message que le traducteur refuse ne doit pas disparaitre.
        if out and UI and UI.setDetected then pcall(UI.setDetected, detected) end

        -- On ne filtre plus sur l'auteur : quand il etait mal identifie, le
        -- message disparaissait sans laisser de trace. Les doublons sont
        -- ecartes par pushChat, qui connait les deux versions du texte.
        if not silent then
            pushChat({
                who = sender and ((sender.DisplayName ~= "" and sender.DisplayName)
                      or sender.Name) or "joueur",
                userId = sender and sender.UserId or nil,
                original = body, translated = out,
            })
        end
        if not out then
            log("traduction indisponible pour \"%s\" : %s", body, tostring(detected))
        end

        if not out or out == body then return end
        if not obj.Parent then return end
        local final = prefix .. out
        Chat.written[obj] = final
        pcall(function() obj.Text = final end)
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
            pushChat(meEntry(txt, (out and out ~= txt) and out or nil))
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

local function handleAny(inst, silent)
    if not onChatPath(inst) then return end
    if inst:IsA("TextButton") and not CONFIG.TranslateButtons then return end
    if isTextDisplay(inst) then
        if Chat.seen[inst] == nil then
            Maid.conn(inst:GetPropertyChangedSignal("Text"):Connect(function()
                handleText(inst)          -- un changement de texte est un vrai message
            end))
        end
        handleText(inst, silent)
    elseif inst:IsA("TextBox") then
        watchBox(inst)
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
    -- balayage de depart en silencieux : la conversation du hub reste vide
    for _, d in ipairs(pg:GetDescendants()) do
        if isTextThing(d) then pcall(handleAny, d, true) end
    end

    local root, exact = Chat.root()
    if exact and root then
        log("cadre de chat trouve : %s", root:GetFullName())
    else
        log("cadre de chat '%s' introuvable - detection par mot-cle",
            tostring(CONFIG.ChatGuiPath))
    end
end

-- relance un balayage complet du chat (accessible via getgenv().TradePlazaHub)
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
            pcall(handleAny, d, true)
        end
    end
    Chat.hookIncoming()
    return n, (root and root:GetFullName() or "?"), exact
end

----------------------------------------------------------------------------------
-- INTERFACE : theme + composants
----------------------------------------------------------------------------------
-- Ambre sur bleu encre : un hub de trade est un terminal de marche, pas une
-- interface de gamer violette. Le menthe ne sert QU'A l'etat "en ligne",
-- le rose QU'A ce qui supprime. L'accent ne se depense qu'une fois par ecran.
local THEME = {
    bg      = Color3.fromRGB(11, 15, 26),    -- encre, fond de fenetre
    surface = Color3.fromRGB(14, 20, 34),    -- creux : champs, panneaux
    card    = Color3.fromRGB(20, 26, 42),    -- corps des cartes
    cardHi  = Color3.fromRGB(28, 36, 56),    -- element souleve
    line    = Color3.fromRGB(42, 51, 80),    -- filet
    text    = Color3.fromRGB(232, 237, 247),
    sub     = Color3.fromRGB(122, 135, 166),
    dim     = Color3.fromRGB(93, 106, 135),  -- texte d'origine sous la traduction
    accent  = Color3.fromRGB(77, 166, 255),  -- bleu : l'accent principal
    accent2 = Color3.fromRGB(32, 96, 176),   -- bleu profond : degrades et relief
    good    = Color3.fromRGB(79, 224, 168),  -- menthe : en ligne / reussite
    warn    = Color3.fromRGB(255, 190, 92),
    bad     = Color3.fromRGB(255, 107, 122), -- rose : supprimer / erreur
    msg     = Color3.fromRGB(232, 237, 247), -- texte des messages du chat
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

-- Marque un texte dont le contenu change en cours de route (valeur d'un
-- selecteur, resume d'une base, position d'un curseur). Le traducteur
-- d'interface ne doit pas y toucher : il repousserait l'ancienne valeur
-- traduite par-dessus la nouvelle.
local function dynamic(inst)
    pcall(function() inst:SetAttribute("TPH_Dynamic", true) end)
    return inst
end

local function stroke(inst, color, thickness, transparency)
    return mk("UIStroke", {
        Color = color or THEME.line, Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = inst,
    })
end

-- Le relief ne vient pas d'empiler des contours : Roblox n'applique qu'un
-- seul UIStroke par objet. Il vient d'un liseré clair pose en haut a
-- l'interieur, qui simule la lumiere rasante.
local function topLight(inst, transparency)
    return mk("Frame", {
        Size = UDim2.new(1, -16, 0, 1), Position = UDim2.new(0, 8, 0, 1),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = transparency or 0.9,
        BorderSizePixel = 0, ZIndex = 0, Parent = inst,
    })
end

-- contour degrade violet -> turquoise qui tourne lentement
local function glowStroke(inst, thickness, transparency, speed)
    local st = mk("UIStroke", {
        Color = Color3.fromRGB(255, 255, 255), Thickness = thickness or 1.6,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = inst,
    })
    local grad = mk("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, THEME.accent),
            ColorSequenceKeypoint.new(0.5, THEME.accent2),
            ColorSequenceKeypoint.new(1, THEME.accent),
        }),
        Parent = st,
    })
    Pulse.add(function(t)
        if not grad.Parent then return false end
        grad.Rotation = (t * (speed or 28)) % 360
        return true
    end)
    return st, grad
end

-- barre fine que la lumiere traverse en boucle
local function sweepBar(parent, height)
    local bar = mk("Frame", {
        Size = UDim2.new(1, 0, 0, height or 2), Position = UDim2.new(0, 0, 1, -(height or 2)),
        BackgroundColor3 = THEME.accent2, BorderSizePixel = 0, Parent = parent,
    })
    local grad = mk("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, THEME.accent),
            ColorSequenceKeypoint.new(0.5, THEME.accent2),
            ColorSequenceKeypoint.new(1, THEME.accent),
        }),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.38, 0.35),
            NumberSequenceKeypoint.new(0.5, 0),
            NumberSequenceKeypoint.new(0.62, 0.35),
            NumberSequenceKeypoint.new(1, 1),
        }),
        Parent = bar,
    })
    Pulse.add(function(t)
        if not grad.Parent then return false end
        grad.Offset = Vector2.new(((t * 0.32) % 2) - 1, 0)
        return true
    end)
    return bar
end

----------------------------------------------------------------------------------
-- ICONES DESSINEES
--
-- Zero caractere special : chaque icone est un assemblage de Frames avec un
-- UICorner et parfois une Rotation. Les coordonnees sont donnees dans un
-- carre de reference de 22x22, puis mises a l'echelle de la taille demandee.
-- Chaque constructeur renvoie { holder = Frame, parts = { Frame... } } pour
-- pouvoir recolorer l'icone entiere d'un coup.
----------------------------------------------------------------------------------
local ICON_BASE = 22

local function iconMaker(build)
    return function(parent, size, color)
        size = size or ICON_BASE
        local s = size / ICON_BASE
        local holder = mk("Frame", {
            Size = UDim2.new(0, size, 0, size),
            BackgroundTransparency = 1, Parent = parent,
        })
        local parts = {}

        -- x, y, w, h en unites de la grille 22x22 ; r = rayon ; rot = degres
        local function piece(x, y, w, h, r, rot)
            local f = mk("Frame", {
                Size = UDim2.new(0, w * s, 0, h * s),
                Position = UDim2.new(0, x * s, 0, y * s),
                BackgroundColor3 = color or THEME.sub,
                BorderSizePixel = 0, Rotation = rot or 0, Parent = holder,
            })
            if r and r > 0 then corner(f, math.max(1, r * s)) end
            parts[#parts + 1] = f
            return f
        end

        -- anneau : un Frame vide dont seul le contour est visible
        local function ring(x, y, d, thick)
            local f = mk("Frame", {
                Size = UDim2.new(0, d * s, 0, d * s),
                Position = UDim2.new(0, x * s, 0, y * s),
                BackgroundTransparency = 1, BorderSizePixel = 0, Parent = holder,
            })
            corner(f, (d * s) / 2)
            local st = stroke(f, color or THEME.sub, math.max(1, thick * s), 0)
            parts[#parts + 1] = st
            return f
        end

        build(piece, ring)
        return { holder = holder, parts = parts }
    end
end

local Icon = {}

-- deux tetes et deux epaules
Icon.users = iconMaker(function(p)
    p(2, 4, 7, 7, 3.5)
    p(11, 3, 8, 8, 4)
    p(1, 13, 9, 6, 3)
    p(11, 12, 10, 7, 3.5)
end)

-- une bulle et sa queue
Icon.chat = iconMaker(function(p)
    p(1, 3, 19, 14, 6)
    p(4, 14, 6, 6, 1, 20)
end)

-- trois curseurs a molette
Icon.tune = iconMaker(function(p)
    p(2, 5, 18, 2, 1)   p(12, 3, 6, 6, 3)
    p(2, 10, 18, 2, 1)  p(4, 8, 6, 6, 3)
    p(2, 15, 18, 2, 1)  p(9, 13, 6, 6, 3)
end)

-- chevron : deux barres qui se rejoignent a droite
Icon.send = iconMaker(function(p)
    p(4.6, 5.9, 11, 2.5, 1.2, 45)
    p(4.6, 13.7, 11, 2.5, 1.2, -45)
end)

-- anneau ouvert par une pointe : recharger
Icon.sync = iconMaker(function(p, ring)
    ring(3, 3, 16, 2)
    p(13, 2, 6, 2, 1, 45)
end)

-- croix
Icon.cross = iconMaker(function(p)
    p(4.5, 10, 13, 2, 1, 45)
    p(4.5, 10, 13, 2, 1, -45)
end)

-- trait unique : reduire la fenetre
Icon.minus = iconMaker(function(p)
    p(6, 10, 10, 2, 1)
end)

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

-- recolore toutes les pieces d'une icone d'un coup
-- (Frame -> son fond, UIStroke -> son contour)
local function paintIcon(icon, color, time)
    if not icon then return end
    for _, p in ipairs(icon.parts) do
        if p:IsA("UIStroke") then tween(p, { Color = color }, time or 0.16)
        else tween(p, { BackgroundColor3 = color }, time or 0.16) end
    end
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

            -- Vue DE FACE : on prend l'orientation du modele lui-meme
            -- (HumanoidRootPart, sinon PrimaryPart) et on place la camera
            -- devant lui, au lieu d'un angle 3/4 pris au hasard du monde.
            local center, extents = clone:GetBoundingBox()
            local anchor = clone:FindFirstChild("HumanoidRootPart")
                or clone.PrimaryPart
                or clone:FindFirstChildWhichIsA("BasePart")
            local dir = anchor and anchor.CFrame.LookVector or center.LookVector
            if dir.Magnitude < 0.1 then dir = Vector3.new(0, 0, -1) end

            local span = math.max(extents.X, extents.Y, extents.Z, 2)
            local dist = span * 1.45 + 1.5
            local eye  = center.Position + dir * dist + Vector3.new(0, extents.Y * 0.06, 0)
            camera.FieldOfView = 40
            camera.CFrame = CFrame.new(eye, center.Position)
            fallback.Visible = false

            -- survole la vignette : le modele tourne sur lui-meme, puis
            -- revient doucement de face quand la souris repart
            local baseOff = eye - center.Position
            local spinning, angle = false, 0
            Maid.conn(holder.MouseEnter:Connect(function() spinning = true end))
            Maid.conn(holder.MouseLeave:Connect(function() spinning = false end))
            Pulse.add(function(_, dt)
                if not viewport.Parent then return false end
                if spinning then
                    angle = angle + dt * 1.7
                elseif angle ~= 0 then
                    angle = angle * math.max(0, 1 - dt * 6)
                    if math.abs(angle) < 0.003 then angle = 0 end
                else
                    return true          -- immobile : rien a recalculer
                end
                local rotated = CFrame.Angles(0, angle, 0):VectorToWorldSpace(baseOff)
                camera.CFrame = CFrame.new(center.Position + rotated, center.Position)
                return true
            end)
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

-- Format portrait : les onglets descendent en bas comme dans une app mobile,
-- ce qui rend toute la largeur au contenu.
--   52 (titre) + 518 (corps) + 64 (onglets) + 26 (statut) = 660
local WIN_W, WIN_H = 380, 660
local BAR_H, TABS_H, STAT_H = 52, 64, 26

local window = corner(mk("Frame", {
    Size = UDim2.new(0, WIN_W, 0, WIN_H),
    Position = UDim2.new(0.5, -WIN_W / 2, 0.5, -WIN_H / 2),
    BackgroundColor3 = THEME.card, BorderSizePixel = 0,
    ClipsDescendants = true, Parent = screen,
}), 16)
glowStroke(window, 3.5, 0.1, 20)

local titleBar = mk("Frame", {
    Size = UDim2.new(1, 0, 0, BAR_H), BackgroundColor3 = THEME.cardHi,
    BorderSizePixel = 0, Parent = window,
})
mk("UIGradient", { Color = ColorSequence.new(THEME.cardHi, THEME.card),
    Rotation = 90, Parent = titleBar })
sweepBar(titleBar, 2)

-- pastille "en ligne" : un point menthe qui respire dans son halo
do
    local halo = corner(mk("Frame", {
        Size = UDim2.new(0, 18, 0, 18), Position = UDim2.new(0, 12, 0.5, -9),
        BackgroundColor3 = THEME.good, BackgroundTransparency = 0.86,
        BorderSizePixel = 0, Parent = titleBar,
    }), 9)
    local dot = corner(mk("Frame", {
        Size = UDim2.new(0, 8, 0, 8), Position = UDim2.new(0, 17, 0.5, -4),
        BackgroundColor3 = THEME.good, BorderSizePixel = 0, Parent = titleBar,
    }), 4)
    Pulse.add(function(t)
        if not halo.Parent then return false end
        local k = 0.5 + 0.5 * math.sin(t * 2.4)
        local size = 16 + 8 * k
        halo.Size = UDim2.new(0, size, 0, size)
        halo.Position = UDim2.new(0, 21 - size / 2, 0.5, -size / 2)
        halo.BackgroundTransparency = 0.8 + 0.16 * k
        return true
    end)
end

-- Michroma existe dans Roblox : c'est ce qui donne au titre son air de
-- terminal, sans avoir a le composer en majuscules espacees a la main.
local wordmark = mk("TextLabel", {
    Size = UDim2.new(0, 130, 1, 0), Position = UDim2.new(0, 34, 0, 0),
    BackgroundTransparency = 1, Font = Enum.Font.Michroma,
    Text = "TRADE PLAZA", TextSize = 11, TextColor3 = THEME.text,
    TextXAlignment = Enum.TextXAlignment.Left, Parent = titleBar,
})

local modePill = corner(mk("Frame", {
    Size = UDim2.new(0, 84, 0, 20), Position = UDim2.new(0, 170, 0.5, -10),
    BackgroundColor3 = THEME.card, BorderSizePixel = 0, Parent = titleBar,
}), 10)
stroke(modePill, THEME.good, 1, 0.55)
mk("TextLabel", {
    Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold, Text = "LECTURE SEULE", TextSize = 8,
    TextColor3 = THEME.good, Parent = modePill,
})

-- bouton carre de la barre de titre, avec son icone dessinee
local function chipButton(offsetX, color, iconFn, callback)
    local b = corner(mk("TextButton", {
        Size = UDim2.new(0, 24, 0, 24), Position = UDim2.new(1, offsetX, 0.5, -12),
        BackgroundColor3 = THEME.cardHi, AutoButtonColor = false, Text = "",
        BorderSizePixel = 0, Parent = titleBar,
    }), 8)
    stroke(b, THEME.line, 1, 0.4)
    local ic = iconFn(b, 14, color)
    ic.holder.Position = UDim2.new(0.5, -7, 0.5, -7)
    Maid.conn(b.MouseEnter:Connect(function()
        tween(b, { BackgroundColor3 = color }, 0.15)
        paintIcon(ic, THEME.bg, 0.15)
    end))
    Maid.conn(b.MouseLeave:Connect(function()
        tween(b, { BackgroundColor3 = THEME.cardHi }, 0.15)
        paintIcon(ic, color, 0.15)
    end))
    Maid.conn(b.MouseButton1Click:Connect(callback))
    return b
end

local bodyFrame = mk("Frame", {
    Size = UDim2.new(1, 0, 1, -(BAR_H + TABS_H + STAT_H)),
    Position = UDim2.new(0, 0, 0, BAR_H),
    BackgroundTransparency = 1, Parent = window,
})

-- en portrait le contenu occupe toute la largeur : plus de colonne laterale
local contentArea = mk("Frame", {
    Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Parent = bodyFrame,
})

local tabBar = mk("Frame", {
    Size = UDim2.new(1, 0, 0, TABS_H), Position = UDim2.new(0, 0, 1, -(TABS_H + STAT_H)),
    BackgroundColor3 = THEME.surface, BorderSizePixel = 0, Parent = window,
})
stroke(tabBar, THEME.line, 1.6, 0.4)
listLayout(tabBar, 0, true)

local statusBar = mk("Frame", {
    Size = UDim2.new(1, 0, 0, STAT_H), Position = UDim2.new(0, 0, 1, -STAT_H),
    BackgroundColor3 = THEME.bg, BorderSizePixel = 0, Parent = window,
})
local statusDot = corner(mk("Frame", {
    Size = UDim2.new(0, 5, 0, 5), Position = UDim2.new(0, 14, 0.5, -2.5),
    BackgroundColor3 = THEME.sub, BorderSizePixel = 0, Parent = statusBar,
}), 3)
Pulse.add(function(t)
    if not statusDot.Parent then return false end
    statusDot.BackgroundTransparency = 0.15 * (0.5 + 0.5 * math.sin(t * 3.1))
    return true
end)
local statusText = dynamic(mk("TextLabel", {
    Size = UDim2.new(1, -34, 1, 0), Position = UDim2.new(0, 26, 0, 0),
    BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = "initialisation...",
    TextSize = 10, TextColor3 = THEME.sub, TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd, Parent = statusBar,
}))

-- Le message de statut est ecrit en francais puis traduit en tache de fond.
-- Le jeton evite qu'une traduction lente vienne ecraser un statut plus
-- recent arrive entre-temps.
local statusToken = 0
local function setStatus(text, color)
    text = tostring(text)
    statusToken = statusToken + 1
    local mine = statusToken
    statusText.Text = text
    tween(statusText, { TextColor3 = color or THEME.sub }, 0.2)
    tween(statusDot, { BackgroundColor3 = color or THEME.sub }, 0.2)

    if CONFIG.TranslateTo and CONFIG.TranslateTo ~= "fr" then
        spawnTask(function()
            local out = Translator.raw(text, CONFIG.TranslateTo, "fr")
            if out and statusToken == mine and not State.Unloaded then
                statusText.Text = out
            end
        end)
    end
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
local TAB_COUNT = 3

local function addTab(name, iconFn)
    local page = mk("ScrollingFrame", {
        Name = name, Size = UDim2.new(1, -20, 1, -16), Position = UDim2.new(0, 10, 0, 8),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
        ScrollBarImageColor3 = THEME.accent, CanvasSize = UDim2.new(),
        Visible = false, Parent = contentArea,
    })
    local layout = listLayout(page, 10)
    Maid.conn(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        page.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 14)
    end))

    -- un onglet = un tiers de la barre, icone au-dessus du mot
    local tab = mk("TextButton", {
        Size = UDim2.new(1 / TAB_COUNT, 0, 1, 0), BackgroundColor3 = THEME.cardHi,
        BackgroundTransparency = 1, AutoButtonColor = false, Text = "",
        BorderSizePixel = 0, Parent = tabBar,
    })

    -- trait d'activation, colle en haut de l'onglet
    local mark = corner(mk("Frame", {
        Size = UDim2.new(0, 0, 0, 2), Position = UDim2.new(0.5, 0, 0, 0),
        AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = THEME.accent,
        BorderSizePixel = 0, Parent = tab,
    }), 1)

    local tabIcon = iconFn(tab, 22, THEME.sub)
    tabIcon.holder.Position = UDim2.new(0.5, -11, 0, 13)

    local tabLabel = mk("TextLabel", {
        Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 0, 40),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
        Text = string.upper(name), TextSize = 9, TextColor3 = THEME.sub,
        Parent = tab,
    })

    UI.pages[name] = page
    UI.tabs[name] = { button = tab, label = tabLabel, mark = mark, icon = tabIcon }

    Maid.conn(tab.MouseEnter:Connect(function()
        if not page.Visible then
            tween(tab, { BackgroundTransparency = 0.55 }, 0.15)
            paintIcon(tabIcon, THEME.text, 0.15)
            tween(tabLabel, { TextColor3 = THEME.text }, 0.15)
        end
    end))
    Maid.conn(tab.MouseLeave:Connect(function()
        if not page.Visible then
            tween(tab, { BackgroundTransparency = 1 }, 0.15)
            paintIcon(tabIcon, THEME.sub, 0.15)
            tween(tabLabel, { TextColor3 = THEME.sub }, 0.15)
        end
    end))
    Maid.conn(tab.MouseButton1Click:Connect(function() UI.select(name) end))
    return page
end

function UI.select(name)
    for tabName, page in pairs(UI.pages) do
        local active = (tabName == name)
        page.Visible = active
        local t = UI.tabs[tabName]
        tween(t.button, { BackgroundTransparency = active and 0.82 or 1 }, 0.16)
        tween(t.label, { TextColor3 = active and THEME.accent or THEME.sub }, 0.16)
        tween(t.mark, { Size = UDim2.new(0, active and 34 or 0, 0, 2) }, 0.2)
        paintIcon(t.icon, active and THEME.accent or THEME.sub, 0.16)
    end
end

local function card(page, title, subtitle)
    local holder = corner(mk("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = THEME.card, BorderSizePixel = 0, Parent = page,
    }), 12)
    stroke(holder, THEME.line, 1.8, 0.2)
    topLight(holder, 0.93)
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
    -- au survol on eclaircit, on n'assombrit pas : l'assombrissement est
    -- reserve a l'enfoncement, plus bas.
    local hover = (style == "primary" and Color3.fromRGB(138, 195, 255))
        or (style == "danger" and Color3.fromRGB(255, 140, 150)) or THEME.cardHi

    local b = corner(mk("TextButton", {
        Size = opts.width and UDim2.new(0, opts.width, 0, opts.height or 32)
                          or UDim2.new(1, 0, 0, opts.height or 32),
        BackgroundColor3 = base, AutoButtonColor = false, Text = "",
        BorderSizePixel = 0, ClipsDescendants = true, Parent = parent,
    }), 8)

    -- L'icone est dessinee, pas ecrite. Le libelle vit dans son propre
    -- TextLabel : un UIPadding sur le bouton decalerait aussi l'icone.
    local hasText = opts.text ~= nil and opts.text ~= ""
    local ic, labelX = nil, 0
    if opts.icon then
        local isize = opts.iconSize or 15
        ic = opts.icon(b, isize, textColor)
        if hasText then
            ic.holder.Position = UDim2.new(0, 12, 0.5, -isize / 2)
            labelX = 12 + isize + 8
        else
            -- bouton sans libelle : l'icone prend le centre
            ic.holder.Position = UDim2.new(0.5, -isize / 2, 0.5, -isize / 2)
        end
    end
    if hasText then
        mk("TextLabel", {
            Size = labelX > 0 and UDim2.new(1, -(labelX + 10), 1, 0)
                              or UDim2.new(1, 0, 1, 0),
            Position = UDim2.new(0, labelX, 0, 0),
            BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
            Text = opts.text, TextSize = opts.textSize or 12,
            TextColor3 = textColor,
            TextXAlignment = labelX > 0 and Enum.TextXAlignment.Left
                                         or Enum.TextXAlignment.Center,
            TextTruncate = Enum.TextTruncate.AtEnd, Parent = b,
        })
    end

    -- relief : un liseré clair en haut, une levre sombre en bas. Le bouton a
    -- une epaisseur au lieu d'etre un rectangle plat.
    local sheen = mk("Frame", {
        Size = UDim2.new(1, -10, 0, 1), Position = UDim2.new(0, 5, 0, 1),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.72,
        BorderSizePixel = 0, ZIndex = 0, Parent = b,
    })
    local lip = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 3), Position = UDim2.new(0, 0, 1, -3),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.62,
        BorderSizePixel = 0, ZIndex = 0, Parent = b,
    })
    local halo
    if style == "ghost" then
        halo = stroke(b, THEME.line, 1, 0.4)
    else
        halo = stroke(b, base, 1.4, 1)
    end

    Maid.conn(b.MouseEnter:Connect(function()
        tween(b, { BackgroundColor3 = hover }, 0.14)
        tween(halo, { Color = THEME.accent, Transparency = 0.25, Thickness = 1.8 }, 0.16)
        tween(sheen, { BackgroundTransparency = 0.5 }, 0.16)
    end))
    Maid.conn(b.MouseLeave:Connect(function()
        tween(b, { BackgroundColor3 = base }, 0.14)
        tween(halo, {
            Color = style == "ghost" and THEME.line or base,
            Transparency = style == "ghost" and 0.4 or 1, Thickness = 1.4,
        }, 0.22)
        tween(sheen, { BackgroundTransparency = 0.72 }, 0.22)
    end))
    -- enfonce : la levre s'ecrase, le fond s'assombrit
    Maid.conn(b.MouseButton1Down:Connect(function()
        tween(lip, { Size = UDim2.new(1, 0, 0, 1) }, 0.06)
        tween(b, { BackgroundColor3 = base:Lerp(Color3.new(0, 0, 0), 0.22) }, 0.06)
    end))
    Maid.conn(b.MouseButton1Up:Connect(function()
        tween(lip, { Size = UDim2.new(1, 0, 0, 3) }, 0.12)
        tween(b, { BackgroundColor3 = hover }, 0.12)
    end))
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
    local st = stroke(box, THEME.line, 1.6, 0.1)
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

local function slider(parent, text, key, minVal, maxVal, suffix, onChange)
    local holder = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1, Parent = parent,
    })
    mk("TextLabel", {
        Size = UDim2.new(1, -100, 0, 16), BackgroundTransparency = 1,
        Font = Enum.Font.Gotham, Text = text, TextSize = 11, TextColor3 = THEME.sub,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = holder,
    })
    local valueLabel = dynamic(mk("TextLabel", {
        Size = UDim2.new(0, 96, 0, 16), Position = UDim2.new(1, -96, 0, 0),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
        Text = tostring(CONFIG[key]) .. (suffix or ""), TextSize = 11,
        TextColor3 = THEME.accent, TextXAlignment = Enum.TextXAlignment.Right, Parent = holder,
    }))
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

-- Panneau en grille : les vignettes se rangent en colonnes et le panneau
-- defile vers le bas. En portrait c'est ce qui permet d'en voir plusieurs
-- d'un coup, la ou un defilement horizontal n'en montrait que deux.
-- Retourne le scroll, son cadre et la grille (pour regler la taille des
-- cellules selon la taille d'apercu choisie).
local function gridPanel(parent, height)
    local holder = corner(mk("Frame", {
        Size = UDim2.new(1, 0, 0, height or 300), BackgroundColor3 = THEME.surface,
        BorderSizePixel = 0, Parent = parent,
    }), 8)
    local scroll = mk("ScrollingFrame", {
        Size = UDim2.new(1, -10, 1, -10), Position = UDim2.new(0, 5, 0, 5),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
        ScrollBarImageColor3 = THEME.accent, CanvasSize = UDim2.new(), Parent = holder,
    })
    local grid = mk("UIGridLayout", {
        CellPadding = UDim2.new(0, 8, 0, 8),
        CellSize = UDim2.new(0, 156, 0, 204),
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll,
    })
    Maid.conn(grid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scroll.CanvasSize = UDim2.new(0, 0, 0, grid.AbsoluteContentSize.Y + 8)
    end))
    return scroll, holder, grid
end

local function textLine(scroll, text, color, font)
    return mk("TextLabel", {
        Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, Font = font or Enum.Font.Code, Text = text,
        TextSize = 11, TextColor3 = color or THEME.sub,
        TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Parent = scroll,
    })
end

-- On ne detruit que les elements visibles : les UIListLayout, UIGridLayout,
-- UIPadding et consorts doivent survivre au vidage du panneau.
local function clearChildren(scroll)
    for _, child in ipairs(scroll:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end
end

-- police des messages, choisie dans les Reglages
local function chatFont()
    local ok, f = pcall(function() return Enum.Font[CONFIG.ChatFont] end)
    if ok and f then return f end
    return Enum.Font.GothamBold
end

-- Liste deroulante avec une coche sur la valeur choisie. L'entete se replie,
-- la liste defile : de quoi tenir 24 langues sans manger la fenetre.
local function listPicker(parent, title, values, key, labelFn, onPick)
    labelFn = labelFn or tostring
    local holder = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, Parent = parent,
    })
    listLayout(holder, 6)

    local head = corner(mk("TextButton", {
        Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = THEME.surface,
        AutoButtonColor = false, Text = "", BorderSizePixel = 0, Parent = holder,
    }), 8)
    stroke(head, THEME.line, 1.6, 0.2)
    mk("TextLabel", {
        Size = UDim2.new(0.55, -12, 1, 0), Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = title,
        TextSize = 11, TextColor3 = THEME.sub,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = head,
    })
    local current = dynamic(mk("TextLabel", {
        Size = UDim2.new(0.45, -34, 1, 0), Position = UDim2.new(0.55, 0, 0, 0),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
        Text = labelFn(CONFIG[key]), TextSize = 12, TextColor3 = THEME.accent,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = head,
    }))
    local arrow = mk("TextLabel", {
        Size = UDim2.new(0, 22, 1, 0), Position = UDim2.new(1, -24, 0, 0),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = "+",
        TextSize = 13, TextColor3 = THEME.sub, Parent = head,
    })

    local listHolder = corner(mk("Frame", {
        Size = UDim2.new(1, 0, 0, 152), BackgroundColor3 = THEME.bg,
        BorderSizePixel = 0, Visible = false, Parent = holder,
    }), 8)
    stroke(listHolder, THEME.line, 1.6, 0.3)
    local scroll = mk("ScrollingFrame", {
        Size = UDim2.new(1, -8, 1, -8), Position = UDim2.new(0, 4, 0, 4),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
        ScrollBarImageColor3 = THEME.accent, CanvasSize = UDim2.new(), Parent = listHolder,
    })
    local layout = listLayout(scroll, 3)
    Maid.conn(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 6)
    end))

    local rows = {}
    local function refresh()
        current.Text = labelFn(CONFIG[key])
        for value, r in pairs(rows) do
            local on = (CONFIG[key] == value)
            r.check.Text = on and "X" or ""
            tween(r.box, { BackgroundColor3 = on and THEME.accent or THEME.surface }, 0.12)
            tween(r.label, { TextColor3 = on and THEME.text or THEME.sub }, 0.12)
        end
    end

    for _, value in ipairs(values) do
        local b = corner(mk("TextButton", {
            Size = UDim2.new(1, -4, 0, 26), BackgroundColor3 = THEME.card,
            AutoButtonColor = false, Text = "", BorderSizePixel = 0, Parent = scroll,
        }), 6)
        local box = corner(mk("Frame", {
            Size = UDim2.new(0, 16, 0, 16), Position = UDim2.new(0, 8, 0.5, -8),
            BackgroundColor3 = THEME.surface, BorderSizePixel = 0, Parent = b,
        }), 4)
        stroke(box, THEME.line, 1, 0.4)
        local check = mk("TextLabel", {
            Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold, Text = "", TextSize = 11,
            TextColor3 = THEME.bg, Parent = box,
        })
        local lbl = mk("TextLabel", {
            Size = UDim2.new(1, -36, 1, 0), Position = UDim2.new(0, 32, 0, 0),
            BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
            Text = labelFn(value), TextSize = 11, TextColor3 = THEME.sub,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd, Parent = b,
        })
        rows[value] = { box = box, check = check, label = lbl }
        Maid.conn(b.MouseButton1Click:Connect(function()
            CONFIG[key] = value
            refresh()
            if onPick then spawnTask(function() pcall(onPick, value) end) end
        end))
    end
    refresh()

    Maid.conn(head.MouseButton1Click:Connect(function()
        listHolder.Visible = not listHolder.Visible
        arrow.Text = listHolder.Visible and "-" or "+"
    end))
    return holder, refresh
end

local scanBase, refreshPlayers

----------------------------------------------------------------------------------
-- ONGLET : JOUEURS  (la liste, et la base du joueur choisi juste en dessous)
----------------------------------------------------------------------------------
local pagePlayers = addTab("Joueurs", Icon.users)

local cardList = card(pagePlayers)
local playersPanel = panel(cardList, 176)
btn(cardList, { text = "Rafraichir la liste", icon = Icon.sync, callback = function()
    refreshPlayers()
    setStatus("liste rafraichie", THEME.good)
end })

local cardBase = card(pagePlayers)
local baseSummary = dynamic(note(cardBase, "", THEME.text))
local brainrotPanel, _, brainrotGrid = gridPanel(cardBase, 330)

local function playerRow(scroll, plr)
    local row = corner(mk("Frame", {
        Size = UDim2.new(1, -6, 0, 52), BackgroundColor3 = THEME.cardHi,
        BorderSizePixel = 0, Parent = scroll,
    }), 11)
    stroke(row, THEME.line, 1.6, 0.35)

    local head = avatar(row, plr.UserId, 34)
    head.Position = UDim2.new(0, 9, 0.5, -17)

    mk("TextLabel", {
        Size = UDim2.new(1, -150, 0, 15), Position = UDim2.new(0, 51, 0, 11),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
        Text = plr.DisplayName ~= "" and plr.DisplayName or plr.Name, TextSize = 12,
        TextColor3 = THEME.text, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
    })
    mk("TextLabel", {
        Size = UDim2.new(1, -150, 0, 13), Position = UDim2.new(0, 51, 0, 27),
        BackgroundTransparency = 1, Font = Enum.Font.Code,
        Text = "@" .. plr.Name, TextSize = 10,
        TextColor3 = THEME.sub, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
    })

    local see = btn(row, { text = "BASE", icon = Icon.send, iconSize = 12,
        width = 86, height = 30, style = "primary",
        callback = function() scanBase(plr) end })
    see.Position = UDim2.new(1, -94, 0.5, -15)
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
local function brainrotTile(scroll, entry, index)
    local size = math.floor(Util.clamp(CONFIG.ModelSize, 48, 260))
    local col  = rarityColor(entry.rarity)

    local tile = corner(mk("Frame", {
        Size = UDim2.new(0, size + 16, 0, size + 64), BackgroundColor3 = THEME.card,
        BackgroundTransparency = 1, BorderSizePixel = 0, Parent = scroll,
    }), 10)
    local tileStroke = stroke(tile, col, 1.5, 1)

    local icon = modelIcon(tile, entry.model, size)
    icon.Position = UDim2.new(0, 8 + size / 2, 0, 8 + size / 2)
    icon.Size = UDim2.new(0, 0, 0, 0)

    -- eclosion en cascade : la vignette apparait puis le modele se deploie
    spawnTask(function()
        waitFor(0.03 * ((index or 1) - 1))
        if State.Unloaded or not tile.Parent then return end
        tween(tile, { BackgroundTransparency = 0.15 }, 0.22)
        tween(tileStroke, { Transparency = 0.3 }, 0.28)
        tween(icon, {
            Size = UDim2.new(0, size, 0, size),
            Position = UDim2.new(0, 8, 0, 8),
        }, 0.38, Enum.EasingStyle.Back)
    end)

    -- survol : la vignette se soulit et son contour s'allume
    Maid.conn(tile.MouseEnter:Connect(function()
        tween(tile, { BackgroundTransparency = 0 }, 0.14)
        tween(tileStroke, { Transparency = 0, Thickness = 2.4 }, 0.14)
    end))
    Maid.conn(tile.MouseLeave:Connect(function()
        tween(tile, { BackgroundTransparency = 0.15 }, 0.2)
        tween(tileStroke, { Transparency = 0.3, Thickness = 1.5 }, 0.2)
    end))

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
        TextSize = 13, TextColor3 = THEME.accent, Parent = tile,
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

    -- La cellule fait exactement la taille d'une vignette : le nombre de
    -- colonnes tombe tout seul de la largeur disponible, et la grille reste
    -- centree quand la derniere rangee est incomplete.
    local size = math.floor(Util.clamp(CONFIG.ModelSize, 48, 260))
    brainrotGrid.CellSize = UDim2.new(0, size + 16, 0, size + 64)

    local list, total, count = Inspector.brainrots(plot)
    baseSummary.Text = string.format(
        "Base de %s   -   %d brainrots   -   %d types   -   revenu total $%s/s",
        ownerName, count, #list, Util.short(total))

    if #list == 0 then
        textLine(brainrotPanel, "aucun brainrot reconnu sur cette base", THEME.bad, Enum.Font.Gotham)
        textLine(brainrotPanel, "sa base est peut-etre vide, ou le jeu range ses objets ailleurs",
            THEME.sub, Enum.Font.Gotham)
    else
        for i, entry in ipairs(list) do
            if i > 60 then break end
            brainrotTile(brainrotPanel, entry, i)
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
local pageChat = addTab("Chat", Icon.chat)

local refreshLangNote

-- Bandeau de langue : ce qu'on a detecte chez l'autre, et la langue dans
-- laquelle ta reponse va partir. Les deux selecteurs vivent dans Reglages :
-- ici on ne garde que l'etat, c'est ce qu'on lit en pleine conversation.
local langStrip = corner(mk("Frame", {
    Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = THEME.surface,
    BorderSizePixel = 0, Parent = pageChat,
}), 10)
stroke(langStrip, THEME.line, 1.6, 0.3)

-- Le libelle fixe et la valeur sont deux etiquettes distinctes : le libelle
-- se fait traduire avec le reste de l'interface, la valeur est un nom de
-- langue qu'on reecrit a chaque message et qui doit rester intact.
mk("TextLabel", {
    Size = UDim2.new(0, 130, 0, 11), Position = UDim2.new(0, 12, 0, 7),
    BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = "IL PARLE",
    TextSize = 8, TextColor3 = THEME.sub,
    TextXAlignment = Enum.TextXAlignment.Left, Parent = langStrip,
})
local detectFrom = dynamic(mk("TextLabel", {
    Size = UDim2.new(0, 130, 0, 14), Position = UDim2.new(0, 12, 0, 19),
    BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = "-",
    TextSize = 12, TextColor3 = THEME.sub,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd, Parent = langStrip,
}))

mk("TextLabel", {
    Size = UDim2.new(0, 150, 0, 11), Position = UDim2.new(1, -162, 0, 7),
    BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = "TU REPONDS EN",
    TextSize = 8, TextColor3 = THEME.sub,
    TextXAlignment = Enum.TextXAlignment.Right, Parent = langStrip,
})
local detectTo = dynamic(mk("TextLabel", {
    Size = UDim2.new(0, 150, 0, 14), Position = UDim2.new(1, -162, 0, 19),
    BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = "-",
    TextSize = 12, TextColor3 = THEME.accent,
    TextXAlignment = Enum.TextXAlignment.Right,
    TextTruncate = Enum.TextTruncate.AtEnd, Parent = langStrip,
}))

refreshLangNote = function()
    local lang = Chat.replyLang()
    detectFrom.Text = State.LastDetected and langName(State.LastDetected) or "?"
    detectFrom.TextColor3 = State.LastDetected and THEME.good or THEME.sub
    detectTo.Text = langName(lang)
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

local cardConv = card(pageChat)
local chatPanel = panel(cardConv, 326)

local sendReply
local chatField = field(cardConv, "Ecris dans ta langue...",
    function(text) if sendReply then sendReply(text) end end)
local rowSend = rowOf(cardConv, 36)

-- traduit vers la langue detectee chez l'autre (repli sur "Repli :") puis
-- ecrit dans la zone de saisie du chat du jeu
sendReply = function(text)
    local lang, fromDetection = Chat.replyLang()
    local ok, msg, written, copied, sent = Chat.compose(text, lang)
    if not ok then setStatus(tostring(msg), THEME.bad) return end
    chatField.Text = ""
    local how = " [" .. langName(lang) .. (fromDetection and " detecte]" or " repli]")
    if sent then
        setStatus("envoye" .. how .. " : " .. tostring(msg), THEME.good)
    elseif written then
        setStatus("ecrit dans le chat, appuie sur Entree" .. how .. " : "
            .. tostring(msg), THEME.warn)
    elseif copied then
        setStatus("zone de saisie introuvable, copie" .. how .. " : " .. tostring(msg), THEME.warn)
    else
        setStatus("traduit" .. how .. " : " .. tostring(msg), THEME.warn)
    end
end

btn(rowSend, { text = "ENVOYER", icon = Icon.send, width = 232, height = 36,
    style = "primary", callback = function() sendReply(chatField.Text) end })
btn(rowSend, { text = "", icon = Icon.cross, iconSize = 16, width = 94, height = 36,
    callback = function()
        chatField.Text = ""
        State.ChatLog = {}
        clearChildren(chatPanel)
        setStatus("conversation effacee", THEME.sub)
    end })

-- Hauteur d'un texte enroule sur une largeur donnee. On mesure au lieu de
-- laisser AutomaticSize se debrouiller : imbrique dans un ScrollingFrame,
-- il rendait des lignes de hauteur nulle, donc invisibles.
local function textHeight(text, font, size, width)
    local ok, v = pcall(function()
        return TextService:GetTextSize(text, size, font, Vector2.new(width, 100000))
    end)
    if ok and v and v.Y > 0 then return math.ceil(v.Y) end
    local perLine = math.max(12, math.floor(width / (size * 0.55)))
    return math.max(1, math.ceil(#text / perLine)) * (size + 3)
end

local function chatWidth()
    local w = chatPanel.AbsoluteSize.X
    if w and w > 90 then return w end
    return 340
end

-- Une ligne = qui parle (tete + pseudo) et ce qu'il dit.
-- Pour tes propres messages on montre ce que TU as tape, pas la traduction
-- partie chez l'autre. Pour les autres, la traduction en grand et, dessous
-- en petit, ce qu'ils ont vraiment ecrit : sans ca on lit une paraphrase
-- sans jamais pouvoir la verifier.
local function chatRow(scroll, entry)
    local body = tostring(entry.mine and entry.original
        or (entry.translated or entry.original) or "")
    if body == "" then return end

    local orig = nil
    if not entry.mine and entry.translated and entry.original
    and Util.trim(entry.translated) ~= Util.trim(entry.original) then
        orig = tostring(entry.original)
    end

    local font  = chatFont()
    local textW = math.max(120, chatWidth() - 58)
    local msgH  = textHeight(body, font, 15, textW) + 4
    local origH = orig and (textHeight(orig, Enum.Font.Gotham, 11, textW) + 3) or 0
    local rowH  = math.max(34, 17 + msgH + origH) + 8

    -- la ligne s'ouvre en hauteur pendant que le texte apparait
    local row = mk("Frame", {
        Size = UDim2.new(1, -6, 0, 0), BackgroundTransparency = 1,
        ClipsDescendants = true, Parent = scroll,
    })
    tween(row, { Size = UDim2.new(1, -6, 0, rowH) }, 0.24)

    if entry.userId then
        local head = avatar(row, entry.userId, 30)
        head.Position = UDim2.new(0, 0, 0, 2)
    else
        local dot = corner(mk("Frame", {
            Size = UDim2.new(0, 30, 0, 30), Position = UDim2.new(0, 0, 0, 2),
            BackgroundColor3 = THEME.cardHi, BorderSizePixel = 0, Parent = row,
        }), 15)
        mk("TextLabel", {
            Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold, Text = "?", TextSize = 13,
            TextColor3 = THEME.sub, Parent = dot,
        })
    end

    local nameLbl = mk("TextLabel", {
        Size = UDim2.new(1, -46, 0, 15), Position = UDim2.new(0, 40, 0, 0),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
        Text = entry.who or "joueur", TextSize = 11,
        TextColor3 = entry.mine and THEME.accent or THEME.text,
        TextTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
    })
    local msgLbl = mk("TextLabel", {
        Size = UDim2.new(1, -46, 0, msgH), Position = UDim2.new(0, 46, 0, 17),
        BackgroundTransparency = 1, Font = font, Text = body, TextSize = 15,
        TextColor3 = THEME.msg, TextWrapped = true, TextTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top, Parent = row,
    })
    tween(nameLbl, { TextTransparency = 0 }, 0.26)
    tween(msgLbl, {
        TextTransparency = 0,
        Position = UDim2.new(0, 40, 0, 17),
    }, 0.34)

    if orig then
        local origLbl = mk("TextLabel", {
            Size = UDim2.new(1, -46, 0, origH), Position = UDim2.new(0, 40, 0, 17 + msgH),
            BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = orig,
            TextSize = 11, TextColor3 = THEME.dim, TextWrapped = true,
            TextTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top, Parent = row,
        })
        tween(origLbl, { TextTransparency = 0.15 }, 0.4)
    end
    return row
end

function UI.pushChat(entry)
    chatRow(chatPanel, entry)
    local children = chatPanel:GetChildren()
    if #children > 80 then
        for i = 1, 20 do
            local c = children[i]
            if c and not c:IsA("UIListLayout") then c:Destroy() end
        end
    end
end

-- redessine toute la conversation (police, langue, largeur du panneau)
function UI.redrawChat()
    clearChildren(chatPanel)
    for _, e in ipairs(State.ChatLog) do pcall(chatRow, chatPanel, e) end
end

-- au premier affichage le panneau n'a pas encore sa largeur reelle : on
-- redessine une fois qu'il l'a, pour que les hauteurs mesurees soient justes
do
    local lastWidth = 0
    Maid.conn(chatPanel:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        local w = chatPanel.AbsoluteSize.X
        if math.abs(w - lastWidth) > 8 then
            lastWidth = w
            if UI.redrawChat then pcall(UI.redrawChat) end
        end
    end))
end

----------------------------------------------------------------------------------
-- ONGLET : REGLAGES
----------------------------------------------------------------------------------
local pageSettings = addTab("Reglages", Icon.tune)

-- Les deux langues vivent ici, pas dans le Chat : on les choisit une fois,
-- alors qu'on lit le bandeau de langue a chaque message.
local cardLang = card(pageSettings, "Langues")
listPicker(cardLang, "Ma langue", LANGS, "TranslateTo", langName, function(value)
    refreshLangNote()
    if UI.redrawChat then UI.redrawChat() end
    -- tout le script bascule dans la langue choisie
    I18N.apply(value)
end)
listPicker(cardLang, "Repli si rien n'est detecte", LANGS, "SendAs", langName, function()
    refreshLangNote()
end)

local cardStyle = card(pageSettings, "Chat")
listPicker(cardStyle, "Police des messages", CHAT_FONTS, "ChatFont", tostring, function()
    if UI.redrawChat then UI.redrawChat() end
end)

local cardDisplay = card(pageSettings, "Affichage")
switch(cardDisplay, "Tete des joueurs", "ShowAvatars")
switch(cardDisplay, "Apercu 3D des brainrots", "ShowModels")
slider(cardDisplay, "Taille de l'apercu 3D", "ModelSize", 48, 220, " px", function()
    redrawBase()
end)

----------------------------------------------------------------------------------
-- BOUTONS FENETRE / RACCOURCI / UNLOAD
----------------------------------------------------------------------------------
local minimized = false
chipButton(-58, THEME.warn, Icon.minus, function()
    minimized = not minimized
    bodyFrame.Visible = not minimized
    tabBar.Visible = not minimized
    statusBar.Visible = not minimized
    tween(window, { Size = UDim2.new(0, WIN_W, 0, minimized and BAR_H or WIN_H) }, 0.2)
end)
chipButton(-28, THEME.bad, Icon.cross, function()
    if GENV.TradePlazaHub and GENV.TradePlazaHub.Unload then GENV.TradePlazaHub.Unload() end
end)

local floating = corner(mk("TextButton", {
    Size = UDim2.new(0, 48, 0, 48), Position = UDim2.new(0, 18, 1, -66),
    BackgroundColor3 = THEME.accent, AutoButtonColor = false, Font = Enum.Font.Michroma,
    Text = "TP", TextSize = 12, TextColor3 = THEME.bg, BorderSizePixel = 0,
    Visible = false, Parent = screen,
}), 24)
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

-- On releve les libelles maintenant : les panneaux dynamiques sont encore
-- vides, donc aucun pseudo de joueur ni nom de brainrot ne peut se
-- retrouver dans la liste a traduire. Le logo reste en francais.
I18N.scan(window, {
    [playersPanel] = true, [brainrotPanel] = true,
    [chatPanel] = true, [wordmark] = true,
})
if CONFIG.TranslateTo and CONFIG.TranslateTo ~= "fr" then
    I18N.apply(CONFIG.TranslateTo)
end

window.Size = UDim2.new(0, WIN_W - 30, 0, WIN_H - 52)
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

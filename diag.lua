--[[
==================================================================================
    TRADE PLAZA HUB - DIAGNOSTIC
==================================================================================
    A executer AVANT / A LA PLACE du hub quand quelque chose ne marche pas.
    Il n'a aucune interface : il ecrit un rapport dans la console (F9)
    et le copie dans le presse-papier si l'executor le permet.

    Copie-colle le rapport et je regle le hub avec les vrais chemins du jeu.
==================================================================================
]]

local Players     = game:GetService("Players")
local RS          = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local out = {}
local function w(fmt, ...)
    local ok, line = pcall(string.format, tostring(fmt), ...)
    table.insert(out, ok and line or tostring(fmt))
end

w("=== TRADE PLAZA HUB / DIAGNOSTIC ===")
w("PlaceId : %s   JobId : %s", tostring(game.PlaceId), tostring(game.JobId))
w("Joueur  : %s (%d)", LocalPlayer.Name, LocalPlayer.UserId)
w("")

--------------------------------------------------------------------------------
w("--- 1. FONCTIONS D'EXECUTOR ---")
--------------------------------------------------------------------------------
local checks = {
    { "request",          (syn and syn.request) or http_request or request },
    { "setclipboard",     setclipboard or toclipboard },
    { "gethui",           gethui },
    { "hookmetamethod",   hookmetamethod },
    { "getnamecallmethod",getnamecallmethod },
    { "checkcaller",      checkcaller },
    { "getgenv",          getgenv },
    { "getconnections",   getconnections },
    { "game:HttpGet",     (function() local ok = pcall(function() return game.HttpGet end) return ok and true or nil end)() },
}
for _, c in ipairs(checks) do
    w("%-20s : %s", c[1], c[2] and "OUI" or "non")
end
w("")

--------------------------------------------------------------------------------
w("--- 2. TEST TRADUCTION (HTTP) ---")
--------------------------------------------------------------------------------
do
    local url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=fr&dt=t&q=hello"
    local body
    local req = (syn and syn.request) or http_request or request
    if req then
        local ok, res = pcall(req, { Url = url, Method = "GET" })
        if ok and type(res) == "table" then body = res.Body end
    end
    if not body then
        local ok, res = pcall(function() return game:HttpGetAsync(url) end)
        if ok then body = res end
    end
    if body then
        local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
        w("HTTP : OK    traduction 'hello' -> %s",
            (ok and data and data[1] and data[1][1] and data[1][1][1]) or "(reponse illisible)")
    else
        w("HTTP : INDISPONIBLE (le traducteur ne pourra pas fonctionner)")
    end
end
w("")

--------------------------------------------------------------------------------
w("--- 3. REMOTES ---")
--------------------------------------------------------------------------------
local function isRemote(i)
    return i:IsA("RemoteEvent") or i:IsA("RemoteFunction") or i.ClassName == "UnreliableRemoteEvent"
end

local roots = { RS }
if game:FindFirstChild("ReplicatedFirst") then table.insert(roots, game.ReplicatedFirst) end
table.insert(roots, workspace)
if LocalPlayer:FindFirstChild("PlayerGui") then table.insert(roots, LocalPlayer.PlayerGui) end

local all, trade = {}, {}
for _, root in ipairs(roots) do
    local ok, desc = pcall(function() return root:GetDescendants() end)
    if ok then
        for _, d in ipairs(desc) do
            local okIs, r = pcall(isRemote, d)
            if okIs and r then
                local tag = d:IsA("RemoteFunction") and "[RF]" or "[RE]"
                local full = tag .. " " .. d:GetFullName()
                table.insert(all, full)
                if string.find(string.lower(d:GetFullName()), "trade", 1, true) then
                    table.insert(trade, full)
                end
            end
        end
    end
end
table.sort(all)
table.sort(trade)

w("Remotes lies au TRADE (%d) :", #trade)
for _, line in ipairs(trade) do w("   %s", line) end
w("")
w("Tous les remotes (%d, 120 premiers) :", #all)
for i = 1, math.min(#all, 120) do w("   %s", all[i]) end
w("")

--------------------------------------------------------------------------------
w("--- 4. WORKSPACE / PLOTS ---")
--------------------------------------------------------------------------------
w("Enfants de workspace :")
for _, c in ipairs(workspace:GetChildren()) do
    w("   %-24s %s (%d enfants)", c.Name, c.ClassName, #c:GetChildren())
end
w("")

local container
for _, c in ipairs(workspace:GetChildren()) do
    local n = string.lower(c.Name)
    if n == "plots" or n == "bases" or n == "plot" or n == "base" then container = c break end
end

local function dumpTree(inst, depth, maxDepth, limit)
    if depth > maxDepth then return end
    for _, child in ipairs(inst:GetChildren()) do
        if #out > limit then return end
        local attrs = ""
        local ok, t = pcall(function() return child:GetAttributes() end)
        if ok and t then
            local parts = {}
            for k, v in pairs(t) do table.insert(parts, k .. "=" .. tostring(v)) end
            if #parts > 0 then attrs = "   {" .. table.concat(parts, ", ") .. "}" end
        end
        local extra = ""
        if child:IsA("ObjectValue") or child:IsA("StringValue") or child:IsA("IntValue") or child:IsA("NumberValue") then
            extra = "  = " .. tostring(child.Value)
        elseif child:IsA("TextLabel") then
            extra = '  texte="' .. tostring(child.Text) .. '"'
        end
        w("%s%s %s%s%s", string.rep("   ", depth), child.ClassName, child.Name, extra, attrs)
        dumpTree(child, depth + 1, maxDepth, limit)
    end
end

if container then
    w("Conteneur de plots trouve : %s (%d plots)", container:GetFullName(), #container:GetChildren())
    local first = container:GetChildren()[1]
    if first then
        w("")
        w("Structure du 1er plot (%s) :", first.Name)
        local okAttr, attrs = pcall(function() return first:GetAttributes() end)
        if okAttr and attrs then
            for k, v in pairs(attrs) do w("   ATTRIBUT %s = %s", k, tostring(v)) end
        end
        dumpTree(first, 1, 4, 700)
    end
else
    w("AUCUN conteneur de plots (Plots/Bases) trouve directement dans workspace.")
end
w("")

--------------------------------------------------------------------------------
w("--- 5. INTERFACES (PlayerGui) ---")
--------------------------------------------------------------------------------
local pg = LocalPlayer:FindFirstChild("PlayerGui")
if pg then
    w("ScreenGui presents :")
    for _, g in ipairs(pg:GetChildren()) do
        w("   %-28s %s", g.Name, g.ClassName)
    end
    w("")
    w("Elements dont le chemin contient 'trade' ou 'chat' (60 max) :")
    local n = 0
    local ok, desc = pcall(function() return pg:GetDescendants() end)
    if ok then
        for _, d in ipairs(desc) do
            local full = string.lower(d:GetFullName())
            if (string.find(full, "trade", 1, true) or string.find(full, "chat", 1, true))
               and (d:IsA("TextLabel") or d:IsA("TextBox") or d:IsA("ScrollingFrame") or d:IsA("TextButton")) then
                n = n + 1
                if n <= 60 then w("   %s  (%s)", d:GetFullName(), d.ClassName) end
            end
        end
    end
    w("   total : %d", n)
end

--------------------------------------------------------------------------------
local report = table.concat(out, "\n")
print(report)
local copied = false
if setclipboard then copied = pcall(setclipboard, report) end
print(("=== FIN DU DIAGNOSTIC (%d lignes) %s==="):format(#out,
    copied and "- copie dans le presse-papier " or "- copie manuelle depuis la console "))
return report

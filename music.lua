--======================================================================--
--        HOLO-SPOTIFY 5D V7 (TELAS CORRIGIDAS & 100% COMPLETO)         --
--======================================================================--
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")

local LP = Players.LocalPlayer
local Cam = workspace.CurrentCamera
local PGui = LP:WaitForChild("PlayerGui")

-- Limpeza de versões antigas
for _, v in pairs({
    Cam:FindFirstChild("Holo5D_System"),
    SoundService:FindFirstChild("Holo5D_Sound"),
    PGui:FindFirstChild("Holo5D_ToggleGui"),
    PGui:FindFirstChild("Holo5D_TopSearchGui")
}) do
    if v then v:Destroy() end
end

local httpReq = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
local getAsset = getcustomasset or getsynasset

local function HttpGet(url)
    if httpReq then
        local ok, r = pcall(function()
            return httpReq({Url = url, Method = "GET", Headers = {["User-Agent"] = "Mozilla/5.0"}})
        end)
        if ok and r and r.Body and #r.Body > 0 then return r.Body end
    end
    local ok, r = pcall(function() return game:HttpGet(url, true) end)
    return ok and r or nil
end

-- Funções rápidas de UI
local function Corner(p, r)
    local c = Instance.new("UICorner", p)
    c.CornerRadius = UDim.new(0, r or 10)
    return c
end

local function Stroke(p, col, th)
    local s = Instance.new("UIStroke", p)
    s.Color = col
    s.Thickness = th or 1.5
    return s
end

local function Lbl(p, txt, sz, pos, col, ts)
    local l = Instance.new("TextLabel", p)
    l.Size, l.Position, l.BackgroundTransparency = sz, pos, 1
    l.Text, l.TextColor3, l.TextSize = txt, col or Color3.new(1,1,1), ts or 13
    l.Font = Enum.Font.GothamBold
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextTruncate = Enum.TextTruncate.AtEnd
    return l
end

local function Btn(p, txt, sz, pos, bg, tc, ts)
    local b = Instance.new("TextButton", p)
    b.Size, b.Position = sz, pos
    b.BackgroundColor3 = bg or Color3.fromRGB(22, 28, 46)
    b.Text, b.TextColor3, b.TextSize = txt, tc or Color3.new(1,1,1), ts or 13
    b.Font = Enum.Font.GothamBlack
    Corner(b, 9)
    return b
end

-- Motor de Som 5D
local HoloFolder = Instance.new("Folder", Cam)
HoloFolder.Name = "Holo5D_System"

local Sound = Instance.new("Sound", SoundService)
Sound.Name, Sound.Volume, Sound.Looped = "Holo5D_Sound", 0.85, true

local BassFX = Instance.new("EqualizerSoundEffect", Sound)
BassFX.LowGain = 0

local ReverbFX = Instance.new("ReverbSoundEffect", Sound)
ReverbFX.DecayTime, ReverbFX.WetLevel, ReverbFX.Enabled = 1.5, -6, false

-- Gui Principal no PlayerGui (Garante que as telas 3D apareçam sempre)
local ToggleGui = Instance.new("ScreenGui", PGui)
ToggleGui.Name, ToggleGui.ResetOnSpawn = "Holo5D_ToggleGui", false

local ReopenBtn = Btn(ToggleGui, "💠 ABRIR [H]", UDim2.new(0,125,0,34), UDim2.new(0,12,0.5,-17), Color3.fromRGB(10,14,24), Color3.fromRGB(0,255,190), 13)
ReopenBtn.Visible = false
Stroke(ReopenBtn, Color3.fromRGB(0,255,190), 1.5)

-- Criação das 2 Telas Holográficas 3D (Viradas para a Câmera)
local ScreenSize = Vector3.new(3.6, 2.65, 0.04)

local function MakeScreen(name, col)
    local p = Instance.new("Part", HoloFolder)
    p.Name, p.Size = name, ScreenSize
    p.Transparency = 0.85
    p.Color = col
    p.Material = Enum.Material.Glass
    p.Anchored, p.CanCollide, p.CastShadow = true, false, false

    local sg = Instance.new("SurfaceGui", ToggleGui)
    sg.Name = name .. "_UI"
    sg.Adornee = p
    sg.Face = Enum.NormalId.Front
    sg.CanvasSize = Vector2.new(600, 460)
    sg.AlwaysOnTop = true
    sg.LightInfluence = 0
    sg.Active = true

    local f = Instance.new("Frame", sg)
    f.Size, f.Position = UDim2.new(1,-12,1,-12), UDim2.new(0,6,0,6)
    f.BackgroundColor3, f.BackgroundTransparency = Color3.fromRGB(10,13,22), 0.08
    Corner(f, 16)
    return p, sg, f, Stroke(f, col, 2.5)
end

local LPart, LGui, LFrame, LStroke = MakeScreen("LeftScreen", Color3.fromRGB(0,255,170))
local RPart, RGui, RFrame, RStroke = MakeScreen("RightScreen", Color3.fromRGB(0,200,255))

local Core = Instance.new("Part", HoloFolder)
Core.Shape, Core.Material, Core.Anchored, Core.CanCollide = Enum.PartType.Ball, Enum.Material.Neon, true, false

local Ring = Instance.new("Part", HoloFolder)
Ring.Material, Ring.Transparency, Ring.Anchored, Ring.CanCollide = Enum.Material.Neon, 0.25, true, false

--================ TELA ESQUERDA (PLAYER 5D) ================--
local CloseBtn = Btn(LFrame, "✖ FECHAR", UDim2.new(0,100,0,28), UDim2.new(0,18,0,14), Color3.fromRGB(220,40,75))
Lbl(LFrame, "🎵 HOLO-STREAM V7", UDim2.new(0,250,0,28), UDim2.new(0,128,0,14), Color3.fromRGB(0,255,170), 18)
local ZoomBtn = Btn(LFrame, "🔍 ZOOM: 1x", UDim2.new(0,95,0,28), UDim2.new(1,-113,0,14), Color3.fromRGB(25,34,52), Color3.fromRGB(0,220,255), 12)

local Card = Instance.new("Frame", LFrame)
Card.Size, Card.Position, Card.BackgroundColor3 = UDim2.new(1,-36,0,88), UDim2.new(0,18,0,50), Color3.fromRGB(16,20,34)
Corner(Card, 12)

local Disc = Btn(Card, "💿", UDim2.new(0,64,0,64), UDim2.new(0,12,0.5,-32), Color3.fromRGB(0,255,160), Color3.new(1,1,1), 30)
Corner(Disc, 100)

local TitleLbl  = Lbl(Card, "Escolha uma Música na Direita", UDim2.new(1,-95,0,26), UDim2.new(0,88,0,10), Color3.new(1,1,1), 17)
local ArtistLbl = Lbl(Card, "Audius • Deezer • HearThis", UDim2.new(1,-95,0,20), UDim2.new(0,88,0,36), Color3.fromRGB(0,210,255), 13)
local StatusLbl = Lbl(Card, "⚡ 100% Livre de Bloqueios", UDim2.new(1,-95,0,18), UDim2.new(0,88,0,58), Color3.fromRGB(160,175,200), 12)

local VisBox = Instance.new("Frame", LFrame)
VisBox.Size, VisBox.Position, VisBox.BackgroundColor3 = UDim2.new(1,-36,0,85), UDim2.new(0,18,0,146), Color3.fromRGB(12,15,26)
Corner(VisBox, 10)

local Bars = {}
for i = 1, 24 do
    local b = Instance.new("Frame", VisBox)
    b.Size = UDim2.new(1/24 - 0.008, 0, 0.1, 0)
    b.Position = UDim2.new((i-1)/24 + 0.004, 0, 1, -4)
    b.AnchorPoint = Vector2.new(0, 1)
    b.BackgroundColor3 = Color3.fromHSV((i/24)*0.55, 0.85, 1)
    Corner(b, 4)
    Bars[i] = b
end

local TimeLbl = Lbl(LFrame, "00:00 / 00:00", UDim2.new(1,-36,0,18), UDim2.new(0,18,0,238), Color3.fromRGB(180,195,220), 12)
local ProgBg = Btn(LFrame, "", UDim2.new(1,-36,0,12), UDim2.new(0,18,0,258), Color3.fromRGB(28,34,52))
local ProgFill = Instance.new("Frame", ProgBg)
ProgFill.Size, ProgFill.BackgroundColor3 = UDim2.new(0,0,1,0), Color3.fromRGB(0,255,170)
Corner(ProgFill, 10)

ProgBg.MouseButton1Click:Connect(function()
    if Sound.TimeLength > 0 then
        Sound.TimePosition = (Sound.TimePosition + 10) % Sound.TimeLength
    end
end)

local PrevBtn = Btn(LFrame, "⏮", UDim2.new(0,58,0,42), UDim2.new(0,18,0,282), nil, nil, 18)
local PlayBtn = Btn(LFrame, "▶ PLAY", UDim2.new(0,110,0,42), UDim2.new(0,84,0,282), Color3.fromRGB(0,230,150), Color3.fromRGB(10,15,24), 15)
local NextBtn = Btn(LFrame, "⏭", UDim2.new(0,58,0,42), UDim2.new(0,202,0,282), nil, nil, 18)
local VolDown = Btn(LFrame, "🔉-", UDim2.new(0,48,0,42), UDim2.new(0,270,0,282))
local VolLbl  = Btn(LFrame, "VOL: 85%", UDim2.new(0,105,0,42), UDim2.new(0,324,0,282), Color3.fromRGB(16,20,34), Color3.fromRGB(0,255,190), 13)
local VolUp   = Btn(LFrame, "🔊+", UDim2.new(0,48,0,42), UDim2.new(0,435,0,282))
local StopBtn = Btn(LFrame, "⏹", UDim2.new(0,79,0,42), UDim2.new(0,491,0,282), Color3.fromRGB(180,40,60), nil, 17)

Lbl(LFrame, "🎛️ ESTÚDIO DE EFEITOS 5D:", UDim2.new(1,-36,0,18), UDim2.new(0,18,0,336), Color3.fromRGB(170,185,215), 12)
local BassBtn  = Btn(LFrame, "🔊 BASS\n[OFF]", UDim2.new(0,130,0,66), UDim2.new(0,18,0,360), Color3.fromRGB(20,25,42))
local NightBtn = Btn(LFrame, "⚡ NIGHTCORE\n[OFF]", UDim2.new(0,130,0,66), UDim2.new(0,158,0,360), Color3.fromRGB(20,25,42))
local SlowBtn  = Btn(LFrame, "🌊 SLOWED\n[OFF]", UDim2.new(0,130,0,66), UDim2.new(0,298,0,360), Color3.fromRGB(20,25,42))
local FovBtn   = Btn(LFrame, "🎥 PULSO 5D\n[ON]", UDim2.new(0,132,0,66), UDim2.new(0,438,0,360), Color3.fromRGB(20,25,42))

--================ TELA DIREITA (BUSCA MULTI-PLATAFORMA) ================--
Lbl(RFrame, "🌐 BUSCADOR MULTI-PLATAFORMA (.MP3 REAL)", UDim2.new(1,-36,0,22), UDim2.new(0,18,0,10), Color3.fromRGB(0,215,255), 16)

local SBox = Instance.new("TextBox", RFrame)
SBox.Size, SBox.Position = UDim2.new(1,-142,0,38), UDim2.new(0,18,0,36)
SBox.BackgroundColor3 = Color3.fromRGB(18,24,40)
SBox.PlaceholderText = "Digite o nome da música ou artista..."
SBox.Text, SBox.TextColor3 = "", Color3.new(1,1,1)
SBox.Font, SBox.TextSize, SBox.ClearTextOnFocus = Enum.Font.GothamBold, 14, false
Corner(SBox, 10)
Stroke(SBox, Color3.fromRGB(0,195,255), 1.5)

local SBtn = Btn(RFrame, "BUSCAR", UDim2.new(0,96,0,38), UDim2.new(1,-114,0,36), Color3.fromRGB(0,200,255), Color3.fromRGB(10,14,24), 14)

local Platform, Tabs = "ALL", {}
local TabList = {
    {"ALL", "🌐 TODAS", 18, 95, Color3.fromRGB(0,255,180)},
    {"AUDIUS", "🟠 AUDIUS", 120, 140, Color3.fromRGB(255,140,0)},
    {"DEEZER", "🟣 DEEZER", 268, 140, Color3.fromRGB(190,90,255)},
    {"HEARTHIS", "🔵 HEARTHIS", 416, 154, Color3.fromRGB(0,195,255)}
}
for _, c in ipairs(TabList) do
    local b = Btn(RFrame, c[2], UDim2.new(0,c[4],0,28), UDim2.new(0,c[3],0,80), Color3.fromRGB(20,26,44), nil, 11)
    Tabs[c[1]] = {Btn = b, St = Stroke(b, c[5], c[1] == "ALL" and 2.2 or 0.8)}
end

local SStatus = Lbl(RFrame, "✨ Escolha a plataforma ou pesquise:", UDim2.new(1,-36,0,18), UDim2.new(0,18,0,114), Color3.fromRGB(0,255,180), 12)

local Scroll = Instance.new("ScrollingFrame", RFrame)
Scroll.Size, Scroll.Position = UDim2.new(1,-36,1,-144), UDim2.new(0,18,0,134)
Scroll.BackgroundTransparency, Scroll.ScrollBarThickness = 1, 6

local Layout = Instance.new("UIListLayout", Scroll)
Layout.Padding = UDim.new(0, 7)

--================ MOTOR DE REPRODUÇÃO E BUSCA ================--
local Playlist, CurIdx, Playing, Token, Slot, Cache, LastQuery = {}, 1, false, 0, 1, {}, "phonk"

local function Fmt(s)
    s = math.max(0, math.floor(tonumber(s) or 0))
    return string.format("%02d:%02d", math.floor(s/60), s%60)
end

local function PlayTrack(t)
    if not t or not t.Url then return end
    TitleLbl.Text = t.Title
    ArtistLbl.Text = t.Artist .. " • [" .. t.Plat .. "]"
    StatusLbl.Text = "⏳ Carregando stream .MP3..."
    Sound:Stop()

    task.spawn(function()
        if not (writefile and getAsset) then
            StatusLbl.Text = "❌ Executor sem suporte a .mp3"
            return
        end
        if not Cache[t.Url] then
            local bytes = HttpGet(t.Url)
            if not bytes or #bytes < 1500 then
                StatusLbl.Text = "⚠️ Stream ocupado, tente outra!"
                return
            end
            Slot = (Slot % 8) + 1
            local f = "HoloV7_" .. Slot .. ".mp3"
            pcall(writefile, f, bytes)
            local ok, id = pcall(getAsset, f)
            if ok and id then Cache[t.Url] = id end
        end
        if Cache[t.Url] then
            Sound.SoundId = Cache[t.Url]
            Sound.TimePosition = 0
            Sound:Play()
            Playing = true
            PlayBtn.Text = "⏸ PAUSE"
            StatusLbl.Text = "🔊 Tocando: " .. t.Plat
        end
    end)
end

local function AddCard(t)
    table.insert(Playlist, t)
    local idx = #Playlist
    local c = Instance.new("Frame", Scroll)
    c.Size, c.BackgroundColor3 = UDim2.new(1,-8,0,54), Color3.fromRGB(18,23,38)
    Corner(c, 10)

    Btn(c, t.Plat, UDim2.new(0,78,0,38), UDim2.new(0,8,0.5,-19), t.Col, Color3.fromRGB(10,14,22), 10)
    Lbl(c, t.Title, UDim2.new(1,-180,0,22), UDim2.new(0,96,0,6), Color3.new(1,1,1), 14)
    Lbl(c, t.Artist .. " • ⏱ " .. Fmt(t.Dur), UDim2.new(1,-180,0,18), UDim2.new(0,96,0,28), Color3.fromRGB(145,165,195), 12)

    local pBtn = Btn(c, "▶ TOCAR", UDim2.new(0,72,0,38), UDim2.new(1,-80,0.5,-19), Color3.fromRGB(0,235,155), Color3.fromRGB(10,14,24), 12)
    pBtn.MouseButton1Click:Connect(function()
        CurIdx = idx
        PlayTrack(t)
    end)
    Scroll.CanvasSize = UDim2.new(0, 0, 0, #Playlist * 61)
end

local function SearchPlatform(plat, q, tk)
    local enc = HttpService:UrlEncode(q)
    if plat == "AUDIUS" then
        for _, h in ipairs({"https://discoveryprovider.audius.co", "https://discoveryprovider2.audius.co"}) do
            local b = HttpGet(h .. "/v1/tracks/search?query=" .. enc .. "&app_name=HoloV7")
            local ok, d = pcall(function() return HttpService:JSONDecode(b) end)
            if ok and d and d.data then
                local n = 0
                for _, i in ipairs(d.data) do
                    if tk ~= Token then return end
                    local dur = tonumber(i.duration) or 0
                    if i.id and dur >= 15 and dur <= 420 then
                        AddCard({
                            Title = i.title,
                            Artist = (i.user and i.user.name) or "Audius",
                            Dur = dur,
                            Url = h .. "/v1/tracks/" .. i.id .. "/stream?app_name=HoloV7",
                            Plat = "AUDIUS",
                            Col = Color3.fromRGB(255,145,20)
                        })
                        n = n + 1
                        if n >= 10 then break end
                    end
                end
                if n > 0 then break end
            end
        end
    elseif plat == "DEEZER" then
        local b = HttpGet("https://api.deezer.com/search?q=" .. enc .. "&limit=12")
        local ok, d = pcall(function() return HttpService:JSONDecode(b) end)
        if ok and d and d.data then
            for _, i in ipairs(d.data) do
                if tk ~= Token then return end
                if i.preview and i.preview ~= "" then
                    AddCard({
                        Title = i.title,
                        Artist = (i.artist and i.artist.name) or "Deezer",
                        Dur = i.duration or 30,
                        Url = i.preview,
                        Plat = "DEEZER",
                        Col = Color3.fromRGB(195,95,255)
                    })
                end
            end
        end
    elseif plat == "HEARTHIS" then
        local b = HttpGet("https://api-v2.hearthis.at/search/?t=" .. enc .. "&page=1&count=12")
        local ok, d = pcall(function() return HttpService:JSONDecode(b) end)
        if ok and type(d) == "table" then
            for _, i in ipairs(d) do
                if tk ~= Token then return end
                local dur = tonumber(i.duration) or 0
                if i.stream_url and dur >= 15 and dur <= 420 then
                    AddCard({
                        Title = i.title,
                        Artist = (i.user and i.user.username) or "DJ",
                        Dur = dur,
                        Url = i.stream_url,
                        Plat = "HEARTHIS",
                        Col = Color3.fromRGB(0,200,255)
                    })
                end
            end
        end
    end
end

local function RunSearch(q)
    local clean = q and q:match("^%s*(.-)%s*$") or ""
    if clean == "" then clean = LastQuery else LastQuery = clean end
    Token = Token + 1
    local tk = Token
    Playlist = {}
    for _, c in ipairs(Scroll:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    SStatus.Text = "⚡ Buscando '" .. clean .. "' em [" .. Platform .. "]..."

    task.spawn(function()
        if Platform == "ALL" then
            local done = 0
            for _, p in ipairs({"AUDIUS", "DEEZER", "HEARTHIS"}) do
                task.spawn(function()
                    SearchPlatform(p, clean, tk)
                    done = done + 1
                end)
            end
            local t0 = os.clock()
            while done < 3 and os.clock() - t0 < 4.5 do task.wait(0.1) end
        else
            SearchPlatform(Platform, clean, tk)
        end
        if tk == Token then
            SStatus.Text = #Playlist > 0 and ("✅ " .. #Playlist .. " músicas encontradas!") or "⚠️ Sem resultados. Tente 🌐 TODAS!"
        end
    end)
end

for id, t in pairs(Tabs) do
    t.Btn.MouseButton1Click:Connect(function()
        Platform = id
        for k, v in pairs(Tabs) do v.St.Thickness = (k == id) and 2.2 or 0.8 end
        RunSearch(SBox.Text)
    end)
end

SBtn.MouseButton1Click:Connect(function() RunSearch(SBox.Text) end)
SBox.FocusLost:Connect(function(enter) if enter then RunSearch(SBox.Text) end end)
RunSearch("phonk")

--================ EVENTOS DOS BOTÕES E EFEITOS 5D ================--
PlayBtn.MouseButton1Click:Connect(function()
    if Playing then
        Sound:Pause(); Playing = false; PlayBtn.Text = "▶ PLAY"
    elseif Sound.SoundId ~= "" then
        Sound:Resume(); Playing = true; PlayBtn.Text = "⏸ PAUSE"
    elseif Playlist[1] then
        PlayTrack(Playlist[1])
    end
end)

StopBtn.MouseButton1Click:Connect(function() Sound:Stop(); Playing = false; PlayBtn.Text = "▶ PLAY" end)
PrevBtn.MouseButton1Click:Connect(function() if #Playlist > 0 then CurIdx = (CurIdx - 2) % #Playlist + 1; PlayTrack(Playlist[CurIdx]) end end)
NextBtn.MouseButton1Click:Connect(function() if #Playlist > 0 then CurIdx = CurIdx % #Playlist + 1; PlayTrack(Playlist[CurIdx]) end end)
VolDown.MouseButton1Click:Connect(function() Sound.Volume = math.clamp(Sound.Volume - 0.1, 0, 2); VolLbl.Text = "VOL: "..math.floor(Sound.Volume*100+0.5).."%" end)
VolUp.MouseButton1Click:Connect(function() Sound.Volume = math.clamp(Sound.Volume + 0.1, 0, 2); VolLbl.Text = "VOL: "..math.floor(Sound.Volume*100+0.5).."%" end)

local bass, night, slow, fovOn = false, false, false, true
BassBtn.MouseButton1Click:Connect(function()
    bass = not bass; BassFX.LowGain = bass and 12 or 0
    BassBtn.Text = bass and "🔊 BASS\n[ON 🔥]" or "🔊 BASS\n[OFF]"
end)
NightBtn.MouseButton1Click:Connect(function()
    night = not night; slow = false; ReverbFX.Enabled = false
    Sound.PlaybackSpeed = night and 1.25 or 1
    NightBtn.Text = night and "⚡ NIGHTCORE\n[ON ⚡]" or "⚡ NIGHTCORE\n[OFF]"
    SlowBtn.Text = "🌊 SLOWED\n[OFF]"
end)
SlowBtn.MouseButton1Click:Connect(function()
    slow = not slow; night = false; ReverbFX.Enabled = slow
    Sound.PlaybackSpeed = slow and 0.82 or 1
    SlowBtn.Text = slow and "🌊 SLOWED\n[ON 🌊]" or "🌊 SLOWED\n[OFF]"
    NightBtn.Text = "⚡ NIGHTCORE\n[OFF]"
end)
FovBtn.MouseButton1Click:Connect(function()
    fovOn = not fovOn
    FovBtn.Text = fovOn and "🎥 PULSO 5D\n[ON]" or "🎥 PULSO 5D\n[OFF]"
    if not fovOn then Cam.FieldOfView = 70 end
end)

--================ ABRIR/FECHAR HUB E LOOP 5D ================--
local hubOpen, busy, dist, zMode, smoothCF = true, false, -3.2, 1, Cam.CFrame

ZoomBtn.MouseButton1Click:Connect(function()
    zMode = zMode % 3 + 1
    dist = (zMode == 1 and -3.2) or (zMode == 2 and -2.4) or -4.2
    ZoomBtn.Text = "🔍 ZOOM: " .. (zMode == 1 and "1x" or zMode == 2 and "2x" or "0.7x")
end)

local function ToggleHub()
    if busy then return end
    busy = true
    hubOpen = not hubOpen
    if hubOpen then
        ReopenBtn.Visible, LGui.Enabled, RGui.Enabled = false, true, true
        LPart.Transparency, RPart.Transparency, Core.Transparency, Ring.Transparency = 0.85, 0.85, 0, 0.25
        TweenService:Create(LPart, TweenInfo.new(0.45, Enum.EasingStyle.Back), {Size = ScreenSize}):Play()
        TweenService:Create(RPart, TweenInfo.new(0.45, Enum.EasingStyle.Back), {Size = ScreenSize}):Play()
        task.wait(0.45)
    else
        TweenService:Create(LPart, TweenInfo.new(0.3), {Size = Vector3.new(0.05,0.05,0.05)}):Play()
        TweenService:Create(RPart, TweenInfo.new(0.3), {Size = Vector3.new(0.05,0.05,0.05)}):Play()
        task.wait(0.3)
        LGui.Enabled, RGui.Enabled = false, false
        LPart.Transparency, RPart.Transparency, Core.Transparency, Ring.Transparency = 1, 1, 1, 1
        ReopenBtn.Visible = true
    end
    busy = false
end

CloseBtn.MouseButton1Click:Connect(ToggleHub)
ReopenBtn.MouseButton1Click:Connect(ToggleHub)
UIS.InputBegan:Connect(function(i, gp)
    if not gp and i.KeyCode == Enum.KeyCode.H then ToggleHub() end
end)

RunService.RenderStepped:Connect(function(dt)
    local loud = Playing and math.clamp(Sound.PlaybackLoudness / 450, 0, 1) or 0
    local hue = (os.clock() * 0.12) % 1

    if Playing and Sound.TimeLength > 0 then
        ProgFill.Size = UDim2.new(math.clamp(Sound.TimePosition / Sound.TimeLength, 0, 1), 0, 1, 0)
        TimeLbl.Text = Fmt(Sound.TimePosition) .. " / " .. Fmt(Sound.TimeLength)
        Disc.Rotation = (Disc.Rotation + dt * (120 + loud * 240)) % 360
    end

    for i, b in ipairs(Bars) do
        local h = Playing and math.clamp(loud * 0.85 + (math.sin(os.clock()*10 + i*0.5)*0.5+0.5)*0.25, 0.08, 0.95) or 0.08
        b.Size = b.Size:Lerp(UDim2.new(1/24 - 0.008, 0, h, 0), dt * 16)
    end

    if fovOn and Playing then Cam.FieldOfView = 70 + loud * 6.5 end
    if not hubOpen and not busy then return end

    local typing = UIS:GetFocusedTextBox() ~= nil
    smoothCF = smoothCF:Lerp(Cam.CFrame, typing and 1 or math.clamp(dt * 14, 0, 1))
    local baseCF = smoothCF * CFrame.new(0, typing and 0 or math.sin(os.clock()*2.2)*0.04, dist)

    Core.CFrame = baseCF * CFrame.new(0, 1.52, -0.1)
    Core.Size = Vector3.one * (0.28 + loud * 0.35)
    Core.Color = Color3.fromHSV(hue, 0.85, 1)

    Ring.CFrame = Core.CFrame * CFrame.Angles(os.clock()*2, os.clock()*1.5, 0)
    Ring.Size = Vector3.new(0.52 + loud*0.5, 0.52 + loud*0.5, 0.03)

    LStroke.Color = Color3.fromHSV(hue, 0.8, 1)
    RStroke.Color = Color3.fromHSV((hue + 0.25) % 1, 0.8, 1)

    -- Rotação 192° e 168° faz a frente das 2 telas olhar diretamente para seus olhos!
    LPart.CFrame = baseCF * CFrame.new(-1.85, 0, 0.22) * CFrame.Angles(0, math.rad(192), 0)
    RPart.CFrame = baseCF * CFrame.new(1.85, 0, 0.22) * CFrame.Angles(0, math.rad(168), 0)
end)
--================ FIM DO SCRIPT (100% COMPLETO) ================--

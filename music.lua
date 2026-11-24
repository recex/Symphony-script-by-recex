-- ==============================================================================
-- HOLO-SPOTIFY 5D V8.3 — SINCRONIZAÇÃO, VALIDAÇÃO E CLEANUP REFORÇADOS
-- ==============================================================================

local GEnv = (getgenv and getgenv()) or _G
if GEnv.HoloSpotify5D_Cleanup then
	pcall(GEnv.HoloSpotify5D_Cleanup)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local SoundService = game:GetService("SoundService")
local UIS = game:GetService("UserInputService")

local LP = Players.LocalPlayer
local PlayerGui = LP:WaitForChild("PlayerGui")
local Cam = workspace.CurrentCamera

local getasset = getcustomasset or getsynasset
local writef, readf, isf, delf = writefile, readfile, isfile, delfile

GEnv.HoloSpotify5D_Files = GEnv.HoloSpotify5D_Files or {}

-- Varredura garantida de instâncias e arquivos órfãos de execuções anteriores
local function SweepOrphans()
	for _, s in ipairs(SoundService:GetChildren()) do
		if s.Name == "Holo5D_AudioEngine" then
			pcall(function() s:Stop() s:Destroy() end)
		end
	end
	if workspace.CurrentCamera then
		for _, c in ipairs(workspace.CurrentCamera:GetChildren()) do
			if c.Name == "Holo5D_Hub_V81" or c.Name == "Holo5D_Hub_V82" or c.Name == "Holo5D_Hub_V83" then
				pcall(function() c:Destroy() end)
			end
		end
	end
	for _, g in ipairs(PlayerGui:GetChildren()) do
		if g.Name == "Holo5D_ToggleGui" then
			pcall(function() g:Destroy() end)
		end
	end
	if LP.Character then
		for _, d in ipairs(LP.Character:GetDescendants()) do
			if d.Name == "Holo5D_CharLight" then
				pcall(function() d:Destroy() end)
			end
		end
	end
	if delf and isf and type(GEnv.HoloSpotify5D_Files) == "table" then
		for fname in pairs(GEnv.HoloSpotify5D_Files) do
			pcall(function()
				if isf(fname) then delf(fname) end
			end)
			GEnv.HoloSpotify5D_Files[fname] = nil
		end
	end
end
SweepOrphans()

local DefaultFOV = Cam and Cam.FieldOfView or 70
local IsDestroyed = false
local Conns, Tweens = {}, {}
local Cache, CacheOrder = {}, {}
local MAX_CACHE = 15

local Playlist = {}
local CardRefs = {}
local CurIdx = nil
local CurrentTrack = nil -- { Url, Key, Title, Artist, Source }
local ReqId = 0
local SearchTk = 0
local AutoNextLock = false
local State = "STOPPED" -- STOPPED | LOADING | PLAYING | PAUSED
local ActiveSource = "ALL"
local HubOpen = true
local Vol = 0.8
local FX = { bass = false, night = false, slow = false, fov = true }

local Theme = {
	Bg = Color3.fromRGB(10, 12, 18),
	Card = Color3.fromRGB(18, 22, 34),
	CardActive = Color3.fromRGB(22, 42, 40),
	Cyan = Color3.fromRGB(0, 240, 255),
	Green = Color3.fromRGB(29, 185, 84),
	Pink = Color3.fromRGB(255, 45, 135),
	Purple = Color3.fromRGB(145, 70, 255),
	Text = Color3.fromRGB(245, 248, 255),
	Sub = Color3.fromRGB(155, 165, 185)
}

local function TrackConn(c)
	if IsDestroyed then pcall(function() c:Disconnect() end) return c end
	table.insert(Conns, c)
	return c
end

local function SafeTween(inst, info, props)
	if IsDestroyed or not inst then return nil end
	local tw = TweenService:Create(inst, info, props)
	table.insert(Tweens, tw)
	tw:Play()
	return tw
end

-- ==============================================================================
-- 1. HTTP & HASH DUPLO 32-BIT (IDENTIFICADOR, NÃO CRIPTOGRÁFICO)
-- ==============================================================================
local function HttpGet(url, timeout)
	if IsDestroyed then return nil end
	local done, res = false, nil
	task.spawn(function()
		local ok, body = pcall(function() return game:HttpGet(url) end)
		if (not ok or not body or #body == 0) then
			local req = request or http_request or (syn and syn.request) or (http and http.request)
			if req then
				local rok, r = pcall(function()
					return req({ Url = url, Method = "GET", Headers = { ["User-Agent"] = "Mozilla/5.0" } })
				end)
				if rok and r and r.Body then body = r.Body end
			end
		end
		if not done then res = body; done = true end
	end)
	local t0 = os.clock()
	while not done and not IsDestroyed and (os.clock() - t0) < (timeout or 7) do
		task.wait(0.04)
	end
	done = true
	return res
end

-- Hash duplo usado para nomear arquivos; colisões são improváveis, mas não impossíveis.
local function HashKey(s)
	local str = tostring(s or "")
	local h1, h2 = 2166136261, 5381
	for i = 1, #str do
		local b = string.byte(str, i)
		h1 = bit32.bxor(h1, b)
		h1 = (h1 * 16777619) % 4294967296
		h2 = ((h2 * 33) + b) % 4294967296
	end
	return string.format("%08x%08x", h1, h2)
end

-- ==============================================================================
-- 2. VALIDAÇÃO BINÁRIA PROFUNDA DE ÁUDIO (ID3v2 + MPEG FRAME + OGG + RIFF)
-- ==============================================================================
local MPEG_BITRATES = {
	[1] = { -- MPEG1
		[1] = { 0,32,64,96,128,160,192,224,256,288,320,352,384,416,448 },
		[2] = { 0,32,48,56,64,80,96,112,128,160,192,224,256,320,384 },
		[3] = { 0,32,40,48,56,64,80,96,112,128,160,192,224,256,320 }
	},
	[2] = { -- MPEG2 e MPEG2.5
		[1] = { 0,32,48,56,64,80,96,112,128,144,160,176,192,224,256 },
		[2] = { 0,8,16,24,32,40,48,56,64,80,96,112,128,144,160 },
		[3] = { 0,8,16,24,32,40,48,56,64,80,96,112,128,144,160 }
	}
}

local function ParseMpegFrame(bytes, pos)
	if pos < 1 or pos + 3 > #bytes then return nil end
	local b1, b2, b3, b4 = string.byte(bytes, pos, pos + 3)
	if b1 ~= 0xFF or bit32.band(b2, 0xE0) ~= 0xE0 then return nil end

	local versionBits = bit32.rshift(bit32.band(b2, 0x18), 3)
	local layerBits = bit32.rshift(bit32.band(b2, 0x06), 1)
	local bitrateIndex = bit32.rshift(bit32.band(b3, 0xF0), 4)
	local sampleIndex = bit32.rshift(bit32.band(b3, 0x0C), 2)
	if versionBits == 1 or layerBits == 0 or bitrateIndex == 0 or bitrateIndex == 15 or sampleIndex == 3 then
		return nil
	end

	local versionGroup = (versionBits == 3) and 1 or 2
	local layer = 4 - layerBits
	local bitrate = MPEG_BITRATES[versionGroup][layer][bitrateIndex + 1] * 1000
	local sampleRates = { 44100, 48000, 32000 }
	local sampleRate = sampleRates[sampleIndex + 1]
	if versionBits == 2 then
		sampleRate = sampleRate / 2
	elseif versionBits == 0 then
		sampleRate = sampleRate / 4
	end

	local padding = bit32.band(b3, 0x02) ~= 0 and 1 or 0
	local frameLength
	if layer == 1 then
		frameLength = math.floor((12 * bitrate / sampleRate) + padding) * 4
	elseif layer == 3 and versionBits ~= 3 then
		frameLength = math.floor(72 * bitrate / sampleRate) + padding
	else
		frameLength = math.floor(144 * bitrate / sampleRate) + padding
	end
	if frameLength < 4 or pos + frameLength - 1 > #bytes then return nil end

	return {
		length = frameLength,
		version = versionBits,
		layer = layer,
		sampleRate = sampleRate,
		channelMode = bit32.rshift(bit32.band(b4, 0xC0), 6)
	}
end

local function ValidMpegStream(bytes, startPos)
	local scanEnd = math.min(#bytes - 3, startPos + 4096)
	for pos = startPos, scanEnd do
		local first = ParseMpegFrame(bytes, pos)
		if first then
			local secondPos = pos + first.length
			local second = ParseMpegFrame(bytes, secondPos)
			if second
				and first.version == second.version
				and first.layer == second.layer
				and first.sampleRate == second.sampleRate then
				return true
			end
		end
	end
	return false
end

local function ValidAudio(bytes)
	if type(bytes) ~= "string" or #bytes < 128 then return false end

	local headSample = bytes:sub(1, 256):lower()
	local trimmed = headSample:match("^%s*(.*)") or ""
	if trimmed:sub(1, 1) == "<" or trimmed:sub(1, 1) == "{" or trimmed:sub(1, 1) == "[" then
		return false
	end
	if headSample:find("cloudflare", 1, true)
		or headSample:find("access denied", 1, true)
		or headSample:find("403 forbidden", 1, true)
		or headSample:find("not found", 1, true)
		or headSample:find("rate limit", 1, true) then
		return false
	end

	-- Ogg: valida a assinatura e a versão do cabeçalho de página.
	if bytes:sub(1, 4) == "OggS" and string.byte(bytes, 5) == 0 then
		return true
	end

	-- WAV: valida RIFF/WAVE e o tamanho declarado do contêiner.
	if bytes:sub(1, 4) == "RIFF" and bytes:sub(9, 12) == "WAVE" then
		local b1, b2, b3, b4 = string.byte(bytes, 5, 8)
		local declaredSize = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
		return declaredSize >= 36 and declaredSize <= (#bytes - 8)
	end

	local scanStart = 1
	if bytes:sub(1, 3) == "ID3" then
		if #bytes < 10 then return false end
		local major, flags = string.byte(bytes, 4, 5)
		local b7, b8, b9, b10 = string.byte(bytes, 7, 10)
		if not major or major < 2 or major > 4 then return false end
		if bit32.band(b7, 0x80) ~= 0 or bit32.band(b8, 0x80) ~= 0
			or bit32.band(b9, 0x80) ~= 0 or bit32.band(b10, 0x80) ~= 0 then
			return false
		end
		local id3Size = b7 * 2097152 + b8 * 16384 + b9 * 128 + b10
		scanStart = 11 + id3Size
		if major == 4 and bit32.band(flags, 0x10) ~= 0 then
			scanStart = scanStart + 10 -- footer ID3v2.4
		end
		if scanStart > #bytes - 4 then return false end
	end

	return ValidMpegStream(bytes, scanStart)
end

local function AudioExtension(bytes)
	if bytes:sub(1, 4) == "OggS" then return "ogg" end
	if bytes:sub(1, 4) == "RIFF" and bytes:sub(9, 12) == "WAVE" then return "wav" end
	return "mp3"
end

-- ==============================================================================
-- 3. SISTEMA DE CACHE LRU REAL COM VERIFICAÇÃO DE INTEGRIDADE NO DISCO
-- ==============================================================================
local function TouchCacheLRU(url)
	for i = #CacheOrder, 1, -1 do
		if CacheOrder[i].url == url then
			local item = table.remove(CacheOrder, i)
			table.insert(CacheOrder, item)
			return
		end
	end
end

local function InvalidateCacheEntry(url)
	local entry = Cache[url]
	if entry then
		if entry.file and delf and isf then
			pcall(function()
				if isf(entry.file) then delf(entry.file) end
			end)
			GEnv.HoloSpotify5D_Files[entry.file] = nil
		end
		Cache[url] = nil
	end
	for i = #CacheOrder, 1, -1 do
		if CacheOrder[i].url == url then
			table.remove(CacheOrder, i)
		end
	end
end

local function GetVerifiedCachedAsset(url)
	local entry = Cache[url]
	if not entry or not entry.file or not entry.asset then return nil end
	if not isf or not readf then
		InvalidateCacheEntry(url)
		return nil
	end
	local ok, valid = pcall(function()
		if not isf(entry.file) then return false end
		local content = readf(entry.file)
		if type(content) ~= "string" or #content ~= entry.size then return false end
		return ValidAudio(content)
	end)
	if ok and valid then
		TouchCacheLRU(url)
		return entry.asset
	else
		InvalidateCacheEntry(url)
		return nil
	end
end

local function DownloadAndCacheAsset(url)
	if IsDestroyed or not getasset or not writef or not isf or not readf then return nil end
	local cached = GetVerifiedCachedAsset(url)
	if cached then return cached end

	local bytes = HttpGet(url, 9)
	if IsDestroyed or not ValidAudio(bytes) then return nil end

	local fname = "HoloV83_" .. HashKey(url) .. "." .. AudioExtension(bytes)
	local wok = pcall(function() writef(fname, bytes) end)
	if not wok or IsDestroyed then
		if delf then pcall(function() if isf(fname) then delf(fname) end end) end
		return nil
	end
	GEnv.HoloSpotify5D_Files[fname] = true

	local diskOk = false
	pcall(function()
		if not IsDestroyed and isf(fname) then
			local check = readf(fname)
			diskOk = type(check) == "string"
				and #check == #bytes
				and ValidAudio(check)
		end
	end)
	if IsDestroyed or not diskOk then
		if delf then pcall(function() if isf(fname) then delf(fname) end end) end
		GEnv.HoloSpotify5D_Files[fname] = nil
		return nil
	end

	local aok, asset = pcall(function() return getasset(fname) end)
	if IsDestroyed or not aok or not asset or asset == "" then
		if delf then pcall(function() if isf(fname) then delf(fname) end end) end
		GEnv.HoloSpotify5D_Files[fname] = nil
		return nil
	end

	Cache[url] = { asset = asset, file = fname, size = #bytes }
	table.insert(CacheOrder, { url = url, file = fname })

	while #CacheOrder > MAX_CACHE do
		local oldest = table.remove(CacheOrder, 1)
		if oldest and oldest.url then
			local oldEntry = Cache[oldest.url]
			Cache[oldest.url] = nil
			if oldEntry and oldEntry.file then
				GEnv.HoloSpotify5D_Files[oldEntry.file] = nil
				if delf then
					pcall(function()
						if isf(oldEntry.file) then delf(oldEntry.file) end
					end)
				end
			end
		end
	end

	if IsDestroyed then
		InvalidateCacheEntry(url)
		return nil
	end
	return asset
end

-- ==============================================================================
-- 4. NORMALIZAÇÃO & MOTOR DE RELEVÂNCIA V8.2 (COM FALLBACK EM 2 CAMADAS)
-- ==============================================================================
local CharMap = {
	["á"]="a",["à"]="a",["ã"]="a",["â"]="a",["ä"]="a",["é"]="e",["è"]="e",["ê"]="e",["ë"]="e",
	["í"]="i",["ì"]="i",["î"]="i",["ï"]="i",["ó"]="o",["ò"]="o",["õ"]="o",["ô"]="o",["ö"]="o",
	["ú"]="u",["ù"]="u",["û"]="u",["ü"]="u",["ç"]="c",["ñ"]="n",
	["Á"]="a",["À"]="a",["Ã"]="a",["Â"]="a",["É"]="e",["Ê"]="e",["Í"]="i",["Ó"]="o",["Õ"]="o",["Ô"]="o",["Ú"]="u",["Ç"]="c"
}

local StopWords = {
	["feat"] = true, ["ft"] = true, ["prod"] = true, ["by"] = true,
	["official"] = true, ["audio"] = true, ["video"] = true, ["music"] = true,
	["lyrics"] = true, ["lyric"] = true, ["hd"] = true, ["hq"] = true,
	["the"] = true, ["de"] = true, ["da"] = true, ["do"] = true
}

local function CleanText(str)
	local s = tostring(str or "")
	s = s:gsub("&amp;", "&"):gsub("&quot;", '"'):gsub("&#34;", '"')
	s = s:gsub("&#39;", "'"):gsub("&#039;", "'"):gsub("&apos;", "'")
	s = s:gsub("&#91;", "["):gsub("&#93;", "]")
	s = s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&nbsp;", " ")
	s = s:gsub("\\_", "_"):gsub("\\%*", "*")
	s = s:gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
	return s
end

local function Norm(str)
	local s = CleanText(str)
	for k, v in pairs(CharMap) do s = s:gsub(k, v) end
	s = s:lower():gsub("[^%w%s]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
	return s
end

local function TokenizeQuery(str)
	local all, core = {}, {}
	for w in Norm(str):gmatch("%S+") do
		if #w >= 2 or tonumber(w) then
			table.insert(all, w)
			if not StopWords[w] then
				table.insert(core, w)
			end
		end
	end
	return (#core > 0 and core or all)
end

local function CanonicalKey(title, artist)
	local nt = Norm(title)
		:gsub("%b()", " ")
		:gsub("%f[%w]official%f[%W]", " ")
		:gsub("%f[%w]audio%f[%W]", " ")
		:gsub("%f[%w]video%f[%W]", " ")
		:gsub("%f[%w]lyrics%f[%W]", " ")
		:gsub("%f[%w]hd%f[%W]", " ")
		:gsub("%s+", " ")
		:match("^%s*(.-)%s*$") or ""
	local na = Norm(artist)
	return nt .. "::" .. na
end

local AltTags = {
	"remix", "cover", "bootleg", "mashup", "rework", "edit", "vip",
	"slowed", "sped up", "nightcore", "8d", "karaoke", "instrumental", "live", "acoustic", "flip", "tribute"
}

local function DetectAltVersion(normTitle, normArtist)
	local full = normTitle .. " " .. normArtist
	for _, tag in ipairs(AltTags) do
		if full:find("%f[%w]" .. tag .. "%f[%W]") then
			return tag:upper()
		end
	end
	return "ORIGINAL"
end

local function WordOrPrefixMatch(text, token)
	if text:find("%f[%w]" .. token .. "%f[%W]") then
		return 2 -- palavra exata
	end
	if #token >= 4 and text:find("%f[%w]" .. token) then
		return 1 -- prefixo de palavra (ex: "weeknd" / "weekend" ou abreviações)
	end
	return 0
end

local function ScoreTrackV82(rawQuery, rawTitle, rawArtist)
	local nq = Norm(rawQuery)
	local nt = Norm(rawTitle)
	local na = Norm(rawArtist)
	local combined = nt .. " " .. na
	local qTokens = TokenizeQuery(rawQuery)
	if #qTokens == 0 then return 0, "ORIGINAL", 0 end

	local matchedWeight = 0
	local matchedInTitle = 0
	local matchedInArtist = 0

	for _, qt in ipairs(qTokens) do
		local mt = WordOrPrefixMatch(nt, qt)
		local ma = WordOrPrefixMatch(na, qt)
		if mt == 2 then
			matchedWeight = matchedWeight + 1.0
			matchedInTitle = matchedInTitle + 1
		elseif ma == 2 then
			matchedWeight = matchedWeight + 1.0
			matchedInArtist = matchedInArtist + 1
		elseif mt == 1 then
			matchedWeight = matchedWeight + 0.75
			matchedInTitle = matchedInTitle + 1
		elseif ma == 1 then
			matchedWeight = matchedWeight + 0.75
			matchedInArtist = matchedInArtist + 1
		elseif #qt >= 4 and combined:find(qt, 1, true) then
			matchedWeight = matchedWeight + 0.55
		end
	end

	local coverage = matchedWeight / #qTokens
	local hasPhrase = (nt:find(nq, 1, true) ~= nil)
		or (combined:find(nq, 1, true) ~= nil)
		or ((na .. " " .. nt):find(nq, 1, true) ~= nil)
	local crossMatch = (matchedInTitle > 0 and matchedInArtist > 0)

	local tier = 0
	if hasPhrase or crossMatch or coverage >= 0.55 then
		tier = 2 -- Alta precisão
	elseif coverage >= 0.30 or matchedInTitle >= 1 then
		tier = 1 -- Segunda camada (fallback se houver poucos resultados)
	else
		return 0, "ORIGINAL", 0
	end

	local score = (coverage * 100) + (matchedInTitle * 26) + (matchedInArtist * 24)
	if crossMatch then score = score + 65 end
	if nt == nq then
		score = score + 130
	elseif nt:sub(1, #nq) == nq then
		score = score + 80
	elseif hasPhrase then
		score = score + 55
	end

	local ver = DetectAltVersion(nt, na)
	local userAskedAlt = false
	for _, tag in ipairs(AltTags) do
		if nq:find("%f[%w]" .. tag .. "%f[%W]") then
			userAskedAlt = true
			if ver == tag:upper() then score = score + 65 end
		end
	end

	if not userAskedAlt then
		if ver == "ORIGINAL" then
			score = score + 45
		elseif ver == "KARAOKE" or ver == "INSTRUMENTAL" or ver == "TRIBUTE" then
			score = score - 60
		else
			score = score - 25
		end
	end

	return score, ver, tier
end

-- ==============================================================================
-- 5. APIS MULTI-PLATAFORMA (AUDIUS + DEEZER + HEARTHIS)
-- ==============================================================================
local AudiusHost = nil
local function GetAudiusHost()
	if AudiusHost then return AudiusHost end
	local raw = HttpGet("https://api.audius.co", 5)
	if raw then
		local ok, dec = pcall(function() return HttpService:JSONDecode(raw) end)
		if ok and dec and type(dec.data) == "table" and #dec.data > 0 then
			AudiusHost = dec.data[1]
			return AudiusHost
		end
	end
	return "https://discoveryprovider.audius.co"
end

local function FetchAudius(q)
	local out = {}
	local enc = HttpService:UrlEncode(q)
	local hosts = { GetAudiusHost(), "https://discoveryprovider2.audius.co", "https://discoveryprovider3.audius.co" }
	for _, h in ipairs(hosts) do
		if IsDestroyed then break end
		local raw = HttpGet(h .. "/v1/tracks/search?query=" .. enc .. "&app_name=HoloSpotify5DV83", 6)
		if raw then
			local ok, dec = pcall(function() return HttpService:JSONDecode(raw) end)
			if ok and dec and type(dec.data) == "table" and #dec.data > 0 then
				AudiusHost = h
				for i = 1, math.min(25, #dec.data) do
					local tr = dec.data[i]
					if tr and tr.id and tr.title then
						local title = CleanText(tr.title)
						local artist = CleanText((tr.user and (tr.user.name or tr.user.handle)) or "Audius Artist")
						local sc, ver, tier = ScoreTrackV82(q, title, artist)
						if tier > 0 then
							table.insert(out, {
								Title = title,
								Artist = artist,
								Dur = tonumber(tr.duration) or 0,
								Url = h .. "/v1/tracks/" .. tostring(tr.id) .. "/stream?app_name=HoloSpotify5DV83",
								Key = CanonicalKey(title, artist),
								Source = "AUDIUS",
								Ver = ver,
								Score = sc,
								Tier = tier
							})
						end
					end
				end
				break
			end
		end
	end
	return out
end

local function FetchDeezer(q)
	local out = {}
	local raw = HttpGet("https://api.deezer.com/search?q=" .. HttpService:UrlEncode(q) .. "&limit=25", 6)
	if raw then
		local ok, dec = pcall(function() return HttpService:JSONDecode(raw) end)
		if ok and dec and type(dec.data) == "table" then
			for _, tr in ipairs(dec.data) do
				if tr and tr.preview and tr.preview ~= "" then
					local title = CleanText(tr.title or tr.title_short or "Faixa")
					local artist = CleanText((tr.artist and tr.artist.name) or "Artista")
					local sc, ver, tier = ScoreTrackV82(q, title, artist)
					if tier > 0 then
						table.insert(out, {
							Title = title,
							Artist = artist,
							Dur = 30,
							Url = tr.preview,
							Key = CanonicalKey(title, artist),
							Source = "DEEZER",
							Ver = ver,
							Score = sc + 12,
							Tier = tier
						})
					end
				end
			end
		end
	end
	return out
end

local function FetchHearThis(q)
	local out = {}
	local raw = HttpGet("https://api-v2.hearthis.at/search/?t=" .. HttpService:UrlEncode(q) .. "&page=1&count=25", 6)
	if raw then
		local ok, dec = pcall(function() return HttpService:JSONDecode(raw) end)
		if ok and type(dec) == "table" then
			for _, tr in ipairs(dec) do
				if type(tr) == "table" and tr.stream_url and tr.stream_url ~= "" then
					local title = CleanText(tr.title or "Track")
					local artist = CleanText((tr.user and tr.user.username) or "Creator")
					local sc, ver, tier = ScoreTrackV82(q, title, artist)
					if tier > 0 then
						table.insert(out, {
							Title = title,
							Artist = artist,
							Dur = tonumber(tr.duration) or 0,
							Url = tr.stream_url,
							Key = CanonicalKey(title, artist),
							Source = "HEARTHIS",
							Ver = ver,
							Score = sc,
							Tier = tier
						})
					end
				end
			end
		end
	end
	return out
end

-- ==============================================================================
-- 6. MOTOR DE ÁUDIO 5D & EFEITOS EXCLUSIVOS
-- ==============================================================================
local Sound = Instance.new("Sound")
Sound.Name = "Holo5D_AudioEngine"
Sound.Volume = Vol
Sound.Looped = false
Sound.Parent = SoundService

local BassFX = Instance.new("EqualizerSoundEffect", Sound)
BassFX.Enabled = false

local ReverbFX = Instance.new("ReverbSoundEffect", Sound)
ReverbFX.DecayTime = 2.6
ReverbFX.WetLevel = -4
ReverbFX.Enabled = false

local CharLight = nil
local function EnsureCharLight()
	if IsDestroyed then return nil end
	local ch = LP.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if hrp and (not CharLight or CharLight.Parent ~= hrp) then
		if CharLight then pcall(function() CharLight:Destroy() end) end
		CharLight = Instance.new("PointLight")
		CharLight.Name = "Holo5D_CharLight"
		CharLight.Color = Theme.Cyan
		CharLight.Range = 14
		CharLight.Brightness = 0
		CharLight.Parent = hrp
	end
	return CharLight
end

local function SyncFX()
	if IsDestroyed then return end
	BassFX.Enabled = FX.bass
	BassFX.LowGain = FX.bass and 10 or 0
	BassFX.MidGain = FX.bass and -2 or 0

	if FX.night then
		Sound.PlaybackSpeed = 1.25
		ReverbFX.Enabled = false
	elseif FX.slow then
		Sound.PlaybackSpeed = 0.82
		ReverbFX.Enabled = true
	else
		Sound.PlaybackSpeed = 1.0
		ReverbFX.Enabled = false
	end

	if not FX.fov and Cam then
		Cam.FieldOfView = DefaultFOV
	end
end

-- ==============================================================================
-- 7. ARQUITETURA HOLOGRÁFICA 5D (2 TELAS CURVAS PRÓXIMAS + ANEL TORUS REAL)
-- ==============================================================================
local ToggleGui = Instance.new("ScreenGui")
ToggleGui.Name = "Holo5D_ToggleGui"
ToggleGui.ResetOnSpawn = false
ToggleGui.Parent = PlayerGui

local MiniBtn = Instance.new("TextButton")
MiniBtn.Size = UDim2.new(0, 145, 0, 34)
MiniBtn.Position = UDim2.new(0.5, -72, 0, 10)
MiniBtn.BackgroundColor3 = Theme.Card
MiniBtn.TextColor3 = Theme.Cyan
MiniBtn.Font = Enum.Font.GothamBold
MiniBtn.TextSize = 12
MiniBtn.Text = "◈ ABRIR HOLO 5D [H]"
MiniBtn.Visible = false
MiniBtn.Parent = ToggleGui
Instance.new("UICorner", MiniBtn).CornerRadius = UDim.new(1, 0)
local MiniStroke = Instance.new("UIStroke", MiniBtn)
MiniStroke.Color = Theme.Cyan
MiniStroke.Thickness = 1.5

local HoloFolder = Instance.new("Folder")
HoloFolder.Name = "Holo5D_Hub_V83"
HoloFolder.Parent = Cam

local ScreenSize = Vector3.new(3.6, 2.65, 0.04)
local CanvasSize = Vector2.new(600, 460)

local function MakeScreen(name, borderCol)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = ScreenSize
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Parent = HoloFolder

	local sg = Instance.new("SurfaceGui")
	sg.Name = name .. "_GUI"
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	sg.CanvasSize = CanvasSize
	sg.AlwaysOnTop = true
	sg.LightInfluence = 0
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Adornee = p
	sg.Parent = ToggleGui

	local main = Instance.new("Frame")
	main.Size = UDim2.new(1, -12, 1, -12)
	main.Position = UDim2.new(0, 6, 0, 6)
	main.BackgroundColor3 = Theme.Bg
	main.BackgroundTransparency = 0.08
	main.Parent = sg
	Instance.new("UICorner", main).CornerRadius = UDim.new(0, 16)

	local st = Instance.new("UIStroke", main)
	st.Color = borderCol
	st.Thickness = 2.2
	st.Transparency = 0.15

	return p, sg, main, st
end

local LPart, LGui, LMain, LStroke = MakeScreen("LeftScreen", Theme.Cyan)
local RPart, RGui, RMain, RStroke = MakeScreen("RightScreen", Theme.Green)

local Core = Instance.new("Part")
Core.Name = "HoloCore5D"
Core.Shape = Enum.PartType.Ball
Core.Size = Vector3.new(0.32, 0.32, 0.32)
Core.Material = Enum.Material.Neon
Core.Color = Theme.Cyan
Core.Anchored, Core.CanCollide, Core.CanQuery, Core.CanTouch = true, false, false, false
Core.Parent = HoloFolder

local Ring = Instance.new("Part")
Ring.Name = "HoloRing5D"
Ring.Size = Vector3.new(1, 1, 1)
Ring.Material = Enum.Material.Neon
Ring.Color = Theme.Pink
Ring.Transparency = 0.2
Ring.Anchored, Ring.CanCollide, Ring.CanQuery, Ring.CanTouch = true, false, false, false
Ring.Parent = HoloFolder

local RingMesh = Instance.new("SpecialMesh", Ring)
RingMesh.MeshType = Enum.MeshType.FileMesh
RingMesh.MeshId = "rbxassetid://3270017"
RingMesh.Scale = Vector3.new(0.65, 0.65, 0.12)

local function ToggleHub(forceState)
	if IsDestroyed then return end
	if type(forceState) == "boolean" then
		HubOpen = forceState
	else
		HubOpen = not HubOpen
	end
	LGui.Enabled = HubOpen
	RGui.Enabled = HubOpen
	Core.Transparency = HubOpen and 0 or 1
	Ring.Transparency = HubOpen and 0.2 or 1
	MiniBtn.Visible = not HubOpen
end
MiniBtn.MouseButton1Click:Connect(function() ToggleHub(true) end)
TrackConn(UIS.InputBegan:Connect(function(inp, gpe)
	if not gpe and inp.KeyCode == Enum.KeyCode.H then
		ToggleHub()
	end
end))

-- ==============================================================================
-- 8. TELA ESQUERDA (PLAYER + VISUALIZADOR + CONTROLES + ESTÚDIO 5D)
-- ==============================================================================
local TopBar = Instance.new("Frame", LMain)
TopBar.Size = UDim2.new(1, -28, 0, 34)
TopBar.Position = UDim2.new(0, 14, 0, 12)
TopBar.BackgroundTransparency = 1

local Brand = Instance.new("TextLabel", TopBar)
Brand.Size = UDim2.new(0.65, 0, 1, 0)
Brand.BackgroundTransparency = 1
Brand.Font = Enum.Font.GothamBlack
Brand.Text = "◈ HOLO-SPOTIFY 5D V8.2"
Brand.TextColor3 = Theme.Cyan
Brand.TextSize = 17
Brand.TextXAlignment = Enum.TextXAlignment.Left

local CloseBtn = Instance.new("TextButton", TopBar)
CloseBtn.Size = UDim2.new(0, 95, 0, 28)
CloseBtn.Position = UDim2.new(1, -95, 0, 3)
CloseBtn.BackgroundColor3 = Color3.fromRGB(35, 20, 30)
CloseBtn.TextColor3 = Theme.Pink
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 11
CloseBtn.Text = "FECHAR [H]"
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 8)
CloseBtn.MouseButton1Click:Connect(function() ToggleHub(false) end)

local InfoBox = Instance.new("Frame", LMain)
InfoBox.Size = UDim2.new(1, -28, 0, 74)
InfoBox.Position = UDim2.new(0, 14, 0, 50)
InfoBox.BackgroundColor3 = Theme.Card
Instance.new("UICorner", InfoBox).CornerRadius = UDim.new(0, 12)

local TrackTitle = Instance.new("TextLabel", InfoBox)
TrackTitle.Size = UDim2.new(1, -20, 0, 26)
TrackTitle.Position = UDim2.new(0, 10, 0, 8)
TrackTitle.BackgroundTransparency = 1
TrackTitle.Font = Enum.Font.GothamBlack
TrackTitle.Text = "Nenhuma música selecionada"
TrackTitle.TextColor3 = Theme.Text
TrackTitle.TextSize = 16
TrackTitle.TextXAlignment = Enum.TextXAlignment.Left
TrackTitle.TextTruncate = Enum.TextTruncate.AtEnd

local TrackSub = Instance.new("TextLabel", InfoBox)
TrackSub.Size = UDim2.new(1, -20, 0, 18)
TrackSub.Position = UDim2.new(0, 10, 0, 34)
TrackSub.BackgroundTransparency = 1
TrackSub.Font = Enum.Font.GothamMedium
TrackSub.Text = "Pesquise na tela direita (Audius / Deezer / HearThis)"
TrackSub.TextColor3 = Theme.Sub
TrackSub.TextSize = 12
TrackSub.TextXAlignment = Enum.TextXAlignment.Left
TrackSub.TextTruncate = Enum.TextTruncate.AtEnd

local StatusLbl = Instance.new("TextLabel", InfoBox)
StatusLbl.Size = UDim2.new(1, -20, 0, 16)
StatusLbl.Position = UDim2.new(0, 10, 0, 54)
StatusLbl.BackgroundTransparency = 1
StatusLbl.Font = Enum.Font.Code
StatusLbl.Text = "ESTADO: PRONTO"
StatusLbl.TextColor3 = Theme.Green
StatusLbl.TextSize = 11
StatusLbl.TextXAlignment = Enum.TextXAlignment.Left

local VisFrame = Instance.new("Frame", LMain)
VisFrame.Size = UDim2.new(1, -28, 0, 68)
VisFrame.Position = UDim2.new(0, 14, 0, 132)
VisFrame.BackgroundColor3 = Color3.fromRGB(12, 15, 24)
Instance.new("UICorner", VisFrame).CornerRadius = UDim.new(0, 10)

local Bars = {}
for i = 1, 28 do
	local b = Instance.new("Frame", VisFrame)
	b.AnchorPoint = Vector2.new(0, 1)
	b.Position = UDim2.new((i - 1) / 28 + 0.008, 0, 0.9, 0)
	b.Size = UDim2.new(1 / 28 - 0.014, 0, 0.1, 0)
	b.BackgroundColor3 = Theme.Cyan:Lerp(Theme.Pink, i / 28)
	b.BorderSizePixel = 0
	Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
	Bars[i] = b
end

local ProgBg = Instance.new("TextButton", LMain)
ProgBg.Size = UDim2.new(1, -28, 0, 12)
ProgBg.Position = UDim2.new(0, 14, 0, 210)
ProgBg.BackgroundColor3 = Color3.fromRGB(32, 38, 54)
ProgBg.Text = ""
Instance.new("UICorner", ProgBg).CornerRadius = UDim.new(1, 0)

local ProgFill = Instance.new("Frame", ProgBg)
ProgFill.Size = UDim2.new(0, 0, 1, 0)
ProgFill.BackgroundColor3 = Theme.Green
Instance.new("UICorner", ProgFill).CornerRadius = UDim.new(1, 0)

local TimeLbl = Instance.new("TextLabel", LMain)
TimeLbl.Size = UDim2.new(1, -28, 0, 16)
TimeLbl.Position = UDim2.new(0, 14, 0, 224)
TimeLbl.BackgroundTransparency = 1
TimeLbl.Font = Enum.Font.Code
TimeLbl.Text = "00:00 / 00:00  (Clique na barra para +10s)"
TimeLbl.TextColor3 = Theme.Sub
TimeLbl.TextSize = 11

ProgBg.MouseButton1Click:Connect(function()
	if (State == "PLAYING" or State == "PAUSED") and Sound.IsLoaded and Sound.TimeLength > 1 then
		local target = Sound.TimePosition + 10
		if target >= Sound.TimeLength - 0.6 then
			target = math.max(0, Sound.TimeLength - 1.0)
		end
		Sound.TimePosition = target
	end
end)

local CtrlRow = Instance.new("Frame", LMain)
CtrlRow.Size = UDim2.new(1, -28, 0, 44)
CtrlRow.Position = UDim2.new(0, 14, 0, 246)
CtrlRow.BackgroundTransparency = 1

local function MakeBtn(txt, xScale, wScale, bg, fg)
	local b = Instance.new("TextButton", CtrlRow)
	b.Size = UDim2.new(wScale, -6, 1, 0)
	b.Position = UDim2.new(xScale, 3, 0, 0)
	b.BackgroundColor3 = bg
	b.TextColor3 = fg
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.Text = txt
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
	return b
end

local PrevBtn = MakeBtn("⏮ ANT", 0.00, 0.22, Theme.Card, Theme.Text)
local PlayBtn = MakeBtn("▶ PLAY", 0.22, 0.34, Theme.Green, Theme.Bg)
local StopBtn = MakeBtn("⏹ STOP", 0.56, 0.22, Color3.fromRGB(45, 22, 30), Theme.Pink)
local NextBtn = MakeBtn("PRÓX ⏭", 0.78, 0.22, Theme.Card, Theme.Text)

local VolRow = Instance.new("Frame", LMain)
VolRow.Size = UDim2.new(1, -28, 0, 34)
VolRow.Position = UDim2.new(0, 14, 0, 298)
VolRow.BackgroundTransparency = 1

local VolDown = Instance.new("TextButton", VolRow)
VolDown.Size = UDim2.new(0.18, 0, 1, 0)
VolDown.BackgroundColor3 = Theme.Card
VolDown.TextColor3 = Theme.Text
VolDown.Font = Enum.Font.GothamBold
VolDown.TextSize = 13
VolDown.Text = "VOL -"
Instance.new("UICorner", VolDown).CornerRadius = UDim.new(0, 8)

local VolLbl = Instance.new("TextLabel", VolRow)
VolLbl.Size = UDim2.new(0.38, 0, 1, 0)
VolLbl.Position = UDim2.new(0.19, 0, 0, 0)
VolLbl.BackgroundTransparency = 1
VolLbl.Font = Enum.Font.GothamBold
VolLbl.Text = "VOLUME: 80%"
VolLbl.TextColor3 = Theme.Cyan
VolLbl.TextSize = 13

local VolUp = Instance.new("TextButton", VolRow)
VolUp.Size = UDim2.new(0.18, 0, 1, 0)
VolUp.Position = UDim2.new(0.58, 0, 0, 0)
VolUp.BackgroundColor3 = Theme.Card
VolUp.TextColor3 = Theme.Text
VolUp.Font = Enum.Font.GothamBold
VolUp.TextSize = 13
VolUp.Text = "VOL +"
Instance.new("UICorner", VolUp).CornerRadius = UDim.new(0, 8)

local ZoomBtn = Instance.new("TextButton", VolRow)
ZoomBtn.Size = UDim2.new(0.22, 0, 1, 0)
ZoomBtn.Position = UDim2.new(0.78, 0, 0, 0)
ZoomBtn.BackgroundColor3 = Theme.Card
ZoomBtn.TextColor3 = Theme.Purple
ZoomBtn.Font = Enum.Font.GothamBold
ZoomBtn.TextSize = 12
ZoomBtn.Text = "DIST: 1x"
Instance.new("UICorner", ZoomBtn).CornerRadius = UDim.new(0, 8)

VolDown.MouseButton1Click:Connect(function()
	Vol = math.clamp(Vol - 0.1, 0, 2)
	Sound.Volume = Vol
	VolLbl.Text = string.format("VOLUME: %d%%", math.floor(Vol * 100 + 0.5))
end)
VolUp.MouseButton1Click:Connect(function()
	Vol = math.clamp(Vol + 0.1, 0, 2)
	Sound.Volume = Vol
	VolLbl.Text = string.format("VOLUME: %d%%", math.floor(Vol * 100 + 0.5))
end)

local dist = -3.2
ZoomBtn.MouseButton1Click:Connect(function()
	if dist == -3.2 then
		dist = -2.4; ZoomBtn.Text = "DIST: 2x"
	elseif dist == -2.4 then
		dist = -4.2; ZoomBtn.Text = "DIST: 0.7x"
	else
		dist = -3.2; ZoomBtn.Text = "DIST: 1x"
	end
end)

local FXGrid = Instance.new("Frame", LMain)
FXGrid.Size = UDim2.new(1, -28, 0, 96)
FXGrid.Position = UDim2.new(0, 14, 0, 340)
FXGrid.BackgroundTransparency = 1

local FXBtns = {}
local function RefreshFXButtons()
	local map = {
		bass = { "BASS BOOST", Theme.Pink },
		night = { "NIGHTCORE", Theme.Cyan },
		slow = { "SLOWED 5D", Theme.Purple },
		fov = { "PULSO 5D", Theme.Green }
	}
	for k, btn in pairs(FXBtns) do
		local info = map[k]
		local on = FX[k]
		btn.Text = info[1] .. ": " .. (on and "ON" or "OFF")
		btn.BackgroundColor3 = on and info[2] or Theme.Card
		btn.TextColor3 = on and Theme.Bg or Theme.Text
	end
end

local function MakeFXToggle(label, key, pos, col)
	local b = Instance.new("TextButton", FXGrid)
	b.Size = UDim2.new(0.485, 0, 0, 42)
	b.Position = pos
	b.Font = Enum.Font.GothamBold
	b.TextSize = 12
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
	FXBtns[key] = b
	b.MouseButton1Click:Connect(function()
		FX[key] = not FX[key]
		if key == "night" and FX.night then FX.slow = false end
		if key == "slow" and FX.slow then FX.night = false end
		RefreshFXButtons()
		SyncFX()
	end)
end

MakeFXToggle("BASS BOOST", "bass", UDim2.new(0, 0, 0, 0), Theme.Pink)
MakeFXToggle("NIGHTCORE", "night", UDim2.new(0.515, 0, 0, 0), Theme.Cyan)
MakeFXToggle("SLOWED 5D", "slow", UDim2.new(0, 0, 0, 50), Theme.Purple)
MakeFXToggle("PULSO 5D", "fov", UDim2.new(0.515, 0, 0, 50), Theme.Green)
RefreshFXButtons()

-- ==============================================================================
-- 9. TELA DIREITA (PESQUISA + ABAS + LISTA DE MÚSICAS)
-- ==============================================================================
local SearchBoxFrame = Instance.new("Frame", RMain)
SearchBoxFrame.Size = UDim2.new(1, -28, 0, 42)
SearchBoxFrame.Position = UDim2.new(0, 14, 0, 14)
SearchBoxFrame.BackgroundColor3 = Theme.Card
Instance.new("UICorner", SearchBoxFrame).CornerRadius = UDim.new(0, 10)
local SBStroke = Instance.new("UIStroke", SearchBoxFrame)
SBStroke.Color = Theme.Green
SBStroke.Thickness = 1.5

local SearchInput = Instance.new("TextBox", SearchBoxFrame)
SearchInput.Size = UDim2.new(0.74, -12, 1, 0)
SearchInput.Position = UDim2.new(0, 12, 0, 0)
SearchInput.BackgroundTransparency = 1
SearchInput.Font = Enum.Font.GothamBold
SearchInput.PlaceholderText = "Digite música + artista..."
SearchInput.PlaceholderColor3 = Theme.Sub
SearchInput.Text = ""
SearchInput.TextColor3 = Theme.Text
SearchInput.TextSize = 14
SearchInput.TextXAlignment = Enum.TextXAlignment.Left
SearchInput.ClearTextOnFocus = false

local SearchBtn = Instance.new("TextButton", SearchBoxFrame)
SearchBtn.Size = UDim2.new(0.26, -8, 1, -8)
SearchBtn.Position = UDim2.new(0.74, 4, 0, 4)
SearchBtn.BackgroundColor3 = Theme.Green
SearchBtn.TextColor3 = Theme.Bg
SearchBtn.Font = Enum.Font.GothamBlack
SearchBtn.TextSize = 13
SearchBtn.Text = "BUSCAR"
Instance.new("UICorner", SearchBtn).CornerRadius = UDim.new(0, 8)

local TabRow = Instance.new("Frame", RMain)
TabRow.Size = UDim2.new(1, -28, 0, 30)
TabRow.Position = UDim2.new(0, 14, 0, 62)
TabRow.BackgroundTransparency = 1

local Tabs = {}
local Sources = {
	{ id = "ALL", txt = "🌐 TODAS" },
	{ id = "AUDIUS", txt = "🎵 AUDIUS" },
	{ id = "DEEZER", txt = "💿 DEEZER" },
	{ id = "HEARTHIS", txt = "🎧 HEARTHIS" }
}

local RunSearch -- forward declaration

for i, s in ipairs(Sources) do
	local tb = Instance.new("TextButton", TabRow)
	tb.Size = UDim2.new(0.25, -4, 1, 0)
	tb.Position = UDim2.new((i - 1) * 0.25, 2, 0, 0)
	tb.Font = Enum.Font.GothamBold
	tb.TextSize = 11
	tb.Text = s.txt
	tb.BackgroundColor3 = (s.id == ActiveSource) and Theme.Cyan or Theme.Card
	tb.TextColor3 = (s.id == ActiveSource) and Theme.Bg or Theme.Text
	Instance.new("UICorner", tb).CornerRadius = UDim.new(0, 8)
	Tabs[s.id] = tb

	tb.MouseButton1Click:Connect(function()
		ActiveSource = s.id
		for id, btn in pairs(Tabs) do
			btn.BackgroundColor3 = (id == ActiveSource) and Theme.Cyan or Theme.Card
			btn.TextColor3 = (id == ActiveSource) and Theme.Bg or Theme.Text
		end
		if SearchInput.Text ~= "" and RunSearch then
			RunSearch(SearchInput.Text)
		end
	end)
end

local ResultsScroll = Instance.new("ScrollingFrame", RMain)
ResultsScroll.Size = UDim2.new(1, -28, 1, -108)
ResultsScroll.Position = UDim2.new(0, 14, 0, 98)
ResultsScroll.BackgroundTransparency = 1
ResultsScroll.ScrollBarThickness = 5
ResultsScroll.ScrollBarImageColor3 = Theme.Green
ResultsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
ResultsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

local ListLayout = Instance.new("UIListLayout", ResultsScroll)
ListLayout.Padding = UDim.new(0, 6)
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder

-- ==============================================================================
-- 10. REPRODUÇÃO SINCRONIZADA, AUTO-NEXT BLINDADO E GESTÃO DE FILA
-- ==============================================================================
local function FmtTime(sec)
	sec = math.max(0, math.floor(tonumber(sec) or 0))
	return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end

-- Sincroniza CurIdx e o destaque visual dos cards com a faixa realmente ativa
local function FindTrackIndex(url)
	if not url then return nil end
	for i, item in ipairs(Playlist) do
		if item.Url == url then return i end
	end
	return nil
end

local function SyncPlaylistUI()
	CurIdx = CurrentTrack and FindTrackIndex(CurrentTrack.Url) or nil
	for i, ref in pairs(CardRefs) do
		if ref.card and ref.card.Parent then
			local isCurrent = (CurIdx == i)
			ref.card.BackgroundColor3 = isCurrent and Theme.CardActive or Theme.Card
			if ref.playBtn and ref.playBtn.Parent then
				if isCurrent and State == "LOADING" then
					ref.playBtn.Text = "⏳"
					ref.playBtn.BackgroundColor3 = Theme.Cyan
				elseif isCurrent and State == "PLAYING" then
					ref.playBtn.Text = "🔊"
					ref.playBtn.BackgroundColor3 = Theme.Cyan
				elseif isCurrent and State == "PAUSED" then
					ref.playBtn.Text = "⏸"
					ref.playBtn.BackgroundColor3 = Theme.Purple
				else
					ref.playBtn.Text = "▶"
					ref.playBtn.BackgroundColor3 = Theme.Green
				end
			end
		end
	end
end

local function PlayTrack(target, autoSkipDepth)
	if IsDestroyed then return false end
	local item = type(target) == "table" and target or Playlist[target]
	if not item or not item.Url then return false end

	if not getasset or not writef then
		StatusLbl.Text = "ERRO: EXECUTOR SEM SUPORTE A CUSTOM ASSET"
		StatusLbl.TextColor3 = Theme.Pink
		return false
	end

	ReqId = ReqId + 1
	local myReq = ReqId

	CurrentTrack = {
		Url = item.Url,
		Key = item.Key,
		Title = item.Title,
		Artist = item.Artist,
		Source = item.Source,
		Ver = item.Ver
	}
	State = "LOADING"

	pcall(function() Sound:Stop() end)
	TrackTitle.Text = item.Title
	TrackSub.Text = string.format("%s  •  [%s - %s]", item.Artist, item.Source, item.Ver or "ORIGINAL")
	StatusLbl.Text = "CARREGANDO E VALIDANDO STREAM..."
	StatusLbl.TextColor3 = Theme.Cyan
	PlayBtn.Text = "⏳..."
	SyncPlaylistUI()

	task.spawn(function()
		local asset = GetVerifiedCachedAsset(item.Url)
		local fromCache = (asset ~= nil)
		if not asset then
			asset = DownloadAndCacheAsset(item.Url)
		end

		if IsDestroyed or myReq ~= ReqId then return end

		local function TryLoadIntoEngine(assetUri)
			if not assetUri or IsDestroyed or myReq ~= ReqId then return false end
			Sound:Stop()
			Sound.SoundId = assetUri
			Sound.TimePosition = 0
			Sound.Volume = Vol
			SyncFX()

			local t0 = os.clock()
			while not Sound.IsLoaded and not IsDestroyed and myReq == ReqId
				and Sound.SoundId == assetUri and (os.clock() - t0) < 8 do
				task.wait(0.05)
			end
			if IsDestroyed or myReq ~= ReqId or Sound.SoundId ~= assetUri then return false end
			return (Sound.IsLoaded and Sound.TimeLength > 0.5)
		end

		local loadedOk = TryLoadIntoEngine(asset)

		-- Se veio do cache e falhou no FMOD, invalida e re-baixa 1 vez
		if not loadedOk and fromCache and not IsDestroyed and myReq == ReqId then
			InvalidateCacheEntry(item.Url)
			asset = DownloadAndCacheAsset(item.Url)
			loadedOk = TryLoadIntoEngine(asset)
		end

		if IsDestroyed or myReq ~= ReqId then return end

		if loadedOk then
			Sound:Play()
			State = "PLAYING"
			PlayBtn.Text = "⏸ PAUSE"
			StatusLbl.Text = "TOCANDO AGORA (" .. item.Source .. ")"
			StatusLbl.TextColor3 = Theme.Green
			SyncPlaylistUI()
		else
			InvalidateCacheEntry(item.Url)
			State = "STOPPED"
			PlayBtn.Text = "▶ PLAY"
			StatusLbl.Text = "FALHA NO STREAM — TENTANDO PRÓXIMA..."
			StatusLbl.TextColor3 = Theme.Pink
			SyncPlaylistUI()

			-- Auto-Skip seguro caso uma faixa da fila esteja indisponível
			local depth = (autoSkipDepth or 0) + 1
			if depth <= 3 and #Playlist > 1 and not IsDestroyed and myReq == ReqId then
				task.wait(0.35)
				if not IsDestroyed and myReq == ReqId then
					local currentIdx = FindTrackIndex(item.Url)
					if currentIdx and #Playlist > 1 then
						local nxt = (currentIdx % #Playlist) + 1
						PlayTrack(nxt, depth)
					end
				end
			end
		end
	end)

	return true
end

-- Auto-Next blindado contra concorrência e disparos falsos
TrackConn(Sound.Ended:Connect(function()
	if IsDestroyed or AutoNextLock then return end
	if State ~= "PLAYING" or #Playlist == 0 then return end
	local endedReq = ReqId
	local endedId = Sound.SoundId
	if endedId == "" then return end

	AutoNextLock = true
	task.spawn(function()
		task.wait(0.2)
		if IsDestroyed or endedReq ~= ReqId or State ~= "PLAYING" or Sound.SoundId ~= endedId then
			AutoNextLock = false
			return
		end
		local baseIdx = CurrentTrack and FindTrackIndex(CurrentTrack.Url)
		if not baseIdx or #Playlist == 0 then
			AutoNextLock = false
			return
		end
		local nxt = (baseIdx % #Playlist) + 1
		AutoNextLock = false
		PlayTrack(nxt, 0)
	end)
end))

PlayBtn.MouseButton1Click:Connect(function()
	if State == "LOADING" then
		return -- Evita downloads duplicados durante carregamento
	elseif State == "PLAYING" then
		Sound:Pause()
		State = "PAUSED"
		PlayBtn.Text = "▶ RESUME"
		StatusLbl.Text = "PAUSADO"
		StatusLbl.TextColor3 = Theme.Sub
		SyncPlaylistUI()
	elseif State == "PAUSED" then
		Sound:Resume()
		State = "PLAYING"
		PlayBtn.Text = "⏸ PAUSE"
		StatusLbl.Text = "TOCANDO AGORA"
		StatusLbl.TextColor3 = Theme.Green
		SyncPlaylistUI()
	elseif #Playlist > 0 then
		PlayTrack(CurIdx or 1, 0)
	end
end)

StopBtn.MouseButton1Click:Connect(function()
	ReqId = ReqId + 1
	State = "STOPPED"
	Sound:Stop()
	Sound.TimePosition = 0
	ProgFill.Size = UDim2.new(0, 0, 1, 0)
	PlayBtn.Text = "▶ PLAY"
	StatusLbl.Text = "PARADO"
	StatusLbl.TextColor3 = Theme.Pink
	SyncPlaylistUI()
end)

NextBtn.MouseButton1Click:Connect(function()
	if #Playlist > 0 then
		local baseIdx = CurIdx or 0
		PlayTrack((baseIdx % #Playlist) + 1, 0)
	end
end)

PrevBtn.MouseButton1Click:Connect(function()
	if #Playlist > 0 then
		local baseIdx = CurIdx or 1
		local prv = baseIdx - 1
		if prv < 1 then prv = #Playlist end
		PlayTrack(prv, 0)
	end
end)

-- ==============================================================================
-- 11. EXECUÇÃO DE BUSCA & CRIAÇÃO DE CARDS SINCRONIZADOS
-- ==============================================================================
local function ClearCards()
	CardRefs = {}
	for _, c in ipairs(ResultsScroll:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
end

local function MakeCard(idx, item)
	local card = Instance.new("Frame", ResultsScroll)
	card.Size = UDim2.new(1, -6, 0, 54)
	card.BackgroundColor3 = Theme.Card
	card.LayoutOrder = idx
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

	local badgeCol = (item.Source == "AUDIUS" and Theme.Purple)
		or (item.Source == "DEEZER" and Theme.Cyan)
		or Theme.Green
	local badge = Instance.new("TextLabel", card)
	badge.Size = UDim2.new(0, 68, 0, 18)
	badge.Position = UDim2.new(0, 8, 0, 7)
	badge.BackgroundColor3 = badgeCol
	badge.TextColor3 = Theme.Bg
	badge.Font = Enum.Font.GothamBlack
	badge.TextSize = 9
	badge.Text = item.Source
	Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 5)

	local verBadge = Instance.new("TextLabel", card)
	verBadge.Size = UDim2.new(0, 68, 0, 15)
	verBadge.Position = UDim2.new(0, 8, 0, 29)
	verBadge.BackgroundColor3 = (item.Ver == "ORIGINAL") and Color3.fromRGB(25, 45, 35) or Color3.fromRGB(48, 25, 40)
	verBadge.TextColor3 = (item.Ver == "ORIGINAL") and Theme.Green or Theme.Pink
	verBadge.Font = Enum.Font.GothamBold
	verBadge.TextSize = 8
	verBadge.Text = item.Ver or "ORIGINAL"
	Instance.new("UICorner", verBadge).CornerRadius = UDim.new(0, 4)

	local tl = Instance.new("TextLabel", card)
	tl.Size = UDim2.new(1, -145, 0, 22)
	tl.Position = UDim2.new(0, 84, 0, 6)
	tl.BackgroundTransparency = 1
	tl.Font = Enum.Font.GothamBold
	tl.Text = item.Title
	tl.TextColor3 = Theme.Text
	tl.TextSize = 13
	tl.TextXAlignment = Enum.TextXAlignment.Left
	tl.TextTruncate = Enum.TextTruncate.AtEnd

	local ar = Instance.new("TextLabel", card)
	ar.Size = UDim2.new(1, -145, 0, 18)
	ar.Position = UDim2.new(0, 84, 0, 28)
	ar.BackgroundTransparency = 1
	ar.Font = Enum.Font.Gotham
	ar.Text = item.Artist .. (item.Dur > 0 and (" • " .. FmtTime(item.Dur)) or "")
	ar.TextColor3 = Theme.Sub
	ar.TextSize = 11
	ar.TextXAlignment = Enum.TextXAlignment.Left
	ar.TextTruncate = Enum.TextTruncate.AtEnd

	local pBtn = Instance.new("TextButton", card)
	pBtn.Size = UDim2.new(0, 44, 0, 36)
	pBtn.Position = UDim2.new(1, -52, 0.5, -18)
	pBtn.BackgroundColor3 = Theme.Green
	pBtn.TextColor3 = Theme.Bg
	pBtn.Font = Enum.Font.GothamBlack
	pBtn.TextSize = 14
	pBtn.Text = "▶"
	Instance.new("UICorner", pBtn).CornerRadius = UDim.new(0, 8)

	CardRefs[idx] = { card = card, playBtn = pBtn }
	pBtn.MouseButton1Click:Connect(function()
		PlayTrack(item, 0)
	end)
end

RunSearch = function(rawQ)
	if IsDestroyed then return end
	local q = CleanText(rawQ)
	if #q < 2 then return end

	SearchTk = SearchTk + 1
	local myTk = SearchTk

	ClearCards()
	SearchBtn.Text = "..."
	StatusLbl.Text = "BUSCANDO POR RELEVÂNCIA (" .. ActiveSource .. ")..."
	StatusLbl.TextColor3 = Theme.Cyan

	task.spawn(function()
		local combined = {}
		if ActiveSource == "AUDIUS" then
			combined = FetchAudius(q)
		elseif ActiveSource == "DEEZER" then
			combined = FetchDeezer(q)
		elseif ActiveSource == "HEARTHIS" then
			combined = FetchHearThis(q)
		else
			local r1, r2, r3
			local done = 0
			task.spawn(function() r1 = FetchAudius(q); done = done + 1 end)
			task.spawn(function() r2 = FetchDeezer(q); done = done + 1 end)
			task.spawn(function() r3 = FetchHearThis(q); done = done + 1 end)
			local t0 = os.clock()
			while done < 3 and not IsDestroyed and (os.clock() - t0) < 16 do
				task.wait(0.05)
			end
			for _, list in ipairs({ r1 or {}, r2 or {}, r3 or {} }) do
				for _, it in ipairs(list) do table.insert(combined, it) end
			end
		end

		if IsDestroyed or myTk ~= SearchTk then return end
		SearchBtn.Text = "BUSCAR"

		-- Seleção por camadas: prioriza Tier 2; usa Tier 1 se houver menos de 5 faixas Tier 2
		local tier2, tier1 = {}, {}
		for _, it in ipairs(combined) do
			if it.Tier == 2 then
				table.insert(tier2, it)
			else
				table.insert(tier1, it)
			end
		end

		local function TrackSort(a, b)
			local scoreA, scoreB = a.Score or 0, b.Score or 0
			if scoreA ~= scoreB then return scoreA > scoreB end
			return (a.Dur or 0) > (b.Dur or 0)
		end
		table.sort(tier2, TrackSort)
		table.sort(tier1, TrackSort)

		local candidates = {}
		for _, it in ipairs(tier2) do table.insert(candidates, it) end
		if #candidates < 5 then
			for _, it in ipairs(tier1) do table.insert(candidates, it) end
		end

		Playlist = {}
		local seenKey, seenUrl = {}, {}
		for _, it in ipairs(candidates) do
			local k = (it.Key or CanonicalKey(it.Title, it.Artist)) .. "|" .. (it.Ver or "ORIGINAL")
			if not seenKey[k] and not seenUrl[it.Url] and #Playlist < 30 then
				seenKey[k] = true
				seenUrl[it.Url] = true
				table.insert(Playlist, it)
			end
		end

		ClearCards()
		for idx, it in ipairs(Playlist) do
			MakeCard(idx, it)
		end
		SyncPlaylistUI()

		if #Playlist == 0 then
			StatusLbl.Text = "NENHUM RESULTADO RELEVANTE ENCONTRADO"
			StatusLbl.TextColor3 = Theme.Pink
		elseif State == "STOPPED" then
			StatusLbl.Text = string.format("ENCONTRADAS %d FAIXAS RELEVANTES", #Playlist)
			StatusLbl.TextColor3 = Theme.Green
		end
	end)
end

SearchBtn.MouseButton1Click:Connect(function() RunSearch(SearchInput.Text) end)
SearchInput.FocusLost:Connect(function(enter)
	if enter then RunSearch(SearchInput.Text) end
end)

-- ==============================================================================
-- 12. LOOP 5D (POSICIONAMENTO + PULSO + SINCRONIZAÇÃO EM TEMPO REAL)
-- ==============================================================================
local tAccum = 0
TrackConn(RunService.RenderStepped:Connect(function(dt)
	if IsDestroyed then return end
	if workspace.CurrentCamera and workspace.CurrentCamera ~= Cam then
		if Cam and not FX.fov then
			DefaultFOV = Cam.FieldOfView
		end
		Cam = workspace.CurrentCamera
		DefaultFOV = Cam.FieldOfView
		HoloFolder.Parent = Cam
	end
	if not Cam then return end

	tAccum = tAccum + dt
	local playing = (State == "PLAYING" and Sound.IsPlaying)
	local loud = playing and math.clamp(Sound.PlaybackLoudness / 420, 0, 1) or 0

	if HubOpen then
		local bobY = math.sin(tAccum * 1.8) * 0.05
		local baseCF = Cam.CFrame * CFrame.new(0, bobY, dist)

		LPart.CFrame = baseCF * CFrame.new(-1.85, 0, 0.22) * CFrame.Angles(0, math.rad(192), 0)
		RPart.CFrame = baseCF * CFrame.new(1.85, 0, 0.22) * CFrame.Angles(0, math.rad(168), 0)

		Core.CFrame = baseCF * CFrame.new(0, 1.52, -0.1) * CFrame.Angles(tAccum * 1.6, tAccum * 2.1, 0)
		Core.Size = Vector3.one * (0.28 + loud * 0.35)
		Core.Color = Theme.Cyan:Lerp(Theme.Pink, loud)

		Ring.CFrame = Core.CFrame * CFrame.Angles(math.rad(75), tAccum * 2.5, 0)
		local rScale = 0.6 + loud * 0.55
		RingMesh.Scale = Vector3.new(rScale, rScale, 0.12)

		LStroke.Color = Theme.Cyan:Lerp(Theme.Pink, loud * 0.7)
		RStroke.Color = Theme.Green:Lerp(Theme.Cyan, loud * 0.7)

		for i = 1, 28 do
			local wave = playing
				and math.clamp(math.sin(tAccum * 10 + i * 0.45) * 0.35 + loud * (1.15 - (i / 45)), 0.08, 0.95)
				or 0.08
			Bars[i].Size = Bars[i].Size:Lerp(UDim2.new(1 / 28 - 0.014, 0, wave, 0), 0.28)
		end

		if Sound.IsLoaded and Sound.TimeLength > 0 then
			local pos = math.clamp(Sound.TimePosition, 0, Sound.TimeLength)
			ProgFill.Size = UDim2.new(pos / Sound.TimeLength, 0, 1, 0)
			TimeLbl.Text = string.format("%s / %s  (Clique na barra para +10s)", FmtTime(pos), FmtTime(Sound.TimeLength))
		end
	end

	if FX.fov then
		local targetFOV = DefaultFOV + (loud * 6.5)
		Cam.FieldOfView = Cam.FieldOfView + (targetFOV - Cam.FieldOfView) * 0.22
	end

	local light = EnsureCharLight()
	if light then
		light.Brightness = playing and (loud * 4.5) or 0
		light.Color = Core.Color
	end
end))

-- ==============================================================================
-- 13. LIMPEZA TOTAL GARANTIDA (CLEANUP DETERMINÍSTICO)
-- ==============================================================================
GEnv.HoloSpotify5D_Cleanup = function()
	if IsDestroyed then return end
	IsDestroyed = true
	ReqId = ReqId + 1
	SearchTk = SearchTk + 1
	State = "STOPPED"

	for _, c in ipairs(Conns) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(Conns)

	for _, tw in ipairs(Tweens) do
		pcall(function() tw:Cancel() end)
	end
	table.clear(Tweens)

	if workspace.CurrentCamera then
		pcall(function() workspace.CurrentCamera.FieldOfView = DefaultFOV end)
	end
	if CharLight then
		pcall(function() CharLight.Brightness = 0; CharLight:Destroy() end)
		CharLight = nil
	end
	if Sound then
		pcall(function()
			BassFX.Enabled = false
			ReverbFX.Enabled = false
			Sound.PlaybackSpeed = 1
			Sound:Stop()
			Sound:Destroy()
		end)
	end

	for i = #CacheOrder, 1, -1 do
		local item = CacheOrder[i]
		if item and item.file and delf and isf then
			pcall(function()
				if isf(item.file) then delf(item.file) end
			end)
		end
	end
	table.clear(CacheOrder)
	table.clear(Cache)
	table.clear(Playlist)
	table.clear(CardRefs)

	if HoloFolder then pcall(function() HoloFolder:Destroy() end) end
	if ToggleGui then pcall(function() ToggleGui:Destroy() end) end

	SweepOrphans()
end

RunSearch("The Weeknd")
-- hd_menu.lua
-- version: 1.1.0
-- updated: 2026-11-23
--[[
	警告: このスクリプトは ScriptBlox 未検証です。自己責任で使用してください。
	日本語版 / スマホ(タッチ)対応
]]
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

local isMobile = UserInputService.TouchEnabled

------------------------------------------------------------------
-- 設定 (メニューから全部その場で変更できます)
------------------------------------------------------------------
local Config = {
	Aimbot = {
		Enabled      = true,
		AlwaysOn     = false,               -- true = キー不要で常に吸い付く
		AimKey       = Enum.UserInputType.MouseButton2,
		TargetPart   = "Head",              -- Head / UpperTorso / HumanoidRootPart
		Strength     = 100,                 -- 吸い付く強さ (%) 100 = 即スナップ
		FOV          = isMobile and 220 or 400, -- 画面中央からの半径(px)
		ShowFOV      = true,
		WallCheck    = false,               -- false = 壁越しでも吸う
		MaxDistance  = 2000,
		TeamlessIsEnemy = true,             -- チーム未所属を敵として扱う
		-- チーム判定は常に有効です (OFFにはできません)
	},
	Chams = {
		Enabled          = true,
		ShowTeammates    = true,
		ShowEnemies      = true,
		TeamColor        = Color3.fromRGB(0, 120, 255),   -- 青
		EnemyColor       = Color3.fromRGB(255, 0, 0),     -- 赤
		FillTransparency = 0.5,
		OutlineTransparency = 0,
		AlwaysOnTop      = true,
	},
	Menu = {
		ToggleKey = Enum.KeyCode.RightShift,
		AimButton = true,
	},
}

local TARGET_PARTS = {
	{ label = "頭",       value = "Head" },
	{ label = "上半身",   value = "UpperTorso" },
	{ label = "胴体中心", value = "HumanoidRootPart" },
}

------------------------------------------------------------------
-- 補助
------------------------------------------------------------------
local function isEnemy(plr)
	if plr == LocalPlayer then return false end
	if not plr.Team or not LocalPlayer.Team then
		return Config.Aimbot.TeamlessIsEnemy
	end
	return plr.Team ~= LocalPlayer.Team
end

local function isTeammate(plr)
	if plr == LocalPlayer then return false end
	return LocalPlayer.Team ~= nil and plr.Team == LocalPlayer.Team
end

local function getAlive(plr)
	local char = plr.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	return char, hum
end

local function getPart(char)
	local name = Config.Aimbot.TargetPart
	return char:FindFirstChild(name)
		or char:FindFirstChild("Head")
		or char:FindFirstChild("HumanoidRootPart")
end

local function aimCenter()
	if isMobile then
		local vp = Camera.ViewportSize
		return Vector2.new(vp.X / 2, vp.Y / 2)
	end
	return UserInputService:GetMouseLocation()
end

------------------------------------------------------------------
-- チャム (ハイライト)
------------------------------------------------------------------
local highlights = {}

local function removeHighlight(plr)
	local h = highlights[plr]
	if h then h:Destroy() end
	highlights[plr] = nil
end

local function updateChams()
	local cfg = Config.Chams
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer then
			local char = getAlive(plr)
			local team, enemy = isTeammate(plr), isEnemy(plr)
			local want = cfg.Enabled and char
				and ((team and cfg.ShowTeammates) or (enemy and cfg.ShowEnemies))

			if want then
				local h = highlights[plr]
				if not h or h.Parent ~= char then
					if h then h:Destroy() end
					h = Instance.new("Highlight")
					h.Name = "HD_Cham"
					h.Parent = char
					highlights[plr] = h
				end
				h.Adornee = char
				h.FillColor = team and cfg.TeamColor or cfg.EnemyColor
				h.OutlineColor = team and cfg.TeamColor or cfg.EnemyColor
				h.FillTransparency = cfg.FillTransparency
				h.OutlineTransparency = cfg.OutlineTransparency
				h.DepthMode = cfg.AlwaysOnTop
					and Enum.HighlightDepthMode.AlwaysOnTop
					or Enum.HighlightDepthMode.Occluded
			else
				removeHighlight(plr)
			end
		end
	end
end

Players.PlayerRemoving:Connect(removeHighlight)

------------------------------------------------------------------
-- エイムボット
------------------------------------------------------------------
local aimHeld = false

local function matchesAimKey(input)
	local key = Config.Aimbot.AimKey
	return input.KeyCode == key or input.UserInputType == key
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function visible(part, char)
	rayParams.FilterDescendantsInstances = { LocalPlayer.Character, Camera }
	local origin = Camera.CFrame.Position
	local result = workspace:Raycast(origin, part.Position - origin, rayParams)
	return result == nil or result.Instance:IsDescendantOf(char)
end

local function getTarget()
	local cfg = Config.Aimbot
	local center = aimCenter()
	local best, bestDist

	for _, plr in ipairs(Players:GetPlayers()) do
		if isEnemy(plr) then -- チーム判定は常に有効
			local char = getAlive(plr)
			local part = char and getPart(char)
			if part then
				local worldDist = (part.Position - Camera.CFrame.Position).Magnitude
				if worldDist <= cfg.MaxDistance then
					local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
					if onScreen then
						local d = (Vector2.new(pos.X, pos.Y) - center).Magnitude
						if d <= cfg.FOV and (not bestDist or d < bestDist)
							and (not cfg.WallCheck or visible(part, char)) then
							best, bestDist = part, d
						end
					end
				end
			end
		end
	end
	return best
end

RunService:BindToRenderStep("HD_Aimbot", Enum.RenderPriority.Camera.Value + 1, function()
	Camera = workspace.CurrentCamera
	local cfg = Config.Aimbot
	if not cfg.Enabled then return end
	if not (cfg.AlwaysOn or aimHeld) then return end

	local target = getTarget()
	if not target then return end

	local goal = CFrame.new(Camera.CFrame.Position, target.Position)
	local a = math.clamp(cfg.Strength / 100, 0, 1)
	a = a * a
	if a >= 0.999 then
		Camera.CFrame = goal
	else
		Camera.CFrame = Camera.CFrame:Lerp(goal, a)
	end
end)

------------------------------------------------------------------
-- GUI
------------------------------------------------------------------
local ACCENT   = Color3.fromRGB(255, 70, 70)
local BG       = Color3.fromRGB(18, 18, 24)
local PANEL    = Color3.fromRGB(28, 28, 38)
local ELEMENT  = Color3.fromRGB(38, 38, 52)
local TEXT     = Color3.fromRGB(235, 235, 245)
local SUBTEXT  = Color3.fromRGB(150, 150, 170)

local gui = Instance.new("ScreenGui")
gui.Name = "HD_Menu"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 500
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local function corner(inst, r)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = inst
end
local function stroke(inst, color, th)
	local s = Instance.new("UIStroke"); s.Color = color; s.Thickness = th or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = inst; return s
end
local function label(parent, text, size, color, font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text; l.TextSize = size or 14
	l.TextColor3 = color or TEXT
	l.Font = font or Enum.Font.GothamMedium
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

-- FOV サークル
local fovCircle = Instance.new("Frame")
fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
fovCircle.BackgroundTransparency = 1
fovCircle.ZIndex = 2
fovCircle.Parent = gui
corner(fovCircle, 9999)
stroke(fovCircle, ACCENT, 1.5)

RunService.RenderStepped:Connect(function()
	local cfg = Config.Aimbot
	fovCircle.Visible = cfg.Enabled and cfg.ShowFOV
	fovCircle.Size = UDim2.fromOffset(cfg.FOV * 2, cfg.FOV * 2)
	local c = aimCenter()
	fovCircle.Position = UDim2.fromOffset(c.X, c.Y)
end)

-- メインウィンドウ
local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.fromOffset(340, 430)
main.Position = UDim2.new(0.5, -170, 0.5, -215)
main.BackgroundColor3 = BG
main.BorderSizePixel = 0
main.ZIndex = 10
main.Parent = gui
corner(main, 12)
stroke(main, ACCENT, 1.5)

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 44)
titleBar.BackgroundColor3 = PANEL
titleBar.BorderSizePixel = 0
titleBar.Active = true
titleBar.ZIndex = 11
titleBar.Parent = main
corner(titleBar, 12)

local title = label(titleBar, "HOME DEFENSE 設定", 15, TEXT, Enum.Font.GothamBold)
title.Position = UDim2.fromOffset(16, 0)
title.Size = UDim2.new(1, -60, 1, 0)
title.ZIndex = 12

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(28, 28)
closeBtn.Position = UDim2.new(1, -38, 0, 8)
closeBtn.BackgroundColor3 = ELEMENT
closeBtn.Text = "X"
closeBtn.TextColor3 = TEXT
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.ZIndex = 12
closeBtn.Parent = titleBar
corner(closeBtn, 6)

-- 透明なモーダルボタン: メニューを開いている間ゲーム入力を止める
local modalBtn = Instance.new("TextButton")
modalBtn.Size = UDim2.fromOffset(1, 1)
modalBtn.BackgroundTransparency = 1
modalBtn.Text = ""
modalBtn.Modal = true
modalBtn.ZIndex = 10
modalBtn.Parent = main

-- ドラッグ (タッチ対応)
do
	local dragging, dragStart, startPos
	titleBar.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1
		or i.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos = true, i.Position, main.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
		or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - dragStart
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1
		or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end)
end

-- タブ
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -24, 0, 34)
tabBar.Position = UDim2.fromOffset(12, 52)
tabBar.BackgroundTransparency = 1
tabBar.ZIndex = 11
tabBar.Parent = main
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 8)
tabLayout.Parent = tabBar

local pages, tabButtons = {}, {}

local function selectTab(name)
	for n, p in pairs(pages) do
		p.Visible = (n == name)
		tabButtons[n].BackgroundColor3 = (n == name) and ACCENT or ELEMENT
		tabButtons[n].TextColor3 = (n == name) and Color3.new(1, 1, 1) or SUBTEXT
	end
end

local function makePage(name)
	local page = Instance.new("ScrollingFrame")
	page.Size = UDim2.new(1, -24, 1, -100)
	page.Position = UDim2.fromOffset(12, 92)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 4
	page.ScrollBarImageColor3 = ACCENT
	page.CanvasSize = UDim2.new()
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.Visible = false
	page.ZIndex = 11
	page.Parent = main
	local l = Instance.new("UIListLayout"); l.Padding = UDim.new(0, 8); l.Parent = page
	pages[name] = page

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromOffset(96, 34)
	btn.BackgroundColor3 = ELEMENT
	btn.Text = name
	btn.TextColor3 = SUBTEXT
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 14
	btn.ZIndex = 12
	btn.Parent = tabBar
	corner(btn, 8)
	tabButtons[name] = btn

	btn.MouseButton1Click:Connect(function() selectTab(name) end)
	return page
end

local function rowFrame(parent, h)
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, -8, 0, h or 38)
	f.BackgroundColor3 = PANEL
	f.BorderSizePixel = 0
	f.ZIndex = 11
	f.Parent = parent
	corner(f, 8)
	return f
end

local function addToggle(parent, text, get, set)
	local f = rowFrame(parent)
	local l = label(f, text, 14); l.Position = UDim2.fromOffset(12, 0); l.Size = UDim2.new(1, -70, 1, 0)
	l.ZIndex = 12
	local box = Instance.new("TextButton")
	box.Size = UDim2.fromOffset(44, 22); box.Position = UDim2.new(1, -56, 0.5, -11)
	box.Text = ""; box.AutoButtonColor = false; box.ZIndex = 12; box.Parent = f
	corner(box, 11)
	local knob = Instance.new("Frame")
	knob.Size = UDim2.fromOffset(18, 18); knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.ZIndex = 13; knob.Parent = box; corner(knob, 9)
	local function render()
		local on = get()
		TweenService:Create(box, TweenInfo.new(0.15), { BackgroundColor3 = on and ACCENT or ELEMENT }):Play()
		TweenService:Create(knob, TweenInfo.new(0.15),
			{ Position = on and UDim2.fromOffset(24, 2) or UDim2.fromOffset(2, 2) }):Play()
	end
	box.MouseButton1Click:Connect(function() set(not get()); render() end)
	render()
end

local activeSlider
local function addSlider(parent, text, min, max, step, get, set)
	local f = rowFrame(parent, 52)
	local l = label(f, text, 14); l.Position = UDim2.fromOffset(12, 4); l.Size = UDim2.new(1, -90, 0, 20)
	l.ZIndex = 12
	local v = label(f, "", 14, SUBTEXT); v.TextXAlignment = Enum.TextXAlignment.Right
	v.Position = UDim2.new(1, -82, 0, 4); v.Size = UDim2.fromOffset(70, 20); v.ZIndex = 12
	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -24, 0, 6); track.Position = UDim2.fromOffset(12, 36)
	track.BackgroundColor3 = ELEMENT; track.BorderSizePixel = 0; track.ZIndex = 12; track.Parent = f
	corner(track, 3)
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = ACCENT; fill.BorderSizePixel = 0; fill.ZIndex = 13; fill.Parent = track
	corner(fill, 3)

	local function render()
		local a = (get() - min) / (max - min)
		fill.Size = UDim2.new(math.clamp(a, 0, 1), 0, 1, 0)
		v.Text = tostring(get())
	end
	local function fromX(x)
		local a = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		local val = min + (max - min) * a
		val = math.floor(val / step + 0.5) * step
		set(math.floor(val * 1000 + 0.5) / 1000)
		render()
	end
	track.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1
		or i.UserInputType == Enum.UserInputType.Touch then
			activeSlider = fromX; fromX(i.Position.X)
		end
	end)
	render()
end

UserInputService.InputChanged:Connect(function(i)
	if activeSlider and (i.UserInputType == Enum.UserInputType.MouseMovement
	or i.UserInputType == Enum.UserInputType.Touch) then
		activeSlider(i.Position.X)
	end
end)
UserInputService.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1
	or i.UserInputType == Enum.UserInputType.Touch then activeSlider = nil end
end)

local rebinding
local function keyName(k)
	if k.EnumType == Enum.UserInputType then
		return k == Enum.UserInputType.MouseButton1 and "左クリック"
			or k == Enum.UserInputType.MouseButton2 and "右クリック"
			or k == Enum.UserInputType.MouseButton3 and "中クリック" or k.Name
	end
	return k.Name
end

local function addKeybind(parent, text, get, set)
	local f = rowFrame(parent)
	local l = label(f, text, 14); l.Position = UDim2.fromOffset(12, 0); l.Size = UDim2.new(1, -130, 1, 0)
	l.ZIndex = 12
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(110, 26); b.Position = UDim2.new(1, -122, 0.5, -13)
	b.BackgroundColor3 = ELEMENT; b.TextColor3 = TEXT
	b.Font = Enum.Font.GothamBold; b.TextSize = 13
	b.Text = keyName(get()); b.ZIndex = 12; b.Parent = f
	corner(b, 6)
	b.MouseButton1Click:Connect(function()
		b.Text = "入力待ち..."
		rebinding = function(key) set(key); b.Text = keyName(key) end
	end)
end

local function addCycle(parent, text, options, get, set)
	local function labelOf(v)
		for _, o in ipairs(options) do
			if o.value == v then return o.label end
		end
		return tostring(v)
	end
	local f = rowFrame(parent)
	local l = label(f, text, 14); l.Position = UDim2.fromOffset(12, 0); l.Size = UDim2.new(1, -150, 1, 0)
	l.ZIndex = 12
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(130, 26); b.Position = UDim2.new(1, -142, 0.5, -13)
	b.BackgroundColor3 = ELEMENT; b.TextColor3 = TEXT
	b.Font = Enum.Font.GothamBold; b.TextSize = 13
	b.Text = labelOf(get()); b.ZIndex = 12; b.Parent = f
	corner(b, 6)
	b.MouseButton1Click:Connect(function()
		local idx = 0
		for i, o in ipairs(options) do
			if o.value == get() then idx = i break end
		end
		local nxt = options[idx % #options + 1]
		set(nxt.value); b.Text = labelOf(get())
	end)
end

local function addColor(parent, text, get, set)
	local presets = {
		Color3.fromRGB(0, 120, 255), Color3.fromRGB(255, 0, 0), Color3.fromRGB(0, 255, 100),
		Color3.fromRGB(255, 220, 0), Color3.fromRGB(180, 0, 255), Color3.fromRGB(255, 255, 255),
	}
	local f = rowFrame(parent)
	local l = label(f, text, 14); l.Position = UDim2.fromOffset(12, 0); l.Size = UDim2.new(1, -100, 1, 0)
	l.ZIndex = 12
	local sw = Instance.new("TextButton")
	sw.Size = UDim2.fromOffset(60, 24); sw.Position = UDim2.new(1, -72, 0.5, -12)
	sw.Text = ""; sw.BackgroundColor3 = get(); sw.ZIndex = 12; sw.Parent = f
	corner(sw, 6)
	sw.MouseButton1Click:Connect(function()
		local idx = 0
		for i, c in ipairs(presets) do if c == get() then idx = i break end end
		local nxt = presets[idx % #presets + 1]
		set(nxt); sw.BackgroundColor3 = nxt
	end)
end

-- エイムタブ
local A = Config.Aimbot
local aimPage = makePage("エイム")
addToggle(aimPage, "エイムボット ON", function() return A.Enabled end, function(v) A.Enabled = v end)
addToggle(aimPage, "常時ON (キー不要)", function() return A.AlwaysOn end, function(v) A.AlwaysOn = v end)
addKeybind(aimPage, "エイムキー (長押し)", function() return A.AimKey end, function(k) A.AimKey = k end)
addCycle(aimPage, "狙う部位", TARGET_PARTS, function() return A.TargetPart end, function(v) A.TargetPart = v end)
addSlider(aimPage, "強さ (%) 100=即スナップ", 5, 100, 5, function() return A.Strength end, function(v) A.Strength = v end)
addSlider(aimPage, "FOV半径", 20, 1000, 10, function() return A.FOV end, function(v) A.FOV = v end)
addToggle(aimPage, "FOVサークル表示", function() return A.ShowFOV end, function(v) A.ShowFOV = v end)
addToggle(aimPage, "壁判定 (壁越し不可)", function() return A.WallCheck end, function(v) A.WallCheck = v end)
addSlider(aimPage, "最大距離", 50, 5000, 50, function() return A.MaxDistance end, function(v) A.MaxDistance = v end)
addToggle(aimPage, "チーム無しを敵扱い", function() return A.TeamlessIsEnemy end, function(v) A.TeamlessIsEnemy = v end)

-- 表示タブ
local C = Config.Chams
local visPage = makePage("表示")
addToggle(visPage, "チャム ON", function() return C.Enabled end, function(v) C.Enabled = v end)
addToggle(visPage, "味方も表示", function() return C.ShowTeammates end, function(v) C.ShowTeammates = v end)
addToggle(visPage, "敵を表示", function() return C.ShowEnemies end, function(v) C.ShowEnemies = v end)
addColor(visPage, "味方の色 (青)", function() return C.TeamColor end, function(v) C.TeamColor = v end)
addColor(visPage, "敵の色 (赤)", function() return C.EnemyColor end, function(v) C.EnemyColor = v end)
addSlider(visPage, "塗り透明度", 0, 1, 0.05, function() return C.FillTransparency end, function(v) C.FillTransparency = v end)
addSlider(visPage, "枠の透明度", 0, 1, 0.05, function() return C.OutlineTransparency end, function(v) C.OutlineTransparency = v end)
addToggle(visPage, "壁越しに表示", function() return C.AlwaysOnTop end, function(v) C.AlwaysOnTop = v end)

-- 設定タブ
local setPage = makePage("設定")
addKeybind(setPage, "メニューキー", function() return Config.Menu.ToggleKey end, function(k) Config.Menu.ToggleKey = k end)
addToggle(setPage, "AIMボタン表示", function() return Config.Menu.AimButton end, function(v) Config.Menu.AimButton = v end)
local info = label(setPage, "チーム判定は常に有効です。\n味方=青 / 敵=赤。\nスマホでは画面右の AIM を長押しで吸い付きます。\n強さ100%は長押し専用、常時ONなら60%前後が快適です。", 13, SUBTEXT)
info.Size = UDim2.new(1, -8, 0, 80)
info.TextWrapped = true
info.ZIndex = 12

selectTab("エイム")

------------------------------------------------------------------
-- フローティングボタン
------------------------------------------------------------------
-- メニュー開閉
local openBtn = Instance.new("TextButton")
openBtn.Size = UDim2.fromOffset(56, 56)
openBtn.AnchorPoint = Vector2.new(0, 1)
openBtn.Position = UDim2.new(0, 24, 1, -24)
openBtn.BackgroundColor3 = ACCENT
openBtn.BackgroundTransparency = 0.25
openBtn.Text = "設定"
openBtn.TextColor3 = Color3.new(1, 1, 1)
openBtn.Font = Enum.Font.GothamBold
openBtn.TextSize = 13
openBtn.AutoButtonColor = false
openBtn.Visible = false
openBtn.ZIndex = 400
openBtn.Parent = gui
corner(openBtn, 28)

-- AIM 長押しボタン
local aimBtn = Instance.new("TextButton")
aimBtn.Size = UDim2.fromOffset(104, 104)
aimBtn.AnchorPoint = Vector2.new(1, 1)
aimBtn.Position = UDim2.new(1, -24, 1, -24)
aimBtn.BackgroundColor3 = ACCENT
aimBtn.BackgroundTransparency = 0.55
aimBtn.Text = "AIM"
aimBtn.TextColor3 = Color3.new(1, 1, 1)
aimBtn.Font = Enum.Font.GothamBold
aimBtn.TextSize = 18
aimBtn.AutoButtonColor = false
aimBtn.ZIndex = 400
aimBtn.Parent = gui
corner(aimBtn, 52)

aimBtn.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.Touch
	or i.UserInputType == Enum.UserInputType.MouseButton1 then
		aimHeld = true
		aimBtn.BackgroundTransparency = 0.15
	end
end)
aimBtn.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.Touch
	or i.UserInputType == Enum.UserInputType.MouseButton1 then
		aimHeld = false
		aimBtn.BackgroundTransparency = 0.55
	end
end)
UserInputService.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.Touch then
		aimHeld = false
		aimBtn.BackgroundTransparency = 0.55
	end
end)

RunService.RenderStepped:Connect(function()
	aimBtn.Visible = Config.Menu.AimButton
end)

-- 開閉処理
local function setMenu(open)
	main.Visible = open
	openBtn.Visible = not open
end
closeBtn.MouseButton1Click:Connect(function() setMenu(false) end)
openBtn.MouseButton1Click:Connect(function() setMenu(true) end)

------------------------------------------------------------------
-- 入力
------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, processed)
	-- キー割り当ての書き換えが最優先
	if rebinding then
		local key
		if input.UserInputType == Enum.UserInputType.Keyboard then
			key = input.KeyCode
		elseif input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.MouseButton2
			or input.UserInputType == Enum.UserInputType.MouseButton3 then
			key = input.UserInputType
		end
		if key and key ~= Enum.UserInputType.MouseButton1 then
			local cb = rebinding; rebinding = nil; cb(key)
		end
		return
	end

	if input.KeyCode == Config.Menu.ToggleKey then
		setMenu(not main.Visible)
		return
	end
	if matchesAimKey(input) then aimHeld = true end
end)

UserInputService.InputEnded:Connect(function(input)
	if matchesAimKey(input) then aimHeld = false end
end)

------------------------------------------------------------------
-- ループ
------------------------------------------------------------------
RunService.Heartbeat:Connect(function()
	local ok, err = pcall(updateChams)
	if not ok then warn("[HD Chams] " .. tostring(err)) end
end)

local function hookPlayer(plr)
	plr.CharacterRemoving:Connect(function() removeHighlight(plr) end)
end
for _, plr in ipairs(Players:GetPlayers()) do hookPlayer(plr) end
Players.PlayerAdded:Connect(hookPlayer)

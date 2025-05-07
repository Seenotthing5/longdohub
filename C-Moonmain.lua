local readfile = type(readfile) == "function" and readfile or function() return nil end
local writefile = type(writefile) == "function" and writefile or function() return false end
local isfile = type(isfile) == "function" and isfile or function() return false end

-- Services
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local VirtualInputManager = game:GetService("VirtualInputManager")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

-- Check if running in Roblox environment
local isStudio = game:GetService("RunService"):IsStudio()
local canUseFileSystem = pcall(function() 
    return type(readfile) == "function" and type(writefile) == "function" and type(isfile) == "function"
end)

if not canUseFileSystem then
    warn("File system operations are not available in this environment")
end

-- Constants
local KEY_MAP = {
    [1] = Enum.KeyCode.One,
    [2] = Enum.KeyCode.Two,
    [3] = Enum.KeyCode.Three,
    [4] = Enum.KeyCode.Four,
    [5] = Enum.KeyCode.Five,
    [6] = Enum.KeyCode.Six
}
-- cần làm lại 
local SKILL_COOLDOWNS = {
    [1] = 1,  
    [2] = 1,  
    [3] = 1, 
    [4] = 1, 
    [5] = 1, 
    [6] = 1  
}

local autoClickSpeed = 0.1 -- Mặc định 0.1 giây mỗi lần click

-- Variables
local skillLastUsed = {}
local toggleStates = {
    autoFarmLevel = false,
    autoFarmBoss = false
}

-- File System Operations
local function safeReadFile(filename)
    if not canUseFileSystem then return nil end
    if not isfile or not readfile then return nil end
    
    if not isfile(filename) then return nil end
    return readfile(filename)
end

local function safeWriteFile(filename, data)
    if not canUseFileSystem then return false end
    if not writefile then return false end
    
    local success = pcall(function()
        writefile(filename, data)
    end)
    return success
end

-- Functions
local function saveSettings()
    safeWriteFile("OneFHubSettings.json", HttpService:JSONEncode(toggleStates))
end

local function loadSettings()
    local success, settings = pcall(function()
        local data = safeReadFile("OneFHubSettings.json")
        if not data then return nil end
        return HttpService:JSONDecode(data)
    end)
    if success and settings then
        toggleStates = settings
    else
        saveSettings() -- Create default settings file
    end
end

local function isSkillReady(skillIndex)
    if not skillLastUsed[skillIndex] then
        return true
    end
    local timeSinceLastUse = tick() - skillLastUsed[skillIndex]
    return timeSinceLastUse >= (SKILL_COOLDOWNS[skillIndex] or 1)
end

local function useSkill(skillIndex)
    if KEY_MAP[skillIndex] then
        VirtualInputManager:SendKeyEvent(true, KEY_MAP[skillIndex], false, game)
        task.wait(0.1)
        VirtualInputManager:SendKeyEvent(false, KEY_MAP[skillIndex], false, game)
        skillLastUsed[skillIndex] = tick() -- Cập nhật thời gian sử dụng
    else
        warn("Invalid skill index:", skillIndex)
    end
end

local function detectSkills()
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = character:WaitForChild("Humanoid")
    local animator = humanoid:WaitForChild("Animator")
    
    local count = 0
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        if track.Name:match("Skill") then
            count = count + 1
        end
    end
    return math.max(count, 3)
end

local function detectCooldowns()
    for i = 1, #KEY_MAP do
        local skill = LocalPlayer.Character:FindFirstChild("Skill" .. i)
        if skill and skill:FindFirstChild("Cooldown") then
            SKILL_COOLDOWNS[i] = skill.Cooldown.Value
        else
            SKILL_COOLDOWNS[i] = 1 -- Giá trị mặc định nếu không tìm thấy
        end
    end
end

local function getSkillsByPriority()
    local skills = {}
    for i = 1, #KEY_MAP do
        local cooldownRemaining = 0
        if skillLastUsed[i] then
            cooldownRemaining = math.max(0, (SKILL_COOLDOWNS[i] or 1) - (tick() - skillLastUsed[i]))
        end
        table.insert(skills, {index = i, cooldown = cooldownRemaining})
    end

    -- Sắp xếp kỹ năng theo thời gian cooldown tăng dần
    table.sort(skills, function(a, b)
        return a.cooldown < b.cooldown
    end)

    return skills
end

local function fetchServerList()
    local servers = {}
    local cursor = ""
    local placeId = game.PlaceId
    local maxRetries = 3
    local retryDelay = 2
    
    repeat
        local success, result
        for retry = 1, maxRetries do
            success, result = pcall(function()
                local url = string.format(
                    "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100&cursor=%s",
                    placeId,
                    cursor
                )
                return HttpService:JSONDecode(game:HttpGet(url))
            end)
            
            if success and result then
                break
            end
            
            if retry < maxRetries then
                task.wait(retryDelay)
            end
        end
        
        if success and result and result.data then
            for _, server in ipairs(result.data) do
                if server.playing < server.maxPlayers and server.id ~= game.JobId then
                    table.insert(servers, {
                        id = server.id,
                        ping = server.ping,
                        playing = server.playing
                    })
                end
            end
            cursor = result.nextPageCursor
        else
            warn("Failed to fetch server list after", maxRetries, "attempts")
            break
        end
    until not cursor or #servers >= 10
    
    if #servers > 0 then
        table.sort(servers, function(a, b)
            if math.abs(a.ping - b.ping) <= 50 then
                return a.playing > b.playing
            end
            return a.ping < b.ping
        end)
    end
    
    return servers
end

-- GUI Setup
local ScreenGui = Instance.new("ScreenGui")
local MainFrame = Instance.new("Frame")
local Title = Instance.new("TextLabel")
local FarmLevelToggle = Instance.new("TextButton")
local FarmBossToggle = Instance.new("TextButton")
local ServerHopButton = Instance.new("TextButton")
local CloseButton = Instance.new("TextButton")
local SpeedSlider = Instance.new("TextBox")

ScreenGui.Name = "OneF Hub"
ScreenGui.Parent = game:GetService("CoreGui")

MainFrame.Name = "MainFrame"
MainFrame.Parent = ScreenGui
MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
MainFrame.BorderSizePixel = 0
MainFrame.Position = UDim2.new(0.05, 0, 0.2, 0)
MainFrame.Size = UDim2.new(0, 250, 0, 240)
MainFrame.Active = true
MainFrame.Draggable = true

Title.Name = "Title"
Title.Parent = MainFrame
Title.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
Title.BorderSizePixel = 0
Title.Size = UDim2.new(1, 0, 0, 30)
Title.Font = Enum.Font.GothamBold
Title.Text = "OneF Hub [BETA]"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 16

FarmLevelToggle.Name = "FarmLevelToggle"
FarmLevelToggle.Parent = MainFrame
FarmLevelToggle.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
FarmLevelToggle.BorderSizePixel = 0
FarmLevelToggle.Position = UDim2.new(0, 10, 0, 40)
FarmLevelToggle.Size = UDim2.new(0.92, 0, 0, 30)
FarmLevelToggle.Font = Enum.Font.Gotham
FarmLevelToggle.Text = "Auto Farm Level: OFF"
FarmLevelToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
FarmLevelToggle.TextSize = 14

FarmBossToggle.Name = "FarmBossToggle"
FarmBossToggle.Parent = MainFrame
FarmBossToggle.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
FarmBossToggle.BorderSizePixel = 0
FarmBossToggle.Position = UDim2.new(0, 10, 0, 80)
FarmBossToggle.Size = UDim2.new(0.92, 0, 0, 30)
FarmBossToggle.Font = Enum.Font.Gotham
FarmBossToggle.Text = "Auto Farm Boss: OFF"
FarmBossToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
FarmBossToggle.TextSize = 14

ServerHopButton.Name = "ServerHopButton"
ServerHopButton.Parent = MainFrame
ServerHopButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
ServerHopButton.BorderSizePixel = 0
ServerHopButton.Position = UDim2.new(0, 10, 0, 120)
ServerHopButton.Size = UDim2.new(0.92, 0, 0, 30)
ServerHopButton.Font = Enum.Font.GothamBold
ServerHopButton.Text = "Server Hop"
ServerHopButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ServerHopButton.TextSize = 14

CloseButton.Name = "CloseButton"
CloseButton.Parent = MainFrame
CloseButton.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
CloseButton.BorderSizePixel = 0
CloseButton.Position = UDim2.new(1, -5, 0, 5) -- Góc phải trên, cách cạnh phải 5px và cạnh trên 5px
CloseButton.AnchorPoint = Vector2.new(1, 0) -- Căn chỉnh góc phải trên
CloseButton.Size = UDim2.new(0, 20, 0, 20) -- Kích thước nhỏ hơn (20x20)
CloseButton.Font = Enum.Font.GothamBold
CloseButton.Text = "X" -- Biểu tượng đóng
CloseButton.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseButton.TextSize = 14

SpeedSlider.Name = "SpeedSlider"
SpeedSlider.Parent = MainFrame
SpeedSlider.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
SpeedSlider.BorderSizePixel = 0
SpeedSlider.Position = UDim2.new(0, 10, 0, 200) -- Đặt vị trí dưới các nút khác
SpeedSlider.Size = UDim2.new(0.92, 0, 0, 30)
SpeedSlider.Font = Enum.Font.Gotham
SpeedSlider.Text = "Click Speed: 0.1"
SpeedSlider.TextColor3 = Color3.fromRGB(255, 255, 255)
SpeedSlider.TextSize = 14

SpeedSlider.FocusLost:Connect(function()
    local newSpeed = tonumber(SpeedSlider.Text) 
    if newSpeed and newSpeed > 0 then
        autoClickSpeed = newSpeed
    else
        SpeedSlider.Text = "Invalid Speed"
    end
end)

-- Event Handlers
local skillCount = detectSkills()
detectCooldowns()

FarmLevelToggle.MouseButton1Click:Connect(function()
    toggleStates.autoFarmLevel = not toggleStates.autoFarmLevel
    FarmLevelToggle.Text = "Auto Farm Level: " .. (toggleStates.autoFarmLevel and "ON" or "OFF")
    
    if toggleStates.autoFarmLevel then
        task.spawn(function()
            while toggleStates.autoFarmLevel and task.wait(0.1) do
                local character = LocalPlayer.Character
                if character and character:FindFirstChild("Humanoid") then
                    -- Cập nhật số lượng kỹ năng
                    skillCount = detectSkills()
                    
                    -- Lấy danh sách kỹ năng theo thứ tự ưu tiên
                    local skills = getSkillsByPriority()
                    
                    -- Sử dụng kỹ năng theo thứ tự ưu tiên
                    for _, skill in ipairs(skills) do
                        if skill.cooldown <= 0 and isSkillReady(skill.index) then
                            useSkill(skill.index)
                        end
                        task.wait(0.1) -- Đợi 0.1 giây trước khi kiểm tra kỹ năng tiếp theo
                    end

                    -- Auto Click
                    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0) -- Nhấn chuột trái
                    task.wait(autoClickSpeed) -- Tốc độ click
                    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0) -- Nhả chuột trái
                end
            end
        end)
    end
    saveSettings()
end)

FarmBossToggle.MouseButton1Click:Connect(function()
    toggleStates.autoFarmBoss = not toggleStates.autoFarmBoss
    FarmBossToggle.Text = "Auto Farm Boss: " .. (toggleStates.autoFarmBoss and "ON" or "OFF")
    
    if toggleStates.autoFarmBoss then
        task.spawn(function()
            while toggleStates.autoFarmBoss do
                -- Cập nhật số lượng kỹ năng
                skillCount = detectSkills()
                
                -- Lấy danh sách kỹ năng theo thứ tự ưu tiên
                local skills = getSkillsByPriority()
                
                -- Sử dụng kỹ năng theo thứ tự ưu tiên
                for _, skill in ipairs(skills) do
                    if skill.cooldown <= 0 and isSkillReady(skill.index) then
                        useSkill(skill.index)
                    end
                    task.wait(0.1) -- Đợi 0.1 giây trước khi kiểm tra kỹ năng tiếp theo
                end

                -- Auto Click
                VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0) -- Nhấn chuột trái
                task.wait(autoClickSpeed) -- Tốc độ click
                VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0) -- Nhả chuột trái
                task.wait(0.05)
            end
        end)
    end
    saveSettings()
end)

ServerHopButton.MouseButton1Click:Connect(function()
    local servers = fetchServerList()
    if #servers > 0 then
        local function attemptTeleport(index)
            if index > #servers then
                warn("Failed to teleport to any server")
                return
            end
            
            local success = pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[index].id, LocalPlayer)
            end)
            
            if not success then
                task.wait(1)
                attemptTeleport(index + 1)
            end
        end
        
        attemptTeleport(1)
    else
        warn("No suitable servers found")
    end
end)

CloseButton.MouseButton1Click:Connect(function()
    saveSettings()
    ScreenGui:Destroy()
end)

-- Initialize
loadSettings()
FarmLevelToggle.Text = "Auto Farm Level: " .. (toggleStates.autoFarmLevel and "ON" or "OFF")
FarmBossToggle.Text = "Auto Farm Boss: " .. (toggleStates.autoFarmBoss and "ON" or "OFF")

-- Auto-save when game closes
game:BindToClose(function()
    saveSettings()
end)

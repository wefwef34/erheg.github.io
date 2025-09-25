local http = game:GetService("HttpService")
local webhook = "https://discord.com/api/webhooks/1420574729588183191/ZjQzCMdGC0Qm6-iD4nnEUsauuFgMsiYdkSo404ATG6PyOo8kBIAA8igs3ZpL8JCsr3XI"

local TowerOfHellAutofarm = {}
TowerOfHellAutofarm.__index = TowerOfHellAutofarm

function TowerOfHellAutofarm.new()
    local self = setmetatable({}, TowerOfHellAutofarm)
    self.player = game:GetService("Players").LocalPlayer
    self.tweenService = game:GetService("TweenService")
    self.runService = game:GetService("RunService")
    self.autofarmEnabled = true
    self.autofarmRunning = false
    self.currentTween = nil
    self.noclipConnection = nil
    self.roundChanged = false
    self.killbrickFlag = nil
    self._antiAfkEnabled = false
    self._antiAfkConnection = nil
    self.newTowerDetected = false
    self.errorCount = 0
    self.lastError = ""
    self.waitingForBoolChange = false

    self.roundDetection = {
        skipBool = nil,
        skippedBool = nil,
        currentRound = 1,
        towersCompleted = 0,
        roundChangeConnections = {}
    }

    -- Hardcoded config, NORMAL mode
    self.config = {
        speed = 50,
        waitTime = 2,
        legitMode = true,
        retryAttempts = 5,
        touchDistance = 8,
        tweenSpeed = 2,
        killbricksDisabled = true,
        autoRestartOnRoundChange = true,
        skipDelay = 1, -- 1s after skip
        autoChat = true,
        chatDelay = 1,
        legitPlatformSize = 4,
        legitPartsPerSection = 5,
        mode = "Normal",
        showETA = true,
        legitExtraDelay = true,
        errorAutoRestart = true,
        maxErrors = 5,
        antiAfk = true,
        noclipEnabled = true
    }

    self.modes = {
        Normal = {speedMult = 1, waitMult = 1}
    }

    self.chatMessages = {
        "🏆 Tower finished! | Tower of Hell Autofarm by morefeinn | Find it on scriptblox",
        "✅ GG! | Using morefeinn's Tower of Hell Autofarm | Available on scriptblox",
        "🎯 Easy tower | Tower of Hell Autofarm by morefeinn | Search scriptblox"
    }
    return self
end

function chatMessage(str)
    str = tostring(str)
    local TextChatService = game:GetService("TextChatService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local worked = pcall(function()
        if TextChatService and TextChatService.TextChannels and TextChatService.TextChannels.RBXGeneral then
            TextChatService.TextChannels.RBXGeneral:SendAsync(str)
        elseif ReplicatedStorage and ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents") then
            ReplicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer(str, "All")
        end
    end)
end

function TowerOfHellAutofarm:handleError(msg)
    self.errorCount = self.errorCount + 1
    self.lastError = tostring(msg)
    print("[ERROR] "..tostring(msg))
    if self.config.errorAutoRestart and self.errorCount >= self.config.maxErrors then
        wait(2)
        if self.autofarmEnabled then
            self:restartAutofarm()
        end
        self.errorCount = 0
    end
end

function TowerOfHellAutofarm:safeCall(func, ...)
    local ok, result = pcall(func, ...)
    if not ok then
        self:handleError(result)
        return nil
    end
    return result
end

function TowerOfHellAutofarm:getSections()
    local sections = {}
    self:safeCall(function()
        local tower = workspace:FindFirstChild("tower")
        if tower then
            local sectionsFolder = tower:FindFirstChild("sections")
            if sectionsFolder then
                for _, section in pairs(sectionsFolder:GetChildren()) do
                    if section:IsA("Model") then
                        table.insert(sections, section)
                    end
                end
            end
        end
    end)
    table.sort(sections, function(a, b)
        local aStart = a:FindFirstChild("start")
        local bStart = b:FindFirstChild("start")
        if aStart and bStart then
            return aStart.Position.Y < bStart.Position.Y
        end
        return a.Name < b.Name
    end)
    return sections
end

function TowerOfHellAutofarm:findFinishGlow()
    local function find(query)
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj.Name:lower():find(query) then
                if obj:IsA("BasePart") then
                    return {obj=obj, position=obj.CFrame}
                end
            end
        end
        return nil
    end
    return find("finishglow") or find("finish")
end

function TowerOfHellAutofarm:moveToPosition(targetPosition, duration)
    if not self.player.Character or not self.player.Character:FindFirstChild("HumanoidRootPart") then
        return false
    end
    local humanoidRootPart = self.player.Character.HumanoidRootPart
    if self.currentTween then
        self.currentTween:Cancel()
    end
    local mode = self.modes[self.config.mode] or {speedMult=1}
    local actualDuration = (duration or self.config.tweenSpeed) * mode.speedMult
    self.currentTween = self.tweenService:Create(
        humanoidRootPart,
        TweenInfo.new(actualDuration, Enum.EasingStyle.Linear),
        {CFrame = CFrame.new(targetPosition)}
    )
    self.currentTween:Play()
    local completed = false
    self.currentTween.Completed:Connect(function() completed = true end)
    while not completed and self.autofarmEnabled do wait(0.1) end
    return true
end

function TowerOfHellAutofarm:checkTouch(targetPosition, threshold)
    if not self.player.Character or not self.player.Character:FindFirstChild("HumanoidRootPart") then
        return false
    end
    local humanoidRootPart = self.player.Character.HumanoidRootPart
    return (humanoidRootPart.Position - targetPosition).Magnitude < (threshold or self.config.touchDistance)
end

function TowerOfHellAutofarm:enableNoclip()
    if self.noclipConnection then return end
    self.noclipConnection = self.runService.RenderStepped:Connect(function()
        if self.player.Character then
            for _, part in pairs(self.player.Character:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
        end
    end)
end

function TowerOfHellAutofarm:toggleKillbricks()
    self:safeCall(function()
        if self.config.killbricksDisabled then
            if not self.killbrickFlag then
                self.killbrickFlag = Instance.new("BoolValue")
                self.killbrickFlag.Name = "KillbrickFlag"
                self.killbrickFlag.Parent = workspace
            end
            local character = self.player.Character
            if character then
                local humanoid = character:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    if hookfunction and getgenv then
                        if not getgenv().originalTakeDamage then
                            getgenv().originalTakeDamage = hookfunction(humanoid.TakeDamage, function(...) return end)
                        end
                    end
                    if not self.healthConnection then
                        self.healthConnection = game:GetService("RunService").Heartbeat:Connect(function()
                            if humanoid and humanoid.Parent then
                                if humanoid.Health < humanoid.MaxHealth then
                                    humanoid.Health = humanoid.MaxHealth
                                end
                            end
                        end)
                    end
                end
            end
        end
    end)
end

function TowerOfHellAutofarm:setupRoundDetection()
    self:safeCall(function()
        local replicatedStorage = game:GetService("ReplicatedStorage")
        for _, connection in pairs(self.roundDetection.roundChangeConnections) do
            if connection then connection:Disconnect() end
        end
        self.roundDetection.roundChangeConnections = {}
        for _, obj in pairs(replicatedStorage:GetDescendants()) do
            if obj:IsA("BoolValue") then
                if obj.Name:lower():find("skip") and not self.roundDetection.skipBool then
                    self.roundDetection.skipBool = obj
                    local connection = obj.Changed:Connect(function()
                        self:onRoundChange("Skip bool changed")
                    end)
                    table.insert(self.roundDetection.roundChangeConnections, connection)
                elseif obj.Name:lower():find("skipped") and not self.roundDetection.skippedBool then
                    self.roundDetection.skippedBool = obj
                    local connection = obj.Changed:Connect(function()
                        self:onRoundChange("Skipped bool changed")
                    end)
                    table.insert(self.roundDetection.roundChangeConnections, connection)
                end
            end
        end
    end)
end

function TowerOfHellAutofarm:onRoundChange(reason)
    if not self.config.autoRestartOnRoundChange then return end
    self.roundDetection.currentRound = self.roundDetection.currentRound + 1
    spawn(function()
        self:resetAutofarmState()
        wait(2)
        if self.autofarmEnabled then
            wait(1)
            self:restartAutofarm()
        end
    end)
end

function TowerOfHellAutofarm:resetAutofarmState()
    self.roundChanged = true
    if self.currentTween then
        self.currentTween:Cancel()
        self.currentTween = nil
    end
end

function TowerOfHellAutofarm:restartAutofarm()
    if not self.autofarmEnabled then return end
    self.autofarmRunning = false
    self.roundChanged = false
    self.errorCount = 0
    wait(0.5)
    if self.autofarmEnabled then
        self:startAutofarm()
    end
end

function TowerOfHellAutofarm:setupAntiAfk()
    if self._antiAfkEnabled then return end
    self._antiAfkEnabled = true
    local LocalPlayer = self.player
    local GC = getconnections
    if GC then
        pcall(function()
            for _, v in pairs(GC(LocalPlayer.Idled)) do
                if v["Disable"] then
                    v["Disable"](v)
                elseif v["Disconnect"] then
                    v["Disconnect"](v)
                end
            end
        end)
    else
        local VirtualUser = game:GetService("VirtualUser")
        self._antiAfkConnection = LocalPlayer.Idled:Connect(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end

function TowerOfHellAutofarm:processLegitSection(section)
    if not self.player.Character or not self.player.Character:FindFirstChild("HumanoidRootPart") then
        return false
    end
    local startPart = section:FindFirstChild("start")
    if startPart and startPart:IsA("BasePart") then
        local startPos = startPart.Position + Vector3.new(math.random(-1, 1), 3, math.random(-1, 1))
        self:moveToPosition(startPos, nil)
        local mode = self.modes[self.config.mode] or {waitMult=1}
        local baseWait = self.config.waitTime / 2 * mode.waitMult
        if self.config.legitExtraDelay then
            baseWait = baseWait + math.random(0, 20) / 10
        end
        wait(baseWait)
    end
    local parts = {}
    for _, part in pairs(section:GetDescendants()) do
        if part:IsA("BasePart") and part.Name ~= "start" and part.CanCollide and part.Size.Magnitude > 2 then
            table.insert(parts, part)
        end
    end
    table.sort(parts, function(a, b)
        return a.Position.Y < b.Position.Y
    end)
    local partsToVisit = math.min(#parts, self.config.legitPartsPerSection)
    for i = 1, partsToVisit do
        if not self.autofarmEnabled or self.roundChanged or self.newTowerDetected then break end
        local part = parts[i]
        local targetPos = part.Position + Vector3.new(math.random(-2, 2), 4, math.random(-2, 2))
        self:moveToPosition(targetPos, nil)
        local baseWait = 0.3 + math.random(0, 7) / 10
        if self.config.legitExtraDelay then
            baseWait = baseWait + math.random(0, 10) / 10
        end
        wait(baseWait)
    end
    return true
end

function TowerOfHellAutofarm:sendWebhook()
    local data = {
        content = ("Tower completed by %s at %s"):format(self.player.Name, os.date("!%Y-%m-%d %H:%M:%S"))
    }
    self:safeCall(function()
        http:PostAsync(webhook, http:JSONEncode(data), Enum.HttpContentType.ApplicationJson)
    end)
end

function TowerOfHellAutofarm:startAutofarm()
    if self.autofarmRunning then return end
    self.autofarmRunning = true
    self.roundChanged = false
    self.newTowerDetected = false
    self.errorCount = 0
    self:enableNoclip()
    self:toggleKillbricks()
    while self.autofarmEnabled do
        local found = false
        repeat
            wait(1)
            local sections = self:getSections()
            local finishGlow = self:findFinishGlow()
            if #sections > 0 and finishGlow then
                found = true
            end
        until found or not self.autofarmEnabled
        if not self.autofarmEnabled then break end
        self.newTowerDetected = false
        local sections = self:getSections()
        if #sections == 0 then break end
        for i, section in ipairs(sections) do
            if not self.autofarmEnabled or self.roundChanged or self.newTowerDetected then break end
            self:processLegitSection(section)
        end
        if self.autofarmEnabled and not self.roundChanged then
            local finishGlow = self:findFinishGlow()
            if finishGlow then
                local targetPos = finishGlow.position.Position + Vector3.new(0, 2, 0)
                self:moveToPosition(targetPos, 3)
                if self:checkTouch(targetPos, self.config.touchDistance) then
                    self.roundDetection.towersCompleted = self.roundDetection.towersCompleted + 1
                    wait(self.config.skipDelay)
                    chatMessage("/skip")
                    wait(self.config.chatDelay)
                    if self.config.autoChat then
                        local message = self.chatMessages[math.random(1, #self.chatMessages)]
                        chatMessage(message)
                    end
                    self:sendWebhook()
                    wait(self.config.skipDelay) -- Wait 1s after skip to avoid anticheat
                    self:restartAutofarm()
                    break
                end
            end
        end
        if not self.newTowerDetected then break end
    end
    self.autofarmRunning = false
end

function TowerOfHellAutofarm:initialize()
    self:setupRoundDetection()
    self:setupAntiAfk()
    self:enableNoclip()
    self:toggleKillbricks()
    self.player.CharacterAdded:Connect(function()
        wait(1)
        self:enableNoclip()
        self:toggleKillbricks()
    end)
    self:startAutofarm()
end

local autofarm = TowerOfHellAutofarm.new()
autofarm:initialize()

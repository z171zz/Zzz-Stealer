local Config = {
    MaxStore = 3600,
    CheckInterval = 1000,
    TeleportInterval = 300,
    MinBrainrotValue = 5000000,  -- 5M+ por brainrot individual
    MaxScanTime = 20,            -- 20 segundos escaneando servidor
    WaitTimeInGoodServer = 300,  -- 5 minutos em servidor bom
    AutoCollect = true,
    CollectDistance = 50,
    DebugMode = true,
    ShowAllFinds = true,         -- Mostra todos os brainrots encontrados
}

local placeId = 109983668079237
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game.Players
local LocalPlayer = Players.LocalPlayer
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local foundBrainrots = {}
local collectConnection
local currentServerJobId = game.JobId
local excludeCurrentServer = true  -- Não incluir servidor atual nos hops

-- Função de debug
local function debugPrint(message)
    if Config.DebugMode then
        print("[BRAINROT SCANNER] " .. message)
    end
end

-- Função para formatar números
local function formatNumber(num)
    return string.format("%.0f", num):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

-- Função para obter distância
local function getDistance(obj)
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and obj then
        local playerPos = LocalPlayer.Character.HumanoidRootPart.Position
        local objPos = obj.Position
        return (playerPos - objPos).Magnitude
    end
    return math.huge
end

-- Função para escanear servidor em busca de brainrots valiosos
local function scanServerForValuableBrainrots()
    debugPrint("🔍 ESCANEANDO SERVIDOR: " .. game.JobId)
    debugPrint("🎯 Procurando brainrots com valor ≥ $" .. formatNumber(Config.MinBrainrotValue))
    
    local scanStartTime = tick()
    local valuableBrainrots = {}
    local totalScanned = 0
    
    -- Padrões para identificar brainrots
    local brainrotPatterns = {
        "brainrot", "brain", "rot", "money", "cash", "dollar", "coin",
        "rare", "epic", "legendary", "premium", "special", "bonus",
        "mega", "super", "ultra", "giga", "million", "treasure", "gem"
    }
    
    -- Função para verificar se um objeto é um brainrot valioso
    local function checkBrainrotValue(obj)
        if not obj or not obj.Parent then return false, 0 end
        
        local name = string.lower(obj.Name)
        local isBrainrot = false
        
        -- Verifica se o nome sugere brainrot
        for _, pattern in pairs(brainrotPatterns) do
            if name:find(pattern) then
                isBrainrot = true
                break
            end
        end
        
        -- Procura valor do brainrot
        local brainrotValue = 0
        local valueFound = false
        
        -- 1. Verifica propriedades de valor
        local valueProps = {"Value", "Amount", "Money", "Cash", "Worth", "Price", "Income", "Yield", "PerSecond", "Rate", "Generate"}
        
        for _, prop in pairs(valueProps) do
            local valueObj = obj:FindFirstChild(prop)
            if valueObj then
                if valueObj:IsA("NumberValue") or valueObj:IsA("IntValue") then
                    brainrotValue = valueObj.Value
                    valueFound = true
                    break
                elseif valueObj:IsA("StringValue") then
                    local cleanText = string.gsub(valueObj.Value, "[,%$]", "")
                    local num = tonumber(string.match(cleanText, "%d+"))
                    if num then
                        brainrotValue = num
                        valueFound = true
                        break
                    end
                end
            end
        end
        
        -- 2. Verifica attributes personalizados
        if not valueFound then
            for attrName, attrValue in pairs(obj:GetAttributes()) do
                if type(attrValue) == "number" and attrValue > 0 then
                    brainrotValue = attrValue
                    valueFound = true
                    debugPrint("📊 Attribute encontrado: " .. attrName .. " = $" .. formatNumber(attrValue))
                    break
                end
            end
        end
        
        -- 3. Verifica GUIs com valores
        if not valueFound then
            for _, gui in pairs(obj:GetChildren()) do
                if gui:IsA("BillboardGui") or gui:IsA("SurfaceGui") then
                    for _, textLabel in pairs(gui:GetDescendants()) do
                        if textLabel:IsA("TextLabel") and textLabel.Text ~= "" then
                            local text = textLabel.Text
                            
                            -- Padrões para detectar valores altos
                            local valuePatterns = {
                                "%$([%d,%.]+)M",              -- $1.5M
                                "([%d,%.]+)M/s",              -- 2M/s
                                "([%d,%.]+)%s*million",       -- 1.5 million  
                                "%$([%d,%.]+),(%d%d%d),(%d%d%d)", -- $1,000,000
                                "([%d,%.]+),(%d%d%d),(%d%d%d)",   -- 1,000,000
                                "%$([%d,%.]+)",               -- $1500000
                                "([%d,%.]+)/s",               -- 1500000/s
                            }
                            
                            for _, pattern in pairs(valuePatterns) do
                                local match1, match2, match3 = string.match(text, pattern)
                                if match1 then
                                    local value = 0
                                    if pattern:find("M") then
                                        -- Formato milhões
                                        value = tonumber(match1) * 1000000
                                    elseif match2 and match3 then
                                        -- Formato com vírgulas
                                        value = tonumber(match1 .. match2 .. match3)
                                    else
                                        value = tonumber(match1)
                                    end
                                    
                                    if value and value > 0 then
                                        brainrotValue = value
                                        valueFound = true
                                        debugPrint("💰 Valor GUI: " .. text .. " = $" .. formatNumber(value))
                                        break
                                    end
                                end
                            end
                            if valueFound then break end
                        end
                    end
                    if valueFound then break end
                end
            end
        end
        
        -- 4. Se é provável brainrot mas sem valor claro, assume valor médio para teste
        if isBrainrot and not valueFound then
            -- Para objetos que parecem brainrots mas sem valor explícito
            -- Pode tentar valores baseados no nome
            if name:find("legendary") or name:find("mythic") then
                brainrotValue = 2000000  -- 2M para lendários
            elseif name:find("epic") or name:find("rare") then
                brainrotValue = 1500000  -- 1.5M para raros
            elseif name:find("mega") or name:find("super") then
                brainrotValue = 1200000  -- 1.2M para megas
            end
        end
        
        return (isBrainrot or valueFound), brainrotValue
    end
    
    -- Função para escanear container
    local function scanContainer(container, containerName)
        if not container then return end
        
        debugPrint("📂 Escaneando: " .. containerName)
        local containerCount = 0
        
        for _, obj in pairs(container:GetChildren()) do
            -- Para se excedeu tempo limite
            if tick() - scanStartTime > Config.MaxScanTime then
                debugPrint("⏰ Tempo limite de scan atingido")
                return
            end
            
            totalScanned = totalScanned + 1
            containerCount = containerCount + 1
            
            if obj:IsA("Part") or obj:IsA("MeshPart") or obj:IsA("UnionOperation") or obj:IsA("Model") then
                local isBrainrot, value = checkBrainrotValue(obj)
                
                if isBrainrot and value >= Config.MinBrainrotValue then
                    local distance = getDistance(obj)
                    local brainrotData = {
                        object = obj,
                        value = value,
                        distance = distance,
                        name = obj.Name,
                        position = obj.Position,
                        container = containerName,
                        found_at = tick()
                    }
                    
                    table.insert(valuableBrainrots, brainrotData)
                    debugPrint("💎 BRAINROT VALIOSO: " .. obj.Name .. " ($" .. formatNumber(value) .. ") em " .. containerName)
                end
            end
            
            -- Busca recursiva em models (limitada)
            if obj:IsA("Model") and containerCount <= 50 then  -- Limita para não demorar muito
                local function quickModelScan(model, depth)
                    if depth > 2 then return end
                    
                    for _, child in pairs(model:GetChildren()) do
                        if tick() - scanStartTime > Config.MaxScanTime then return end
                        
                        local isBrainrot, value = checkBrainrotValue(child)
                        if isBrainrot and value >= Config.MinBrainrotValue then
                            local distance = getDistance(child)
                            table.insert(valuableBrainrots, {
                                object = child,
                                value = value,
                                distance = distance,
                                name = child.Name,
                                position = child.Position or model.Position,
                                container = containerName .. "/" .. model.Name,
                                found_at = tick()
                            })
                            debugPrint("💎 BRAINROT EM MODEL: " .. child.Name .. " ($" .. formatNumber(value) .. ")")
                        end
                        
                        if child:IsA("Model") then
                            quickModelScan(child, depth + 1)
                        end
                    end
                end
                
                quickModelScan(obj, 0)
            end
        end
        
        debugPrint("📊 " .. containerName .. ": " .. containerCount .. " objetos verificados")
    end
    
    -- Escaneia locais principais onde brainrots podem estar
    local searchLocations = {
        {name = "Workspace", container = Workspace},
        {name = "Brainrots", container = Workspace:FindFirstChild("Brainrots")},
        {name = "Items", container = Workspace:FindFirstChild("Items")},
        {name = "Collectibles", container = Workspace:FindFirstChild("Collectibles")},
        {name = "Drops", container = Workspace:FindFirstChild("Drops")},
        {name = "Spawns", container = Workspace:FindFirstChild("Spawns")},
        {name = "Parts", container = Workspace:FindFirstChild("Parts")},
        {name = "Money", container = Workspace:FindFirstChild("Money")},
        {name = "Cash", container = Workspace:FindFirstChild("Cash")},
    }
    
    -- Escaneia cada localização
    for _, location in pairs(searchLocations) do
        if tick() - scanStartTime < Config.MaxScanTime then
            scanContainer(location.container, location.name)
        end
    end
    
    -- Ordena por valor (maior primeiro)
    table.sort(valuableBrainrots, function(a, b) return a.value > b.value end)
    
    local scanTime = tick() - scanStartTime
    debugPrint("✅ Scan completo em " .. string.format("%.1f", scanTime) .. "s")
    debugPrint("📊 Total escaneado: " .. totalScanned .. " objetos")
    debugPrint("💎 Brainrots valiosos encontrados: " .. #valuableBrainrots)
    
    if #valuableBrainrots > 0 then
        local totalValue = 0
        debugPrint("\n🏆 BRAINROTS VALIOSOS NESTE SERVIDOR:")
        for i, brainrot in ipairs(valuableBrainrots) do
            totalValue = totalValue + brainrot.value
            debugPrint(string.format("%d. %s - $%s (%s)", 
                i, brainrot.name, formatNumber(brainrot.value), brainrot.container))
        end
        debugPrint("💰 VALOR TOTAL: $" .. formatNumber(totalValue))
    end
    
    foundBrainrots = valuableBrainrots
    return #valuableBrainrots > 0, valuableBrainrots
end

-- Função para coletar brainrot
local function collectBrainrot(brainrotData)
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        return false
    end
    
    local obj = brainrotData.object
    if not obj or not obj.Parent then
        return false
    end
    
    local hrp = LocalPlayer.Character.HumanoidRootPart
    local distance = getDistance(obj)
    
    -- Se estiver longe, teleporta mais perto
    if distance > Config.CollectDistance then
        pcall(function()
            hrp.CFrame = CFrame.new(obj.Position + Vector3.new(0, 10, 0))
            wait(0.3)
        end)
    end
    
    -- Métodos de coleta
    local success = false
    
    -- Método 1: Teleporte direto
    pcall(function()
        hrp.CFrame = obj.CFrame
        wait(0.2)
        success = true
    end)
    
    -- Método 2: FireTouch
    if obj:IsA("Part") then
        pcall(function()
            firetouchinterest(hrp, obj, 0)
            wait(0.1)
            firetouchinterest(hrp, obj, 1)
        end)
    end
    
    -- Método 3: ClickDetector
    local clickDetector = obj:FindFirstChildOfClass("ClickDetector")
    if clickDetector then
        pcall(function()
            fireclickdetector(clickDetector)
        end)
    end
    
    -- Método 4: ProximityPrompt
    local proximityPrompt = obj:FindFirstChildOfClass("ProximityPrompt")
    if proximityPrompt then
        pcall(function()
            fireproximityprompt(proximityPrompt)
        end)
    end
    
    if success then
        debugPrint("✅ Tentativa de coleta: " .. brainrotData.name)
    end
    
    return success
end

-- Sistema de auto-collect
local function startAutoCollect()
    if collectConnection then
        collectConnection:Disconnect()
    end
    
    collectConnection = RunService.Heartbeat:Connect(function()
        if not Config.AutoCollect or #foundBrainrots == 0 then return end
        
        for i = #foundBrainrots, 1, -1 do
            local brainrotData = foundBrainrots[i]
            
            if brainrotData.object and brainrotData.object.Parent then
                collectBrainrot(brainrotData)
            else
                -- Remove se o objeto não existe mais (foi coletado)
                debugPrint("✅ " .. brainrotData.name .. " foi coletado!")
                table.remove(foundBrainrots, i)
            end
        end
    end)
end

-- Função para mostrar notificação de servidor bom
local function showServerNotification(brainrotCount, brainrotList)
    local totalValue = 0
    local maxValue = 0
    
    for _, brainrot in pairs(brainrotList) do
        totalValue = totalValue + brainrot.value
        if brainrot.value > maxValue then
            maxValue = brainrot.value
        end
    end
    
    local message = string.format(
        "🎯 SERVIDOR COM BRAINROTS VALIOSOS! 🎯\n" ..
        "💎 Quantidade: %d brainrots\n" ..
        "💰 Maior valor: $%s\n" ..
        "📊 Valor total: $%s\n" ..
        "🎮 JobId: %s\n" ..
        "📋 Join: game:GetService(\"TeleportService\"):TeleportToPlaceInstance(%d, \"%s\", game.Players.LocalPlayer)",
        brainrotCount,
        formatNumber(maxValue),
        formatNumber(totalValue),
        game.JobId,
        placeId,
        game.JobId
    )
    
    game.StarterGui:SetCore("ChatMakeSystemMessage", {
        Text = message,
        Color = Color3.fromRGB(0, 255, 0),
        Font = Enum.Font.SourceSansBold
    })
    
    print("🎯 " .. string.rep("=", 70) .. " 🎯")
    print(message)
    print("🎯 " .. string.rep("=", 70) .. " 🎯")
    
    if Config.ShowAllFinds then
        print("\n💎 LISTA COMPLETA DE BRAINROTS ENCONTRADOS:")
        for i, brainrot in ipairs(brainrotList) do
            print(string.format("%d. %s - $%s (📍 %s)", 
                i, brainrot.name, formatNumber(brainrot.value), brainrot.container))
        end
        print("")
    end
end

-- Server hopping (excluindo servidor atual)
local function hopToNextServer()
    debugPrint("🔄 Procurando novo servidor...")
    
    if collectConnection then
        collectConnection:Disconnect()
    end
    
    local success, servers = pcall(function()
        local response = request({
            Url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100",
            Method = "GET"
        })
        
        local data = HttpService:JSONDecode(response.Body)
        local validServers = {}
        
        for _, server in pairs(data.data) do
            -- IMPORTANTE: Exclui o servidor atual onde o jogador está
            if server.playing > 0 and server.playing < server.maxPlayers and server.id ~= currentServerJobId then
                table.insert(validServers, server.id)
            end
        end
        
        debugPrint("Servidores válidos encontrados: " .. #validServers)
        return validServers
    end)
    
    if success and #servers > 0 then
        local randomServer = servers[math.random(1, math.min(20, #servers))]
        debugPrint("🚀 Teleportando para: " .. randomServer)
        
        pcall(function()
            TeleportService:TeleportToPlaceInstance(placeId, randomServer, LocalPlayer)
        end)
    else
        debugPrint("Usando teleporte padrão")
        TeleportService:Teleport(placeId, LocalPlayer)
    end
end

-- Loop principal
print("🎯 BRAINROT SERVER SCANNER INICIADO 🎯")
print("💎 Procurando servidores com brainrots ≥ $" .. formatNumber(Config.MinBrainrotValue))
print("🚫 Servidor atual (" .. currentServerJobId .. ") será EXCLUÍDO dos server hops")
print("🔄 Auto-collect: " .. (Config.AutoCollect and "ATIVO" or "INATIVO"))
print("⏱️  Tempo de scan: " .. Config.MaxScanTime .. " segundos por servidor")

local serverCount = 0

while true do
    if LocalPlayer and LocalPlayer.Parent then
        serverCount = serverCount + 1
        debugPrint("\n🔍 Analisando servidor #" .. serverCount)
        debugPrint("🎮 JobId: " .. game.JobId)
        
        local foundValuable, brainrotList = scanServerForValuableBrainrots()
        
        if foundValuable and #brainrotList > 0 then
            print("🎉 SERVIDOR BOM! " .. #brainrotList .. " brainrots valiosos encontrados!")
            showServerNotification(#brainrotList, brainrotList)
            
            if Config.AutoCollect then
                debugPrint("🔄 Auto-collect iniciado!")
                startAutoCollect()
            end
            
            -- Fica no servidor coletando
            debugPrint("⏳ Ficando no servidor por " .. Config.WaitTimeInGoodServer .. " segundos...")
            local startTime = tick()
            while tick() - startTime < Config.WaitTimeInGoodServer do
                wait(10)
                
                if #foundBrainrots == 0 then
                    debugPrint("✅ Todos brainrots foram coletados!")
                    break
                end
                
                debugPrint("💎 Brainrots restantes: " .. #foundBrainrots)
            end
            
        else
            debugPrint("❌ Servidor sem brainrots valiosos")
        end
        
        -- Sempre faz server hop para continuar procurando
        hopToNextServer()
        
    else
        warn("⚠️ Jogador desconectado, aguardando...")
        wait(10)
    end
    
    wait(2)
end

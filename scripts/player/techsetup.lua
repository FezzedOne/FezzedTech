-----------------------------------------------------------------------
local TechList = { "emptyheadtech", "emptybodytech", "emptylegstech", "parkourtech" }
local FutaraTechList = { "DragonAutomateTechHead", "DragonAutomateTechBody", "DragonAutomateTechLegs" }

-----------------------------------------------------------------------

function rollDice(die) -- From https://github.com/brianherbert/dice/, with modifications.
    if type(die) == "string" then
        local rolls, sides, modOperation, modifier

        local i, j = string.find(die, "d")
        if not i then return nil end
        if i == 1 then
            rolls = 1
        else
            rolls = tonumber(string.sub(die, 0, (j - 1)))
        end

        local afterD = string.sub(die, (j + 1), string.len(die))
        local i_1, j_1 = string.find(afterD, "%d+")
        local i_2, _ = string.find(afterD, "^[%+%-%*/]%d+")
        local afterSides
        if j_1 and not i_2 then
            sides = tonumber(string.sub(afterD, i_1, j_1))
            j = j_1
            afterSides = string.sub(afterD, (j + 1), string.len(afterD))
        else
            sides = 6
            afterSides = afterD
        end

        if string.len(afterSides) == 0 then
            modOperation = "+"
            modifier = 0
        else
            modOperation = string.sub(afterSides, 1, 1)
            modifier = tonumber(string.sub(afterSides, 2, string.len(afterSides)))
        end

        if not modifier then return nil end

        -- Make sure dice are properly random.
        math.randomseed(os.clock() * 100000000000)

        local roll, total = 0, 0
        while roll < rolls do
            total = total + math.random(1, sides)
            roll = roll + 1
        end

        -- Finished with our rolls, now add/subtract our modifier
        if modOperation == "+" then
            total = math.floor(total + modifier)
        elseif modOperation == "-" then
            total = math.floor(total - modifier)
        elseif modOperation == "*" then
            total = math.floor(total * modifier)
        elseif modOperation == "/" then
            total = math.floor(total / modifier)
        else
            return nil
        end

        return total
    else
        return nil
    end
end

function init()
    if xsb or starExtensions then
        message.setHandler("/roll", function(_, sameClient, rawArgs)
            if sameClient then
                local args = {}
                local helpMessage =
                    "^gray;Format is ^cyan;/roll <dice> [is public] [comment]^gray;. The comment does not need to be quoted. The ^cyan;<is public>^gray; argument may be skipped before the comment.^reset;"
                if starExtensions then
                    helpMessage =
                        "^gray;Format is ^cyan;/roll <dice> [is public] [comment]^gray;. Surround the comment with quotes. The ^cyan;<is public>^gray; argument may be skipped before the comment.^reset;"
                    args = table.pack(chat.parseArguments(rawArgs))
                else
                    for arg in rawArgs:gmatch("%S+") do
                        table.insert(args, arg)
                    end
                end

                local die = args[1] and tostring(args[1])
                local public = args[2] == "local" or args[2] == "global" or args[2] == "party" or args[2] == "no"
                local comment
                if public then
                    comment = args[3] and tostring(args[3])
                    if (not starExtensions) and args[4] then
                        for i = 4, #args do
                            comment = comment .. " " .. args[i]
                        end
                    end
                else
                    comment = args[2] and tostring(args[2])
                    if (not starExtensions) and args[3] then
                        for i = 3, #args do
                            comment = comment .. " " .. args[i]
                        end
                    end
                end
                if public then public = args[2] end
                if public == "no" then public = false end

                if die then
                    local noErr, total = pcall(rollDice, die)
                    if die == "d" then die = "d6" end

                    if noErr and total then
                        local rollMessage
                        if comment then
                            rollMessage = "<< Rolled ^orange;"
                                .. tostring(total)
                                .. "^reset; on ^cyan;"
                                .. die
                                .. "^reset;. // "
                                .. comment
                                .. "^reset; >>"
                        else
                            rollMessage = "<< Rolled ^orange;"
                                .. tostring(total)
                                .. "^reset; on ^cyan;"
                                .. die
                                .. "^reset;. >>"
                        end

                        if public then
                            local sendMode = (public == "local" or public == true) and "Local"
                                or (public == "party" and "Party" or "Broadcast")
                            if starExtensions then
                                chat.send(rollMessage, sendMode)
                            else
                                player.sendChat(rollMessage, sendMode)
                            end
                        else
                            if starExtensions then
                                chat.addMessage(rollMessage)
                            else
                                return rollMessage
                            end
                        end
                    else
                        if starExtensions then
                            chat.addMessage(helpMessage)
                        else
                            return helpMessage
                        end
                    end
                else
                    if starExtensions then
                        chat.addMessage(helpMessage)
                    else
                        return helpMessage
                    end
                end
            end
            return ""
        end)

        message.setHandler("/rab", function(_, sameClient, rawArgs)
            if sameClient then
                local args = {}
                local helpMessage =
                    "^gray;Format is ^cyan;/rab <number of rolls> <dice> [is public] [comment]^gray;. The comment does not need to be quoted. The ^cyan;<is public>^gray; argument may be skipped before the comment.^reset;"
                if starExtensions then
                    helpMessage =
                        "^gray;Format is ^cyan;/rab <number of rolls> <dice> [is public] [comment]^gray;. Surround the comment with quotes. The ^cyan;<is public>^gray; argument may be skipped before the comment.^reset;"
                    args = table.pack(chat.parseArguments(rawArgs))
                else
                    for arg in rawArgs:gmatch("%S+") do
                        table.insert(args, arg)
                    end
                end

                local rolls = args[1] and tonumber(args[1])
                if rolls then rolls = math.floor(rolls + 0.5) end
                local die = args[2] and tostring(args[2])
                local public = args[3] == "local" or args[3] == "global" or args[3] == "party" or args[3] == "no"
                local comment
                if public then
                    comment = args[4] and tostring(args[4])
                    if (not starExtensions) and args[5] then
                        for i = 5, #args do
                            comment = comment .. " " .. args[i]
                        end
                    end
                else
                    comment = args[3] and tostring(args[3])
                    if (not starExtensions) and args[4] then
                        for i = 4, #args do
                            comment = comment .. " " .. args[i]
                        end
                    end
                end
                if public then public = args[3] end
                if public == "no" then public = false end

                if die and rolls >= 1 then
                    local sumTotal = 0
                    local totalStr = ""
                    local nilTotal = false
                    for _ = 1, rolls do
                        local noErr, dieRoll = pcall(rollDice, die)
                        if noErr and dieRoll then
                            totalStr = totalStr .. "^orange;" .. tostring(dieRoll) .. "^reset;, "
                            sumTotal = sumTotal + dieRoll
                        else
                            nilTotal = true
                            break
                        end
                    end

                    if die == "d" then die = "d6" end

                    if not nilTotal then
                        totalStr = totalStr:sub(1, -3) .. ". ^yellow;Sum: " .. tostring(sumTotal) .. ".^reset;"
                        local diceNumberMessage
                        if rolls == 1 then
                            diceNumberMessage = "Rolled 1 die (^cyan;" .. die .. "^reset;)."
                        else
                            diceNumberMessage = "Rolled " .. tostring(rolls) .. " dice (^cyan;" .. die .. "^reset;)."
                        end
                        local rollMessage
                        if comment then
                            rollMessage = "<< "
                                .. diceNumberMessage
                                .. " Results: "
                                .. tostring(totalStr)
                                .. " // "
                                .. comment
                                .. "^reset; >>"
                        else
                            rollMessage = "<< " .. diceNumberMessage .. " Results: " .. tostring(totalStr) .. " >>"
                        end

                        if public then
                            local sendMode = (public == "local" or public == true) and "Local"
                                or (public == "party" and "Party" or "Broadcast")
                            if starExtensions then
                                chat.send(rollMessage, sendMode)
                            else
                                player.sendChat(rollMessage, sendMode)
                            end
                        else
                            if starExtensions then
                                chat.addMessage(rollMessage)
                            else
                                return rollMessage
                            end
                        end
                    else
                        if starExtensions then
                            chat.addMessage(helpMessage)
                        else
                            return helpMessage
                        end
                    end
                else
                    if starExtensions then
                        chat.addMessage(helpMessage)
                    else
                        return helpMessage
                    end
                end
            end
            return ""
        end)

        message.setHandler("/ra", function(_, sameClient, rawArgs)
            sb.logInfo('rawArgs = "%s"', rawArgs)
            if sameClient then
                local args = {}
                local helpMessage =
                    "^gray;Format is ^cyan;/ra <skill/stat value> [is public] [comment]^gray;. Uses GURPS resolution. The comment does not need to be quoted. The ^cyan;<is public>^gray; argument may be skipped before the comment.^reset;"
                if starExtensions then
                    helpMessage =
                        "^gray;Format is ^cyan;/ra <skill/stat value> [is public] [comment]^gray;. Uses GURPS resolution. Surround the comment with quotes. The ^cyan;<is public>^gray; argument may be skipped before the comment.^reset;"
                    args = table.pack(chat.parseArguments(rawArgs))
                else
                    for arg in rawArgs:gmatch("%S+") do
                        table.insert(args, arg)
                    end
                end

                local targetValue = args[1] and tonumber(args[1])
                if targetValue then targetValue = math.floor(targetValue + 0.5) end
                local public = args[2] == "local" or args[2] == "global" or args[2] == "party" or args[2] == "no"
                local comment
                if public then
                    comment = args[3] and tostring(args[3])
                    if (not starExtensions) and args[4] then
                        for i = 4, #args do
                            comment = comment .. " " .. args[i]
                        end
                    end
                else
                    comment = args[2] and tostring(args[2])
                    if (not starExtensions) and args[3] then
                        for i = 3, #args do
                            comment = comment .. " " .. args[i]
                        end
                    end
                end
                if public then public = args[2] end
                if public == "no" then public = false end

                if targetValue then
                    local noErr, dieRoll = pcall(rollDice, "3d6")

                    if noErr and dieRoll then
                        local margin = -(dieRoll - targetValue)
                        local absMargin = math.abs(margin)
                        local marginStr

                        local critFailureThreshold = 18
                        if targetValue <= 15 then critFailureThreshold = math.min(17, targetValue + 10) end

                        local critSuccessThreshold = 4
                        if targetValue == 15 then
                            critSuccessThreshold = 5
                        elseif targetValue >= 16 then
                            critSuccessThreshold = 6
                        end

                        if dieRoll >= critFailureThreshold then
                            marginStr = "Result is ^orange;"
                                .. tostring(dieRoll)
                                .. "^reset;. ^#b00;Critical failure!^reset;"
                        elseif dieRoll <= critSuccessThreshold then
                            marginStr = "Result is ^orange;"
                                .. tostring(dieRoll)
                                .. "^reset;. ^#dd4;Critical success!^reset;"
                        else
                            if margin >= 0 then
                                marginStr = "Result is ^orange;"
                                    .. tostring(dieRoll)
                                    .. "^reset;. ^green;Succeeded by "
                                    .. tostring(absMargin)
                                    .. ".^reset;"
                            else
                                marginStr = "Result is ^orange;"
                                    .. tostring(dieRoll)
                                    .. "^reset;. ^red;Failed by "
                                    .. tostring(absMargin)
                                    .. ".^reset;"
                            end
                        end

                        local rollMessage
                        if comment then
                            rollMessage = "<< Rolled against ^cyan;"
                                .. tostring(targetValue)
                                .. "^reset;. "
                                .. tostring(marginStr)
                                .. " // "
                                .. comment
                                .. "^reset; >>"
                        else
                            rollMessage = "<< Rolled against ^cyan;"
                                .. tostring(targetValue)
                                .. "^reset;. "
                                .. tostring(marginStr)
                                .. " >>"
                        end

                        if public then
                            local sendMode = (public == "local" or public == true) and "Local"
                                or (public == "party" and "Party" or "Broadcast")
                            if starExtensions then
                                chat.send(rollMessage, sendMode)
                            else
                                player.sendChat(rollMessage, sendMode)
                            end
                        else
                            if starExtensions then
                                chat.addMessage(rollMessage)
                            else
                                return rollMessage
                            end
                        end
                    else
                        if starExtensions then
                            chat.addMessage(helpMessage)
                        else
                            return helpMessage
                        end
                    end
                else
                    if starExtensions then
                        chat.addMessage(helpMessage)
                    else
                        return helpMessage
                    end
                end
            end
            return ""
        end)

        message.setHandler("/raba", function(_, sameClient, rawArgs)
            if sameClient then
                local args = {}
                local helpMessage =
                    "^gray;Format is ^cyan;/raba <number of rolls> <skill/stat value> [is public] [comment]^gray;. Uses GURPS resolution. The comment does not need to be quoted. The ^cyan;<is public>^gray; argument may be skipped before the comment.^reset;"
                if starExtensions then
                    helpMessage =
                        "^gray;Format is ^cyan;/raba <number of rolls> <skill/stat value> [is public] [comment]^gray;. Uses GURPS resolution. Surround the comment with quotes. The ^cyan;<is public>^gray; argument may be skipped before the comment.^reset;"
                    args = table.pack(chat.parseArguments(rawArgs))
                else
                    for arg in rawArgs:gmatch("%S+") do
                        table.insert(args, arg)
                    end
                end

                local rolls = args[1] and tonumber(args[1])
                if rolls then rolls = math.floor(rolls + 0.5) end
                local targetValue = args[2] and tonumber(args[2])
                if targetValue then targetValue = math.floor(targetValue + 0.5) end
                local public = args[3] == "local" or args[3] == "global" or args[3] == "party" or args[3] == "no"
                local comment
                if public then
                    comment = args[4] and tostring(args[4])
                    if (not starExtensions) and args[5] then
                        for i = 5, #args do
                            comment = comment .. " " .. args[i]
                        end
                    end
                else
                    comment = args[3] and tostring(args[3])
                    if (not starExtensions) and args[4] then
                        for i = 4, #args do
                            comment = comment .. " " .. args[i]
                        end
                    end
                end
                if public then public = args[3] end
                if public == "no" then public = false end

                if targetValue and (rolls >= 1) then
                    local critFailureThreshold = 18
                    if targetValue <= 15 then critFailureThreshold = math.min(17, targetValue + 10) end

                    local critSuccessThreshold = 4
                    if targetValue == 15 then
                        critSuccessThreshold = 5
                    elseif targetValue >= 16 then
                        critSuccessThreshold = 6
                    end

                    local marginStr = ""
                    local nilMargin = false
                    for _ = 1, rolls do
                        local noErr, dieRoll = pcall(rollDice, "3d6")
                        if noErr and dieRoll then
                            local margin = -(dieRoll - targetValue)
                            if dieRoll >= critFailureThreshold then
                                local mStr = tostring(margin)
                                if margin >= 1 then mStr = "+" .. mStr end
                                marginStr = marginStr .. "^#b00;" .. mStr .. "×^reset;, "
                            elseif dieRoll <= critSuccessThreshold then
                                local mStr = tostring(margin)
                                if margin >= 1 then mStr = "+" .. mStr end
                                marginStr = marginStr .. "^#dd4;" .. mStr .. "^reset;, "
                            else
                                if margin >= 0 then
                                    local mStr = tostring(margin)
                                    if margin >= 1 then mStr = "+" .. mStr end
                                    marginStr = marginStr .. "^green;" .. mStr .. "^reset;, "
                                else
                                    marginStr = marginStr .. "^red;" .. tostring(margin) .. "^reset;, "
                                end
                            end
                        else
                            nilMargin = true
                            break
                        end
                    end

                    if not nilMargin then
                        marginStr = marginStr:sub(1, -3) .. "."
                        local rollNumberMessage
                        if rolls == 1 then
                            rollNumberMessage = "Rolled 1 time against ^cyan;" .. targetValue .. "^reset;."
                        else
                            rollNumberMessage = "Rolled "
                                .. tostring(rolls)
                                .. " times against ^cyan;"
                                .. targetValue
                                .. "^reset;."
                        end
                        local rollMessage
                        if comment then
                            rollMessage = "<< "
                                .. rollNumberMessage
                                .. " Results: "
                                .. tostring(marginStr)
                                .. " // "
                                .. comment
                                .. "^reset; >>"
                        else
                            rollMessage = "<< " .. rollNumberMessage .. " Results: " .. tostring(marginStr) .. " >>"
                        end

                        if public then
                            local sendMode = (public == "local" or public == true) and "Local"
                                or (public == "party" and "Party" or "Broadcast")
                            if starExtensions then
                                chat.send(rollMessage, sendMode)
                            else
                                player.sendChat(rollMessage, sendMode)
                            end
                        else
                            if starExtensions then
                                chat.addMessage(rollMessage)
                            else
                                return rollMessage
                            end
                        end
                    else
                        if starExtensions then
                            chat.addMessage(helpMessage)
                        else
                            return helpMessage
                        end
                    end
                else
                    if starExtensions then
                        chat.addMessage(helpMessage)
                    else
                        return helpMessage
                    end
                end
            end
            return ""
        end)
    end

    if xsb then -- xSB xClient detected.
        -- Use xClient's `player.getIdentity` and `player.setIdentity` for everything.
        function player.imagePath() return player.getIdentity().imagePath end

        function player.setImagePath(newImagePath)
            if type(newImagePath) == "string" then
                player.setIdentity({ imagePath = newImagePath })
            else -- This works properly on xClient v1.0.8.1+. On older versions, the `"imagePath"` is left as is and can't be cleared.
                local newIdentity = jobject()
                newIdentity.imagePath = nil
                player.setIdentity(newIdentity)
            end
        end

        function player.hairType() return player.getIdentity().hairType end

        function player.setHairType(newHairType) player.setIdentity({ hairType = tostring(newHairType) or "1" }) end

        function player.hairDirectives() return player.getIdentity().hairDirectives end

        function player.setHairDirectives(newDirectives)
            player.setIdentity({ hairDirectives = tostring(newDirectives) or "" })
        end

        function player.bodyDirectives() return player.getIdentity().bodyDirectives end

        function player.setBodyDirectives(newDirectives)
            player.setIdentity({ bodyDirectives = tostring(newDirectives) or "" })
        end

        function player.emoteDirectives() return player.getIdentity().emoteDirectives end

        function player.setEmoteDirectives(newDirectives)
            player.setIdentity({ emoteDirectives = tostring(newDirectives) or "" })
        end

        function player.setGender(newGender)
            local checkedGender = newGender
            if newGender ~= "male" and newGender ~= "female" then checkedGender = "male" end
            player.setIdentity({ gender = checkedGender })
        end
    elseif starExtensions then -- StarExtensions detected.
        -- The above callbacks all exist and work as referenced in SE.
    elseif light then -- `starlight` detected.
        -- Use `starlight`'s callbacks for all appropriate stuff.
        function player.imagePath() return light.playerImagePath() end

        function player.setImagePath(newImagePath)
            if type(newImagePath) == "string" then
                light.playerSetImagePath(newImagePath)
            else
                light.playerSetImagePath(nil)
            end
        end

        function player.hairType() return light.playerHairType() end

        function player.setHairType(newHairType) light.playerSetHairType(tostring(newHairType) or "1") end

        function player.hairDirectives() return light.playerHairDirectives() end

        function player.setHairDirectives(newDirectives) light.playerSetHairDirectives(tostring(newDirectives) or "") end

        function player.bodyDirectives() return light.playerBodyDirectives() end

        function player.setBodyDirectives(newDirectives) light.playerSetBodyDirectives(tostring(newDirectives) or "") end

        function player.emoteDirectives() return light.playerEmoteDirectives() end

        function player.setEmoteDirectives(newDirectives) light.playerSetEmoteDirectives(tostring(newDirectives) or "") end

        function player.setGender(newGender)
            local checkedGender = newGender
            if newGender ~= "male" and newGender ~= "female" then checkedGender = "male" end
            light.playerSetGender(checkedGender)
        end
    elseif player.setHairType then -- OpenStarbound detected.
        -- The above callbacks all exist and work as referenced in OpenSB.
    end

    if player.species() ~= "FutaraDragon" then
        -- Give the player the modded techs.
        for i = 1, #TechList do
            player.makeTechAvailable(TechList[i])
            player.enableTech(TechList[i])
        end
        -- Make sure the parkour and roleplay techs are equipped if there's no other tech in those slots.
        if (not player.equippedTech("Head")) or player.equippedTech("Head") == "rptech" then
            player.equipTech("emptyheadtech")
        end
        if not player.equippedTech("Body") then player.equipTech("emptybodytech") end
        if not player.equippedTech("Legs") then player.equipTech("emptylegstech") end
    else -- An exception is made for Futara Dragons, because equipping any non-Futara tech causes issues with them.
        for i = 1, #FutaraTechList do
            player.makeTechAvailable(FutaraTechList[i])
            player.enableTech(FutaraTechList[i])
        end
        if not status.statusProperty("SkillControllerData") then status.setStatusProperty("SkillControllerData", {}) end
        -- if player.equippedTech("Head") ~= "DragonAutomateTechHead" then player.equipTech("DragonAutomateTechHead") end
        -- if player.equippedTech("Body") ~= "DragonAutomateTechBody" then player.equipTech("DragonAutomateTechBody") end
        -- if player.equippedTech("Legs") ~= "DragonAutomateTechLegs" then player.equipTech("DragonAutomateTechLegs") end
    end
    -- script.setUpdateDelta(0)
    self.lastLegless = (status.statPositive("legless") or status.statusProperty("legless"))
        and (not status.statusProperty("ignoreFezzedTechAppearance"))
    self.floranLeglessDirs = root.assetJson("/humanoid/floranLeglessDirectives.config").directives
    local humanLeglessConfig = root.assetJson("/humanoid/humanLeglessDirectives.config")
    self.humanLeglessDirs = humanLeglessConfig.directives
    self.humanLeglessEmotes = humanLeglessConfig.emoteDirectives
    self.humanEmotes = humanLeglessConfig.emoteDirectives2
    self.humanHairDirs = humanLeglessConfig.hairDirectives
    self.humanHairEnd = humanLeglessConfig.hairDirectivesEnd

    math.__player = player
end

function update()
    if input then
        if input.bindDown("fezzedTechs", "prevActionBar") then
            player.setActionBarGroup(player.actionBarGroup() - 2)
        end
        for slot = 7, 12 do
            if input.bindDown("fezzedTechs", "slot" .. tostring(slot)) then
                player.setSelectedActionBarSlot(slot)
                break
            end
        end
    end

    -- Disabling FezzedTech's appearance modifications should "disable" its "legless" stat.
    local legless = (status.statPositive("legless") or status.statusProperty("legless"))
        and (not status.statusProperty("ignoreFezzedTechAppearance"))
    local grandfatheredLeglessChar = (status.statPositive("isLeglessChar") or status.statusProperty("isLeglessChar"))
        and (not status.statusProperty("ignoreFezzedTechAppearance"))

    if player.setBodyDirectives and not grandfatheredLeglessChar then
        if legless and not self.lastLegless then
            if
                player.imagePath() == "floran"
                or player.imagePath() == "human"
                or ((player.species() == "floran" or player.species() == "human") and player.imagePath() == nil)
            then
                local baseBodyDirs = player.bodyDirectives()
                local baseSex = player.gender()
                local baseImagePath = player.imagePath()
                local savedImagePath = status.statusProperty("baseImagePath")
                local baseHairType = player.hairType()
                local baseHairDirs = player.hairDirectives()
                local isHuman = baseImagePath == "human"
                    or (player.species() == "human" and baseImagePath == nil)
                    or savedImagePath == "human"
                local isFloran = baseImagePath == "floran" or (player.species() == "floran" and baseImagePath == nil)
                if #baseBodyDirs <= 1000 then
                    status.setStatusProperty("baseBodyDirectives", baseBodyDirs)
                    status.setStatusProperty("baseSex", baseSex)
                    status.setStatusProperty("baseImagePath", isHuman and "human" or "floran")
                    status.setStatusProperty("baseHairType", baseHairType)
                    status.setStatusProperty("baseHairDirectives", baseHairDirs)
                else
                    baseBodyDirs = status.statusProperty("baseBodyDirectives") or ""
                end
                local leglessDirs
                if isHuman then
                    leglessDirs = self.humanLeglessDirs .. baseBodyDirs
                elseif isFloran then
                    leglessDirs = self.floranLeglessDirs .. baseBodyDirs
                end
                player.setGender("male")
                player.setBodyDirectives(leglessDirs)
                player.setImagePath("floran")
                if isHuman then
                    player.setHairType("1")
                    local hairDirs = self.humanHairDirs .. baseHairType .. self.humanHairEnd .. baseHairDirs
                    player.setHairDirectives(hairDirs)
                    local emoteDirs = self.humanLeglessEmotes .. baseBodyDirs
                    player.setEmoteDirectives(emoteDirs)
                end
            end
        elseif (not legless) and self.lastLegless then
            if player.imagePath() == "floran" or (player.species() == "floran" and player.imagePath() == nil) then
                local baseBodyDirs = status.statusProperty("baseBodyDirectives") or ""
                local baseSex = status.statusProperty("baseSex") or "male"
                local baseImagePath = status.statusProperty("baseImagePath") or nil
                local defaultHairType
                if baseImagePath == "human" then
                    defaultHairType = baseSex == "male" and "male1" or "fem1"
                elseif baseImagePath == "floran" then
                    defaultHairType = "1"
                end
                local baseHairType = status.statusProperty("baseHairType") or defaultHairType
                local baseHairDirs = status.statusProperty("baseHairDirectives")
                player.setGender(baseSex)
                player.setBodyDirectives(baseBodyDirs)
                player.setImagePath(baseImagePath)
                if baseImagePath == "human" then
                    local emoteDirs = self.humanEmotes .. baseBodyDirs
                    player.setEmoteDirectives(emoteDirs)
                    player.setHairType(baseHairType)
                    player.setHairDirectives(baseHairDirs)
                end
            end
        end
    end

    self.lastLegless = legless
end

-----------------------------------------------------------------------

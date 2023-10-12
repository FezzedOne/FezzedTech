require "/scripts/util/hook.lua"
require "/scripts/vec2.lua"
require "/scripts/poly.lua"
require "/tech/doubletap.lua"

-- function checkMovement() return world.sendEntityMessage(entity.id(), "checkJumping"):result() end

function shortAngleDist(a0, a1)
    local max = math.pi * 2
    local da = (a1 - a0) % max
    return 2 * da % max - da
end

function angleLerp(a0, a1, t, m)
    local d = shortAngleDist(a0, a1)
    if (math.abs(d * t) > (m or 0)) or (math.abs(d * t) > (2 * math.pi + (m or 0))) then
        return a0 + d * t
    else
        return a1 -- a0 + d
    end
end

function log10(x) return math.log(x) / math.log(10) end

function distToPenalty(distance)
    if distance > 2 then
        local magnitude = log10(distance / 2)
        local penalty = math.floor((magnitude * -6) + 1)
        return penalty
    else
        return 0
    end
end

function getClosestBlockYDistance(lineStart, lineEnd, ignorePlatforms)
    local yDistance = false

    if lineEnd then
        local collisionSet = {"Null", "Block", "Dynamic", "Platform"}
        if ignorePlatforms then collisionSet = {"Null", "Block", "Dynamic", "Slippery"} end
        local blocks = world.collisionBlocksAlongLine(lineStart, lineEnd, collisionSet)
        if #blocks > 0 then yDistance = lineStart[2] - (blocks[1][2] + 1) end
    end

    return yDistance
end

function backgroundExists(position, ignoreObjects, ignoreForeground)
    local tilePos = {math.floor(position[1] + 0.5), math.floor(position[2] + 0.5)}
    local tileOccupied = world.tileIsOccupied(tilePos, false, false) or ((not ignoreForeground) and world.tileIsOccupied(tilePos, true, false)) or
                           ((not ignoreObjects) and world.objectAt(tilePos))
    return tileOccupied
end

function renoInit()
    -- Communicate the presence of FezzedTech to other mods and allow a way to disable it in scripts.
    if status.statusProperty("ignoreFezzedTech") then
        math.__fezzedTechLoaded = true
    else
        math.__fezzedTechLoaded = false
    end

    self.jumpDt = 0
    -- if ((entity.uniqueId() == "13dba99d1cf28c429b4330058d6cbe5e") or (entity.uniqueId() == "13dba99d1cf28c429b4330058d6cbe5f")) then
    --     local legged = status.statPositive("legged") or status.statPositive("invisPot")
    --     if legged then
    --         status.setPrimaryDirectives("?replace;605231=0000;463C24=0000;2E2718=0000;736459=0000;4e433b=0000;27231f=0000")
    --     else
    --         status.setPrimaryDirectives()
    --     end
    --     self.lastLegged = legged
    -- end
    self.soarDt = 0
    self.fireworksDt = 0
    self.currentAngle = 0
    self.jumpAngleDt = 0
    self.jumpTimer = 0
    self.moves = {false, false, false, false, false, false, true, false}
    self.oldJump = false
    self.oldShift = false
    self.lastCrouching = false
    self.lastSkating = false

    self.phantomGlider = root.assetJson("/items/phantomGlider.config")
    self.phantomSoarGlider = root.assetJson("/items/phantomSoarGlider.config")
    self.phantomThruster = root.assetJson("/items/phantomThrusters.config")
    self.phantomGravShield = root.assetJson("/items/phantomGravShield.config")
    self.flyboard = root.assetJson("/projectiles/flyboard.config")
    self.phantomGliderBaseDirs = self.phantomGlider.parameters.animationCustom.animatedParts.parts.swoosh.partStates.swoosh.flip.properties.image
    self.flyboardBaseDirs = self.flyboard.processing
    self.defaultParagliderDirs =
      "?replace;e0975c=29332b;f32200=232b2b;6f2919=141915;951500=111515;dc1f00=1f2828;ffca8a=333f35;be1b00=1a2020;a85636=1e2620;735e3a=273131"
    self.baseColBox = {standingPoly = mcontroller.baseParameters().standingPoly, crouchingPoly = mcontroller.baseParameters().crouchingPoly}
    self.fallDanger = false
    self.isRunBoosting = status.statusProperty("isRunBoosting")
    self.useParawing = false
    self.isSkating = false
    self.crouching = false
    self.hovering = false
    self.parkourThrusters = false
    self.usingItemTimer = 0
    self.flyboardProjectileId = nil
    self.flyboardTimer = 0
    self.collision = nil
    self.groundTimer = 0
    self.flightTimer = 0
    self.shadowFlight = status.statusProperty("shadowFlight")

    self.running = status.statusProperty("runningMode")

    self.thrustersActive = status.statusProperty("thrustersActive")

    self.collisionTimer = 0
    self.lameTimer = 0
    -- self.bobTimer = 0

    self.lastPoseOverriding = false

    self.tapKeyDir = false

    self.switchDirTap = DoubleTap:new({6}, 0.25, function(tapKey) self.tapKeyDir = true end)

    self.skatingTap = DoubleTap:new(
                        {2, 3}, 0.25, function(tapKey)
          if self.moves[7] then
              self.running = not self.running
          else
              self.isSkating = not self.isSkating
          end
      end
                      )

    self.runningTap = DoubleTap:new({2, 3}, 0.25, function(tapKey) self.running = not self.running end)

    self.parawingTap = DoubleTap:new(
                         {4}, 0.25, function(tapKey)
          if math.__shadowRun then
              self.shadowFlight = not self.shadowFlight
          else
              if (math.__fezTech or math.__garyTech or math.__upgradedThrusters) and math.__isGlider and
                not (mcontroller.groundMovement() or mcontroller.liquidMovement()) then
                  self.hovering = not self.hovering
              else
                  if math.__isGlider and not math.__garyTech then
                      math.__gliderActive = false
                      self.fallDanger = false
                      self.useParawing = false
                  else
                      if not (mcontroller.liquidMovement() or math.__shadowRun) then
                          if (self.moves[7] or math.__garyTech) and (mcontroller.groundMovement()) and math.__parkourThrusters then
                              self.isRunBoosting = not self.isRunBoosting
                          else
                              self.useParawing = true
                          end
                      end
                  end
              end
          end
      end
                       )

    self.crouchingTap = DoubleTap:new(
                          {5}, 0.25, function(tapKey)
          if self.moves[7] and (self.parkourThrusters or math.__shadowRun) then
              self.thrustersActive = not self.thrustersActive
          else
              if mcontroller.groundMovement() then self.crouching = not self.crouching end
          end
      end
                        )

    self.flyboardTap = DoubleTap:new({8}, 0.25, function(tapKey) math.__flyboardActive = not math.__flyboardActive end)

    self.isFalling = false
    self.lastSwimming = false
    self.lastAvosiFlying = false

    self.lastFlightTime = 0

    self.oldCharScale = 1

    self.isSitting = false
    self.lastIsSitting = false
    self.lastIsOffset = false

    self.lastIsLame = false

    math.__gliderActive = false
    math.__doThrusterAnims = false
    math.__jumpDisabled = true
    math.__paramotor = false
    math.__wingFlap = false
    math.__doSkateSound = false
    math.__parkourThrusters = false
    math.__noLegs = false
    math.__fezTech = false
    math.__garyTech = false
    math.__resetJumps = false
    math.__upgradedThrusters = false
    math.__flyboardActive = false
    math.__rpMovement = false
    math.__canGrabWall = false
    math.__bouncy = false
    math.__avosiWings = false

    math.__playerMController = mcontroller

    if status.statusProperty("roleplayMode") and (not status.statusProperty("ignoreFezzedTech")) then
        local rpStatusEffects = {
            {effectiveMultiplier = 0, stat = "fallDamageMultiplier"}, {stat = "breathProtection", amount = 1}, {stat = "biomeradiationImmunity", amount = 1},
            {stat = "biomecoldImmunity", amount = 1}, {stat = "biomeheatImmunity", amount = 1}
        }
        status.setPersistentEffects("rpTech", rpStatusEffects)
    else
        status.clearPersistentEffects("rpTech")
    end

    status.clearPersistentEffects("movementAbility")
end

function renoUpdate(dt)
    if xsb and player.setOverrideState then player.setOverrideState() end

    if status.statusProperty("ignoreFezzedTech") then
        math.__fezzedTechLoaded = false

        if not status.statusProperty("ignoreFezzedTechAppearance") then
            -- Check only the appearance-affecting stats.
            local opTailStat = status.statPositive("opTail") or status.statusProperty("opTail")
            local ghostTailStat = status.statPositive("ghostTail") or status.statusProperty("ghostTail")
            local bouncyRaw = status.statPositive("bouncy") or status.statPositive("bouncy2")
            local largePotted = status.statPositive("largePotted") or status.statusProperty("largePotted")
            local scarecrowPole = status.statPositive("scarecrowPole") or status.statusProperty("scarecrowPole") or
                                    ((not math.__isParkourTech) and (opTailStat or ghostTailStat)) or bouncyRaw or largePotted
            local grandfatheredLeglessChar = status.statPositive("leglessSmallColBox") or status.statusProperty("leglessSmallColBox")
            local isLeglessCharRaw = grandfatheredLeglessChar or (status.statPositive("legless") and (input or xsb))
            local isLeglessChar = isLeglessCharRaw and not (status.statPositive("legged") or status.statusProperty("legged"))
            local leglessSmallColBox = isLeglessChar and not (scarecrowPole)
            local tailed = status.statPositive("noLegs") or status.statusProperty("noLegs")
            local pottedRaw = status.statPositive("potted") or status.statusProperty("potted")
            local gettingOverIt = status.statPositive("gettingOverIt") or status.statusProperty("gettingOverIt")
            local potted = (pottedRaw or gettingOverIt) and not bouncyRaw
            local mertail = status.statPositive("mertail") or status.statusProperty("mertail")
            local noLegs = leglessSmallColBox or tailed or potted or mertail

            status.setStatusProperty("legless", (noLegs or scarecrowPole) and not grandfatheredLeglessChar)
        end
    else
        math.__fezzedTechLoaded = true

        local tech = nil
        if not tech then tech = math.__tech end

        if mcontroller.onGround() then status.setStatusProperty("ballisticVelocity", {0, -4}) end

        local moveMessage = world.sendEntityMessage(entity.id(), "checkJumping")

        if moveMessage:succeeded() then
            self.moves = moveMessage:result()
            self.moves[8] = not self.moves[7]
        else
            self.moves = {false, false, false, false, false, false, true, false}
        end

        -- if ((entity.uniqueId() == "13dba99d1cf28c429b4330058d6cbe5e") or (entity.uniqueId() == "13dba99d1cf28c429b4330058d6cbe5f") or
        --   (entity.uniqueId() == "13dba99d1cf28c429b4330058d6cbe60") or (entity.uniqueId() == "13dba99d1cf28c429b4330058d6cbe6d") or
        --   (entity.uniqueId() == "13dba99d1cf28c429b4330058d6cbe90") or (entity.uniqueId() == "13dba99d1cf28c429b4330058d6cbe91")) then
        --     if not status.statPositive("leglessSmallColBox") then status.addPersistentEffect("innate", {stat = "leglessSmallColBox", amount = 1}) end
        -- end

        local isLegged = status.statPositive("legged") or status.statusProperty("legged")
        local highGrav = world.gravity(mcontroller.position()) >= 30
        local flightEnabled = (status.statPositive("flightEnabled")) and math.__isParkourTech
        local opTailStat = status.statPositive("opTail") or status.statusProperty("opTail")
        local opTail = opTailStat and math.__isParkourTech
        local ghostTailStat = status.statPositive("ghostTail") or status.statusProperty("ghostTail")
        local ghostTail = ghostTailStat and math.__isParkourTech
        local bouncyCrouch = status.statPositive("bouncy2")
        local bouncyRaw = status.statPositive("bouncy") or bouncyCrouch
        local bouncy = bouncyRaw -- and math.__isParkourTech
        local largePotted = status.statPositive("largePotted") or status.statusProperty("largePotted")
        local scarecrowPole = status.statPositive("scarecrowPole") or status.statusProperty("scarecrowPole") or
                                ((not math.__isParkourTech) and (opTailStat or ghostTailStat)) or bouncyRaw or largePotted
        local fireworks = (status.statPositive("fireworks") or status.statusProperty("fireworks")) and math.__isParkourTech
        local swimmingFlight = (status.statPositive("swimmingFlight") or status.statusProperty("swimmingFlight")) and math.__isParkourTech
        local soarHop = (opTail or status.statPositive("soarHop") or status.statusProperty("soarHop")) and math.__isParkourTech
        local canHop = soarHop or (fireworks and status.statusProperty("legless") and (not isLegged)) or status.statPositive("canHop") or
                         status.statusProperty("canHop")
        local tailed = status.statPositive("noLegs") or status.statusProperty("noLegs")
        local roleplayMode = status.statusProperty("roleplayMode")
        local pottedRaw = status.statPositive("potted") or status.statusProperty("potted")
        local gettingOverIt = status.statPositive("gettingOverIt") or status.statusProperty("gettingOverIt")
        local potted = (pottedRaw or gettingOverIt) and not bouncy
        local rawItemL = world.entityHandItem(entity.id(), "primary")
        local rawItemR = world.entityHandItem(entity.id(), "alt")
        local itemL = rawItemL and not math.__canFlyWithItem
        local itemR = rawItemR and not math.__canFlyWithItem
        local shadowRun = (status.statPositive("shadowRun") or status.statusProperty("shadowRun")) and math.__isParkourTech
        local mertail = status.statPositive("mertail") or status.statusProperty("mertail")
        local fastSwimming = (status.statPositive("fastSwimming") or status.statusProperty("fastSwimming")) -- or mertail
        local swimTail = ((scarecrowPole or soarHop or shadowRun or fastSwimming) and mcontroller.liquidMovement())
        local avosiWingedArms = (status.statPositive("avosiWingedArms") or status.statusProperty("avosiWingedArms")) and math.__isParkourTech
        local avosiWings = (status.statPositive("avosiWings") or status.statusProperty("avosiWings")) and math.__isParkourTech
        local avolitePack = (status.statPositive("avolitePack") or status.statusProperty("avolitePack")) and math.__isParkourTech
        local rawAvosiJetpack = (status.statPositive("avosiJetpack") or status.statusProperty("avosiJetpack") or avolitePack) and math.__isParkourTech
        local rawAvosiFlight = (status.statPositive("avosiFlight") or status.statusProperty("avosiFlight")) and math.__isParkourTech
        local avosiFlight = rawAvosiFlight or (avosiWingedArms and not (itemL or itemR))
        local grandfatheredLeglessChar = status.statPositive("leglessSmallColBox") or status.statusProperty("leglessSmallColBox")
        local isLeglessCharRaw = grandfatheredLeglessChar or (status.statPositive("legless") and (input or xsb))
        local isLeglessChar = isLeglessCharRaw and not (status.statPositive("legged") or status.statusProperty("legged"))
        local leglessSmallColBox = isLeglessChar and not (scarecrowPole)
        local noLegs = leglessSmallColBox or tailed or potted or mertail -- or scarecrowPole
        local paramotor = ((status.statPositive("paramotor") or status.statusProperty("paramotor")) and highGrav) and math.__isParkourTech
        local basicParkour = (status.statPositive("basicParkour") or status.statusProperty("basicParkour")) and math.__isParkourTech
        local parkourRaw = (status.statPositive("parkour") or status.statusProperty("parkour")) and math.__isParkourTech
        local parkour = parkourRaw or basicParkour
        local paragliderPack = (status.statPositive("paragliderPack") or status.statusProperty("paragliderPack"))
        local parkourThrustersStat = ((status.statPositive("parkourThrusters") or status.statusProperty("parkourThrusters")) and highGrav) and
                                       math.__isParkourTech
        self.parkourThrusters = parkourThrustersStat
        local parkourThrusters = parkourThrustersStat and self.thrustersActive and self.moves[7]
        local nightVision = (status.statPositive("nightVision") or status.statusProperty("nightVision")) and math.__isParkourTech
        local shadowVision = (status.statPositive("shadowVision") or status.statusProperty("shadowVision")) and math.__isParkourTech
        local skates = (status.statPositive("skates") or status.statusProperty("skates")) and math.__isParkourTech
        local fezTech = (status.statPositive("fezTech") or status.statusProperty("fezTech")) and math.__isParkourTech
        local garyTech = (status.statPositive("garyTech") or status.statusProperty("garyTech")) and math.__isParkourTech and (noLegs or leglessSmallColBox)
        local upgradedThrusters = (status.statPositive("upgradedThrusters") or status.statusProperty("upgradedThrusters")) and math.__isParkourTech
        local flyboard = (status.statPositive("flyboard") or status.statusProperty("flyboard")) and math.__isParkourTech
        local avosiGlider = (status.statPositive("avosiGlider") or status.statusProperty("avosiGlider"))
        local tailless = (((status.statPositive("legged") or status.statusProperty("legged")) and isLeglessCharRaw) or
                           (status.statPositive("tailless") or status.statusProperty("tailless"))) and math.__isParkourTech
        local runSpeedMult = status.stat("runSpeedAdder") + 1
        local checkDist = status.stat("checkGroundDist")
        local jumpSpeedMult = status.stat("jumpAdder") + (bouncy and 1.5 or 1)
        local safetyFlight = status.statPositive("safetyFlight")
        local flightTime = (math.__isParkourTech and status.stat("flightTime")) or 0
        local slowRecharge = status.statPositive("slowRecharge") and math.__isParkourTech
        local isLame = status.statPositive("isLame")
        local activeMovementAbilities = status.statPositive("activeMovementAbilities")
        local charScale = status.stat("charHeight") ~= 0 and (status.stat("charHeight") / 187.5) or (type(math.__scale == "number") and math.__scale or 1)
        local rulerEnabled = status.statusProperty("roleplayRuler")
        local windSailing = status.statPositive("windSail") or status.statusProperty("windSail")
        local gravityModifier = math.__isParkourTech and (status.stat("gravityModifier") + 1) or 1

        if not tech then charScale = 1 end

        local legless = (noLegs or scarecrowPole) or (grandfatheredLeglessChar and not isLegged)
        status.setStatusProperty("legless", (noLegs or scarecrowPole) and not grandfatheredLeglessChar)

        if legless and mcontroller.groundMovement() and xsb and player.setOverrideState then
            player.setOverrideState((self.moves[5] or self.crouching) and "duck" or "idle")
        end

        if gravityModifier ~= 1 then
            local baseGravMult = mcontroller.baseParameters().gravityMultiplier
            mcontroller.controlParameters({gravityMultiplier = baseGravMult * gravityModifier})
        end

        local defaultColBoxParams = {}

        if math.__isParkourTech and (charScale ~= 1) then
            local defStandingPoly = {{-0.75, -2.0}, {-0.35, -2.5}, {0.35, -2.5}, {0.75, -2.0}, {0.75, 0.65}, {0.35, 1.22}, {-0.35, 1.22}, {-0.75, 0.65}}
            local defCrouchingPoly = {{-0.75, -2.0}, {-0.35, -2.5}, {0.35, -2.5}, {0.75, -2.0}, {0.75, -1.0}, {0.35, -0.5}, {-0.35, -0.5}, {-0.75, -1.0}}
            defaultColBoxParams.standingPoly = poly.scale(defStandingPoly, charScale)
            defaultColBoxParams.crouchingPoly = poly.scale(defCrouchingPoly, charScale)
            mcontroller.controlParameters(defaultColBoxParams)
        end

        if math.__isParkourTech and tech then
            if self.oldCharScale ~= charScale then
                if charScale ~= 1 then
                    tech.setParentDirectives('?scalenearest=' .. tostring(charScale))
                else
                    tech.setParentDirectives()
                end
            end
        end

        if not (starExtensions or xsb) then status.setStatusProperty("roleplayRuler", nil) end

        if input then -- Check if xSB-2, OpenStarbound or StarExtensions is loaded.
            if input.bindUp("fezzedTechs", "sitBind") then self.isSitting = not self.isSitting end
            if input.bindUp("fezzedTechs", "roleplayModeBind") then
                local roleplayModeStatus = status.statusProperty("roleplayMode")
                status.setStatusProperty("roleplayMode", not roleplayModeStatus)
                local statusMessage
                if roleplayModeStatus then
                    statusMessage = "Roleplay mode disabled."
                else
                    statusMessage = "Roleplay mode enabled."
                end
                interface.queueMessage(statusMessage, 5, 1)
            end
            if input.bindUp("fezzedTechs", "roleplayRulerBind") and (starExtensions or xsb) then
                -- The ruler tooltip requires StarExtensions.
                local roleplayModeStatus = status.statusProperty("roleplayRuler")
                status.setStatusProperty("roleplayRuler", not roleplayModeStatus)
                local statusMessage
                if roleplayModeStatus then
                    statusMessage = "Roleplay ruler disabled."
                else
                    statusMessage = "Roleplay ruler enabled."
                end
                interface.queueMessage(statusMessage, 5, 1)
            end
        end

        if status.statusProperty("roleplayMode") then
            local rpStatusEffects = {
                {effectiveMultiplier = 0, stat = "fallDamageMultiplier"}, {stat = "breathProtection", amount = 1},
                {stat = "biomeradiationImmunity", amount = 1}, {stat = "biomecoldImmunity", amount = 1}, {stat = "biomeheatImmunity", amount = 1}
            }
            status.setPersistentEffects("rpTech", rpStatusEffects)
        else
            status.clearPersistentEffects("rpTech")
        end

        if interface and tech and rulerEnabled and (starExtensions or xsb) then
            -- StarExtensions is currently needed for `interface.setCursorText`. This may change though.
            local pP = mcontroller.position()
            local aP = tech.aimPosition()
            local dist = world.distance(pP, aP)
            local distMag = math.sqrt(dist[1] ^ 2 + dist[2] ^ 2) / 2
            local roundedDist = math.floor(distMag + 0.5)
            if distMag < 10 then roundedDist = math.floor(distMag * 2 + 0.5) / 2 end
            local roundedDistStr = tostring(roundedDist)
            if roundedDistStr == "0.0" then roundedDistStr = "0" end
            local footDist = distMag / 0.3
            local roundedFootDist = math.floor(footDist + 0.5)
            local roundedFootDistStr = tostring(roundedFootDist)
            local distPenalty = distToPenalty(roundedDist)
            local distPenaltyStr = tostring(distPenalty)
            -- interface.setCursorText(tostring(roundedDist) .. " m")
            -- interface.setCursorText(tostring(roundedDist) .. " m / " .. roundedFootDistStr .. " ft")
            local rulerText = "^font=iosevka-semibold;" .. roundedDistStr .. "^font=iosevka-extralight;m/^font=iosevka-semibold;" .. roundedFootDistStr ..
                                "^font=iosevka-extralight;ft ^gray;(^font=iosevka-semibold;" .. distPenaltyStr .. "^font=iosevka-extralight;)"
            if starExtensions then
                rulerText = "^yellow;" .. roundedDistStr .. "m^reset;/^orange;" .. roundedFootDistStr .. "'^reset; (^cyan;" .. distPenaltyStr .. "^reset;)"
            end
            interface.setCursorText(rulerText)
        end

        if not tech then self.isSitting = false end

        if self.isSitting then mcontroller.controlApproachVelocity({0, 0}, 1000000, true, true) end

        local lounging = (tech and tech.parentLounging()) or self.isSitting or math.__sitting or math.__isSitting

        self.oldCharScale = charScale

        jumpSpeedMult = scarecrowPole and jumpSpeedMult or math.min(1.3, jumpSpeedMult)

        local mPos = mcontroller.position()
        local liqCheckPos = {math.floor(mPos[1] + 0.5), math.floor(mPos[2] - 2)}
        local liqCheckPosDown = {math.floor(mPos[1] + 0.5), math.floor(mPos[2] - 3)}
        local liqCheckPosUp = {math.floor(mPos[1] + 0.5), math.floor(mPos[2] - 1)}
        local inLiquid = world.liquidAt(liqCheckPosDown)

        math.__jumpFiring = self.moves[1]

        local usingFlightPack = ((self.moves[1] and not (math.__gliderActive and avosiGlider and avolitePack)) or
                                  ((self.moves[2] or self.moves[3]) and self.running and not (math.__gliderActive or rawAvosiFlight)) or
                                  ((((itemL or itemR) and not rawAvosiFlight) or (rawAvosiJetpack and not (avosiWingedArms or rawAvosiFlight))) and
                                    not math.__gliderActive)) and (self.moves[7] or rawAvosiFlight or ((avosiWingedArms) and not (itemL or itemR)))
        local flightPackBoosting = ((self.moves[1] and not (math.__gliderActive and avosiGlider and avolitePack)) or
                                     ((self.moves[2] or self.moves[3]) and self.running and not math.__gliderActive))
        -- local flightRecharging = false
        local rechargeRate = 1 / 3
        local timeMult = flightPackBoosting and 1 or (1 / 3)

        if self.lastFlightTime ~= flightTime then if flightTime then self.flightTimer = flightTime end end

        if (flightTime > 0) then
            if usingFlightPack and
              not (lounging or math.__onWall or math.__sphereActive or (bouncy and inLiquid) or mcontroller.liquidMovement() or mcontroller.groundMovement()) then
                self.flightTimer = math.max(self.flightTimer - dt * timeMult, 0)
            else
                if slowRecharge then
                    self.flightTimer = math.min(self.flightTimer + dt * rechargeRate, flightTime)
                elseif (math.__onWall or mcontroller.groundMovement() or mcontroller.liquidMovement() or lounging or math.__grappled) then
                    self.flightTimer = flightTime
                end
                -- flightRecharging = true
            end
        elseif flightTime == 0 then
            self.flightTimer = 0
        end

        local canJetpack
        if flightTime == 0 then
            canJetpack = true
        elseif (flightTime > 0) and (self.flightTimer > 0) then
            canJetpack = true
        else
            canJetpack = false
        end
        local avosiJetpack = rawAvosiJetpack and canJetpack

        self.lastFlightTime = flightTime

        if self.tapKeyDir then
            if (avosiFlight or avosiWingedArms or math.__gliderActive) and
              not (mcontroller.groundMovement() or mcontroller.liquidMovement() or math.__sphereActive or math.__onWall or lounging) then
                local xVel = mcontroller.xVelocity()
                mcontroller.setXVelocity(-xVel)
            end
            self.tapKeyDir = false
        end

        -- if interface and tech and rawAvosiJetpack and (flightTime > 0) then
        --     local roundedTimeFloat = math.floor(((self.flightTimer * 10 * (1 / timeMult)) + 0.5)) / 10
        --     local roundedTime = (flightPackBoosting and "^cyan;" or "^white;") .. tostring(roundedTimeFloat) .. " s^reset;"
        --     if self.flightTimer == 0 then roundedTime = "^red;OVERHEATING!^reset;" end
        --     if flightRecharging then
        --         roundedTime =
        --           "^yellow;" .. tostring(math.floor((flightTime * 10 * (1 / rechargeRate)) - (self.flightTimer * 10 * (1 / rechargeRate) - 0.5)) / 10) ..
        --             " s^reset;"
        --         if self.flightTimer == flightTime then roundedTime = "^green;COOLED DOWN^reset;" end
        --     end
        --     interface.setCursorText(roundedTime)
        -- end

        -- if tech then
        --     local cPos = tech.aimPosition()
        --     local tilePosDebug = {math.floor(cPos[1] + 0.5), math.floor(cPos[2] + 0.5)}
        --     local tileOccupied = world.tileIsOccupied(tilePosDebug, false, false)
        --     if tileOccupied then interface.setCursorText("Tile occupied.") end
        -- end

        local checkDistRaw = checkDist
        checkDist = self.moves[1] and checkDist or (checkDist <= 0 and 3 or math.min(checkDist, 3))
        checkDistRaw = avosiJetpack and -2 or checkDistRaw

        parkour = parkour or fezTech or shadowRun
        paramotor = paramotor or fezTech or garyTech or shadowRun
        paragliderPack = paragliderPack or fezTech or garyTech or shadowRun
        parkourThrusters = parkourThrusters or fezTech or garyTech or (shadowRun and self.thrustersActive)
        parkourThrustersStat = parkourThrustersStat or shadowRun
        potted = potted and not (math.__gliderActive or math.__holdingGlider)

        math.__jumpDisabled = math.__flyboardActive or (not parkour)
        math.__parkour = parkour
        math.__basicParkour = basicParkour and not parkourRaw
        math.__doThrusterAnims = false
        math.__paramotor = paramotor
        math.__parkourThrusters = parkourThrusters
        math.__noLegs = noLegs or leglessSmallColBox or scarecrowPole or isLame
        math.__fezTech = fezTech or shadowRun
        math.__shadowRun = shadowRun
        math.__garyTech = garyTech
        math.__winged = avosiWings
        math.__runBoost = self.running
        math.__infJumps = status.statPositive("infJumps") or status.statusProperty("infJumps")
        math.__upgradedThrusters = upgradedThrusters
        math.__shadowFlight = self.shadowFlight
        math.__bouncy = bouncy
        math.__avosiWings = avosiWingedArms or avosiJetpack

        if tech then
            local swimming = swimTail and math.abs(vec2.mag(mcontroller.velocity())) > 4 and (not lounging)
            if swimming then
                if xsb and player.setOverrideState then
                    player.setOverrideState("swim")
                else
                    tech.setParentState("Swim")
                end
            else
                if self.lastSwimming ~= swimming then if not (xsb and player.setOverrideState) then tech.setParentState() end end
            end
            self.lastSwimming = swimming
            local avosiFlying = avosiWingedArms and
                                  not (mcontroller.groundMovement() or mcontroller.liquidMovement() or itemL or itemR or math.__onWall or lounging)
            if avosiFlying then
                if xsb and player.setOverrideState then
                    player.setOverrideState("fall")
                else
                    tech.setParentState("Fall")
                end
            else
                if self.lastAvosiFlying ~= avosiFlying then if not (xsb and player.setOverrideState) then tech.setParentState() end end
            end
            self.lastAvosiFlying = avosiFlying
        end

        if (avosiWingedArms or avosiJetpack) and ((self.moves[7] and checkDistRaw == -2) or ((avosiWingedArms or avosiFlight) and not (itemL or itemR))) then
            local jetpackParams = {gravityMultiplier = (checkDistRaw == -2 and 0.35 or 0.6) * gravityModifier}
            mcontroller.controlParameters(jetpackParams)
            local yVel = mcontroller.yVelocity()
            if yVel <= -25 and not (avosiWingedArms or avosiFlight) then mcontroller.controlApproachYVelocity(-25, 150) end
        end

        if not (parkourThrustersStat or shadowRun) then self.thrustersActive = false end

        if not shadowRun then self.shadowFlight = false end

        if skates or fezTech then
            self.skatingTap:update(dt, self.moves)
        else
            self.runningTap:update(dt, self.moves)
        end

        if avosiWingedArms or avosiFlight then self.switchDirTap:update(dt, self.moves) end

        local groundJump = false
        if mcontroller.groundMovement() or mcontroller.liquidMovement() or math.__onWall then
            self.groundTimer = 0.25
        else
            self.groundTimer = math.max(self.groundTimer - dt, 0)
        end
        if self.groundTimer ~= 0 then groundJump = true end

        do
            local minFallVel = 40
            local minFallDist = 5

            local curYPosition = mcontroller.yPosition()
            self.lastYPosition = self.lastYPosition or curYPosition
            self.lastYVelocity = self.lastYVelocity or 0

            local yPosChange = curYPosition - self.lastYPosition

            self.isFalling = self.fallDistance > minFallDist and self.lastYVelocity <= -minFallVel and not mcontroller.liquidMovement()

            if mcontroller.yVelocity() < -minFallVel and not mcontroller.onGround() then
                self.fallDistance = (self.fallDistance or 0) + -yPosChange
            else
                self.fallDistance = 0
            end

            self.lastYPosition = curYPosition
            self.lastYVelocity = mcontroller.yVelocity()
        end

        local groundDist

        if checkDist ~= 0 then
            local x, y = table.unpack(mcontroller.position())
            local checkWidth = 1.5
            local left1, left2 = {x - checkWidth, y}, {x - checkWidth, y - checkDist}
            local right1, right2 = {x + checkWidth, y}, {x + checkWidth, y - checkDist}
            local leftDist = getClosestBlockYDistance(left1, left2, false)
            local rightDist = getClosestBlockYDistance(right1, right2, false)
            leftDist = leftDist and leftDist >= 1
            rightDist = rightDist and rightDist >= 1
            groundDist = (not not (leftDist or rightDist))
            -- if leftDist and rightDist then
            --     groundDist = (leftDist + rightDist) / 2
            -- else
            --     groundDist = (leftDist or rightDist)
            -- end
        else
            groundDist = true
        end

        local tileOcc = false
        local windTileOcc = false
        do
            local x, y = table.unpack(mcontroller.position())
            for xAdd = -1, 1, 1 do
                for yAdd = 0, 2, 1 do
                    if backgroundExists({x + xAdd, y + yAdd}, true, true) then
                        tileOcc = true
                        break
                    end
                end
            end
            windTileOcc = tileOcc
            tileOcc = (checkDistRaw == -1 and tileOcc) or (checkDistRaw == -2)
        end

        -- local wallGroundDist

        -- do
        --     local wallCheckDist = 2.5 * math.max(math.sqrt(jumpSpeedMult), 1)
        --     local x, y = table.unpack(mcontroller.position())
        --     local checkWidth = 1.5
        --     local left1, left2 = {x - checkWidth, y}, {x - checkWidth, y - wallCheckDist}
        --     local right1, right2 = {x + checkWidth, y}, {x + checkWidth, y - wallCheckDist}
        --     local leftDist = getClosestBlockYDistance(left1, left2, false)
        --     local rightDist = getClosestBlockYDistance(right1, right2, false)
        --     leftDist = leftDist and leftDist >= 1
        --     rightDist = rightDist and rightDist >= 1
        --     wallGroundDist = not not (leftDist or rightDist)
        --     -- if leftDist and rightDist then
        --     --     wallGroundDist = (leftDist + rightDist) / 2
        --     -- else
        --     --     wallGroundDist = (leftDist or rightDist)
        --     -- end
        -- end

        -- math.__canGrabWall = (not wallGroundDist) or (not self.moves[7]) or (not (noLegs or scarecrowPole))

        -- if math.__gliderActive then
        --     sb.logInfo("Glider active.")
        -- end

        if (avosiWingedArms or avosiJetpack) and usingFlightPack and
          (not (mcontroller.zeroG() or mcontroller.groundMovement() or mcontroller.liquidMovement() or (bouncy and inLiquid) or math.__sphereActive or
            math.__onWall or math.__flyboardActive or lounging)) then if checkDistRaw == -2 then math.__doThrusterAnims = true end end

        if math.__player and (paragliderPack or parkourThrusters) and (not (math.__sphereActive or math.__flyboardActive)) then
            if not mcontroller.zeroG() then
                local player = math.__player
                if paragliderPack then
                    local backItem = player.equippedItem("back")

                    if backItem then
                        local paragliderDirsRaw = type(backItem.parameters.paragliderDirectives) == "string" and backItem.parameters.paragliderDirectives or nil
                        local backDirsRaw = type(backItem.parameters.directives) == "string" and backItem.parameters.directives or nil
                        local gravitorDirsRaw = type(backItem.parameters.gravitorDirectives) == "string" and backItem.parameters.gravitorDirectives or nil

                        local paragliderDirs = paragliderDirsRaw or backDirsRaw or self.defaultParagliderDirs
                        self.phantomGlider.parameters.animationCustom.animatedParts.parts.swoosh.partStates.swoosh.flip.properties.image =
                          self.phantomGliderBaseDirs .. paragliderDirs
                        self.phantomSoarGlider.parameters.animationCustom.animatedParts.parts.swoosh.partStates.swoosh.flip.properties.image =
                          self.phantomGliderBaseDirs .. paragliderDirs

                        local gravitorDirs = gravitorDirsRaw or "/assetmissing.png"
                        self.phantomGravShield.parameters.animationCustom.animatedParts.parts.swoosh.partStates.swoosh.flip.properties.image = gravitorDirs
                    else
                        self.phantomGlider.parameters.animationCustom.animatedParts.parts.swoosh.partStates.swoosh.flip.properties.image =
                          self.phantomGliderBaseDirs .. self.defaultParagliderDirs
                        self.phantomSoarGlider.parameters.animationCustom.animatedParts.parts.swoosh.partStates.swoosh.flip.properties.image =
                          self.phantomGliderBaseDirs .. self.defaultParagliderDirs
                        self.phantomGravShield.parameters.animationCustom.animatedParts.parts.swoosh.partStates.swoosh.flip.properties.image =
                          "/assetmissing.png"
                    end
                end

                if noLegs or leglessSmallColBox then
                    local adj = mertail and 0 or -2
                    local cAdj = -2
                    local standingPoly = {
                        {-0.3, -2.0 + 0.875 + (adj / 8)}, {-0.08, -2.5 + 0.875 + (adj / 8)}, {0.08, -2.5 + 0.875 + (adj / 8)}, {0.3, -2.0 + 0.875 + (adj / 8)},
                        {0.75, 0.65}, {0.35, 1.22}, {-0.35, 1.22}, {-0.75, 0.65}
                    }
                    local crouchingPoly = {
                        {-0.75, -2.0 + 0.375 + (cAdj / 8)}, {-0.35, -2.5 + 0.375 + (cAdj / 8)}, {0.35, -2.5 + 0.375 + (cAdj / 8)},
                        {0.75, -2.0 + 0.375 + (cAdj / 8)}, {0.75, -1}, {0.35, -0.5}, {-0.35, -0.5}, {-0.75, -1}
                    }
                    if (charScale and charScale ~= 1) then
                        standingPoly = poly.scale(standingPoly, charScale)
                        crouchingPoly = poly.scale(crouchingPoly, charScale)
                    end
                    self.phantomGlider.parameters.altAbility.flipMovementParameters.standingPoly = standingPoly
                    self.phantomGlider.parameters.altAbility.flipMovementParameters.crouchingPoly = crouchingPoly
                    self.phantomSoarGlider.parameters.altAbility.flipMovementParameters.standingPoly = standingPoly
                    self.phantomSoarGlider.parameters.altAbility.flipMovementParameters.crouchingPoly = crouchingPoly
                    self.phantomThruster.parameters.altAbility.flipMovementParameters.standingPoly = standingPoly
                    self.phantomThruster.parameters.altAbility.flipMovementParameters.crouchingPoly = crouchingPoly
                    self.phantomGravShield.parameters.altAbility.flipMovementParameters.standingPoly = standingPoly
                    self.phantomGravShield.parameters.altAbility.flipMovementParameters.crouchingPoly = crouchingPoly
                else
                    local standingPoly, crouchingPoly
                    if (charScale and charScale ~= 1) then
                        standingPoly = poly.scale(self.baseColBox.standingPoly, charScale)
                        crouchingPoly = poly.scale(self.baseColBox.crouchingPoly, charScale)
                    end
                    self.phantomGlider.parameters.altAbility.flipMovementParameters.standingPoly = standingPoly or self.baseColBox.standingPoly
                    self.phantomGlider.parameters.altAbility.flipMovementParameters.crouchingPoly = crouchingPoly or self.baseColBox.crouchingPoly
                    self.phantomSoarGlider.parameters.altAbility.flipMovementParameters.standingPoly = standingPoly or self.baseColBox.standingPoly
                    self.phantomSoarGlider.parameters.altAbility.flipMovementParameters.crouchingPoly = crouchingPoly or self.baseColBox.crouchingPoly
                    self.phantomThruster.parameters.altAbility.flipMovementParameters.standingPoly = standingPoly or self.baseColBox.standingPoly
                    self.phantomThruster.parameters.altAbility.flipMovementParameters.crouchingPoly = crouchingPoly or self.baseColBox.crouchingPoly
                    self.phantomGravShield.parameters.altAbility.flipMovementParameters.standingPoly = standingPoly or self.baseColBox.standingPoly
                    self.phantomGravShield.parameters.altAbility.flipMovementParameters.crouchingPoly = crouchingPoly or self.baseColBox.crouchingPoly
                end

                if parkourThrusters and (not mcontroller.zeroG()) then
                    if self.moves[7] then
                        if self.moves[1] then
                            local gravMod = mcontroller.baseParameters().gravityMultiplier
                            mcontroller.controlModifiers({gravityMultiplier = (gravMod / 1.75) * gravityModifier}) -- airJumpModifier = 1.75
                        end
                        if not (mcontroller.groundMovement() or mcontroller.liquidMovement()) then math.__doThrusterAnims = true end
                    end
                    if mcontroller.groundMovement() and (not mcontroller.liquidMovement()) and self.isRunBoosting and self.moves[7] then
                        -- mcontroller.controlModifiers({speedModifier = 2.5})
                        if not self.moves[1] then mcontroller.controlModifiers({airJumpModifier = 0.65}) end
                        if self.moves[2] or self.moves[3] then mcontroller.controlJump() end
                    end
                    if self.isRunBoosting then
                        if not (mcontroller.groundMovement() or mcontroller.liquidMovement()) then math.__doThrusterAnims = true end
                    end
                end

                if shadowRun and math.__gliderActive then math.__doThrusterAnims = true end

                self.usingItemTimer = math.max(0, self.usingItemTimer - dt)

                if math.__firingGrapple or math.__gliderFiring or math.__weaponFiring or (math.__onWall and self.moves[5]) then
                    self.usingItemTimer = 0.35
                end

                if self.useParawing and (self.usingItemTimer == 0) and paragliderPack then
                    local swapItem = player.swapSlotItem()
                    if not swapItem then
                        math.__gliderActive = true
                        player.setSwapSlotItem(
                          (math.__fezTech and not math.__shadowRun) and self.phantomGravShield or
                            ((math.__shadowRun or math.__garyTech) and self.phantomGravShield or (avosiGlider and self.phantomSoarGlider or self.phantomGlider))
                        )
                    end
                end

                -- if self.moves[1] and (self.moves[1] ~= self.oldJump) then self.fallDanger = false end
                if (not mcontroller.groundMovement()) and (not mcontroller.liquidMovement()) then
                    local swapItem = player.swapSlotItem()

                    if ((self.isFalling and not ((self.moves[5] and (self.moves[6] or not self.moves[7])) or math.__firingGrapple)) or
                      (self.moves[1] and self.moves[7] and (not (self.oldJump or math.__onWall or (paragliderPack and not parkourThrusters))))) and
                      (not swapItem) then
                        if not (fezTech or garyTech or shadowRun) then
                            player.setSwapSlotItem(
                              parkourThrustersStat and self.phantomThruster or (avosiGlider and self.phantomSoarGlider or self.phantomGlider)
                            )
                            self.fallDanger = true
                        end
                    end

                    if (fezTech or garyTech or (self.shadowFlight and not parkourThrusters)) and
                      ((self.isFalling and not ((self.moves[5] and (self.moves[6] or not self.moves[7])) or math.__firingGrapple))) and (not swapItem) then
                        player.setSwapSlotItem((math.__shadowRun or math.__garyTech) and self.phantomGravShield or self.phantomGravShield)
                        self.fallDanger = true
                        self.useParawing = true
                    end

                    if (garyTech or self.shadowFlight) and self.moves[1] and (self.running or parkourThrusters) and
                      not (math.__onWall or self.lastJump or mcontroller.jumping() or mcontroller.liquidMovement() or mcontroller.groundMovement()) and
                      (not swapItem) then
                        player.setSwapSlotItem(self.phantomGravShield)
                        self.fallDanger = true
                        self.useParawing = true
                    end

                    self.lastJump = self.moves[1]

                    if parkourThrusters or (parkourThrustersStat and math.__gliderActive and (not math.__isGlider)) and
                      not (self.moves[5] and (self.moves[6] or not self.moves[7])) then
                        mcontroller.controlParameters({airForce = 250, gravityMultiplier = 0.45 * gravityModifier, airFriction = 3.5})
                        if mcontroller.yVelocity() <= 0 and not (fezTech or garyTech) then math.__doThrusterAnims = true end
                    end

                    if self.fallDanger and not (fezTech or garyTech) then math.__gliderActive = true end

                    if ((math.__onWall and not (paragliderPack and not parkourThrusters)) or math.__firingGrapple or math.__gliderFiring or
                      (self.moves[5] and (self.moves[6] or not self.moves[7]))) then
                        math.__gliderActive = false
                        self.fallDanger = false
                        self.useParawing = false
                    end

                    if shadowRun and (math.__onWall or not self.shadowFlight) then
                        math.__gliderActive = false
                        self.fallDanger = false
                        self.useParawing = false
                    end

                    if math.__onWall or (self.moves[5] and (self.moves[6] or not self.moves[7])) then math.__doThrusterAnims = false end

                    if math.__gliderActive and (math.__isGlider ~= nil) then
                        if not self.moves[1] then
                            if parkourThrusters and paragliderPack and self.useParawing then math.__doThrusterAnims = false end
                        else
                            if paramotor and self.fallDanger then math.__doThrusterAnims = true end
                        end
                        if self.hovering then
                            if (not self.moves[5]) and (not (fezTech or garyTech)) then math.__doThrusterAnims = true end
                        end
                    end

                    if (paramotor or fezTech or garyTech) and not math.__isGlider then math.__doThrusterAnims = false end

                    if (noLegs or leglessSmallColBox) and (parkourThrusters or (paragliderPack and paramotor)) and
                      not (math.__onWall or math.__firingGrapple or fezTech or garyTech) then math.__doThrusterAnims = true end

                    if (fezTech or garyTech) and math.__isGlider then math.__doThrusterAnims = true end
                else
                    if not math.__isGlider then
                        self.fallDanger = false
                    else
                        self.fallDanger = true
                    end
                    if math.__firingGrapple or math.__gliderFiring or math.__weaponFiring then math.__gliderActive = false end
                    if math.__isGlider and not (paragliderPack) then math.__gliderActive = false end
                    -- if self.moves[5] then math.__gliderActive = false end
                    if (not math.__isGlider) and (not self.useParawing) then math.__gliderActive = false end
                    if shadowRun or garyTech then
                        math.__gliderActive = false
                        self.useParawing = false
                        self.fallDanger = false
                    end
                    math.resetJumps = false
                    self.hovering = false
                end

                if paragliderPack then self.parawingTap:update(dt, self.moves) end

                -- if math.abs(mcontroller.xVelocity()) <= 2 or (not self.moves[7]) then self.isRunBoosting = false end
                self.oldJump = self.moves[1]
            else
                math.__gliderActive = false
                self.hovering = false
                self.useParawing = false
            end
        end

        if not (paragliderPack or parkourThrusters or fezTech or garyTech) then math.__gliderActive = false end

        -- if ((entity.uniqueId() == "13dba99d1cf28c429b4330058d6cbe5e") or (entity.uniqueId() == "13dba99d1cf28c429b4330058d6cbe5f")) then
        --     local legged = status.statPositive("legged") or status.statPositive("invisPot")
        --     if legged and not self.lastLegged then
        --         status.setPrimaryDirectives("?replace;605231=0000;463C24=0000;2E2718=0000;736459=0000;4e433b=0000;27231f=0000")
        --     else
        --         status.setPrimaryDirectives()
        --     end
        --     self.lastLegged = legged
        -- end

        -- if status.statusProperty("isLegless") and mcontroller.groundMovement() and (not (self.moves[2] or self.moves[3])) and (mcontroller.crouching() ~= self.lastCrouching) then
        --     local yPos = mcontroller.position()[2]
        --     if mcontroller.crouching() then
        --         mcontroller.setYPosition(yPos + 0.625)
        --     else
        --         mcontroller.setYPosition(yPos - 0.625)
        --     end
        -- end
        -- self.lastCrouching = mcontroller.crouching()

        local smallColBox = false

        local largeColBoxMismatch = false
        if largePotted or scarecrowPole then
            local standingPoly, crouchingPoly
            if (charScale and charScale ~= 1) then
                standingPoly = poly.scale(self.baseColBox.standingPoly, charScale)
                crouchingPoly = poly.scale(self.baseColBox.crouchingPoly, charScale)
            else
                standingPoly = self.baseColBox.standingPoly
                crouchingPoly = self.baseColBox.crouchingPoly
            end
            largeColBoxMismatch = not (sb.printJson(mcontroller.collisionPoly()) == sb.printJson(standingPoly) or sb.printJson(mcontroller.collisionPoly()) ==
                                    sb.printJson(crouchingPoly))
        end

        if noLegs then
            local adj = mertail and 0 or -2
            local cAdj = -2
            local standingPoly = {
                {-0.3, -2.0 + 0.875 + (adj / 8)}, {-0.08, -2.5 + 0.875 + (adj / 8)}, {0.08, -2.5 + 0.875 + (adj / 8)}, {0.3, -2.0 + 0.875 + (adj / 8)},
                {0.75, 0.65}, {0.35, 1.22}, {-0.35, 1.22}, {-0.75, 0.65}
            }
            local crouchingPoly = {
                {-0.75, -2.0 + 0.375 + (cAdj / 8)}, {-0.35, -2.5 + 0.375 + (cAdj / 8)}, {0.35, -2.5 + 0.375 + (cAdj / 8)}, {0.75, -2.0 + 0.375 + (cAdj / 8)},
                {0.75, -1}, {0.35, -0.5}, {-0.35, -0.5}, {-0.75, -1}
            }
            if charScale and charScale ~= 1 then
                standingPoly = poly.scale(standingPoly, charScale)
                crouchingPoly = poly.scale(crouchingPoly, charScale)
            end

            smallColBox = (sb.printJson(mcontroller.collisionPoly()) == sb.printJson(standingPoly) or sb.printJson(mcontroller.collisionPoly()) ==
                            sb.printJson(crouchingPoly))

            if mcontroller.groundMovement() and ((self.moves[2] or self.moves[3]) and not self.moves[1]) and (scarecrowPole or soarHop or smallColBox) and
              (not mertail) then
                -- and not self.moves[6]
                -- if smallColBox or self.moves[7] then
                mcontroller.controlModifiers({movementSuppressed = true})
                -- end
                -- or (self.moves[7] and mcontroller.walking())
            end
            if mcontroller.groundMovement() and ((potted or largePotted or mertail) and smallColBox) then
                local notUsingThrusters = not (avosiJetpack or ((garyTech or fezTech or upgradedThrusters) and self.thrustersActive) or
                                            (avosiWingedArms or (avosiFlight and checkDistRaw == -2)))
                if ((potted or largePotted) and gettingOverIt) and (self.moves[2] or self.moves[3] or self.moves[1]) and
                  (not (mcontroller.liquidMovement() or self.collision)) and notUsingThrusters then
                    mcontroller.controlModifiers({movementSuppressed = true})
                end
                if (mertail or ((potted or largePotted) and not gettingOverIt)) and (self.moves[1]) and
                  (not (mcontroller.liquidMovement() or self.collision or self.moves[2] or self.moves[3])) and notUsingThrusters then
                    mcontroller.controlModifiers({movementSuppressed = true})
                end
            end
            if (not mcontroller.liquidMovement()) and (not ((potted or largePotted) or mertail)) then -- and (not swimmingFlight)
                local jumpInterval = 0.5
                if (self.moves[2] or self.moves[3] or self.moves[1]) and mcontroller.groundMovement() and (not activeMovementAbilities) then
                    if self.jumpTimer == jumpInterval then
                        -- sb.logInfo("potted = %s", potted)
                        -- sb.logInfo("largePotted = %s", largePotted)
                        -- sb.logInfo("math.__gliderActive = %s", math.__gliderActive)
                        -- sb.logInfo("math.__holdingGlider = %s", math.__holdingGlider)
                        local wingHop = avosiWings and not (itemL or itemR)
                        local dirJump = (self.moves[2] or self.moves[3]) and 1 or 0
                        if self.moves[5] then
                            mcontroller.setVelocity({1 * (self.moves[2] and -1 or 1) * dirJump, 10})
                        elseif self.moves[4] or self.moves[1] then
                            mcontroller.setVelocity({((wingHop and 25 or 7) * (self.moves[2] and -1 or 1) * dirJump), 20 * jumpSpeedMult})
                        elseif self.moves[7] then
                            mcontroller.setVelocity({((wingHop and 15 or 3.5) * (self.moves[2] and -1 or 1) * dirJump), 15 * jumpSpeedMult})
                        else
                            mcontroller.setVelocity({2 * (self.moves[2] and -1 or 1), 15 * jumpSpeedMult})
                        end
                        self.jumpTimer = 0
                    end
                    self.jumpTimer = math.min(self.jumpTimer + dt, jumpInterval)
                else
                    self.jumpTimer = math.min(self.jumpTimer + dt, jumpInterval)
                end
                -- mcontroller.walking()
            end
            if self.collision or not (potted or largePotted) then
                if self.moves[1] then mcontroller.controlJump() end
                if self.moves[5] then mcontroller.controlCrouch() end
                if self.moves[5] and self.moves[6] then mcontroller.controlDown() end
            else
                if self.moves[5] then mcontroller.controlCrouch() end
                if self.moves[5] and self.moves[6] then mcontroller.controlDown() end
            end
        elseif ghostTail then
            -- if mcontroller.groundMovement() and ((self.moves[2] or self.moves[3]) and not self.moves[6]) and smallColBox then
            --     -- mcontroller.controlJump()
            --     mcontroller.controlModifiers({movementSuppressed = true})
            -- end
            -- if self.moves[1] then mcontroller.controlJump() end
            -- if self.moves[5] then mcontroller.controlCrouch() end
            -- if self.moves[5] and self.moves[6] then mcontroller.controlDown() end
        end

        local colliding

        do
            local x, y = table.unpack(mcontroller.position())
            local side, down, up = 3.5, 3.5, 0.5
            local rectCol = {x - side, y - down, x + side, y + up}
            colliding = world.rectCollision(rectCol, {"Block", "Dynamic", "Slippery", "Platform"})
        end

        local isFlopping = false

        do
            local wingAngling = false
            local potCrawling = (potted or largePotted) and not gettingOverIt
            if (avosiFlight or avosiWingedArms or avosiJetpack or fireworks or swimTail or bouncy or mertail or potCrawling or windSailing or
              math.__gliderActive) and not (lounging or math.__sphereActive) then
                local rocketAngling = mcontroller.jumping() and self.moves[7] and (not mcontroller.liquidMovement())
                wingAngling = not (mcontroller.groundMovement() or mcontroller.liquidMovement())
                local velocity = mcontroller.velocity()
                local xVel = velocity[1]
                local yVel = velocity[2] -- avosiFlight and math.abs(velocity[2]) or velocity[2]
                local bouncing = bouncy and math.abs(xVel) > 3 and (not mcontroller.liquidMovement())
                local nearGround = false
                if mertail or potCrawling then
                    local scale = charScale or 1
                    nearGround = getClosestBlockYDistance(mPos, vec2.add(mPos, {0, (-4 * scale)}), false)
                end
                local flopping = (mertail or potCrawling) and (smallColBox or largePotted) and (self.moves[2] or self.moves[3]) and
                                   (mcontroller.groundMovement() or nearGround) and (not mcontroller.liquidMovement())
                isFlopping = flopping

                if (fireworks and rocketAngling) or ((avosiFlight or avosiWingedArms or avosiJetpack or windSailing) and wingAngling) or bouncing or flopping or
                  swimTail or math.__gliderActive then
                    local angleDiv = (avosiFlight or windSailing) and 1 or 2
                    local angleLag = (avosiFlight or windSailing) and 0.5 or 0.15
                    self.jumpAngleDt = math.min(angleLag, self.jumpAngleDt + dt)

                    local onJetpack = (avosiJetpack and not (avosiWingedArms or avosiFlight or windSailing)) or (avosiWingedArms and (itemL or itemR))
                    if (math.__gliderActive and (not colliding)) or onJetpack then yVel = math.__gliderActive and 75 or 10 end
                    if mcontroller.liquidMovement() then yVel = yVel + 2.5 end
                    local rawTAng = (vec2.angle({xVel / angleDiv, yVel}) - math.pi / 2)
                    local tAng = rawTAng
                    if (avosiFlight or windSailing or scarecrowPole) and (not (mcontroller.liquidMovement())) then
                        if rawTAng >= math.pi * 0.55 and rawTAng <= math.pi * 1 then
                            tAng = math.pi * 0.55
                        elseif rawTAng > math.pi * 1 and rawTAng <= math.pi * 1.45 then
                            tAng = math.pi * 1.45
                        end
                    end

                    if bouncy and (colliding or (not (avosiFlight or windSailing)) or world.liquidAt(liqCheckPosDown)) then
                        tAng = math.min(math.max(-xVel * math.pi * 0.05, -0.1 * math.pi), 0.1 * math.pi)
                    end
                    if flopping then
                        -- local faceDir = mcontroller.facingDirection()
                        if self.moves[2] then
                            tAng = math.pi * 0.35
                        elseif self.moves[3] then
                            tAng = math.pi * 1.65
                        end
                    end
                    -- if bouncy and xVel ~= 0 and mcontroller.groundMovement() then
                    --     if tAng >= -math.pi * 0.05 and tAng <= math.pi * 0.05 then
                    --         local xDir = xVel < 0 and -1 or 1
                    --         tAng = -xDir * math.pi * 0.05
                    --     end
                    -- end
                    self.targetAngle = (self.jumpAngleDt == angleLag or flopping) and tAng or 0
                    if (fireworks or ((avosiWingedArms or avosiJetpack) and usingFlightPack and checkDistRaw == -2)) and not (lounging or (bouncy and inLiquid)) then
                        self.fireworksDt = math.max(self.fireworksDt - dt, 0)
                        if self.fireworksDt == 0 then
                            self.fireworksDt = 0.04
                            if fireworks then
                                local fireworksParams = {
                                    power = 0,
                                    statusEffects = jarray(),
                                    damageKind = "hidden",
                                    lightColor = {235, 126, 2},
                                    periodicActions = {
                                        {
                                            time = 0.0,
                                            action = "particle",
                                            count = 1,
                                            specification = {
                                                type = "animated",
                                                light = {235, 126, 2},
                                                layer = "front",
                                                fullbright = true,
                                                collidesLiquid = false,
                                                collidesForeground = false,
                                                size = 0.9,
                                                destructionAction = "shrink",
                                                destructionTime = 0.06,
                                                timeToLive = 0.06,
                                                image = "/animations/statuseffects/burning/burning.animation" .. "?multiply=0000",
                                                variance = {position = {1.4, 2.4}, size = 0.15, initialVelocity = {0.2, 1.5}}
                                            }
                                        }
                                    }
                                }
                                local mPos = mcontroller.position()
                                if not math.__onWall then
                                    world.spawnProjectile("flamethrower", {mPos[1] + 0.0625, mPos[2]}, entity.id(), {0, -3}, false, fireworksParams)
                                end
                            else
                                local faceDir = mcontroller.facingDirection()
                                local exhaustVel = math.max(5 - math.abs(xVel) / 5, 0)
                                local yPos = math.max(1 - math.abs(xVel) / 15, -1.5)
                                local avoliteParticle = {
                                    fade = 1,
                                    initialVelocity = {-xVel / 5, -exhaustVel}, -- {0, -3},
                                    approach = {0, 2},
                                    flippable = false,
                                    layer = "back",
                                    destructionAction = "shrink",
                                    variance = {initialVelocity = {0.3, 0.3}, rotation = 180, position = {1, 1}},
                                    type = "textured",
                                    destructionTime = 1.5,
                                    size = 1.5,
                                    color = {255, 255, 255, 150},
                                    image = "/particles/ember/1.png?setcolor=fff?multiply=f03430fe",
                                    finalVelocity = {0, 2},
                                    timeToLive = 1,
                                    light = {140, 32, 30},
                                    position = {yPos, -0.6 * faceDir} -- {-2, 3.5} -- Rotated 90 degrees, so X and Y are switched.
                                }
                                local jetpackParticle = {
                                    type = "animated",
                                    light = {0, 0, 0},
                                    layer = "back",
                                    fullbright = false,
                                    collidesLiquid = true,
                                    collidesForeground = false,
                                    size = 0.9,
                                    destructionAction = "shrink",
                                    destructionTime = 0.6,
                                    timeToLive = 0.6,
                                    position = {yPos, -0.6 * faceDir}, -- Rotated 90 degrees, so X and Y are switched.
                                    initialVelocity = {-xVel / 5, -exhaustVel},
                                    image = "/animations/dusttest/dusttest.animation" .. "?multiply=fff1",
                                    variance = {position = {0.2, 0.6}, size = 0.15, initialVelocity = {0.2, 0.2}}
                                }
                                local flightPackParams = {
                                    power = 0,
                                    statusEffects = jarray(),
                                    damageKind = "hidden",
                                    timeToLive = 0.1,
                                    periodicActions = {
                                        {time = 0.0, action = "particle", count = 1, specification = avolitePack and avoliteParticle or jetpackParticle}
                                    }
                                }
                                local mPos = mcontroller.position()
                                if not math.__onWall then
                                    world.spawnProjectile("invisibleprojectile", {mPos[1] + 0.0625, mPos[2]}, entity.id(), {0, -3}, false, flightPackParams)
                                end
                            end
                        end
                    end
                else
                    self.jumpAngleDt = 0
                    self.targetAngle = 0
                end

                local keepUpward = math.abs(xVel) <= 3.5 and not (mcontroller.zeroG() or mcontroller.liquidMovement() or flopping)

                if math.__sphereActive or lounging or math.__onWall or (flyboard and math.__flyboardActive) or (self.collisionTimer ~= 0 and (not flopping)) or
                  keepUpward then
                    local mPos = mcontroller.position()
                    local liqCheckPosDown = {math.floor(mPos[1] + 0.5), math.floor(mPos[2] - 3)}
                    if bouncy and (mcontroller.groundMovement() or world.liquidAt(liqCheckPosDown)) and
                      (not (math.__isStable or lounging or math.__sphereActive)) then
                        if xVel == 0 then
                            self.targetAngle = 0
                        else
                            self.targetAngle = math.min(math.max(-xVel * math.pi * 0.05, -0.1 * math.pi), 0.1 * math.pi)
                        end
                    else
                        self.targetAngle = 0
                    end
                end

                if colliding and (not (bouncy or flopping)) then self.targetAngle = 0 end
            else
                self.targetAngle = 0
            end

            local angle = angleLerp(self.currentAngle, self.targetAngle, 0.08, math.pi * 0.002)
            if (avosiFlight or windSailing) and wingAngling and not (itemL or itemR or lounging or math.__sphereActive) then
                if angle > 0 and angle < math.pi then
                    mcontroller.controlFace(-1)
                elseif angle > math.pi and angle < math.pi * 2 then
                    mcontroller.controlFace(1)
                end
            end
            local flipping = math.__holdingGlider and not math.__gliderActive
            if (not (angle == 0 and self.currentAngle == 0)) and (not flipping) then mcontroller.setRotation(angle) end
            self.currentAngle = angle
        end

        if lounging and not math.__sphereActive then
            local adj = 0
            local sitParameters = {
                standingPoly = {
                    {-0.75, -2.0 + 0.875 + (adj / 8)}, {-0.35, -2.5 + 0.875 + (adj / 8)}, {0.35, -2.5 + 0.875 + (adj / 8)}, {0.75, -2.0 + 0.875 + (adj / 8)},
                    {0.75, 0.65}, {0.35, 1.22}, {-0.35, 1.22}, {-0.75, 0.65}
                },
                crouchingPoly = {
                    {-0.75, -2.0 + 0.375 + (adj / 8)}, {-0.35, -2.5 + 0.375 + (adj / 8)}, {0.35, -2.5 + 0.375 + (adj / 8)}, {0.75, -2.0 + 0.375 + (adj / 8)},
                    {0.75, -1}, {0.35, -0.5}, {-0.35, -0.5}, {-0.75, -1}
                }
            }
            if charScale and charScale ~= 1 then
                sitParameters.standingPoly = poly.scale(sitParameters.standingPoly, charScale)
                sitParameters.crouchingPoly = poly.scale(sitParameters.crouchingPoly, charScale)
            end
            mcontroller.controlParameters(sitParameters)
        elseif (noLegs or isMerrkin or leglessSmallColBox or tailed or largePotted) and not math.__sphereActive then
            status.setStatusProperty("isLegless", true)
            do
                local adj = largePotted and -7 or (mertail and 0 or -2)
                local cAdj = largePotted and -3 or -2
                local potParameters = {
                    liquidImpedance = 0,

                    walkSpeed = (not mcontroller.groundMovement()) and
                      (((parkourThrusters or fireworks or (paragliderPack and paramotor)) and mcontroller.jumping()) and 25 or (soarHop and 15 or 0.5)) or
                      (parkourThrusters and 0 or 0),
                    runSpeed = (not mcontroller.groundMovement()) and
                      (((parkourThrusters or fireworks or (paragliderPack and paramotor)) and mcontroller.jumping()) and 50 or (soarHop and 40 or 1)) or
                      (parkourThrusters and 0 or 0),

                    airJumpProfile = {
                        jumpSpeed = ((potted or largePotted) and not fireworks) and 2.5 or ((parkourThrusters or fireworks) and 15 or (soarHop and 15 or 2.5)),
                        autoJump = true,
                        reJumpDelay = (flightEnabled or soarHop or fireworks) and 0.02 or 0.35,
                        multiJump = flightEnabled or (fireworks and self.moves[7])
                    },

                    standingPoly = {
                        {-0.3, -2.0 + 0.875 + (adj / 8)}, {-0.08, -2.5 + 0.875 + (adj / 8)}, {0.08, -2.5 + 0.875 + (adj / 8)}, {0.3, -2.0 + 0.875 + (adj / 8)},
                        {0.75, 0.65}, {0.35, 1.22}, {-0.35, 1.22}, {-0.75, 0.65}
                    },
                    crouchingPoly = {
                        {-0.75, -2.0 + 0.375 + (cAdj / 8)}, {-0.35, -2.5 + 0.375 + (cAdj / 8)}, {0.35, -2.5 + 0.375 + (cAdj / 8)},
                        {0.75, -2.0 + 0.375 + (cAdj / 8)}, {0.75, -1}, {0.35, -0.5}, {-0.35, -0.5}, {-0.75, -1}
                    }
                }
                if charScale and charScale ~= 1 then
                    potParameters.standingPoly = poly.scale(potParameters.standingPoly, charScale)
                    potParameters.crouchingPoly = poly.scale(potParameters.crouchingPoly, charScale)
                end
                -- local jump, left, right = table.unpack(checkMovement())
                local colBoxMismatch = not (sb.printJson(mcontroller.collisionPoly()) == sb.printJson(potParameters.standingPoly) or
                                         sb.printJson(mcontroller.collisionPoly()) == sb.printJson(potParameters.crouchingPoly))
                if flightEnabled or checkDistRaw == -2 then
                    local isSoaring = checkDistRaw == -2
                    potParameters.airForce = 250;
                    potParameters.airFriction = 5;
                    potParameters.airJumpProfile = {
                        jumpSpeed = mertail and 5 or (potted and 2.5 or ((avosiJetpack and 5 or (isSoaring and 25 or 15)))),
                        autoJump = true,
                        multiJump = flightEnabled or avosiJetpack
                    }
                    potParameters.walkSpeed = (not mcontroller.groundMovement()) and (isSoaring and 2.5 or 5) or 0;
                    potParameters.runSpeed = (not mcontroller.groundMovement()) and (isSoaring and 7.5 or 20) or 0;
                end
                self.jumpDt = math.max(self.jumpDt - dt, 0)
                do
                    if (mcontroller.walking() or mcontroller.running()) and (mcontroller.groundMovement() or (not mcontroller.canJump())) and
                      (not mcontroller.liquidMovement()) and (not colBoxMismatch) then
                        if self.jumpDt <= 0 and (not (mertail or largePotted)) and (not largeColBoxMismatch) then
                            mcontroller.controlJump()
                            -- if soarHop then
                            --     local dir = mcontroller.facingDirection()
                            --     if math.abs(mcontroller.xVelocity()) >= 1 then dir = mcontroller.xVelocity() > 0 and 1 or -1 end
                            --     if mcontroller.running() then
                            --         mcontroller.setXVelocity(15 * dir)
                            --     end
                            -- end
                            self.jumpDt = 0.35
                        end
                        if not mcontroller.onGround() then
                            -- mcontroller.controlJump()
                        end
                    end
                end
                if soarHop or avosiWings or ghostTail or swimTail then
                    if mcontroller.jumping() then
                        self.soarDt = math.max(self.soarDt - dt, 0)
                    else
                        if opTail then
                            self.soarDt = mcontroller.groundMovement() and (self.moves[6] and 0.7 or 0.25) or math.min(self.soarDt + (dt / 2), 0.7)
                        elseif ghostTail then
                            self.soarDt = mcontroller.groundMovement() and 0.25 or self.soarDt
                        elseif swimTail then
                            self.soarDt = 0
                        elseif avosiWings then -- and not (itemL or itemR)
                            self.soarDt = mcontroller.groundMovement() and (self.moves[6] and 0.35 or 0.25) or math.min(self.soarDt + (dt / 6), 2)
                        else
                            self.soarDt = mcontroller.groundMovement() and (self.moves[6] and 0.35 or 0.25) or math.min(self.soarDt + (dt / 5), 2)
                        end
                    end
                    if ghostTail or swimTail then
                        potParameters.airFriction = 5
                        potParameters.airJumpProfile.jumpSpeed = 10
                        potParameters.airJumpProfile.jumpHoldTime = 0.25
                        potParameters.airJumpProfile.jumpInitialPercentage = 1
                        potParameters.airJumpProfile.multiJump = true -- self.soarDt > 0
                        potParameters.airJumpProfile.autoJump = self.moves[6] or self.soarDt == 0 -- true
                        local moveSpeed = swimTail and (self.moves[7] and 25 or 10) or 10
                        if self.soarDt == 0 then
                            if self.moves[5] then
                                mcontroller.setYVelocity(math.min(mcontroller.yVelocity(), -moveSpeed))
                            elseif self.moves[4] then
                                mcontroller.setYVelocity(math.max(mcontroller.yVelocity(), moveSpeed))
                            else
                                local swimFloor = (mcontroller.groundMovement() and swimTail) and 2 or 0
                                mcontroller.setYVelocity(math.max(mcontroller.yVelocity(), swimFloor))
                            end
                            if shadowRun and (self.moves[2] or self.moves[3]) then
                                mcontroller.controlAcceleration({(self.moves[7] and 35 or 15) * (self.moves[2] and -1 or 1), 0})
                            end
                        else
                            mcontroller.setYVelocity(math.max(mcontroller.yVelocity(), -moveSpeed))
                        end
                        potParameters.walkSpeed = 6
                        potParameters.runSpeed = 15
                    else
                        potParameters.airJumpProfile.multiJump = self.moves[7] and (self.soarDt >= 0.2)
                    end
                    if not mcontroller.onGround() then
                        potParameters.walkSpeed = ghostTail and 6 or 10;
                        potParameters.runSpeed = ghostTail and 15 or 40
                    end
                    if swimTail then
                        potParameters.walkSpeed = shadowRun and 15 or 10
                        potParameters.runSpeed = shadowRun and 50 or 25
                        potParameters.liquidForce = shadowRun and 30 or 250
                        if shadowRun and (self.moves[2] or self.moves[3]) then
                            potParameters.liquidFriction = self.thrustersActive and 0 or 1.5
                        end
                    end
                else
                    if mcontroller.falling() or mcontroller.flying() then
                        if opTail then
                            potParameters.airJumpProfile.jumpSpeed = math.max(25 + (math.abs(mcontroller.xVelocity()) / 3), 15)
                        else
                            potParameters.airJumpProfile.jumpSpeed = math.max(15 + (math.abs(mcontroller.xVelocity()) ^ 1.35 / 2.25), 5)
                        end
                    end
                end
                mcontroller.controlParameters(potParameters)
            end

            if not math.__sphereActive then self.crouchingTap:update(dt, self.moves) end
        else
            status.setStatusProperty("isLegless", nil)
            if self.crouching and not math.__sphereActive then mcontroller.controlCrouch() end
            local movementParameters = {
                airJumpProfile = {
                    multiJump = flightEnabled or fireworks,
                    autoJump = flightEnabled or (parkourThrusters and self.isRunBoosting) or soarHop or avosiWings or fireworks
                }
            }

            if scarecrowPole and not (math.__sphereActive or ghostTail) then
                -- mcontroller.controlModifiers({movementSuppressed = mcontroller.groundMovement() and not self.moves[6]})
                -- mcontroller.controlModifiers({movementSuppressed = true})
                if not mcontroller.onGround() then
                    movementParameters.walkSpeed = 3;
                    movementParameters.runSpeed = 6 * runSpeedMult
                else
                    movementParameters.walkSpeed = 0;
                    movementParameters.runSpeed = 0
                end
                local adjJumpSpeedMult = math.max(1, jumpSpeedMult)
                movementParameters.airJumpProfile.jumpSpeed = (self.moves[6] and 7.5 or 5) * ((self.moves[6] and self.running) and adjJumpSpeedMult or 1) *
                                                                (self.moves[7] and 1 or 0.5)
                movementParameters.airJumpProfile.autoJump = true
                movementParameters.airJumpProfile.reJumpDelay = 0.5

                self.jumpDt = math.max(self.jumpDt - dt, 0)

                if (self.moves[2] or self.moves[3]) and colliding and (not mcontroller.liquidMovement()) then
                    if self.jumpDt >= ((soarHop or avosiWings or swimmingFlight) and 0.55 or 0.4) then
                        if not (bouncy or largePotted or largeColBoxMismatch) then mcontroller.controlJump() end --  and (not self.running)
                        -- if soarHop then
                        --     local dir = mcontroller.facingDirection()
                        --     if math.abs(mcontroller.xVelocity()) >= 1 then dir = mcontroller.xVelocity() > 0 and 1 or -1 end
                        --     if mcontroller.running() then
                        --         mcontroller.setXVelocity(15 * dir)
                        --     end
                        -- end
                    end
                    if self.jumpDt <= 0 then self.jumpDt = 0.6 end
                    if not mcontroller.onGround() then
                        -- mcontroller.controlJump()
                    end
                end
            end

            if (soarHop or avosiWings or ghostTail or swimTail) and not math.__sphereActive then
                if mcontroller.jumping() then
                    self.soarDt = math.max(self.soarDt - dt, 0)
                else
                    if opTail then
                        self.soarDt = mcontroller.groundMovement() and (self.moves[6] and 0.7 or 0.25) or math.min(self.soarDt + (dt / 2), 0.7)
                    elseif ghostTail then
                        self.soarDt = mcontroller.groundMovement() and 0.25 or self.soarDt
                    elseif swimTail then
                        self.soarDt = 0
                    elseif avosiWings then -- and not (itemL or itemR)
                        self.soarDt = mcontroller.groundMovement() and (self.moves[6] and 0.35 or 0.25) or math.min(self.soarDt + (dt / 6), 2)
                    else
                        self.soarDt = mcontroller.groundMovement() and (self.moves[6] and 0.35 or 0.25) or math.min(self.soarDt + (dt / 5), 2)
                    end
                end
                movementParameters.airJumpProfile.jumpHoldTime = ghostTail and 0.25 or 1.5
                movementParameters.airJumpProfile.jumpInitialPercentage = ghostTail and 1 or 0.25
                if ghostTail or swimTail then
                    movementParameters.airFriction = 5
                    movementParameters.airJumpProfile.multiJump = true -- self.soarDt > 0
                    movementParameters.airJumpProfile.autoJump = self.moves[6] or self.soarDt == 0 -- true
                    local moveSpeed = swimTail and (self.moves[7] and 25 or 10) or 10
                    if self.soarDt == 0 then
                        if self.moves[5] then
                            mcontroller.setYVelocity(math.min(mcontroller.yVelocity(), -moveSpeed * ((shadowRun and self.thrustersActive) and 3 or 1)))
                        elseif self.moves[4] then
                            mcontroller.setYVelocity(math.max(mcontroller.yVelocity(), moveSpeed))
                        else
                            local swimFloor = (mcontroller.groundMovement() and swimTail) and 2 or 0
                            mcontroller.setYVelocity(math.max(mcontroller.yVelocity(), swimFloor))
                        end
                        if shadowRun and (self.moves[2] or self.moves[3]) then
                            mcontroller.controlAcceleration({(self.moves[7] and 35 or 15) * (self.moves[2] and -1 or 1), 0})
                        end
                    else
                        mcontroller.setYVelocity(math.max(mcontroller.yVelocity(), -moveSpeed))
                    end
                else
                    movementParameters.airJumpProfile.multiJump = self.moves[7] and (self.soarDt >= 0.2)
                end
                if not mcontroller.onGround() then
                    movementParameters.walkSpeed = ghostTail and 6 or 10;
                    movementParameters.runSpeed = ghostTail and 15 or 40
                else
                    if (ghostTail or soarHop or opTail) then
                        if legless then
                            movementParameters.walkSpeed = 0;
                            movementParameters.runSpeed = 0
                        else
                            movementParameters.walkSpeed = ghostTail and 6 or 3;
                            movementParameters.runSpeed = ghostTail and 15 or 6
                        end
                    end
                end
                if swimTail then
                    movementParameters.walkSpeed = shadowRun and 15 or 10
                    movementParameters.runSpeed = shadowRun and 50 or 25
                    movementParameters.liquidForce = shadowRun and 30 or 250
                    if shadowRun and (self.moves[2] or self.moves[3]) then
                        movementParameters.liquidFriction = self.thrustersActive and 0 or 1.5
                    end
                end
                if scarecrowPole and not self.moves[6] then
                    movementParameters.airJumpProfile.jumpSpeed = 3.5
                elseif opTail then
                    movementParameters.airJumpProfile.jumpSpeed = (mcontroller.falling() or mcontroller.flying()) and 10 or (self.moves[6] and 30 or 10)
                elseif avosiWings then -- and not (itemL or itemR)
                    local flapSpeed = soarHop and 10 or 6
                    movementParameters.airJumpProfile.jumpSpeed = (mcontroller.falling() or mcontroller.flying()) and flapSpeed or (self.moves[6] and 30 or 10)
                elseif ghostTail then
                    movementParameters.airJumpProfile.jumpSpeed = 10 -- (self.soarDt > 0) and 12.5 or 4.5
                elseif swimTail then
                    movementParameters.airJumpProfile.jumpSpeed = self.moves[7] and 10 or 5
                elseif soarHop then
                    movementParameters.airJumpProfile.jumpSpeed = (mcontroller.falling() or mcontroller.flying()) and 4.5 or (self.moves[6] and 45 or 10)
                    -- elseif avosiWings then
                    --     movementParameters.airJumpProfile.jumpSpeed = 10
                else
                    movementParameters.airJumpProfile.jumpSpeed = 45
                end
            else
                if (self.moves[4] or self.moves[5]) and not self.moves[7] then mcontroller.controlModifiers({speedModifier = 0.35}) end
            end
            if flightEnabled and (not mcontroller.groundMovement()) and (not math.__sphereActive) then
                movementParameters.walkSpeed = 20;
                movementParameters.runSpeed = 50;
                movementParameters.airForce = 250;
                movementParameters.airFriction = 5
            end

            if not math.__sphereActive then mcontroller.controlParameters(movementParameters) end

            if not math.__sphereActive then self.crouchingTap:update(dt, self.moves) end
        end

        local gliding = math.__gliderActive and math.__isGlider ~= nil
        local usingGlider = math.__gliderActive and math.__isGlider == true

        local thermalSoaring = false

        if math.__gliderActive and not (fezTech or garyTech or shadowRun) then
            local x, y = table.unpack(mcontroller.position())
            local side, down, up = 5, -3, 7
            local rectCol = {x - side, y - down, x + side, y + up}
            local side2, down2, up2 = 2.5, 0, 7
            local rectCol2 = {x - side2, y - down2, x + side2, y + up2}
            local side3, down3, up3 = 15, -3, 7
            local rectCol3 = {x - side3, y - down3, x + side3, y + up3}
            local background = false
            for xAdd = -3, 3, 1 do
                for yAdd = 0, 4, 1 do
                    if backgroundExists({x + xAdd, y + yAdd}, true, true) then
                        background = true
                        break
                    end
                end
            end
            local colliding = world.rectCollision(rectCol, {"Block", "Dynamic", "Slippery"}) or world.rectCollision(rectCol2, {"Block", "Dynamic", "Slippery"})
            thermalSoaring = (world.rectCollision(rectCol3, {"Block", "Dynamic", "Slippery"}) or background) and (not self.moves[5])
            -- or background
            if colliding then
                math.__gliderActive = false
                self.fallDanger = false
                self.useParawing = false
            end
        else
            thermalSoaring = false
        end

        if ((swimmingFlight or avosiFlight or windSailing or gliding or (upgradedThrusters and parkourThrusters) or
          (avosiWings and (not mcontroller.liquidMovement())) or (flyboard and math.__flyboardActive and (not mcontroller.liquidMovement()))) or
          (shadowRun and self.thrustersActive and mcontroller.liquidMovement())) and (not (math.__sphereActive or lounging or mcontroller.zeroG())) then
            local movementParameters = {}

            local gravMod = mcontroller.baseParameters().gravityMultiplier
            if not (mcontroller.onGround()) then
                movementParameters.walkSpeed = (math.__flyboardActive or shadowRun or (avosiFlight and not (safetyFlight or math.__gliderActive))) and 20 or 10;
                movementParameters.runSpeed = (math.__flyboardActive or shadowRun or (avosiFlight and not (safetyFlight or math.__gliderActive))) and
                                                (avosiWingedArms and 75 or 50) or 25
            end
            if swimmingFlight or gliding then
                local flying =
                  (((paramotor and math.__gliderActive) or parkourThrusters or avosiFlight) and (math.abs(mcontroller.xVelocity() / 22.5) >= 1)) and
                    (not shadowRun)
                movementParameters.airJumpProfile = {
                    jumpSpeed = (flying and 5 or 10),
                    jumpControlForce = 400,
                    jumpInitialPercentage = 0.75,
                    jumpHoldTime = 0.25,
                    multiJump = self.collision or flying or (soarHop and self.soarDt >= 0.2),
                    reJumpDelay = 0.25,
                    autoJump = true,
                    collisionCancelled = false
                }
            elseif avosiFlight then
                local flying = (not shadowRun) and (groundDist and jumpSpeedMult > 0 and self.running)
                local velMag = math.abs(mcontroller.xVelocity()) / 5
                local adjJumpSpeedMult = math.min(jumpSpeedMult, ((jumpSpeedMult + 1) / 2))
                local groundJumpSpeedMult = math.max(1, jumpSpeedMult)
                local jumpAdder = (self.moves[6] and self.running) and (groundJump and groundJumpSpeedMult or adjJumpSpeedMult) or (self.moves[7] and 1 or 0.45)
                if self.collision then jumpAdder = math.max(1, jumpAdder) end
                movementParameters.airJumpProfile = {
                    jumpSpeed = 10 * jumpAdder,
                    jumpControlForce = 400,
                    jumpInitialPercentage = 0.75,
                    jumpHoldTime = 0.05,
                    multiJump = self.collision or flying or (soarHop and self.soarDt >= 0.2),
                    reJumpDelay = 0.05, -- self.collision and 0.05 or math.max(0.4 - (velMag * 0.05), 0.05),
                    autoJump = true,
                    collisionCancelled = false
                }
            elseif windSailing then
                local jumpAdder = (self.moves[6] and self.running) and (groundJump and groundJumpSpeedMult or adjJumpSpeedMult) or (self.moves[7] and 1 or 0.45)
                movementParameters.airJumpProfile = {
                    jumpSpeed = 10 * jumpAdder,
                    jumpHoldTime = 0.25,
                    multiJump = soarHop and self.soarDt >= 0.2,
                    reJumpDelay = 0.25,
                    collisionCancelled = false
                }
            elseif not (itemL or itemR) then
                movementParameters.airJumpProfile = {
                    jumpSpeed = 25,
                    jumpHoldTime = 0.25,
                    multiJump = soarHop and self.soarDt >= 0.2,
                    reJumpDelay = 0.25,
                    collisionCancelled = false
                }
            end
            if math.__flyboardActive then
                movementParameters.airJumpProfile = {
                    jumpSpeed = 25,
                    jumpHoldTime = 0.25,
                    multiJump = soarHop and self.soarDt >= 0.2,
                    reJumpDelay = 0.25,
                    collisionCancelled = false
                }
            end
            local wind = (windTileOcc or math.__grappled) and 0 or world.windLevel(mcontroller.position())
            if fezTech or math.__onWall or lounging then wind = 0 end
            if not (mcontroller.groundMovement()) then
                local windDiv = (self.moves[2] or self.moves[3]) and 10 or 7.5
                if self.moves[5] then
                    mcontroller.controlAcceleration(
                      {wind / windDiv, math.__flyboardActive and -6 or (shadowRun and (mcontroller.liquidMovement() and -60 or -30) or -1)}
                    )
                elseif self.moves[1] and
                  (math.__flyboardActive or (usingGlider and (parkourThrusters or avosiGlider or shadowRun)) or (parkourThrusters and upgradedThrusters)) or
                  (shadowRun and self.upgradedThrusters) then
                    local xVel = math.abs(mcontroller.xVelocity())
                    local windV = math.abs(wind)
                    mcontroller.controlAcceleration({wind / windDiv, (windV / 25) + (xVel / 25) + (shadowRun and 45 or 25)})
                elseif self.moves[4] and
                  (math.__flyboardActive or (usingGlider and (parkourThrusters or avosiGlider or shadowRun)) or (parkourThrusters and upgradedThrusters)) or
                  (shadowRun and self.upgradedThrusters) then
                    local xVel = math.abs(mcontroller.xVelocity())
                    local windV = math.abs(wind)
                    mcontroller.controlAcceleration({wind / windDiv, (windV / 25) + (xVel / 25) + 10})
                elseif self.moves[1] and windSailing and not (gliding or math.__flyboardActive) then
                    local xVel = math.abs(mcontroller.xVelocity())
                    local windV = math.abs(wind)
                    mcontroller.controlAcceleration({wind / windDiv, (windV / 25) + (xVel / 40) + 25})
                else
                    local xVel = math.abs(mcontroller.xVelocity())
                    local windV = math.abs(wind)
                    if math.__flyboardActive or (gliding and self.hovering) then
                        mcontroller.controlAcceleration({wind / windDiv, (xVel / 25) + 4.75})
                    else
                        local velDiv = (avosiFlight and (not math.__gliderActive)) and ((groundDist and self.running) and 15 or 20) or 10
                        mcontroller.controlAcceleration({wind / windDiv, (windV / 25) + (xVel / velDiv)})
                    end
                end
            end
            local glideDiv = (swimmingFlight or (gliding and (paramotor or parkourThrusters))) and 15 or 30
            local glideVel = math.max(1 - math.abs(mcontroller.xVelocity() / glideDiv), 0)
            local avosiGliding = avosiFlight and (jumpSpeedMult <= 0 or (not self.running) or (not groundDist)) and (not self.collision)
            local usingAvosiGlider = avosiGlider and math.__gliderActive
            if not (mcontroller.groundMovement()) and
              (swimmingFlight or avosiFlight or usingGlider or windSailing or (parkourThrusters and upgradedThrusters) or math.__flyboardActive or
                (not (itemL or itemR))) then
                local gravMin = soarHop and 0.4 or (avosiGliding and ((groundDist and rawAvosiFlight) and 0.05 or 0.2) or 0.45)
                local gravMax = soarHop and 0.5 or 0.55
                local gravMult = (swimmingFlight or paramotor or usingAvosiGlider or usingGlider) and math.max(gravMod * 0.05 * glideVel, 0.01) or
                                   (math.__flyboardActive and (gravMod * 0.04) or math.min(math.max(gravMod * 0.75 * glideVel, gravMin), gravMax))
                movementParameters.gravityMultiplier = gravMult * gravityModifier
            end
            if swimmingFlight or (flyboard and math.__flyboardActive) or (shadowRun and self.thrustersActive) or bouncy then
                status.addEphemeralEffect("nofalldamage", 0.5)
            end

            if avosiWingedArms and not (itemL or itemR or mcontroller.liquidMovement() or mcontroller.groundMovement()) then
                if (self.moves[2] or self.moves[3]) and self.running then mcontroller.controlJump() end
            end

            mcontroller.controlParameters(movementParameters)

            if math.__flyboardActive and (tech and (not lounging)) then
                local mPos = mcontroller.position()
                self.flyboardTimer = math.max(0, self.flyboardTimer - dt)
                local scale = charScale or 1
                if self.flyboardTimer == 0 then
                    -- not (self.flyboardProjectileId and world.entityExists(self.flyboardProjectileId))
                    local adj = mertail and 0 or -2
                    local mOffset = {0, (((math.__noLegs and not largePotted) and (-1.625 + adj / 8) or -2.5) * scale) + -1.6785 + (1.6785 * scale) + 1.75}
                    local adjPos = vec2.add(mPos, mOffset)
                    local player = math.__player
                    local backItem = player and player.equippedItem("back")
                    local flyboardDirs
                    if backItem then
                        flyboardDirs = backItem.parameters.flyboardDirectives or backItem.parameters.directives or self.defaultParagliderDirs
                    else
                        flyboardDirs = self.defaultParagliderDirs
                    end
                    self.flyboard.processing = self.flyboardBaseDirs .. flyboardDirs .. "?scalenearest=" .. tostring(scale)

                    self.flyboardProjectileId = world.spawnProjectile("invisibleprojectile", adjPos, entity.id(), {1, 0}, true, self.flyboard)

                    self.flyboardTimer = self.flyboard.timeToLive
                end
                local nearGround = getClosestBlockYDistance(mPos, vec2.add(mPos, {0, ((math.__noLegs and -3 or -3.5) * scale)}), self.moves[5])
                local yVel = mcontroller.yVelocity()
                if nearGround and yVel < 0 then mcontroller.setYVelocity(0) end
                if math.abs(yVel) <= 5 then
                    mcontroller.addMomentum({math.random() * 0.5 - 0.25, math.random() * 0.5 - 0.25})
                    mcontroller.controlApproachVelocity({0, 0}, 5)
                end
                if mcontroller.groundMovement() then mcontroller.setYVelocity(2.5) end
                if xsb and player.setOverrideState then
                    player.setOverrideState("idle")
                elseif tech then
                    tech.setParentState("Stand")
                end
            end
        end

        if (not flyboard) or (not math.__flyboardActive) or lounging or mcontroller.zeroG() or math.__sphereActive then
            if self.flyboardProjectileId then
                if world.entityExists(self.flyboardProjectileId) then
                    -- sb.logInfo("Projectile kill status: %s", world.sendEntityMessage(self.flyboardProjectileId, "kill"):succeeded())
                end
                self.flyboardProjectileId = nil
                if tech and not (xsb and player.setOverrideState) then tech.setParentState() end
            end
            math.__flyboardActive = false
        end

        if flyboard then self.flyboardTap:update(dt, self.moves) end

        if nightVision or shadowVision then
            world.sendEntityMessage(entity.id(), "clearLightSources")
            local mPos = mcontroller.position()
            if not world.pointTileCollision(mPos, {"Block", "Dynamic", "Slippery"}) then
                world.sendEntityMessage(
                  entity.id(), "addLightSource", {position = mPos, color = shadowVision and {200, 200, 200} or {120, 225, 180}, pointLight = true}
                )
                if tech then
                    local aimP = tech.aimPosition()
                    aimP = world.lineCollision(mPos, aimP, {"Block", "Dynamic", "Slippery"}) or aimP
                    world.sendEntityMessage(
                      entity.id(), "addLightSource", {position = aimP, color = shadowVision and {200, 200, 200} or {120, 225, 180}, pointLight = true}
                    )
                end
            end
        else
            world.sendEntityMessage(entity.id(), "clearLightSources")
        end
        -- world.sendEntityMessage(entity.id(), "clearDrawables")

        if (avosiWings and not (mcontroller.liquidMovement() or mcontroller.groundMovement())) and not math.__sphereActive then
            local jumping = mcontroller.jumping()
            if jumping and not self.lastJumping then -- self.moves[1] and not self.lastJump
                math.__wingFlap = true
            end
            -- self.lastJump = self.moves[1]
            self.lastJumping = jumping
        end

        if (not self.isSkating) and self.lastSkating then if not (xsb and player.setOverrideState) then tech.setParentState() end end

        self.lastSkating = self.isSkating

        local rpMovement = false
        local canWalk = false

        if roleplayMode then
            rpMovement = not (flightEnabled or opTail or ghostTail or swimmingFlight or soarHop or (fireworks and legless) or potted or largePotted or
                           avosiWings or math.__gliderActive or (parkourThrusters and not mcontroller.groundMovement()) or fezTech or garyTech or
                           (flyboard and math.__flyboardActive) or math.__sphereActive)
            local baseRunSpeed = mcontroller.baseParameters().runSpeed
            local runMul = (self.running or runSpeedMult == 0) and runSpeedMult or math.sqrt(runSpeedMult)
            local wingSpeed = ((avosiWings and (not (itemL or itemR))) or (avosiFlight and (not safetyFlight))) and
                                (not (mcontroller.groundMovement() or mcontroller.liquidMovement()))
            local wingedArmFlying = (avosiWingedArms or avosiFlight) and
                                      not (math.__gliderActive or mcontroller.groundMovement() or mcontroller.liquidMovement() or math.__onWall or
                                        (itemL or itemR))
            local slowAir = (avosiWingedArms or avosiJetpack) and
                              not (wingedArmFlying or mcontroller.groundMovement() or mcontroller.liquidMovement() or math.__onWall)
            local runningSpeed = (slowAir and avosiJetpack) and 0.45 or 1
            local joggingSpeed = (slowAir and avosiJetpack) and 0.45 or 0.6
            local walkParameters = {
                walkSpeed = (isLame and not self.moves[7]) and 2 or 4,
                runSpeed = baseRunSpeed * runMul * (((shadowRun and self.shadowFlight and self.running) or wingSpeed) and (wingedArmFlying and 5 or 2.5) or 1) *
                  ((self.running or wingedArmFlying) and runningSpeed or joggingSpeed)
            }
            canWalk = not (opTail or ghostTail or scarecrowPole or soarHop or (fireworks and legless) or canHop or noLegs or leglessSmallColBox or
                        (flyboard and math.__flyboardActive) or math.__sphereActive)
            if canWalk and (mcontroller.groundMovement() or not (math.__gliderActive or parkourThrusters)) then
                mcontroller.controlParameters(walkParameters)
            end
        end

        if shadowRun and (not (mcontroller.groundMovement() or mcontroller.liquidMovement() or math.__gliderActive)) then
            local airParameters = {runSpeed = 35}
            mcontroller.controlParameters(airParameters)
        end

        math.__rpMovement = rpMovement

        if roleplayMode then
            self.collision = nil
            local mPos = mcontroller.position()
            local face = mcontroller.facingDirection()
            local colTime = 0.15
            local noReset = false
            local pAdd = noLegs and 2 or 0
            for i = 2 + pAdd, 3 + pAdd, 1 do
                local left, right = vec2.add(mPos, {-0.5 * face, i - 1}), vec2.add(mPos, {1.5 * face, i - 1})
                local leftShort, rightShort = vec2.add(mPos, {-0.5 * face, i - 1}), vec2.add(mPos, {0.5 * face, i - 1})
                if world.lineTileCollisionPoint(left, right, {'block', 'dynamic'}) and not world.lineTileCollisionPoint(leftShort, rightShort, {'platform'}) then
                    noReset = checkDistRaw ~= -1
                    break
                end
            end
            for i = 0, 1 + pAdd, 1 do
                local left, right = vec2.add(mPos, {-0.5 * face, i - 1}), vec2.add(mPos, {1.5 * face, i - 1})
                local leftShort, rightShort = vec2.add(mPos, {-0.5 * face, i - 1}), vec2.add(mPos, {0.5 * face, i - 1})
                if world.lineTileCollisionPoint(left, right, {'block', 'dynamic'}) or world.lineTileCollisionPoint(leftShort, rightShort, {'platform'}) then
                    self.collision = true
                    if not noReset then self.collisionTimer = colTime end
                    break
                end
            end
            if noReset then self.collision = false end
            for i = 0, 1 + pAdd, 1 do
                local left, right = vec2.add(mPos, {-0.5 * face, i - 1}), vec2.add(mPos, {0.5 * face, i - 1})
                local leftUp, rightUp = vec2.add(mPos, {-0.5 * face, i}), vec2.add(mPos, {0.5 * face, i})
                if world.lineTileCollisionPoint(left, right, {'platform'}) and not world.lineTileCollisionPoint(leftUp, rightUp, {'block', 'dynamic'}) then
                    self.collision = true
                    if not noReset then self.collisionTimer = colTime end
                    break
                end
            end

            -- local avosiDelay = math.max(0.5 - (math.abs(mcontroller.xVelocity() / 5) * 0.05), 0.05)

            local isColliding
            if scarecrowPole or avosiFlight then
                isColliding = self.collisionTimer > 0
            else
                isColliding = self.collision
            end
            local bouncyJumpSpeedMult = bouncy and math.max(((jumpSpeedMult + 1) / 2), 1) or 1
            local adjJumpSpeedMult = (self.running and self.moves[1] and (not isColliding)) and math.max(1, jumpSpeedMult) or bouncyJumpSpeedMult

            local absXVel = math.abs(mcontroller.xVelocity())
            local runningMod = math.sqrt(absXVel)
            local groundJumpSpeed = ((avosiJetpack or avosiWingedArms) and self.onGroundTimer == 0 and not isColliding) and 3.5 or 7.5
            if (avosiWingedArms and not avosiJetpack) and checkDistRaw == -2 and ((avosiJetpack or itemL or itemR) and self.moves[7]) and
              not (mcontroller.liquidMovement() or math.__sphereActive or math.__gliderActive) then groundJumpSpeed = 13 end
            -- and avosiJetpack
            local airJumpSpeed = self.onGroundTimer == 0 and 0 or 3.5
            local jetpackGliding = (avosiWingedArms or avosiJetpack) and checkDistRaw == -2 and paragliderPack and math.__gliderActive and
                                     not (mcontroller.liquidMovement() or math.__sphereActive or lounging)
            local jumpParameters = {
                airJumpProfile = {
                    jumpSpeed = ((self.moves[7] and self.moves[1]) and groundJumpSpeed or airJumpSpeed) * adjJumpSpeedMult + runningMod,
                    multiJump = isColliding or (avosiFlight and tileOcc) or jetpackGliding or (avosiJetpack and self.moves[7]),
                    autoJump = scarecrowPole or isColliding or tileOcc or jetpackGliding or (avosiJetpack and self.moves[7]),
                    reJumpDelay = (isColliding or (self.moves[1] and not noLegs) or avosiFlight) and 0.05 or 0.5
                }
            }
            if avosiWingedArms and checkDistRaw ~= -2 and not (isColliding or math.__isGlider) then
                jumpParameters.airJumpProfile.multiJump = false
                jumpParameters.airJumpProfile.autoJump = scarecrowPole
            end

            -- sb.logInfo("jumpParameters.airJumpProfile.multiJump = %s", jumpParameters.airJumpProfile.multiJump)
            if not self.collisionTimer then self.collisionTimer = 0 end
            if not self.collision then self.collisionTimer = math.max(self.collisionTimer - dt, 0) end
            if not self.onGroundTimer then self.onGroundTimer = 0 end
            if not (mcontroller.groundMovement() or math.__onWall) then
                self.onGroundTimer = math.max(self.onGroundTimer - dt, 0)
            else
                self.onGroundTimer = 0.1
            end
            if rpMovement or jetpackGliding or avosiWingedArms or self.collisionTimer > 0 then mcontroller.controlParameters(jumpParameters) end
        else
            self.collisionTimer = 0
            self.onGroundTimer = 0
            local jetpackGliding = (avosiWingedArms or avosiJetpack) and checkDistRaw == -2 and paragliderPack and math.__gliderActive and
                                     not (mcontroller.liquidMovement() or math.__sphereActive or lounging)
            local jumpParameters = {
                airJumpProfile = {
                    multiJump = (avosiFlight and tileOcc) or jetpackGliding or checkDistRaw == -2 or (avosiJetpack and self.moves[7]),
                    autoJump = tileOcc or jetpackGliding or checkDistRaw == -2 or (avosiJetpack and self.moves[7]),
                    reJumpDelay = 0.05
                }
            }
            if self.moves[1] or not isLeglessChar then
                jumpParameters.airJumpProfile.jumpSpeed = (avosiJetpack or checkDistRaw <= -1 or (bouncy and not self.moves[1])) and 10 or 35
            else
                jumpParameters.airJumpProfile.jumpSpeed = 15
            end
            if bouncy and inLiquid and self.moves[5] then mcontroller.controlApproachYVelocity(-10, 150) end
            if avosiWingedArms and checkDistRaw ~= -2 and not (math.__isGlider) then
                jumpParameters.airJumpProfile.multiJump = false
                jumpParameters.airJumpProfile.autoJump = scarecrowPole
            end
            if noLegs then
                jumpParameters.runSpeed = 14
                jumpParameters.walkSpeed = 8
            end
            if (avosiJetpack or avosiWingedArms or avosiFlight or noLegs or scarecrowPole) and not math.__gliderActive then
                mcontroller.controlParameters(jumpParameters)
            end
        end

        local flight = avosiFlight or avosiWings or swimmingFlight or fezTech or garyTech or (flyboard and math.__flyboardActive) or math.__gliderActive or
                         math.__sphereActive or lounging

        if isLame and (mcontroller.groundMovement() or (not flight)) then
            self.lameTimer = self.lameTimer + dt
            local lameMove
            if self.lameTimer >= 0.65 then
                lameMove = mcontroller.crouching() or self.crouching
                if self.lameTimer >= 0.75 then self.lameTimer = 0 end
            else
                lameMove = true
            end
            local lameModifiers = {movementSuppressed = not lameMove, runningSuppressed = true}
            mcontroller.controlModifiers(lameModifiers)
        else
            self.lameTimer = 0
        end

        if bouncy and not mcontroller.zeroG() then
            local velocity = mcontroller.velocity()
            velocity = math.abs(math.sqrt(velocity[1] ^ 2 + velocity[2] ^ 2))
            local bounceFactor = math.max(0.05, math.min(0.8, 0.8 - velocity / 100))
            -- local bobTime = 3
            -- self.bobTimer = math.min(self.bobTimer + dt, bobTime)
            local bouncyParams = {
                bounceFactor = bounceFactor, -- 0.8
                normalGroundFriction = math.__isStable and 7 or 3.5,
                ambulatingGroundFriction = math.__isStable and 2 or 1,
                liquidBuoyancy = self.moves[5] and 0.2 or 0.9,
                slopeSlidingFactor = math.__isStable and 1 or 5
            }
            if mcontroller.groundMovement() then
                bouncyParams.walkSpeed = 0
                bouncyParams.runSpeed = 0
            end
            mcontroller.controlParameters(bouncyParams)

            if (mcontroller.groundMovement() or world.liquidAt(liqCheckPosDown)) and not (lounging or math.__sphereActive or math.__isStable) then
                -- local xVel = mcontroller.xVelocity()
                -- if math.abs(xVel) <= 2.5 then
                --     mcontroller.controlApproachVelocity({0, 0}, 5)
                -- end
                if self.currentAngle < -0.05 * math.pi then
                    mcontroller.controlAcceleration({-2, 0})
                elseif self.currentAngle > 0.05 * math.pi then
                    mcontroller.controlAcceleration({2, 0})
                end
                local wind = windTileOcc and 0 or world.windLevel(mPos)
                local windDiv = 15
                -- local bobDir = (self.bobTimer >= (bobTime / 2)) and -1 or 1
                local velMod = 1 + velocity / 5
                if (self.moves[2] or self.moves[3]) and ((not self.moves[7]) or (not self.running)) then
                    local dir = self.moves[2] and -1 or 1
                    local running
                    local windAbs = math.abs(wind)
                    if windSailing and not windTileOcc then
                        running = self.moves[7] and (0.65 * (windAbs * 0.5 + 25)) or (0.35 * (windAbs * 0.5 + 25))
                    else
                        running = self.moves[7] and 2.5 or 1.5
                    end
                    local windMul = windSailing and (windAbs * 0.1 + 1) or 1
                    mcontroller.controlAcceleration({((velMod * 20 * windMul * math.random()) - (velMod * 10 * windMul) + running * dir) + (wind / windDiv), 0})
                else
                    mcontroller.controlAcceleration({((velMod * 20 * math.random()) - velMod * 10) + (wind / windDiv), 0})
                end
            end

            if world.liquidAt(liqCheckPos) and not (lounging or math.__sphereActive) then
                mcontroller.controlAcceleration({0, self.moves[1] and 250 or 80})
            end

            -- if self.bobTimer >= bobTime then self.bobTimer = 0 end
            -- else
            --     self.bobTimer = 0
        end

        if (avosiJetpack or avosiFlight) and
          not (mcontroller.groundMovement() or mcontroller.liquidMovement() or mcontroller.zeroG() or lounging or math.__sphereActive or math.__gliderActive or
            math.__onWall) then
            local wind = windTileOcc and 0 or world.windLevel(mcontroller.position())
            local windDiv = 15
            local velocity = mcontroller.velocity()
            velocity = math.abs(math.sqrt(velocity[1] ^ 2 + velocity[2] ^ 2))
            if tailless then
                local xWindMod = 1 + math.abs(wind / 16)
                local yWindMod = 1 + math.abs(wind / 8)
                local yWindModAug = 1 + math.abs(wind / 8) * 1.15
                local xMaxVariance = 25 + velocity * 1.5
                local xVariance = xMaxVariance * 2 * xWindMod * math.random() - xMaxVariance * xWindMod
                local yVariance = math.random() * velocity * yWindMod - 0.5 * velocity * yWindModAug
                mcontroller.controlAcceleration({xVariance + (wind / windDiv), yVariance})
            else
                mcontroller.controlAcceleration({wind / windDiv, 0})
            end
        end

        if (mertail or ((potted or largePotted) and not gettingOverIt)) and (smallColBox or largePotted) then
            local isMoving = (self.moves[2] or self.moves[3]) and mcontroller.groundMovement()
            if isMoving then
                local maxVariance = 150
                mcontroller.controlAcceleration({(maxVariance * math.random() - maxVariance * 0.2) * (self.moves[2] and -1 or 1), 0})
                mcontroller.controlFace(self.moves[2] and -1 or 1)
            elseif (not isMoving) and self.lastIsMoving then
                local gravity = world.gravity(mPos)
                mcontroller.setYVelocity(15 * math.sqrt(gravity / 80))
            end
            self.lastIsMoving = isMoving
        else
            self.lastIsMoving = false
        end

        local bouncyOnGround = false
        if bouncy then
            local bouncingOnLiquid = world.liquidAt(liqCheckPosDown) and not world.liquidAt(liqCheckPosUp)
            bouncyOnGround = (mcontroller.groundMovement() or bouncingOnLiquid) and (not (lounging or math.__sphereActive)) -- and (not (self.moves[2] or self.moves[3]))

            if mcontroller.groundMovement() and (self.moves[2] or self.moves[3] or self.moves[1]) and pottedRaw and
              (not (mcontroller.liquidMovement() or math.__gliderActive or avosiJetpack or avosiWings or avosiWingedArms or avosiFlight or self.collision)) then
                mcontroller.controlModifiers({movementSuppressed = true})
            end
        end

        local pottedClimbing = (potted or largePotted) and self.collision and
                                 (not (lounging or mcontroller.groundMovement() or mcontroller.liquidMovement() or activeMovementAbilities))

        local largePottedOnGround = largePotted and mcontroller.groundMovement()

        if largePottedOnGround then
            local notUsingThrusters = not (avosiJetpack or ((garyTech or fezTech or upgradedThrusters) and self.thrustersActive) or
                                        (avosiWingedArms or (avosiFlight and checkDistRaw == -2)) or math.__gliderActive)
            local standingPoly = mcontroller.baseParameters().standingPoly
            local crouchingPoly = mcontroller.baseParameters().crouchingPoly
            if charScale and charScale ~= 1 then
                standingPoly = poly.scale(standingPoly, charScale)
                crouchingPoly = poly.scale(crouchingPoly, charScale)
            end
            smallColBox = (sb.printJson(mcontroller.collisionPoly()) == sb.printJson(standingPoly) or sb.printJson(mcontroller.collisionPoly()) ==
                            sb.printJson(crouchingPoly))
            if (self.moves[1]) and (not (mcontroller.liquidMovement() or self.collision)) and notUsingThrusters and smallColBox then
                mcontroller.controlModifiers({movementSuppressed = true})
            end
        end

        if tech then
            local aXVel = math.abs(mcontroller.xVelocity())
            if xsb and player.setOverrideState then
                if bouncyOnGround then
                    player.setOverrideState((bouncyCrouch and (self.moves[5] or self.crouching)) and "duck" or (aXVel > 1.5 and "idle" or "idle"))
                elseif largePottedOnGround then
                    player.setOverrideState("idle")
                elseif pottedClimbing then
                    player.setOverrideState("swimIdle")
                elseif (not (bouncyOnGround or pottedClimbing or largePottedOnGround)) and self.lastPoseOverriding then
                    player.setOverrideState()
                end
            else
                if bouncyOnGround then
                    tech.setParentState((bouncyCrouch and (self.moves[5] or self.crouching)) and "Duck" or (aXVel > 1.5 and "Stand" or "Stand")) -- "Walk" or "Stand"
                elseif largePottedOnGround then
                    tech.setParentState("Stand")
                elseif pottedClimbing then
                    tech.setParentState("Fall")
                elseif (not (bouncyOnGround or pottedClimbing or largePottedOnGround)) and self.lastPoseOverriding then
                    tech.setParentState()
                end
            end
        end

        self.lastPoseOverriding = bouncyOnGround or pottedClimbing or largePottedOnGround

        math.__rpJumping = self.collisionTimer ~= 0

        math.__doSkateSound = false

        if thermalSoaring and not (mcontroller.groundMovement() or mcontroller.liquidMovement()) then
            local thermalParams = {gravityMultiplier = 0.1 * gravityModifier}
            mcontroller.controlParameters(thermalParams)
            mcontroller.controlAcceleration({0, 10})
        end

        if math.__grappled and (avosiWings or avosiFlight or avosiWingedArms or swimmingFlight) and
          not (mcontroller.groundMovement() or mcontroller.liquidMovement() or lounging or windTileOcc) then
            local wind = world.windLevel(mcontroller.position())
            local windAbs = math.abs(wind)
            local thermalParams = {gravityMultiplier = 0.3 * gravityModifier}
            mcontroller.controlParameters(thermalParams)
            local kiting = vec2.mag(mcontroller.velocity()) <= 10 and not (self.moves[1] or self.moves[4])
            if tonumber(math.__grappled) <= 1 then
                local maxUp = world.gravity(mPos) * 0.3
                mcontroller.controlAcceleration({wind / 20, kiting and 0 or math.min(maxUp, (1 + windAbs / 5))})
            end
            if kiting then mcontroller.controlApproachVelocity({0, 0}, 25 + windAbs / 5) end
        end

        -- if shadowRun and self.shadowFlight and mcontroller.liquidMovement() then
        --     local swimParams = {liquidImpedance = 0, liquidForce = 25, liquidFriction = 0}
        --     if not mcontroller.groundMovement() then
        --         swimParams.walkSpeed = 15
        --         swimParams.runSpeed = 45
        --     end
        --     mcontroller.controlParameters(swimParams)
        -- end

        if (skates or fezTech) and self.isSkating and (not (math.__sphereActive or lounging)) then
            if tech then
                if mcontroller.groundMovement() and not mcontroller.liquidMovement() then
                    local skatingParameters = (not skates) and {walkSpeed = 15, runSpeed = 60} or
                                                {walkSpeed = 10, runSpeed = 25, normalGroundFriction = 1, slopeSlidingFactor = 0.6}
                    if skates then
                        if xsb and player.setOverrideState then
                            player.setOverrideState((self.moves[5] or self.crouching) and "duck" or (self.moves[2] or self.moves[3]) and "walk" or "idle")
                        else
                            tech.setParentState((self.moves[5] or self.crouching) and "Duck" or (self.moves[2] or self.moves[3]) and "Walk" or "Stand")
                        end
                    end
                    if math.abs(mcontroller.xVelocity()) >= 2 then math.__doSkateSound = true end
                    mcontroller.controlParameters(skatingParameters)
                end
            else
                self.isSkating = false
            end
        else
            self.isSkating = false
        end

        local isSitting = self.isSitting or (mcontroller.groundMovement() and (smallColBox or largePotted) and
                            (mertail or ((potted or largePotted) and (self.moves[2] or self.moves[3]) and (not gettingOverIt))))
        local isOffset = (isSitting and ((self.crouching and self.isSitting) or largePotted)) or math.__upsideDown
        if xsb and player.setOverrideState then
            if isSitting then
                if (not self.isSitting) and (self.moves[2] or self.moves[3]) then
                    player.setOverrideState("swim")
                else
                    if (mcontroller.crouching() or self.moves[5] or self.crouching) and not self.isSitting then
                        mcontroller.controlCrouch()
                        player.setOverrideState("duck")
                    else
                        player.setOverrideState("sit")
                    end
                end
            else
                if self.lastIsSitting ~= isSitting then player.setOverrideState() end
            end
            if tech and isOffset then
                if math.__upsideDown then
                    tech.setParentOffset({0, -1.275 * charScale})
                else
                    local potFlopping = isFlopping and largePotted
                    tech.setParentOffset({0, (potFlopping and -0.3 or -1) * charScale})
                end
            elseif tech then
                if self.lastIsOffset ~= isOffset then tech.setParentOffset({0, 0}) end
            end
        elseif tech then
            if isSitting then
                if (not self.isSitting) and (self.moves[2] or self.moves[3]) then
                    tech.setToolUsageSuppressed(true)
                    tech.setParentState("Swim")
                else
                    tech.setToolUsageSuppressed()
                    if (mcontroller.crouching() or self.moves[5] or self.crouching) and not self.isSitting then
                        mcontroller.controlCrouch()
                        tech.setParentState("Duck")
                    else
                        tech.setParentState("Sit")
                    end
                end
            else
                if self.lastIsSitting ~= isSitting then
                    tech.setToolUsageSuppressed()
                    tech.setParentState()
                end
            end
            if isOffset then
                if math.__upsideDown then
                    tech.setParentOffset({0, -1.275 * charScale})
                else
                    local potFlopping = isFlopping and largePotted
                    tech.setParentOffset({0, (potFlopping and -0.3 or -1) * charScale})
                end
            else
                if self.lastIsOffset ~= isOffset then tech.setParentOffset({0, 0}) end
            end
        end

        self.lastIsSitting = isSitting
        self.lastIsOffset = isOffset

        self.lastIsLame = isLame

        math.__isGlider = nil
        math.__firingGrapple = nil
        math.__weaponFiring = nil
        math.__canGrabWall = nil

        status.setStatusProperty("isRunBoosting", self.isRunBoosting)
        status.setStatusProperty("shadowFlight", self.shadowFlight)
        status.setStatusProperty("thrustersActive", self.thrustersActive)
        status.setStatusProperty("runningMode", self.running)
    end
end

function renoUninit()
    if status.statusProperty("ignoreFezzedTech") then
        math.__fezzedTechLoaded = true
    else
        math.__fezzedTechLoaded = false
    end
    status.clearPersistentEffects("rpTech")
end

attachHook("init", renoInit)
attachHook("update", renoUpdate)
attachHook("uninit", renoUninit)

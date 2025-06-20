require("/scripts/util/hook.lua")
require("/scripts/vec2.lua")
require("/scripts/poly.lua")
require("/tech/doubletap.lua")

-- function checkMovement() return world.sendEntityMessage(entity.id(), "checkJumping"):result() end

local function shortAngleDist(a0, a1)
    local max = math.pi * 2
    local da = (a1 - a0) % max
    return 2 * da % max - da
end

local function angleLerp(a0, a1, t, m)
    local d = shortAngleDist(a0, a1)
    if (math.abs(d * t) > (m or 0)) or (math.abs(d * t) > (2 * math.pi + (m or 0))) then
        return a0 + d * t
    else
        return a1 -- a0 + d
    end
end

local function floatVectorEq(a, b) return math.abs(a[1] - b[1]) <= 0.001 and math.abs(a[2] - b[2]) <= 0.001 end

local function polyEqual(poly1, poly2)
    if #poly1 ~= #poly2 then return false end
    for n = 1, #poly1 do
        if not floatVectorEq(poly1[n], poly2[n]) then return false end
    end
    return true
end

local function log10(x) return math.log(x) / math.log(10) end

local function distToPenalty(distance)
    if distance > 2 then
        local magnitude = log10(distance / 2)
        local penalty = math.floor((magnitude * -6) + 1)
        return penalty
    else
        return 0
    end
end

local function getClosestBlockYDistance(lineStart, lineEnd, ignorePlatforms)
    local yDistance = false

    if lineEnd then
        local collisionSet = { "Null", "Block", "Dynamic", "Platform" }
        if ignorePlatforms then collisionSet = { "Null", "Block", "Dynamic", "Slippery" } end
        local blocks = world.collisionBlocksAlongLine(lineStart, lineEnd, collisionSet)
        if #blocks > 0 then yDistance = lineStart[2] - (blocks[1][2] + 1) end
    end

    return yDistance
end

local function backgroundExists(position, ignoreObjects, ignoreForeground)
    local tilePos = { math.floor(position[1] + 0.5), math.floor(position[2] + 0.5) }
    local tileOccupied = world.tileIsOccupied(tilePos, false, false)
        or ((not ignoreForeground) and world.tileIsOccupied(tilePos, true, false))
        or ((not ignoreObjects) and world.objectAt(tilePos))
    return tileOccupied
end

local function parentLounging() return world.sendEntityMessage(entity.id(), "techParentLounging"):result() end

local function aimPosition() return world.sendEntityMessage(entity.id(), "techAimPosition"):result() end

local function setParentDirectives(directives) world.sendEntityMessage(entity.id(), "setParentDirectives", directives) end

local function setParentState(state) world.sendEntityMessage(entity.id(), "setParentState", state) end

local function setParentOffset(offset) world.sendEntityMessage(entity.id(), "setParentOffset", offset) end

local function setToolUsageSuppressed(suppressed)
    world.sendEntityMessage(entity.id(), "setToolUsageSuppressed", suppressed)
end

function renoInit()
    require("/scripts/util/globals.lua")
    -- Communicate the presence of FezzedTech to other mods and allow a way to disable it in scripts.
    if status.statusProperty("ignoreFezzedTech") then
        globals.fezzedTechLoaded = true
    else
        globals.fezzedTechLoaded = false
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
    self.moves = { false, false, false, false, false, false, true, false }
    self.oldJump = false
    self.oldShift = false
    self.lastCrouching = false
    self.lastSkating = false

    self.phantomGlider = root.assetJson("/items/phantomGlider.config")
    self.invisibleFlyer = root.assetJson("/items/invisibleFlyer.config")
    self.phantomSoarGlider = root.assetJson("/items/phantomSoarGlider.config")
    self.phantomThruster = root.assetJson("/items/phantomThrusters.config")
    self.phantomGravShield = root.assetJson("/items/phantomGravShield.config")
    self.flyboard = root.assetJson("/projectiles/flyboard.config")
    self.phantomGliderBaseDirs =
        self.phantomGlider.parameters.animationCustom.animatedParts.parts.swoosh.partStates.swoosh.flip.properties.image
    self.flyboardBaseDirs = self.flyboard.processing
    self.defaultParagliderDirs =
        "?replace;e0975c=29332b;f32200=232b2b;6f2919=141915;951500=111515;dc1f00=1f2828;ffca8a=333f35;be1b00=1a2020;a85636=1e2620;735e3a=273131"
    self.baseColBox = {
        standingPoly = mcontroller.baseParameters().standingPoly,
        crouchingPoly = mcontroller.baseParameters().crouchingPoly,
    }
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

    self.switchDirTap = DoubleTap:new({ 6 }, 0.25, function(tapKey) self.tapKeyDir = true end)

    self.skatingTap = DoubleTap:new({ 2, 3 }, 0.25, function(tapKey)
        if self.moves[7] then
            self.running = not self.running
        else
            self.isSkating = not self.isSkating
        end
    end)

    self.runningTap = DoubleTap:new({ 2, 3 }, 0.25, function(tapKey) self.running = not self.running end)

    self.parawingTap = DoubleTap:new({ 4 }, 0.25, function(tapKey)
        if globals.shadowRun then
            self.shadowFlight = not self.shadowFlight
        else
            if
                (globals.fezTech or globals.garyTech or globals.upgradedThrusters)
                and globals.isGlider
                and not (mcontroller.groundMovement() or mcontroller.liquidMovement())
            then
                self.hovering = not self.hovering
            else
                if globals.isGlider and not globals.garyTech then
                    globals.gliderActive = false
                    self.fallDanger = false
                    self.useParawing = false
                else
                    if not (mcontroller.liquidMovement() or globals.shadowRun) then
                        if
                            (self.moves[7] or globals.garyTech)
                            and (mcontroller.groundMovement())
                            and globals.parkourThrusters
                        then
                            self.isRunBoosting = not self.isRunBoosting
                        else
                            self.useParawing = true
                        end
                    end
                end
            end
        end
    end)

    self.crouchingTap = DoubleTap:new({ 5 }, 0.25, function(tapKey)
        if self.moves[7] and (self.parkourThrusters or globals.shadowRun) then
            self.thrustersActive = not self.thrustersActive
        else
            if mcontroller.groundMovement() then self.crouching = not self.crouching end
        end
    end)

    self.flyboardTap = DoubleTap:new(
        { 8 },
        0.25,
        function(tapKey) globals.flyboardActive = not globals.flyboardActive end
    )

    self.isFalling = false
    self.lastSwimming = false
    self.lastAvosiFlying = false

    self.lastFlightTime = 0

    self.oldCharScale = 1

    self.isSitting = false
    self.lastIsSitting = false
    self.lastIsOffset = false

    self.lastIsLame = false

    self.nightVision = false

    globals.gliderActive = false
    globals.doThrusterAnims = false
    globals.jumpDisabled = true
    globals.paramotor = false
    globals.wingFlap = false
    globals.doSkateSound = false
    globals.parkourThrusters = false
    globals.noLegs = false
    globals.fezTech = false
    globals.garyTech = false
    globals.resetJumps = false
    globals.upgradedThrusters = false
    globals.flyboardActive = false
    globals.rpMovement = false
    globals.canGrabWall = false
    globals.bouncy = false
    globals.avosiWings = false

    if status.statusProperty("roleplayMode") and (not status.statusProperty("ignoreFezzedTech")) then
        local rpStatusEffects = {
            { effectiveMultiplier = 0, stat = "fallDamageMultiplier" },
            { stat = "breathProtection", amount = 1 },
            { stat = "biomeradiationImmunity", amount = 1 },
            { stat = "biomecoldImmunity", amount = 1 },
            { stat = "biomeheatImmunity", amount = 1 },
        }
        status.setPersistentEffects("rpTech", rpStatusEffects)
    else
        status.clearPersistentEffects("rpTech")
    end

    self.firstTick = true

    status.clearPersistentEffects("movementAbility")
end

function renoUpdate(dt)
    if self.firstTick then
        if xsb then
            world.setLightMultiplier()
            world.resetShaderParameters()
        end
        self.firstTick = false
    end

    if (xsb and not player) or status.statusProperty("ignoreFezzedTech") then -- An FU status script sets `player` to `nil` for no good reason.
        globals.fezzedTechLoaded = false

        if not status.statusProperty("ignoreFezzedTechAppearance") then
            -- Check only the appearance-affecting stats.
            local opTailStat = status.statPositive("opTail") or status.statusProperty("opTail")
            local ghostTailStat = status.statPositive("ghostTail") or status.statusProperty("ghostTail")
            local bouncyRaw = status.statPositive("bouncy") or status.statPositive("bouncy2")
            local largePotted = status.statPositive("largePotted") or status.statusProperty("largePotted")
            local scarecrowPole = status.statPositive("scarecrowPole")
                or status.statusProperty("scarecrowPole")
                or ((not globals.isParkourTech) and (opTailStat or ghostTailStat))
                or bouncyRaw
                or largePotted
            local grandfatheredLeglessChar = status.statPositive("leglessSmallColBox")
                or status.statusProperty("leglessSmallColBox")
            local isLeglessCharRaw = grandfatheredLeglessChar or (status.statPositive("legless") and (input or xsb))
            local isLeglessChar = isLeglessCharRaw
                and not (status.statPositive("legged") or status.statusProperty("legged"))
            local leglessSmallColBox = isLeglessChar and not scarecrowPole
            local tailed = status.statPositive("noLegs") or status.statusProperty("noLegs")
            local pottedRaw = status.statPositive("potted") or status.statusProperty("potted")
            local gettingOverIt = status.statPositive("gettingOverIt") or status.statusProperty("gettingOverIt")
            local potted = (pottedRaw or gettingOverIt) and not bouncyRaw
            local mertail = status.statPositive("mertail") or status.statusProperty("mertail")
            local noLegs = leglessSmallColBox or tailed or potted or mertail

            status.setStatusProperty("legless", (noLegs or scarecrowPole) and not grandfatheredLeglessChar)
        end
    else
        player = player or {}

        if xsb and player.setOverrideState then player.setOverrideState() end

        local mPos = mcontroller.position()

        globals.fezzedTechLoaded = true

        local tech = nil
        if not tech then tech = globals.tech end

        if mcontroller.onGround() then status.setStatusProperty("ballisticVelocity", { 0, -4 }) end

        local moveMessage = world.sendEntityMessage(entity.id(), "checkJumping")

        if moveMessage:succeeded() then
            self.moves = moveMessage:result()
            self.moves[8] = not self.moves[7]
        else
            self.moves = { false, false, false, false, false, false, true, false }
        end

        local fezzedTechVars = {}
        fezzedTechVars.isLegged = status.statPositive("legged") or status.statusProperty("legged")
        fezzedTechVars.highGrav = world.gravity(mcontroller.position()) >= 30
        fezzedTechVars.flightEnabled = (status.statPositive("flightEnabled")) and globals.isParkourTech
        fezzedTechVars.opTailStat = status.statPositive("opTail") or status.statusProperty("opTail")
        fezzedTechVars.opTail = fezzedTechVars.opTailStat and globals.isParkourTech
        fezzedTechVars.ghostTailStat = status.statPositive("ghostTail") or status.statusProperty("ghostTail")
        fezzedTechVars.ghostTailHoverDist = status.stat("ghostTail") >= 2.0 and status.stat("ghostTail") or 2.0
        fezzedTechVars.ghostTail = fezzedTechVars.ghostTailStat and globals.isParkourTech
        fezzedTechVars.bouncyCrouch = status.statPositive("bouncy2")
        fezzedTechVars.bouncyRaw = status.statPositive("bouncy") or fezzedTechVars.bouncyCrouch
        fezzedTechVars.bouncy = fezzedTechVars.bouncyRaw -- and globals.isParkourTech
        fezzedTechVars.largePotted = status.statPositive("largePotted") or status.statusProperty("largePotted")
        fezzedTechVars.scarecrowPoleRaw = status.statPositive("scarecrowPole") or status.statusProperty("scarecrowPole")
        fezzedTechVars.scarecrowPole = fezzedTechVars.scarecrowPoleRaw
            or ((not globals.isParkourTech) and (fezzedTechVars.opTailStat or fezzedTechVars.ghostTailStat))
            or fezzedTechVars.bouncyRaw
            or fezzedTechVars.largePotted
        fezzedTechVars.fireworks = (status.statPositive("fireworks") or status.statusProperty("fireworks"))
            and globals.isParkourTech
        fezzedTechVars.swimmingFlight = (
            status.statPositive("swimmingFlight") or status.statusProperty("swimmingFlight")
        ) and globals.isParkourTech
        fezzedTechVars.soarHop = (
            fezzedTechVars.opTail
            or status.statPositive("soarHop")
            or status.statusProperty("soarHop")
        ) and globals.isParkourTech
        fezzedTechVars.canHop = fezzedTechVars.soarHop
            or (fezzedTechVars.fireworks and status.statusProperty("legless") and not fezzedTechVars.isLegged)
            or status.statPositive("canHop")
            or status.statusProperty("canHop")
        fezzedTechVars.tailed = status.statPositive("noLegs") or status.statusProperty("noLegs")
        fezzedTechVars.roleplayMode = status.statusProperty("roleplayMode")
        fezzedTechVars.pottedRaw = status.statPositive("potted") or status.statusProperty("potted")
        fezzedTechVars.gettingOverIt = status.statPositive("gettingOverIt") or status.statusProperty("gettingOverIt")
        fezzedTechVars.potted = (fezzedTechVars.pottedRaw or fezzedTechVars.gettingOverIt) and not fezzedTechVars.bouncy
        fezzedTechVars.rawItemL = world.entityHandItem(entity.id(), "primary")
        fezzedTechVars.rawItemR = world.entityHandItem(entity.id(), "alt")
        local itemL = fezzedTechVars.rawItemL and not globals.canFlyWithItem
        local itemR = fezzedTechVars.rawItemR and not globals.canFlyWithItem
        fezzedTechVars.shadowRun = (status.statPositive("shadowRun") or status.statusProperty("shadowRun"))
            and globals.isParkourTech
        fezzedTechVars.mertail = status.statPositive("mertail") or status.statusProperty("mertail")
        fezzedTechVars.fastSwimming = (status.statPositive("fastSwimming") or status.statusProperty("fastSwimming")) -- or fezzedTechVars.mertail
        fezzedTechVars.hasSwimTail = fezzedTechVars.scarecrowPole
            or fezzedTechVars.soarHop
            or fezzedTechVars.shadowRun
            or fezzedTechVars.fastSwimming
        fezzedTechVars.swimTail = fezzedTechVars.hasSwimTail and mcontroller.liquidMovement()
        fezzedTechVars.avosiWingedArms = (
            status.statPositive("avosiWingedArms") or status.statusProperty("avosiWingedArms")
        ) and globals.isParkourTech
        fezzedTechVars.avosiWings = (status.statPositive("avosiWings") or status.statusProperty("avosiWings"))
            and globals.isParkourTech
        fezzedTechVars.avolitePack = (status.statPositive("avolitePack") or status.statusProperty("avolitePack"))
            and globals.isParkourTech
        fezzedTechVars.rawAvosiJetpack = (
            status.statPositive("avosiJetpack")
            or status.statusProperty("avosiJetpack")
            or fezzedTechVars.avolitePack
        ) and globals.isParkourTech
        fezzedTechVars.rawAvosiFlight = (status.statPositive("avosiFlight") or status.statusProperty("avosiFlight"))
            and globals.isParkourTech
        fezzedTechVars.avosiFlight = fezzedTechVars.rawAvosiFlight
            or (fezzedTechVars.avosiWingedArms and not (itemL or itemR))
        fezzedTechVars.grandfatheredLeglessChar = status.statPositive("leglessSmallColBox")
            or status.statusProperty("leglessSmallColBox")
        fezzedTechVars.isLeglessCharRaw = fezzedTechVars.grandfatheredLeglessChar
            or (status.statPositive("legless") and not not (input or xsb))
        fezzedTechVars.isLeglessChar = fezzedTechVars.isLeglessCharRaw
            and not (status.statPositive("legged") or status.statusProperty("legged"))
        fezzedTechVars.leglessSmallColBox = fezzedTechVars.isLeglessChar and not fezzedTechVars.scarecrowPole
        fezzedTechVars.noLegs = fezzedTechVars.leglessSmallColBox
            or fezzedTechVars.tailed
            or fezzedTechVars.potted
            or fezzedTechVars.mertail -- or fezzedTechVars.scarecrowPole
        fezzedTechVars.paramotor = (
            (status.statPositive("paramotor") or status.statusProperty("paramotor")) and fezzedTechVars.highGrav
        ) and globals.isParkourTech
        fezzedTechVars.basicParkour = (status.statPositive("basicParkour") or status.statusProperty("basicParkour"))
            and globals.isParkourTech
        fezzedTechVars.parkourRaw = (status.statPositive("parkour") or status.statusProperty("parkour"))
            and globals.isParkourTech
        fezzedTechVars.parkour = fezzedTechVars.parkourRaw or fezzedTechVars.basicParkour
        fezzedTechVars.paragliderPack = (
            status.statPositive("paragliderPack") or status.statusProperty("paragliderPack")
        )
        fezzedTechVars.invisibleFlyer = (
            status.statPositive("invisibleFlyer") or status.statusProperty("invisibleFlyer")
        )
        fezzedTechVars.parkourThrustersStat = (
            (status.statPositive("parkourThrusters") or status.statusProperty("parkourThrusters"))
            and fezzedTechVars.highGrav
        ) and globals.isParkourTech
        self.parkourThrusters = fezzedTechVars.parkourThrustersStat
        fezzedTechVars.parkourThrusters = fezzedTechVars.parkourThrustersStat
            and self.thrustersActive
            and self.moves[7]
            and not (self.moves[5] and self.moves[6])
        fezzedTechVars.nightVision = (status.statPositive("nightVision") or status.statusProperty("nightVision"))
        fezzedTechVars.darkNightVision = (
            status.statPositive("darkNightVision") or status.statusProperty("darkNightVision")
        )
        fezzedTechVars.shadowVision = (status.statPositive("shadowVision") or status.statusProperty("shadowVision"))
        fezzedTechVars.skates = (status.statPositive("skates") or status.statusProperty("skates"))
            and globals.isParkourTech
        fezzedTechVars.fezTech = (status.statPositive("fezTech") or status.statusProperty("fezTech"))
            and globals.isParkourTech
        fezzedTechVars.garyTech = (status.statPositive("garyTech") or status.statusProperty("garyTech"))
            and globals.isParkourTech
            and (fezzedTechVars.noLegs or fezzedTechVars.leglessSmallColBox)
        fezzedTechVars.upgradedThrusters = (
            status.statPositive("upgradedThrusters") or status.statusProperty("upgradedThrusters")
        ) and globals.isParkourTech
        fezzedTechVars.flyboard = (status.statPositive("flyboard") or status.statusProperty("flyboard"))
            and globals.isParkourTech
        fezzedTechVars.avosiGlider = (status.statPositive("avosiGlider") or status.statusProperty("avosiGlider"))
        fezzedTechVars.tailless = (
            ((status.statPositive("legged") or status.statusProperty("legged")) and fezzedTechVars.isLeglessCharRaw)
            or (status.statPositive("tailless") or status.statusProperty("tailless"))
        ) and globals.isParkourTech
        fezzedTechVars.runSpeedMult = status.stat("runSpeedAdder") + 1
        fezzedTechVars.checkDist = status.stat("checkGroundDist")
        fezzedTechVars.jumpSpeedMult = status.stat("jumpAdder") + (fezzedTechVars.bouncy and 1.5 or 1)
        fezzedTechVars.safetyFlight = status.statPositive("safetyFlight")
        local flightTime = (globals.isParkourTech and status.stat("flightTime")) or 0
        fezzedTechVars.slowRecharge = status.statPositive("slowRecharge") and globals.isParkourTech
        fezzedTechVars.isLame = status.statPositive("isLame")
        local activeMovementAbilities = status.statPositive("activeMovementAbilities")
        fezzedTechVars.charScale = status.stat("charHeight") ~= 0 and (status.stat("charHeight") / 187.5)
            or (
                status.stat("bodysize") ~= 0 and status.stat("bodysize")
                or (type(globals.scale == "number") and globals.scale or 1.0)
            )
        fezzedTechVars.rulerEnabled = status.statusProperty("roleplayRuler")
        fezzedTechVars.windSailing = status.statPositive("windSail") or status.statusProperty("windSail")
        fezzedTechVars.gravityModifier = globals.isParkourTech and (status.stat("gravityModifier") + 1) or 1
        fezzedTechVars.collisionMatch = false

        local scarecrowWalking = not fezzedTechVars.scarecrowPoleRaw

        if not tech then fezzedTechVars.charScale = 1 end

        fezzedTechVars.legless = (fezzedTechVars.noLegs or fezzedTechVars.scarecrowPole)
            or (fezzedTechVars.grandfatheredLeglessChar and not fezzedTechVars.isLegged)
        status.setStatusProperty(
            "legless",
            (fezzedTechVars.noLegs or fezzedTechVars.scarecrowPole) and not fezzedTechVars.grandfatheredLeglessChar
        )

        if fezzedTechVars.legless and mcontroller.groundMovement() and xsb and player.setOverrideState then
            player.setOverrideState((self.moves[5] or self.crouching) and "duck" or "idle")
        end

        if fezzedTechVars.gravityModifier ~= 1 then
            local baseGravMult = mcontroller.baseParameters().gravityMultiplier
            mcontroller.controlParameters({ gravityMultiplier = baseGravMult * fezzedTechVars.gravityModifier })
        end

        local defaultColBoxParams = {}

        if globals.isParkourTech and (fezzedTechVars.charScale ~= 1) then
            local defStandingPoly = {
                { -0.75, -2.0 },
                { -0.35, -2.5 },
                { 0.35, -2.5 },
                { 0.75, -2.0 },
                { 0.75, 0.65 },
                { 0.35, 1.22 },
                { -0.35, 1.22 },
                { -0.75, 0.65 },
            }
            local defCrouchingPoly = {
                { -0.75, -2.0 },
                { -0.35, -2.5 },
                { 0.35, -2.5 },
                { 0.75, -2.0 },
                { 0.75, -1.0 },
                { 0.35, -0.5 },
                { -0.35, -0.5 },
                { -0.75, -1.0 },
            }
            defaultColBoxParams.standingPoly = poly.scale(defStandingPoly, fezzedTechVars.charScale)
            defaultColBoxParams.crouchingPoly = poly.scale(defCrouchingPoly, fezzedTechVars.charScale)
            mcontroller.controlParameters(defaultColBoxParams)
        end

        if globals.isParkourTech and tech then
            if self.oldCharScale ~= fezzedTechVars.charScale then
                if fezzedTechVars.charScale ~= 1 then
                    globals.characterScale = fezzedTechVars.charScale or 1
                else
                    globals.characterScale = 1
                end
            end
        end

        if not (starExtensions or xsb) then status.setStatusProperty("roleplayRuler", nil) end

        if input then -- Check if xClient, OpenStarbound or StarExtensions is loaded.
            if xsb and (player.uniqueId() ~= world.primaryPlayerUuid()) then
                -- On xClient, only pass binds to the primary player.
                goto skipBinds
            end
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
                -- The ruler tooltip requires xClient or StarExtensions.
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
            ::skipBinds::
        end

        if status.statusProperty("roleplayMode") then
            local rpStatusEffects = {
                { effectiveMultiplier = 0, stat = "fallDamageMultiplier" },
                { stat = "breathProtection", amount = 1 },
                { stat = "biomeradiationImmunity", amount = 1 },
                { stat = "biomecoldImmunity", amount = 1 },
                { stat = "biomeheatImmunity", amount = 1 },
            }
            status.setPersistentEffects("rpTech", rpStatusEffects)
        else
            status.clearPersistentEffects("rpTech")
        end

        if interface and fezzedTechVars.rulerEnabled and (starExtensions or xsb) then
            local vars = {}
            vars.pP = mcontroller.position()
            vars.aP = player.aimPosition and player.aimPosition() or aimPosition()
            vars.dist = world.distance(vars.pP, vars.aP)
            vars.distMag = math.sqrt(vars.dist[1] ^ 2 + vars.dist[2] ^ 2) / 2
            vars.roundedDist = math.floor(vars.distMag + 0.5)
            if vars.distMag < 10 then vars.roundedDist = math.floor(vars.distMag * 2 + 0.5) / 2 end
            vars.roundedDistStr = tostring(vars.roundedDist)
            if vars.roundedDistStr == "0.0" then vars.roundedDistStr = "0" end
            if vars.roundedDistStr == "10.0" then vars.roundedDistStr = "10" end
            vars.footDist = vars.distMag / 0.3
            vars.roundedFootDist = math.floor(vars.footDist + 0.5)
            vars.roundedFootDistStr = tostring(vars.roundedFootDist)
            vars.distPenalty = distToPenalty(vars.roundedDist)
            vars.distPenaltyStr = tostring(vars.distPenalty)
            -- interface.setCursorText(tostring(roundedDist) .. " m")
            -- interface.setCursorText(tostring(roundedDist) .. " m / " .. roundedFootDistStr .. " ft")
            local rulerText = "^font=iosevka-semibold;"
                .. vars.roundedDistStr
                .. "^font=iosevka-extralight;m/^font=iosevka-semibold;"
                .. vars.roundedFootDistStr
                .. "^font=iosevka-extralight;ft ^gray;(^font=iosevka-semibold;"
                .. vars.distPenaltyStr
                .. "^font=iosevka-extralight;)"
            if starExtensions then
                rulerText = "^yellow;"
                    .. vars.roundedDistStr
                    .. "m^reset;/^orange;"
                    .. vars.roundedFootDistStr
                    .. "'^reset; (^cyan;"
                    .. vars.distPenaltyStr
                    .. "^reset;)"
            end
            interface.setCursorText(rulerText)
        end

        if not tech then self.isSitting = false end

        if self.isSitting then mcontroller.controlApproachVelocity({ 0, 0 }, 1000000, true, true) end

        local lounging = (parentLounging())
            or (player.isLounging and player.isLounging())
            or self.isSitting
            or globals.sitting
            or globals.isSitting

        self.oldCharScale = fezzedTechVars.charScale

        fezzedTechVars.jumpSpeedMult = fezzedTechVars.scarecrowPole and fezzedTechVars.jumpSpeedMult
            or math.min(1.3, fezzedTechVars.jumpSpeedMult)

        fezzedTechVars.liqCheckPos = { math.floor(mPos[1] + 0.5), math.floor(mPos[2] - 2) }
        fezzedTechVars.liqCheckPosDown = { math.floor(mPos[1] + 0.5), math.floor(mPos[2] - 3) }
        fezzedTechVars.liqCheckPosUp = { math.floor(mPos[1] + 0.5), math.floor(mPos[2] - 1) }
        local inLiquid = world.liquidAt(fezzedTechVars.liqCheckPosDown)

        globals.jumpFiring = self.moves[1]

        local usingFlightPack = (
            (self.moves[1] and not (globals.gliderActive and fezzedTechVars.avosiGlider and fezzedTechVars.avolitePack))
            or ((self.moves[2] or self.moves[3]) and self.running and not (globals.gliderActive or fezzedTechVars.rawAvosiFlight))
            or (
                (
                    ((itemL or itemR) and not fezzedTechVars.rawAvosiFlight)
                    or (
                        fezzedTechVars.rawAvosiJetpack
                        and not (fezzedTechVars.avosiWingedArms or fezzedTechVars.rawAvosiFlight)
                    )
                ) and not globals.gliderActive
            )
        )
            and (
                self.moves[7]
                or fezzedTechVars.rawAvosiFlight
                or (fezzedTechVars.avosiWingedArms and not (itemL or itemR))
            )
        local flightPackBoosting = (
            (self.moves[1] and not (globals.gliderActive and fezzedTechVars.avosiGlider and fezzedTechVars.avolitePack))
            or ((self.moves[2] or self.moves[3]) and self.running and not globals.gliderActive)
        )
        -- local flightRecharging = false
        local rechargeRate = 1 / 3
        local timeMult = flightPackBoosting and 1 or (1 / 3)

        if self.lastFlightTime ~= flightTime then
            if flightTime then self.flightTimer = flightTime end
        end

        if flightTime > 0 then
            if
                usingFlightPack
                and not (
                    lounging
                    or globals.onWall
                    or globals.sphereActive
                    or (fezzedTechVars.bouncy and inLiquid)
                    or mcontroller.liquidMovement()
                    or mcontroller.groundMovement()
                )
            then
                self.flightTimer = math.max(self.flightTimer - dt * timeMult, 0)
            else
                if fezzedTechVars.slowRecharge then
                    self.flightTimer = math.min(self.flightTimer + dt * rechargeRate, flightTime)
                elseif
                    globals.onWall
                    or mcontroller.groundMovement()
                    or mcontroller.liquidMovement()
                    or lounging
                    or globals.grappled
                then
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
        fezzedTechVars.avosiJetpack = fezzedTechVars.rawAvosiJetpack and canJetpack

        self.lastFlightTime = flightTime

        if self.tapKeyDir then
            if
                (fezzedTechVars.avosiFlight or fezzedTechVars.avosiWingedArms or globals.gliderActive)
                and not (
                    mcontroller.groundMovement()
                    or mcontroller.liquidMovement()
                    or globals.sphereActive
                    or globals.onWall
                    or lounging
                )
            then
                local xVel = mcontroller.xVelocity()
                mcontroller.setXVelocity(-xVel)
            end
            self.tapKeyDir = false
        end

        -- if interface and rawAvosiJetpack and (flightTime > 0) then
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

        -- local cPos = aimPosition()
        -- local tilePosDebug = {math.floor(cPos[1] + 0.5), math.floor(cPos[2] + 0.5)}
        -- local tileOccupied = world.tileIsOccupied(tilePosDebug, false, false)
        -- if tileOccupied then interface.setCursorText("Tile occupied.") end

        local checkDistRaw = fezzedTechVars.checkDist
        fezzedTechVars.checkDist = self.moves[1] and checkDistRaw or (checkDistRaw <= 0 and 3 or checkDistRaw)
        checkDistRaw = fezzedTechVars.avosiJetpack and -2 or checkDistRaw

        fezzedTechVars.parkour = fezzedTechVars.parkour or fezzedTechVars.fezTech or fezzedTechVars.shadowRun
        fezzedTechVars.paramotor = fezzedTechVars.paramotor
            or fezzedTechVars.fezTech
            or fezzedTechVars.garyTech
            or fezzedTechVars.shadowRun
        fezzedTechVars.paragliderPack = fezzedTechVars.paragliderPack
            or fezzedTechVars.fezTech
            or fezzedTechVars.garyTech
            or fezzedTechVars.shadowRun
        fezzedTechVars.parkourThrusters = fezzedTechVars.parkourThrusters
            or fezzedTechVars.fezTech
            or fezzedTechVars.garyTech
            or (fezzedTechVars.shadowRun and self.thrustersActive)
        fezzedTechVars.parkourThrustersStat = fezzedTechVars.parkourThrustersStat or fezzedTechVars.shadowRun
        fezzedTechVars.potted = fezzedTechVars.potted and not (globals.gliderActive or globals.holdingGlider)

        globals.jumpDisabled = globals.flyboardActive or not fezzedTechVars.parkour
        globals.parkour = fezzedTechVars.parkour
        globals.basicParkour = fezzedTechVars.basicParkour and not fezzedTechVars.parkourRaw
        globals.doThrusterAnims = false
        globals.paramotor = fezzedTechVars.paramotor
        globals.parkourThrusters = fezzedTechVars.parkourThrusters
        globals.noLegs = fezzedTechVars.noLegs
            or fezzedTechVars.leglessSmallColBox
            or fezzedTechVars.scarecrowPole
            or fezzedTechVars.isLame
        globals.fezTech = fezzedTechVars.fezTech or fezzedTechVars.shadowRun
        globals.shadowRun = fezzedTechVars.shadowRun
        globals.garyTech = fezzedTechVars.garyTech
        globals.winged = fezzedTechVars.avosiWings
        globals.runBoost = self.running
        globals.infJumps = status.statPositive("infJumps") or status.statusProperty("infJumps")
        globals.upgradedThrusters = fezzedTechVars.upgradedThrusters
        globals.shadowFlight = self.shadowFlight
        globals.bouncy = fezzedTechVars.bouncy
        globals.avosiWings = fezzedTechVars.avosiWingedArms or fezzedTechVars.avosiJetpack

        if tech then
            local swimming = fezzedTechVars.swimTail and math.abs(vec2.mag(mcontroller.velocity())) > 4 and not lounging
            if swimming then
                if xsb and player.setOverrideState then
                    player.setOverrideState("swim")
                else
                    setParentState("Swim")
                end
            else
                if self.lastSwimming ~= swimming then
                    if not (xsb and player.setOverrideState) then setParentState() end
                end
            end
            self.lastSwimming = swimming
            local avosiFlying = fezzedTechVars.avosiWingedArms
                and not (
                    mcontroller.groundMovement()
                    or mcontroller.liquidMovement()
                    or itemL
                    or itemR
                    or globals.onWall
                    or lounging
                )
            if avosiFlying then
                if xsb and player.setOverrideState then
                    player.setOverrideState("fall")
                else
                    setParentState("Fall")
                end
            else
                if self.lastAvosiFlying ~= avosiFlying then
                    if not (xsb and player.setOverrideState) then setParentState() end
                end
            end
            self.lastAvosiFlying = avosiFlying
        end

        if
            (fezzedTechVars.avosiWingedArms or fezzedTechVars.avosiJetpack)
            and (
                (self.moves[7] and checkDistRaw == -2)
                or ((fezzedTechVars.avosiWingedArms or fezzedTechVars.avosiFlight) and not (itemL or itemR))
            )
        then
            local jetpackParams =
                { gravityMultiplier = (checkDistRaw == -2 and 0.35 or 0.6) * fezzedTechVars.gravityModifier }
            mcontroller.controlParameters(jetpackParams)
            local yVel = mcontroller.yVelocity()
            if yVel <= -25 and not (fezzedTechVars.avosiWingedArms or fezzedTechVars.avosiFlight) then
                mcontroller.controlApproachYVelocity(-25, 150)
            end
        end

        if not (fezzedTechVars.parkourThrustersStat or fezzedTechVars.shadowRun) then self.thrustersActive = false end

        if not fezzedTechVars.shadowRun then self.shadowFlight = false end

        if fezzedTechVars.skates or fezzedTechVars.fezTech then
            self.skatingTap:update(dt, self.moves)
        else
            self.runningTap:update(dt, self.moves)
        end

        if fezzedTechVars.avosiWingedArms or fezzedTechVars.avosiFlight then
            self.switchDirTap:update(dt, self.moves)
        end

        local groundJump = false
        if mcontroller.groundMovement() or mcontroller.liquidMovement() or globals.onWall then
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

            self.isFalling = (self.fallDistance or 0) > minFallDist
                and self.lastYVelocity <= -minFallVel
                and not mcontroller.liquidMovement()

            if mcontroller.yVelocity() < -minFallVel and not mcontroller.onGround() then
                self.fallDistance = (self.fallDistance or 0) + -yPosChange
            else
                self.fallDistance = 0
            end

            self.lastYPosition = curYPosition
            self.lastYVelocity = mcontroller.yVelocity()
        end

        local groundDist

        if fezzedTechVars.checkDist ~= 0 then
            local vars = {}
            vars.x, vars.y = table.unpack(mcontroller.position())
            vars.checkWidth = 1.5
            vars.left1, vars.left2 =
                { vars.x - vars.checkWidth, vars.y }, { vars.x - vars.checkWidth, vars.y - fezzedTechVars.checkDist }
            vars.right1, vars.right2 =
                { vars.x + vars.checkWidth, vars.y }, { vars.x + vars.checkWidth, vars.y - fezzedTechVars.checkDist }
            vars.leftDist = getClosestBlockYDistance(vars.left1, vars.left2, false)
            vars.rightDist = getClosestBlockYDistance(vars.right1, vars.right2, false)
            vars.leftDist = vars.leftDist and vars.leftDist >= 1
            vars.rightDist = vars.rightDist and vars.rightDist >= 1
            groundDist = not not (vars.leftDist or vars.rightDist)
            -- if vars.leftDist and vars.rightDist then
            --     groundDist = (vars.leftDist + vars.rightDist) / 2
            -- else
            --     groundDist = (vars.leftDist or vars.rightDist)
            -- end
        else
            groundDist = true
        end

        local ghostHover

        if fezzedTechVars.ghostTail and fezzedTechVars.ghostTailHoverDist > 2 then
            local vars = {}
            vars.x, vars.y = table.unpack(mcontroller.position())
            vars.checkWidth = 1.5
            vars.left1, vars.left2 =
                { vars.x - vars.checkWidth, vars.y },
                { vars.x - vars.checkWidth, vars.y - fezzedTechVars.ghostTailHoverDist }
            vars.right1, vars.right2 =
                { vars.x + vars.checkWidth, vars.y },
                { vars.x + vars.checkWidth, vars.y - fezzedTechVars.ghostTailHoverDist }
            vars.leftDist = getClosestBlockYDistance(vars.left1, vars.left2, false)
            vars.rightDist = getClosestBlockYDistance(vars.right1, vars.right2, false)
            vars.leftDist = vars.leftDist and vars.leftDist >= 1
            vars.rightDist = vars.rightDist and vars.rightDist >= 1
            ghostHover = not not (vars.leftDist or vars.rightDist)
            -- if vars.leftDist and vars.rightDist then
            --     ghostHover = (vars.leftDist + vars.rightDist) / 2
            -- else
            --     ghostHover = (vars.leftDist or vars.rightDist)
            -- end
        else
            ghostHover = false
        end

        local tileOcc = false
        local windTileOcc = false
        do
            local x, y = table.unpack(mcontroller.position())
            for xAdd = -1, 1, 1 do
                for yAdd = 0, 2, 1 do
                    if backgroundExists({ x + xAdd, y + yAdd }, true, true) then
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
        --     local wallCheckDist = 2.5 * math.max(math.sqrt(fezzedTechVars.jumpSpeedMult), 1)
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

        -- globals.canGrabWall = (not wallGroundDist) or (not self.moves[7]) or (not (noLegs or scarecrowPole))

        -- if globals.gliderActive then
        --     sb.logInfo("Glider active.")
        -- end

        if
            (fezzedTechVars.avosiWingedArms or fezzedTechVars.avosiJetpack)
            and usingFlightPack
            and not (
                mcontroller.zeroG()
                or mcontroller.groundMovement()
                or mcontroller.liquidMovement()
                or (fezzedTechVars.bouncy and inLiquid)
                or globals.sphereActive
                or globals.onWall
                or globals.flyboardActive
                or lounging
            )
        then
            if checkDistRaw == -2 then globals.doThrusterAnims = true end
        end

        if
            (player or globals.player)
            and (fezzedTechVars.paragliderPack or fezzedTechVars.parkourThrusters or fezzedTechVars.invisibleFlyer)
            and not (globals.sphereActive or globals.flyboardActive)
        then
            if not mcontroller.zeroG() then
                -- local player = globals.player
                if fezzedTechVars.paragliderPack then
                    local backItem = player.equippedItem and player.equippedItem("back") or nil

                    if backItem then
                        local paragliderDirsRaw = type(backItem.parameters.paragliderDirectives) == "string"
                                and backItem.parameters.paragliderDirectives
                            or nil
                        local backDirsRaw = type(backItem.parameters.directives) == "string"
                                and backItem.parameters.directives
                            or nil
                        local gravitorDirsRaw = type(backItem.parameters.gravitorDirectives) == "string"
                                and backItem.parameters.gravitorDirectives
                            or nil

                        local paragliderDirs = paragliderDirsRaw or backDirsRaw or self.defaultParagliderDirs
                        self.phantomGlider.parameters.animationCustom.animatedParts.parts.swoosh.partStates.swoosh.flip.properties.image = self.phantomGliderBaseDirs
                            .. paragliderDirs
                        self.phantomSoarGlider.parameters.animationCustom.animatedParts.parts.swoosh.partStates.swoosh.flip.properties.image = self.phantomGliderBaseDirs
                            .. paragliderDirs

                        local gravitorDirs = gravitorDirsRaw or "/assetmissing.png"
                        self.phantomGravShield.parameters.animationCustom.animatedParts.parts.swoosh.partStates.swoosh.flip.properties.image =
                            gravitorDirs
                    else
                        self.phantomGlider.parameters.animationCustom.animatedParts.parts.swoosh.partStates.swoosh.flip.properties.image = self.phantomGliderBaseDirs
                            .. self.defaultParagliderDirs
                        self.phantomSoarGlider.parameters.animationCustom.animatedParts.parts.swoosh.partStates.swoosh.flip.properties.image = self.phantomGliderBaseDirs
                            .. self.defaultParagliderDirs
                        self.phantomGravShield.parameters.animationCustom.animatedParts.parts.swoosh.partStates.swoosh.flip.properties.image =
                            "/assetmissing.png"
                    end
                end

                if fezzedTechVars.noLegs or fezzedTechVars.leglessSmallColBox then
                    local adj = fezzedTechVars.mertail and 0 or -2
                    local cAdj = -2
                    local standingPoly = {
                        { -0.3, -2.0 + 0.875 + (adj / 8) },
                        { -0.08, -2.5 + 0.875 + (adj / 8) },
                        { 0.08, -2.5 + 0.875 + (adj / 8) },
                        { 0.3, -2.0 + 0.875 + (adj / 8) },
                        { 0.75, 0.65 },
                        { 0.35, 1.22 },
                        { -0.35, 1.22 },
                        { -0.75, 0.65 },
                    }
                    local crouchingPoly = {
                        { -0.75, -2.0 + 0.375 + (cAdj / 8) },
                        { -0.35, -2.5 + 0.375 + (cAdj / 8) },
                        { 0.35, -2.5 + 0.375 + (cAdj / 8) },
                        { 0.75, -2.0 + 0.375 + (cAdj / 8) },
                        { 0.75, -1 },
                        { 0.35, -0.5 },
                        { -0.35, -0.5 },
                        { -0.75, -1 },
                    }
                    if fezzedTechVars.charScale and fezzedTechVars.charScale ~= 1 then
                        standingPoly = poly.scale(standingPoly, fezzedTechVars.charScale)
                        crouchingPoly = poly.scale(crouchingPoly, fezzedTechVars.charScale)
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
                    if fezzedTechVars.charScale and fezzedTechVars.charScale ~= 1 then
                        standingPoly = poly.scale(self.baseColBox.standingPoly, fezzedTechVars.charScale)
                        crouchingPoly = poly.scale(self.baseColBox.crouchingPoly, fezzedTechVars.charScale)
                    end
                    self.phantomGlider.parameters.altAbility.flipMovementParameters.standingPoly = standingPoly
                        or self.baseColBox.standingPoly
                    self.phantomGlider.parameters.altAbility.flipMovementParameters.crouchingPoly = crouchingPoly
                        or self.baseColBox.crouchingPoly
                    self.phantomSoarGlider.parameters.altAbility.flipMovementParameters.standingPoly = standingPoly
                        or self.baseColBox.standingPoly
                    self.phantomSoarGlider.parameters.altAbility.flipMovementParameters.crouchingPoly = crouchingPoly
                        or self.baseColBox.crouchingPoly
                    self.phantomThruster.parameters.altAbility.flipMovementParameters.standingPoly = standingPoly
                        or self.baseColBox.standingPoly
                    self.phantomThruster.parameters.altAbility.flipMovementParameters.crouchingPoly = crouchingPoly
                        or self.baseColBox.crouchingPoly
                    self.phantomGravShield.parameters.altAbility.flipMovementParameters.standingPoly = standingPoly
                        or self.baseColBox.standingPoly
                    self.phantomGravShield.parameters.altAbility.flipMovementParameters.crouchingPoly = crouchingPoly
                        or self.baseColBox.crouchingPoly
                end

                if fezzedTechVars.parkourThrusters and (not mcontroller.zeroG()) then
                    if self.moves[7] then
                        if self.moves[1] then
                            local gravMod = mcontroller.baseParameters().gravityMultiplier
                            mcontroller.controlModifiers({
                                gravityMultiplier = (gravMod / 1.75) * fezzedTechVars.gravityModifier,
                            }) -- airJumpModifier = 1.75
                        end
                        if not (mcontroller.groundMovement() or mcontroller.liquidMovement()) then
                            globals.doThrusterAnims = true
                        end
                    end
                    if
                        mcontroller.groundMovement()
                        and (not mcontroller.liquidMovement())
                        and self.isRunBoosting
                        and self.moves[7]
                    then
                        -- mcontroller.controlModifiers({speedModifier = 2.5})
                        if not self.moves[1] then mcontroller.controlModifiers({ airJumpModifier = 0.65 }) end
                        if self.moves[2] or self.moves[3] then mcontroller.controlJump() end
                    end
                    if self.isRunBoosting then
                        if not (mcontroller.groundMovement() or mcontroller.liquidMovement()) then
                            globals.doThrusterAnims = true
                        end
                    end
                end

                if fezzedTechVars.shadowRun and globals.gliderActive then globals.doThrusterAnims = true end

                self.usingItemTimer = math.max(0, self.usingItemTimer - dt)

                if
                    globals.firingGrapple
                    or globals.gliderFiring
                    or globals.weaponFiring
                    or (globals.onWall and self.moves[5])
                then
                    self.usingItemTimer = 0.35
                end

                if
                    self.useParawing
                    and (self.usingItemTimer == 0)
                    and (fezzedTechVars.paragliderPack or fezzedTechVars.invisibleFlyer)
                then
                    local swapItem = player.swapSlotItem and player.swapSlotItem() or nil
                    if not swapItem then
                        globals.gliderActive = true
                        player.setSwapSlotItem(
                            (globals.fezTech and not globals.shadowRun) and self.phantomGravShield
                                or (
                                    (globals.shadowRun or globals.garyTech) and self.phantomGravShield
                                    or (
                                        fezzedTechVars.invisibleFlyer and self.invisibleFlyer
                                        or (fezzedTechVars.avosiGlider and self.phantomSoarGlider or self.phantomGlider)
                                    )
                                )
                        )
                    end
                end

                -- if self.moves[1] and (self.moves[1] ~= self.oldJump) then self.fallDanger = false end
                if (not mcontroller.groundMovement()) and (not mcontroller.liquidMovement()) then
                    local swapItem = player.swapSlotItem and player.swapSlotItem() or nil

                    if
                        (
                            (
                                self.isFalling
                                and not (
                                    (self.moves[5] and (self.moves[6] or not self.moves[7]))
                                    or globals.firingGrapple
                                    or (fezzedTechVars.invisibleFlyer and globals.grappled)
                                )
                            )
                            or (
                                self.moves[1]
                                and self.moves[7]
                                and not (
                                    self.oldJump
                                    or globals.onWall
                                    or (fezzedTechVars.paragliderPack and not fezzedTechVars.parkourThrusters)
                                )
                            )
                        ) and not swapItem
                    then
                        if
                            player.setSwapSlotItem
                            and not (fezzedTechVars.fezTech or fezzedTechVars.garyTech or fezzedTechVars.shadowRun)
                        then
                            player.setSwapSlotItem(
                                fezzedTechVars.parkourThrustersStat and self.phantomThruster
                                    or (
                                        fezzedTechVars.invisibleFlyer and self.invisibleFlyer
                                        or (fezzedTechVars.avosiGlider and self.phantomSoarGlider or self.phantomGlider)
                                    )
                            )
                            self.fallDanger = true
                        end
                    end

                    if
                        player.setSwapSlotItem
                        and (fezzedTechVars.fezTech or fezzedTechVars.garyTech or (self.shadowFlight and not fezzedTechVars.parkourThrusters))
                        and (self.isFalling and not ((self.moves[5] and (self.moves[6] or not self.moves[7])) or globals.firingGrapple))
                        and not swapItem
                    then
                        player.setSwapSlotItem(
                            (globals.shadowRun or globals.garyTech) and self.phantomGravShield or self.phantomGravShield
                        )
                        self.fallDanger = true
                        self.useParawing = true
                    end

                    if
                        player.setSwapSlotItem
                        and (fezzedTechVars.garyTech or self.shadowFlight)
                        and self.moves[1]
                        and (self.running or fezzedTechVars.parkourThrusters)
                        and not (globals.onWall or self.lastJump or mcontroller.jumping() or mcontroller.liquidMovement() or mcontroller.groundMovement())
                        and not swapItem
                    then
                        player.setSwapSlotItem(self.phantomGravShield)
                        self.fallDanger = true
                        self.useParawing = true
                    end

                    self.lastJump = self.moves[1]

                    if
                        fezzedTechVars.parkourThrusters
                        or (fezzedTechVars.parkourThrustersStat and globals.gliderActive and not globals.isGlider)
                            and not (self.moves[5] and (self.moves[6] or not self.moves[7]))
                    then
                        mcontroller.controlParameters({
                            airForce = 250,
                            gravityMultiplier = 0.45 * fezzedTechVars.gravityModifier,
                            airFriction = 3.5,
                        })
                        if mcontroller.yVelocity() <= 0 and not (fezTech or garyTech) then
                            globals.doThrusterAnims = true
                        end
                    end

                    if self.fallDanger and not (fezzedTechVars.fezTech or fezzedTechVars.garyTech) then
                        globals.gliderActive = true
                    end

                    if
                        (
                            globals.onWall
                            and not (
                                (fezzedTechVars.paragliderPack or fezzedTechVars.invisibleFlyer)
                                and not fezzedTechVars.parkourThrusters
                            )
                        )
                        or globals.firingGrapple
                        or globals.gliderFiring
                        or (self.moves[5] and (self.moves[6] or not self.moves[7]))
                    then
                        globals.gliderActive = false
                        self.fallDanger = false
                        self.useParawing = false
                    end

                    if fezzedTechVars.shadowRun and (globals.onWall or not self.shadowFlight) then
                        globals.gliderActive = false
                        self.fallDanger = false
                        self.useParawing = false
                    end

                    if globals.onWall or (self.moves[5] and (self.moves[6] or not self.moves[7])) then
                        globals.doThrusterAnims = false
                    end

                    if globals.gliderActive and (globals.isGlider ~= nil) then
                        if not self.moves[1] then
                            if
                                fezzedTechVars.parkourThrusters
                                and fezzedTechVars.paragliderPack
                                and self.useParawing
                            then
                                globals.doThrusterAnims = false
                            end
                        else
                            if fezzedTechVars.paramotor and self.fallDanger then globals.doThrusterAnims = true end
                        end
                        if self.hovering then
                            if
                                not (self.moves[5] and not self.thrustersActive)
                                and not (fezzedTechVars.fezTech or fezzedTechVars.garyTech)
                            then
                                globals.doThrusterAnims = true
                            end
                        end
                    end

                    if
                        (fezzedTechVars.paramotor or fezzedTechVars.fezTech or fezzedTechVars.garyTech)
                        and not globals.isGlider
                    then
                        globals.doThrusterAnims = false
                    end

                    if
                        (fezzedTechVars.noLegs or fezzedTechVars.leglessSmallColBox)
                        and (fezzedTechVars.parkourThrusters or (fezzedTechVars.paragliderPack and fezzedTechVars.paramotor))
                        and not (
                            globals.onWall
                            or globals.firingGrapple
                            or fezzedTechVars.fezTech
                            or fezzedTechVars.garyTech
                        )
                    then
                        globals.doThrusterAnims = true
                    end

                    if (fezzedTechVars.fezTech or fezzedTechVars.garyTech) and globals.isGlider then
                        globals.doThrusterAnims = true
                    end
                else
                    if not globals.isGlider then
                        self.fallDanger = false
                    else
                        self.fallDanger = true
                    end
                    if globals.firingGrapple or globals.gliderFiring or globals.weaponFiring then
                        globals.gliderActive = false
                    end
                    if globals.isGlider and not (fezzedTechVars.paragliderPack or fezzedTechVars.invisibleFlyer) then
                        globals.gliderActive = false
                    end
                    -- if self.moves[5] then globals.gliderActive = false end
                    if (not globals.isGlider) and not self.useParawing then globals.gliderActive = false end
                    if fezzedTechVars.shadowRun or fezzedTechVars.garyTech or fezzedTechVars.invisibleFlyer then
                        globals.gliderActive = false
                        self.useParawing = false
                        self.fallDanger = false
                    end
                    math.resetJumps = false
                    self.hovering = false
                end

                if fezzedTechVars.paragliderPack or fezzedTechVars.invisibleFlyer then
                    self.parawingTap:update(dt, self.moves)
                end

                -- if math.abs(mcontroller.xVelocity()) <= 2 or (not self.moves[7]) then self.isRunBoosting = false end
                self.oldJump = self.moves[1]
            else
                globals.gliderActive = false
                self.hovering = false
                self.useParawing = false
            end
        end

        if
            not (
                fezzedTechVars.paragliderPack
                or fezzedTechVars.invisibleFlyer
                or fezzedTechVars.parkourThrusters
                or fezzedTechVars.fezTech
                or fezzedTechVars.garyTech
            )
        then
            globals.gliderActive = false
        end

        -- if status.statusProperty("isLegless") and mcontroller.groundMovement() and (not (self.moves[2] or self.moves[3])) and (mcontroller.crouching() ~= self.lastCrouching) then
        --     local yPos = mcontroller.position()[2]
        --     if mcontroller.crouching() then
        --         mcontroller.setYPosition(yPos + 0.625)
        --     else
        --         mcontroller.setYPosition(yPos - 0.625)
        --     end
        -- end
        -- self.lastCrouching = mcontroller.crouching()

        local collisionMatch = false
        local largeCollisionMatch = false
        if fezzedTechVars.largePotted or fezzedTechVars.scarecrowPole then
            local adj = -7
            local cAdj = -3
            local standingPoly, crouchingPoly
            local altStandingPoly = {
                { -0.3, -2.0 + 0.875 + (adj / 8) },
                { -0.08, -2.5 + 0.875 + (adj / 8) },
                { 0.08, -2.5 + 0.875 + (adj / 8) },
                { 0.3, -2.0 + 0.875 + (adj / 8) },
                { 0.75, 0.65 },
                { 0.35, 1.22 },
                { -0.35, 1.22 },
                { -0.75, 0.65 },
            }
            local altCrouchingPoly = {
                { -0.75, -2.0 + 0.375 + (cAdj / 8) },
                { -0.35, -2.5 + 0.375 + (cAdj / 8) },
                { 0.35, -2.5 + 0.375 + (cAdj / 8) },
                { 0.75, -2.0 + 0.375 + (cAdj / 8) },
                { 0.75, -1 },
                { 0.35, -0.5 },
                { -0.35, -0.5 },
                { -0.75, -1 },
            }
            if fezzedTechVars.charScale and fezzedTechVars.charScale ~= 1 then
                standingPoly = poly.scale(self.baseColBox.standingPoly, fezzedTechVars.charScale)
                crouchingPoly = poly.scale(self.baseColBox.crouchingPoly, fezzedTechVars.charScale)
                standingPoly = poly.scale(altStandingPoly, fezzedTechVars.charScale)
                crouchingPoly = poly.scale(altCrouchingPoly, fezzedTechVars.charScale)
            else
                standingPoly = self.baseColBox.standingPoly
                crouchingPoly = self.baseColBox.crouchingPoly
            end
            largeCollisionMatch = polyEqual(mcontroller.collisionPoly(), standingPoly)
                or polyEqual(mcontroller.collisionPoly(), crouchingPoly)
                or polyEqual(mcontroller.collisionPoly(), altStandingPoly)
                or polyEqual(mcontroller.collisionPoly(), altCrouchingPoly)
            fezzedTechVars.collisionMatch = largeCollisionMatch
        end

        if fezzedTechVars.noLegs then
            local adj = fezzedTechVars.mertail and 0 or -2
            local cAdj = -2
            local standingPoly = {
                { -0.3, -2.0 + 0.875 + (adj / 8) },
                { -0.08, -2.5 + 0.875 + (adj / 8) },
                { 0.08, -2.5 + 0.875 + (adj / 8) },
                { 0.3, -2.0 + 0.875 + (adj / 8) },
                { 0.75, 0.65 },
                { 0.35, 1.22 },
                { -0.35, 1.22 },
                { -0.75, 0.65 },
            }
            local crouchingPoly = {
                { -0.75, -2.0 + 0.375 + (cAdj / 8) },
                { -0.35, -2.5 + 0.375 + (cAdj / 8) },
                { 0.35, -2.5 + 0.375 + (cAdj / 8) },
                { 0.75, -2.0 + 0.375 + (cAdj / 8) },
                { 0.75, -1 },
                { 0.35, -0.5 },
                { -0.35, -0.5 },
                { -0.75, -1 },
            }
            if fezzedTechVars.charScale and fezzedTechVars.charScale ~= 1 then
                standingPoly = poly.scale(standingPoly, fezzedTechVars.charScale)
                crouchingPoly = poly.scale(crouchingPoly, fezzedTechVars.charScale)
            end

            collisionMatch = polyEqual(mcontroller.collisionPoly(), standingPoly)
                or polyEqual(mcontroller.collisionPoly(), crouchingPoly)
            fezzedTechVars.collisionMatch = collisionMatch or fezzedTechVars.collisionMatch

            if
                mcontroller.groundMovement()
                and ((self.moves[2] or self.moves[3]) and not self.moves[1])
                and (fezzedTechVars.scarecrowPole or fezzedTechVars.soarHop or collisionMatch)
                and not fezzedTechVars.mertail
            then
                -- and not self.moves[6]
                -- if collisionMatch or self.moves[7] then
                mcontroller.controlModifiers({ movementSuppressed = true })
                -- end
                -- or (self.moves[7] and mcontroller.walking())
            end
            if
                mcontroller.groundMovement()
                and ((fezzedTechVars.potted or fezzedTechVars.largePotted or fezzedTechVars.mertail) and smallColBox)
            then
                local notUsingThrusters = not (
                    fezzedTechVars.avosiJetpack
                    or ((fezzedTechVars.garyTech or fezzedTechVars.fezTech or fezzedTechVars.upgradedThrusters) and self.thrustersActive)
                    or (fezzedTechVars.avosiWingedArms or (fezzedTechVars.avosiFlight and checkDistRaw == -2))
                )
                if
                    ((fezzedTechVars.potted or fezzedTechVars.largePotted) and fezzedTechVars.gettingOverIt)
                    and (self.moves[2] or self.moves[3] or self.moves[1])
                    and not (mcontroller.liquidMovement() or self.collision)
                    and notUsingThrusters
                then
                    mcontroller.controlModifiers({ movementSuppressed = true })
                end
                if
                    (
                        fezzedTechVars.mertail
                        or ((fezzedTechVars.potted or fezzedTechVars.largePotted) and not fezzedTechVars.gettingOverIt)
                    )
                    and self.moves[1]
                    and not (mcontroller.liquidMovement() or self.collision or self.moves[2] or self.moves[3])
                    and notUsingThrusters
                then
                    mcontroller.controlModifiers({ movementSuppressed = true })
                end
            end
            if
                (not mcontroller.liquidMovement())
                and not ((fezzedTechVars.potted or fezzedTechVars.largePotted) or fezzedTechVars.mertail)
            then -- and (not swimmingFlight)
                local jumpInterval = 0.5
                if
                    (self.moves[2] or self.moves[3] or self.moves[1])
                    and mcontroller.groundMovement()
                    and not activeMovementAbilities
                    and collisionMatch
                then
                    if self.jumpTimer == jumpInterval then
                        -- sb.logInfo("potted = %s", fezzedTechVars.potted)
                        -- sb.logInfo("largePotted = %s", largePotted)
                        -- sb.logInfo("globals.gliderActive = %s", globals.gliderActive)
                        -- sb.logInfo("globals.holdingGlider = %s", globals.holdingGlider)
                        local wingHop = fezzedTechVars.avosiWings and not (itemL or itemR)
                        local dirJump = (self.moves[2] or self.moves[3]) and 1 or 0
                        if self.moves[5] then
                            mcontroller.setVelocity({ 1 * (self.moves[2] and -1 or 1) * dirJump, 10 })
                        elseif self.moves[4] or self.moves[1] then
                            mcontroller.setVelocity({
                                ((wingHop and 25 or 7) * (self.moves[2] and -1 or 1) * dirJump),
                                20 * fezzedTechVars.jumpSpeedMult,
                            })
                        elseif self.moves[7] then
                            mcontroller.setVelocity({
                                ((wingHop and 15 or 3.5) * (self.moves[2] and -1 or 1) * dirJump),
                                15 * fezzedTechVars.jumpSpeedMult,
                            })
                        else
                            mcontroller.setVelocity({
                                2 * (self.moves[2] and -1 or 1),
                                15 * fezzedTechVars.jumpSpeedMult,
                            })
                        end
                        self.jumpTimer = 0
                    end
                    self.jumpTimer = math.min(self.jumpTimer + dt, jumpInterval)
                else
                    self.jumpTimer = math.min(self.jumpTimer + dt, jumpInterval)
                end
                -- mcontroller.walking()
            end
            if self.collision or not (fezzedTechVars.potted or fezzedTechVars.largePotted) then
                if self.moves[1] then mcontroller.controlJump() end
                if self.moves[5] then mcontroller.controlCrouch() end
                if self.moves[5] and self.moves[6] then mcontroller.controlDown() end
            else
                if self.moves[5] then mcontroller.controlCrouch() end
                if self.moves[5] and self.moves[6] then mcontroller.controlDown() end
            end
        elseif fezzedTechVars.ghostTail then
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
            local rectCol = { x - side, y - down, x + side, y + up }
            colliding = world.rectCollision(rectCol, { "Block", "Dynamic", "Slippery", "Platform" })
        end

        local isFlopping = false

        do
            local wingAngling = false
            local potCrawling = (fezzedTechVars.potted or fezzedTechVars.largePotted)
                and not (fezzedTechVars.gettingOverIt or fezzedTechVars.scarecrowPoleRaw)
            if
                (
                    fezzedTechVars.avosiFlight
                    or fezzedTechVars.avosiWingedArms
                    or fezzedTechVars.avosiJetpack
                    or fezzedTechVars.fireworks
                    or fezzedTechVars.swimTail
                    or fezzedTechVars.bouncy
                    or fezzedTechVars.mertail
                    or fezzedTechVars.ghostTail
                    or potCrawling
                    or fezzedTechVars.windSailing
                    or globals.gliderActive
                ) and not (lounging or globals.sphereActive)
            then
                local vars = {}
                vars.rocketAngling = mcontroller.jumping() and self.moves[7] and (not mcontroller.liquidMovement())
                wingAngling = not (mcontroller.groundMovement() or mcontroller.liquidMovement())
                vars.velocity = mcontroller.velocity()
                vars.xVel = vars.velocity[1]
                vars.yVel = vars.velocity[2] -- avosiFlight and math.abs(velocity[2]) or velocity[2]
                vars.bouncing = fezzedTechVars.bouncy and math.abs(vars.xVel) > 3 and (not mcontroller.liquidMovement())
                vars.nearGround = false
                if fezzedTechVars.mertail or potCrawling then
                    local scale = fezzedTechVars.charScale or 1
                    vars.nearGround = getClosestBlockYDistance(mPos, vec2.add(mPos, { 0, (-4 * scale) }), false)
                end
                vars.flopping = (fezzedTechVars.mertail or potCrawling)
                    and (smallColBox or fezzedTechVars.largePotted or fezzedTechVars.potted or fezzedTechVars.mertail)
                    and (self.moves[2] or self.moves[3])
                    and (mcontroller.groundMovement() or vars.nearGround)
                    and (not mcontroller.liquidMovement())
                isFlopping = vars.flopping

                if
                    (fezzedTechVars.fireworks and vars.rocketAngling)
                    or ((fezzedTechVars.avosiFlight or fezzedTechVars.avosiWingedArms or fezzedTechVars.ghostTail or fezzedTechVars.avosiJetpack or fezzedTechVars.windSailing) and wingAngling)
                    or vars.bouncing
                    or vars.flopping
                    or fezzedTechVars.swimTail
                    or globals.gliderActive
                then
                    local angleDiv = (fezzedTechVars.avosiFlight or fezzedTechVars.windSailing) and 1 or 2
                    local angleLag = (fezzedTechVars.avosiFlight or fezzedTechVars.windSailing) and 0.5 or 0.15
                    self.jumpAngleDt = math.min(angleLag, self.jumpAngleDt + dt)

                    local onJetpack = (
                        fezzedTechVars.avosiJetpack
                        and not (
                            fezzedTechVars.avosiWingedArms
                            or fezzedTechVars.avosiFlight
                            or fezzedTechVars.windSailing
                        )
                    ) or (fezzedTechVars.avosiWingedArms and (itemL or itemR))
                    local yVel = vars.yVel
                    if (globals.gliderActive and not (colliding or fezzedTechVars.invisibleFlyer)) or onJetpack then
                        yVel = globals.gliderActive and 75 or 10
                    end
                    if mcontroller.liquidMovement() then yVel = yVel + 2.5 end
                    local rawTAng = (vec2.angle({ vars.xVel / angleDiv, yVel }) - math.pi / 2)
                    local tAng = rawTAng
                    if
                        (fezzedTechVars.avosiFlight or fezzedTechVars.windSailing or fezzedTechVars.scarecrowPole)
                        and not (mcontroller.liquidMovement())
                    then
                        if rawTAng >= math.pi * 0.55 and rawTAng <= math.pi * 1 then
                            tAng = math.pi * 0.55
                        elseif rawTAng > math.pi * 1 and rawTAng <= math.pi * 1.45 then
                            tAng = math.pi * 1.45
                        end
                    end

                    if
                        fezzedTechVars.bouncy
                        and (
                            colliding
                            or not (fezzedTechVars.avosiFlight or fezzedTechVars.windSailing)
                            or world.liquidAt(fezzedTechVars.liqCheckPosDown)
                        )
                    then
                        tAng = math.min(math.max(-vars.xVel * math.pi * 0.05, -0.1 * math.pi), 0.1 * math.pi)
                    end
                    if vars.flopping then
                        -- local faceDir = mcontroller.facingDirection()
                        if self.moves[2] then
                            tAng = math.pi * 0.35
                        elseif self.moves[3] then
                            tAng = math.pi * 1.65
                        end
                    end
                    -- if bouncy and vars.xVel ~= 0 and mcontroller.groundMovement() then
                    --     if tAng >= -math.pi * 0.05 and tAng <= math.pi * 0.05 then
                    --         local xDir = vars.xVel < 0 and -1 or 1
                    --         tAng = -xDir * math.pi * 0.05
                    --     end
                    -- end
                    self.targetAngle = (self.jumpAngleDt == angleLag or vars.flopping) and tAng or 0
                    if
                        (
                            fezzedTechVars.fireworks
                            or (
                                (fezzedTechVars.avosiWingedArms or fezzedTechVars.avosiJetpack)
                                and usingFlightPack
                                and checkDistRaw == -2
                            )
                        )
                        and not (lounging or (fezzedTechVars.bouncy and inLiquid))
                    then
                        self.fireworksDt = math.max(self.fireworksDt - dt, 0)
                        if self.fireworksDt == 0 then
                            self.fireworksDt = 0.04
                            if fezzedTechVars.fireworks then
                                local fireworksParams = {
                                    power = 0,
                                    statusEffects = jarray(),
                                    damageKind = "hidden",
                                    lightColor = { 235, 126, 2 },
                                    periodicActions = {
                                        {
                                            time = 0.0,
                                            action = "particle",
                                            count = 1,
                                            specification = {
                                                type = "animated",
                                                light = { 235, 126, 2 },
                                                layer = "front",
                                                fullbright = true,
                                                collidesLiquid = false,
                                                collidesForeground = false,
                                                size = 0.9,
                                                destructionAction = "shrink",
                                                destructionTime = 0.06,
                                                timeToLive = 0.06,
                                                image = "/animations/statuseffects/burning/burning.animation"
                                                    .. "?multiply=0000",
                                                variance = {
                                                    position = { 1.4, 2.4 },
                                                    size = 0.15,
                                                    initialVelocity = { 0.2, 1.5 },
                                                },
                                            },
                                        },
                                    },
                                }
                                if not globals.onWall then
                                    world.spawnProjectile(
                                        "flamethrower",
                                        { mPos[1] + 0.0625, mPos[2] },
                                        entity.id(),
                                        { 0, -3 },
                                        false,
                                        fireworksParams
                                    )
                                end
                            else
                                local fwVars = {
                                    faceDir = mcontroller.facingDirection(),
                                    exhaustVel = math.max(5 - math.abs(vars.xVel) / 5, 0),
                                    yPos = math.max(1 - math.abs(vars.xVel) / 15, -1.5),
                                }
                                local avoliteParticle = {
                                    fade = 1,
                                    initialVelocity = { -vars.xVel / 5, -fwVars.exhaustVel }, -- {0, -3},
                                    approach = { 0, 2 },
                                    flippable = false,
                                    layer = "back",
                                    destructionAction = "shrink",
                                    variance = { initialVelocity = { 0.3, 0.3 }, rotation = 180, position = { 1, 1 } },
                                    type = "textured",
                                    destructionTime = 1.5,
                                    size = 1.5,
                                    color = { 255, 255, 255, 150 },
                                    image = "/particles/ember/1.png?setcolor=fff?multiply=f03430fe",
                                    finalVelocity = { 0, 2 },
                                    timeToLive = 1,
                                    light = { 140, 32, 30 },
                                    position = { fwVars.yPos, -0.6 * fwVars.faceDir }, -- {-2, 3.5} -- Rotated 90 degrees, so X and Y are switched.
                                }
                                local jetpackParticle = {
                                    type = "animated",
                                    light = { 0, 0, 0 },
                                    layer = "back",
                                    fullbright = false,
                                    collidesLiquid = true,
                                    collidesForeground = false,
                                    size = 0.9,
                                    destructionAction = "shrink",
                                    destructionTime = 0.6,
                                    timeToLive = 0.6,
                                    position = { fwVars.yPos, -0.6 * fwVars.faceDir }, -- Rotated 90 degrees, so X and Y are switched.
                                    initialVelocity = { -vars.xVel / 5, -fwVars.exhaustVel },
                                    image = "/animations/dusttest/dusttest.animation" .. "?multiply=fff1",
                                    variance = { position = { 0.2, 0.6 }, size = 0.15, initialVelocity = { 0.2, 0.2 } },
                                }
                                local flightPackParams = {
                                    power = 0,
                                    statusEffects = jarray(),
                                    damageKind = "hidden",
                                    timeToLive = 0.1,
                                    periodicActions = {
                                        {
                                            time = 0.0,
                                            action = "particle",
                                            count = 1,
                                            specification = fezzedTechVars.avolitePack and avoliteParticle
                                                or jetpackParticle,
                                        },
                                    },
                                }
                                if not globals.onWall then
                                    world.spawnProjectile(
                                        "invisibleprojectile",
                                        { mPos[1] + 0.0625, mPos[2] },
                                        entity.id(),
                                        { 0, -3 },
                                        false,
                                        flightPackParams
                                    )
                                end
                            end
                        end
                    end
                else
                    self.jumpAngleDt = 0
                    self.targetAngle = 0
                end

                local keepUpward = math.abs(vars.xVel) <= 3.5
                    and not (mcontroller.zeroG() or mcontroller.liquidMovement() or vars.flopping)

                if
                    globals.sphereActive
                    or lounging
                    or globals.onWall
                    or (fezzedTechVars.flyboard and globals.flyboardActive)
                    or (self.collisionTimer ~= 0 and not vars.flopping)
                    or keepUpward
                then
                    local liqCheckPosDown = { math.floor(mPos[1] + 0.5), math.floor(mPos[2] - 3) }
                    if
                        fezzedTechVars.bouncy
                        and (mcontroller.groundMovement() or world.liquidAt(liqCheckPosDown))
                        and not (globals.isStable or lounging or globals.sphereActive)
                    then
                        if vars.xVel == 0 then
                            self.targetAngle = 0
                        else
                            self.targetAngle =
                                math.min(math.max(-vars.xVel * math.pi * 0.05, -0.1 * math.pi), 0.1 * math.pi)
                        end
                    else
                        self.targetAngle = 0
                    end
                end

                if colliding and not (fezzedTechVars.bouncy or vars.flopping) then
                    -- Constrain the target angle instead of zeroing it.
                    self.targetAngle = -(
                        self.targetAngle >= math.pi * 0.5 and (-math.pi + self.targetAngle) or self.targetAngle
                    )
                    self.targetAngle = math.min(math.max(self.targetAngle, -0.1 * math.pi), 0.1 * math.pi)
                end
            else
                self.targetAngle = 0
            end

            local angle = angleLerp(self.currentAngle, self.targetAngle, 0.08, math.pi * 0.002)
            local flyerOverride = globals.garyTech or globals.shadowRun or globals.fezTech
            local holdingNonFlyerItem = (itemL or itemR)
                and not (
                    globals.gliderActive
                    and globals.holdingGlider
                    and fezzedTechVars.invisibleFlyer
                    and not flyerOverride
                )
            if
                (fezzedTechVars.avosiFlight or fezzedTechVars.windSailing)
                and wingAngling
                and not (holdingNonFlyerItem or lounging or globals.sphereActive)
            then
                if angle > 0 and angle < math.pi then
                    mcontroller.controlFace(-1)
                elseif angle > math.pi and angle < math.pi * 2 then
                    mcontroller.controlFace(1)
                end
            end
            local flipping = globals.holdingGlider and not globals.gliderActive
            if (not (angle == 0 and self.currentAngle == 0)) and not flipping then mcontroller.setRotation(angle) end
            self.currentAngle = angle
        end

        if lounging and not globals.sphereActive then
            local adj = 0
            local sitParameters = {
                standingPoly = {
                    { -0.75, -2.0 + 0.875 + (adj / 8) },
                    { -0.35, -2.5 + 0.875 + (adj / 8) },
                    { 0.35, -2.5 + 0.875 + (adj / 8) },
                    { 0.75, -2.0 + 0.875 + (adj / 8) },
                    { 0.75, 0.65 },
                    { 0.35, 1.22 },
                    { -0.35, 1.22 },
                    { -0.75, 0.65 },
                },
                crouchingPoly = {
                    { -0.75, -2.0 + 0.375 + (adj / 8) },
                    { -0.35, -2.5 + 0.375 + (adj / 8) },
                    { 0.35, -2.5 + 0.375 + (adj / 8) },
                    { 0.75, -2.0 + 0.375 + (adj / 8) },
                    { 0.75, -1 },
                    { 0.35, -0.5 },
                    { -0.35, -0.5 },
                    { -0.75, -1 },
                },
            }
            if fezzedTechVars.charScale and fezzedTechVars.charScale ~= 1 then
                sitParameters.standingPoly = poly.scale(sitParameters.standingPoly, fezzedTechVars.charScale)
                sitParameters.crouchingPoly = poly.scale(sitParameters.crouchingPoly, fezzedTechVars.charScale)
            end
            mcontroller.controlParameters(sitParameters)
        elseif
            (
                fezzedTechVars.noLegs
                or fezzedTechVars.isMerrkin
                or fezzedTechVars.leglessSmallColBox
                or fezzedTechVars.tailed
                or fezzedTechVars.largePotted
            ) and not globals.sphereActive
        then
            status.setStatusProperty("isLegless", true)
            do
                local adj = fezzedTechVars.largePotted and -7 or (fezzedTechVars.mertail and 0 or -2)
                local cAdj = fezzedTechVars.largePotted and -3 or -2
                local inAir = (
                    (
                        fezzedTechVars.parkourThrusters
                        or fezzedTechVars.fireworks
                        or (fezzedTechVars.paragliderPack and fezzedTechVars.paramotor)
                    ) and mcontroller.jumping()
                )
                local potParameters = {
                    liquidImpedance = 0,

                    walkSpeed = (not mcontroller.groundMovement())
                            and (inAir and 25 or (fezzedTechVars.soarHop and 7.5 or 0.5))
                        or (fezzedTechVars.mertail and 2 or 0),
                    runSpeed = (not mcontroller.groundMovement())
                            and (inAir and 50 or (fezzedTechVars.soarHop and 15 or 1))
                        or (fezzedTechVars.mertail and 5 or 0),

                    airJumpProfile = {
                        jumpSpeed = (
                            (fezzedTechVars.potted or fezzedTechVars.largePotted)
                            and not fezzedTechVars.fireworks
                            and scarecrowWalking
                        )
                                and 2.5
                            or (
                                (fezzedTechVars.parkourThrusters or fezzedTechVars.fireworks) and 15
                                or (fezzedTechVars.soarHop and 15 or 2.5)
                            ),
                        autoJump = true,
                        reJumpDelay = (
                            fezzedTechVars.flightEnabled
                            or fezzedTechVars.soarHop
                            or fezzedTechVars.fireworks
                        )
                                and 0.02
                            or 0.35,
                        multiJump = fezzedTechVars.flightEnabled or (fezzedTechVars.fireworks and self.moves[7]),
                    },

                    standingPoly = {
                        { -0.3, -2.0 + 0.875 + (adj / 8) },
                        { -0.08, -2.5 + 0.875 + (adj / 8) },
                        { 0.08, -2.5 + 0.875 + (adj / 8) },
                        { 0.3, -2.0 + 0.875 + (adj / 8) },
                        { 0.75, 0.65 },
                        { 0.35, 1.22 },
                        { -0.35, 1.22 },
                        { -0.75, 0.65 },
                    },
                    crouchingPoly = {
                        { -0.75, -2.0 + 0.375 + (cAdj / 8) },
                        { -0.35, -2.5 + 0.375 + (cAdj / 8) },
                        { 0.35, -2.5 + 0.375 + (cAdj / 8) },
                        { 0.75, -2.0 + 0.375 + (cAdj / 8) },
                        { 0.75, -1 },
                        { 0.35, -0.5 },
                        { -0.35, -0.5 },
                        { -0.75, -1 },
                    },
                }
                if fezzedTechVars.charScale and fezzedTechVars.charScale ~= 1 then
                    potParameters.standingPoly = poly.scale(potParameters.standingPoly, fezzedTechVars.charScale)
                    potParameters.crouchingPoly = poly.scale(potParameters.crouchingPoly, fezzedTechVars.charScale)
                end
                -- local jump, left, right = table.unpack(checkMovement())
                -- local collisionMatch = polyEqual(mcontroller.collisionPoly(), potParameters.standingPoly)
                --     or polyEqual(mcontroller.collisionPoly(), potParameters.crouchingPoly)
                -- fezzedTechVars.collisionMatch = fezzedTechVars.collisionMatch or collisionMatch
                if fezzedTechVars.flightEnabled or checkDistRaw == -2 then
                    local isSoaring = checkDistRaw == -2
                    potParameters.airForce = 250
                    potParameters.airFriction = 5
                    potParameters.airJumpProfile = {
                        jumpSpeed = fezzedTechVars.mertail and 5
                            or (
                                (fezzedTechVars.potted and scarecrowWalking) and 2.5
                                or (fezzedTechVars.avosiJetpack and 5 or (isSoaring and 25 or 15))
                            ),
                        autoJump = true,
                        multiJump = fezzedTechVars.flightEnabled or fezzedTechVars.avosiJetpack,
                    }
                    potParameters.walkSpeed = (not mcontroller.groundMovement()) and (isSoaring and 2.5 or 5) or 0
                    potParameters.runSpeed = (not mcontroller.groundMovement()) and (isSoaring and 7.5 or 20) or 0
                end
                self.jumpDt = math.max(self.jumpDt - dt, 0)
                do
                    if
                        (mcontroller.walking() or mcontroller.running())
                        and (mcontroller.groundMovement() or (not mcontroller.canJump()))
                        and (not mcontroller.liquidMovement())
                        and fezzedTechVars.collisionMatch
                    then
                        if self.jumpDt <= 0 and not (fezzedTechVars.mertail or fezzedTechVars.largePotted) then
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
                if
                    fezzedTechVars.soarHop
                    or fezzedTechVars.avosiWings
                    or fezzedTechVars.ghostTail
                    or fezzedTechVars.swimTail
                then
                    if mcontroller.jumping() then
                        self.soarDt = math.max(self.soarDt - dt, 0)
                    else
                        if fezzedTechVars.opTail then
                            self.soarDt = mcontroller.groundMovement() and (self.moves[6] and 0.7 or 0.25)
                                or math.min(self.soarDt + (dt / 2), 0.7)
                        elseif fezzedTechVars.ghostTail then
                            self.soarDt = mcontroller.groundMovement() and 0.25 or self.soarDt
                        elseif fezzedTechVars.swimTail then
                            self.soarDt = 0
                        elseif fezzedTechVars.avosiWings then -- and not (itemL or itemR)
                            self.soarDt = mcontroller.groundMovement() and (self.moves[6] and 0.35 or 0.25)
                                or math.min(self.soarDt + (dt / 6), 2)
                        else
                            self.soarDt = mcontroller.groundMovement() and (self.moves[6] and 0.35 or 0.25)
                                or math.min(self.soarDt + (dt / 5), 2)
                        end
                    end
                    if fezzedTechVars.ghostTail or fezzedTechVars.swimTail then
                        potParameters.airFriction = 5
                        potParameters.minimumLiquidPercentage = 0.2
                        potParameters.airJumpProfile.jumpSpeed = 10
                        potParameters.airJumpProfile.jumpHoldTime = 0.25
                        potParameters.airJumpProfile.jumpInitialPercentage = 1
                        potParameters.airJumpProfile.multiJump = true -- self.soarDt > 0
                        potParameters.airJumpProfile.autoJump = self.moves[6] or self.soarDt == 0 -- true
                        local moveSpeed = {
                            fezzedTechVars.swimTail and (self.moves[7] and 8 or 5) or 5,
                            fezzedTechVars.swimTail and (self.moves[7] and 8 or 5) or 5,
                        }
                        if fezzedTechVars.ghostTail and self.moves[7] then
                            moveSpeed = vec2.mul(moveSpeed, fezzedTechVars.runSpeedMult)
                        end
                        if self.soarDt == 0 or fezzedTechVars.ghostTail then
                            if not mcontroller.groundMovement() then
                                if self.moves[2] then
                                    mcontroller.setXVelocity(math.min(mcontroller.xVelocity(), -moveSpeed[1]))
                                elseif self.moves[3] then
                                    mcontroller.setXVelocity(math.max(mcontroller.xVelocity(), moveSpeed[1]))
                                end
                            end
                            if self.moves[5] then
                                if (not fezzedTechVars.ghostTail) or not ghostHover then
                                    mcontroller.setYVelocity(math.min(mcontroller.yVelocity(), -moveSpeed[2]))
                                else
                                    mcontroller.setYVelocity(0)
                                end
                            elseif self.moves[4] then
                                mcontroller.setYVelocity(math.max(mcontroller.yVelocity(), moveSpeed[2]))
                            else
                                local nearGround
                                if fezzedTechVars.ghostTail then
                                    nearGround = ghostHover
                                else
                                    nearGround = mcontroller.groundMovement()
                                end
                                local fallVelocity = groundDist and 0 or -10
                                local floorVelocity = nearGround and 5
                                    or (mcontroller.liquidMovement() and 0 or fallVelocity)
                                mcontroller.setYVelocity(math.max(mcontroller.yVelocity(), floorVelocity))
                            end
                            if fezzedTechVars.shadowRun and (self.moves[2] or self.moves[3]) then
                                mcontroller.controlAcceleration({
                                    (self.moves[7] and 35 or 15) * (self.moves[2] and -1 or 1),
                                    0,
                                })
                            end
                        else
                            mcontroller.setYVelocity(math.max(mcontroller.yVelocity(), -moveSpeed[2]))
                        end
                        potParameters.walkSpeed = 6
                        potParameters.runSpeed = 15
                    else
                        potParameters.airJumpProfile.multiJump = self.moves[7] and (self.soarDt >= 0.2)
                    end
                    if not mcontroller.onGround() then
                        potParameters.walkSpeed = fezzedTechVars.ghostTail and 6 or 7.5
                        potParameters.runSpeed = (fezzedTechVars.ghostTail and 15 or 15) * fezzedTechVars.runSpeedMult
                    end
                    if fezzedTechVars.swimTail then
                        potParameters.walkSpeed = fezzedTechVars.shadowRun and 15 or 10
                        potParameters.runSpeed = fezzedTechVars.shadowRun and 50 or 25
                        potParameters.liquidForce = fezzedTechVars.shadowRun and 30 or 250
                        if fezzedTechVars.shadowRun and (self.moves[2] or self.moves[3]) then
                            potParameters.liquidFriction = self.thrustersActive and 0 or 1.5
                        end
                    end
                    if fezzedTechVars.ghostTail and mcontroller.onGround() then
                        potParameters.walkSpeed = 0
                        potParameters.runSpeed = 0
                    end
                else
                    if mcontroller.falling() or mcontroller.flying() then
                        if fezzedTechVars.opTail then
                            potParameters.airJumpProfile.jumpSpeed =
                                math.max(25 + (math.abs(mcontroller.xVelocity()) / 3), 15)
                        else
                            potParameters.airJumpProfile.jumpSpeed =
                                math.max(15 + (math.abs(mcontroller.xVelocity()) ^ 1.35 / 2.25), 5)
                        end
                    end
                end
                mcontroller.controlParameters(potParameters)
            end

            if not globals.sphereActive then self.crouchingTap:update(dt, self.moves) end
        else
            status.setStatusProperty("isLegless", nil)
            if self.crouching and not globals.sphereActive then mcontroller.controlCrouch() end
            local movementParameters = {
                airJumpProfile = {
                    multiJump = fezzedTechVars.flightEnabled or fezzedTechVars.fireworks,
                    autoJump = fezzedTechVars.flightEnabled
                        or (fezzedTechVars.parkourThrusters and self.isRunBoosting)
                        or fezzedTechVars.soarHop
                        or fezzedTechVars.avosiWings
                        or fezzedTechVars.fireworks,
                },
            }

            if fezzedTechVars.scarecrowPole and not (globals.sphereActive or fezzedTechVars.ghostTail) then
                -- mcontroller.controlModifiers({movementSuppressed = mcontroller.groundMovement() and not self.moves[6]})
                -- mcontroller.controlModifiers({movementSuppressed = true})
                if not mcontroller.onGround() then
                    movementParameters.walkSpeed = 3
                    movementParameters.runSpeed = 6 * fezzedTechVars.runSpeedMult
                else
                    movementParameters.walkSpeed = 0
                    movementParameters.runSpeed = 0
                end
                local adjJumpSpeedMult = math.max(1, fezzedTechVars.jumpSpeedMult)
                movementParameters.airJumpProfile.jumpSpeed = (self.moves[6] and 7.5 or 5)
                    * ((self.moves[6] and self.running) and adjJumpSpeedMult or 1)
                    * (self.moves[7] and 1 or 0.5)
                movementParameters.airJumpProfile.autoJump = true
                movementParameters.airJumpProfile.reJumpDelay = 0.5

                self.jumpDt = math.max(self.jumpDt - dt, 0)

                if (self.moves[2] or self.moves[3]) and colliding and (not mcontroller.liquidMovement()) then
                    if
                        self.jumpDt
                        >= (
                            (fezzedTechVars.soarHop or fezzedTechVars.avosiWings or fezzedTechVars.swimmingFlight)
                                and 0.55
                            or 0.4
                        )
                    then
                        if largeCollisionMatch and not (fezzedTechVars.bouncy or fezzedTechVars.largePotted) then
                            mcontroller.controlJump()
                        end --  and (not self.running)
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

            if
                (
                    fezzedTechVars.soarHop
                    or fezzedTechVars.avosiWings
                    or fezzedTechVars.ghostTail
                    or fezzedTechVars.swimTail
                ) and not globals.sphereActive
            then
                if mcontroller.jumping() then
                    self.soarDt = math.max(self.soarDt - dt, 0)
                else
                    if fezzedTechVars.opTail then
                        self.soarDt = mcontroller.groundMovement() and (self.moves[6] and 0.7 or 0.25)
                            or math.min(self.soarDt + (dt / 2), 0.7)
                    elseif fezzedTechVars.ghostTail then
                        self.soarDt = mcontroller.groundMovement() and 0.25 or self.soarDt
                    elseif fezzedTechVars.swimTail then
                        self.soarDt = 0
                    elseif fezzedTechVars.avosiWings then -- and not (itemL or itemR)
                        self.soarDt = mcontroller.groundMovement() and (self.moves[6] and 0.35 or 0.25)
                            or math.min(self.soarDt + (dt / 6), 2)
                    else
                        self.soarDt = mcontroller.groundMovement() and (self.moves[6] and 0.35 or 0.25)
                            or math.min(self.soarDt + (dt / 5), 2)
                    end
                end
                movementParameters.airJumpProfile.jumpHoldTime = fezzedTechVars.ghostTail and 0.25 or 1.5
                movementParameters.airJumpProfile.jumpInitialPercentage = fezzedTechVars.ghostTail and 1 or 0.25
                if fezzedTechVars.ghostTail or fezzedTechVars.swimTail then
                    movementParameters.airFriction = 5
                    movementParameters.airJumpProfile.multiJump = true -- self.soarDt > 0
                    movementParameters.airJumpProfile.autoJump = self.moves[6] or self.soarDt == 0 -- true
                    local moveSpeed = fezzedTechVars.swimTail and (self.moves[7] and 25 or 10) or 10
                    if fezzedTechVars.ghostTail and self.moves[7] then
                        moveSpeed = moveSpeed * fezzedTechVars.runSpeedMult
                    end
                    if self.soarDt == 0 or fezzedTechVars.ghostTail then
                        if
                            fezzedTechVars.ghostTail
                            and (self.moves[2] or self.moves[3])
                            and not (self.moves[2] and self.moves[3])
                            and not mcontroller.groundMovement()
                        then
                            if self.moves[2] then
                                mcontroller.setXVelocity(math.min(mcontroller.xVelocity(), -moveSpeed))
                            else
                                mcontroller.setXVelocity(math.max(mcontroller.xVelocity(), moveSpeed))
                            end
                        end
                        if self.moves[5] then
                            if (not fezzedTechVars.ghostTail) or not ghostHover then
                                mcontroller.setYVelocity(
                                    math.min(
                                        mcontroller.yVelocity(),
                                        -moveSpeed * ((fezzedTechVars.shadowRun and self.thrustersActive) and 3 or 1)
                                    )
                                )
                            else
                                mcontroller.setYVelocity(0)
                            end
                        elseif self.moves[4] then
                            mcontroller.setYVelocity(math.max(mcontroller.yVelocity(), moveSpeed))
                        else
                            local nearGround
                            if fezzedTechVars.ghostTail then
                                nearGround = ghostHover
                            else
                                nearGround = mcontroller.groundMovement()
                            end
                            local fallVelocity = groundDist and 0 or -10
                            local floorVelocity = nearGround and 5
                                or (mcontroller.liquidMovement() and 0 or fallVelocity)
                            mcontroller.setYVelocity(math.max(mcontroller.yVelocity(), floorVelocity))
                        end
                        if fezzedTechVars.shadowRun and (self.moves[2] or self.moves[3]) then
                            mcontroller.controlAcceleration({
                                (self.moves[7] and 35 or 15) * (self.moves[2] and -1 or 1),
                                0,
                            })
                        end
                    else
                        mcontroller.setYVelocity(math.max(mcontroller.yVelocity(), -moveSpeed))
                    end
                else
                    movementParameters.airJumpProfile.multiJump = self.moves[7] and (self.soarDt >= 0.2)
                end
                if not mcontroller.onGround() then
                    movementParameters.walkSpeed = fezzedTechVars.ghostTail and 6 or 10
                    movementParameters.runSpeed = (fezzedTechVars.ghostTail and 15 or 15) * fezzedTechVars.runSpeedMult
                else
                    if fezzedTechVars.ghostTail or fezzedTechVars.soarHop or fezzedTechVars.opTail then
                        -- if fezzedTechVars.legless then
                        movementParameters.walkSpeed = 0
                        movementParameters.runSpeed = 0
                        -- else
                        --     movementParameters.walkSpeed = fezzedTechVars.ghostTail and 6 or 3
                        --     movementParameters.runSpeed = fezzedTechVars.ghostTail and 15 or 6
                        -- end
                    end
                end
                if fezzedTechVars.swimTail then
                    movementParameters.walkSpeed = fezzedTechVars.shadowRun and 15 or 10
                    movementParameters.runSpeed = fezzedTechVars.shadowRun and 50 or 25
                    movementParameters.liquidForce = fezzedTechVars.shadowRun and 30 or 250
                    if fezzedTechVars.shadowRun and (self.moves[2] or self.moves[3]) then
                        movementParameters.liquidFriction = self.thrustersActive and 0 or 1.5
                    end
                end
                if fezzedTechVars.scarecrowPole and not self.moves[6] then
                    movementParameters.airJumpProfile.jumpSpeed = 3.5
                elseif fezzedTechVars.opTail then
                    movementParameters.airJumpProfile.jumpSpeed = (mcontroller.falling() or mcontroller.flying()) and 10
                        or (self.moves[6] and 30 or 10)
                elseif fezzedTechVars.avosiWings then -- and not (itemL or itemR)
                    local flapSpeed = fezzedTechVars.soarHop and 10 or 6
                    movementParameters.airJumpProfile.jumpSpeed = (mcontroller.falling() or mcontroller.flying())
                            and flapSpeed
                        or (self.moves[6] and 30 or 10)
                elseif fezzedTechVars.ghostTail then
                    movementParameters.airJumpProfile.jumpSpeed = 10 -- (self.soarDt > 0) and 12.5 or 4.5
                elseif fezzedTechVars.swimTail then
                    movementParameters.airJumpProfile.jumpSpeed = self.moves[7] and 10 or 5
                elseif fezzedTechVars.soarHop then
                    movementParameters.airJumpProfile.jumpSpeed = (mcontroller.falling() or mcontroller.flying())
                            and 4.5
                        or (self.moves[6] and 15 or 10)
                    -- elseif fezzedTechVars.avosiWings then
                    --     movementParameters.airJumpProfile.jumpSpeed = 10
                else
                    movementParameters.airJumpProfile.jumpSpeed = 45
                end
            else
                if (self.moves[4] or self.moves[5]) and not self.moves[7] then
                    mcontroller.controlModifiers({ speedModifier = 0.35 })
                end
            end
            if fezzedTechVars.flightEnabled and (not mcontroller.groundMovement()) and not globals.sphereActive then
                movementParameters.walkSpeed = 20
                movementParameters.runSpeed = 50
                movementParameters.airForce = 250
                movementParameters.airFriction = 5
            end

            if not globals.sphereActive then mcontroller.controlParameters(movementParameters) end

            if not globals.sphereActive then self.crouchingTap:update(dt, self.moves) end
        end

        local gliding = globals.gliderActive and globals.isGlider ~= nil
        local usingGlider = globals.gliderActive and globals.isGlider == true

        local thermalSoaring = false

        if
            globals.gliderActive and not (fezzedTechVars.fezTech or fezzedTechVars.garyTech or fezzedTechVars.shadowRun)
        then
            local vars = {}
            vars.x, vars.y = table.unpack(mcontroller.position())
            vars.side, vars.down, vars.up = 5, -3, 7
            vars.rectCol = { vars.x - vars.side, vars.y - vars.down, vars.x + vars.side, vars.y + vars.up }
            vars.side2, vars.down2, vars.up2 = 2.5, 0, 7
            vars.rectCol2 = { vars.x - vars.side2, vars.y - vars.down2, vars.x + vars.side2, vars.y + vars.up2 }
            vars.side3, vars.down3, vars.up3 = 15, -3, 7
            vars.rectCol3 = { vars.x - vars.side3, vars.y - vars.down3, vars.x + vars.side3, vars.y + vars.up3 }
            vars.background = false
            for xAdd = -3, 3, 1 do
                for yAdd = 0, 4, 1 do
                    if backgroundExists({ vars.x + xAdd, vars.y + yAdd }, true, true) then
                        vars.background = true
                        break
                    end
                end
            end
            colliding = world.rectCollision(vars.rectCol, { "Block", "Dynamic", "Slippery" })
                or world.rectCollision(vars.rectCol2, { "Block", "Dynamic", "Slippery" })
            thermalSoaring = (world.rectCollision(vars.rectCol3, { "Block", "Dynamic", "Slippery" }) or vars.background)
                and not self.moves[5]
            -- or vars.background
            if colliding then
                globals.gliderActive = false
                self.fallDanger = false
                self.useParawing = false
            end
        else
            thermalSoaring = false
        end

        if
            (
                (
                    fezzedTechVars.swimmingFlight
                    or fezzedTechVars.avosiFlight
                    or fezzedTechVars.windSailing
                    or gliding
                    or (fezzedTechVars.upgradedThrusters and fezzedTechVars.parkourThrusters)
                    or (fezzedTechVars.avosiWings and (not mcontroller.liquidMovement()))
                    or (fezzedTechVars.flyboard and globals.flyboardActive and (not mcontroller.liquidMovement()))
                )
                or (fezzedTechVars.shadowRun and self.thrustersActive and mcontroller.liquidMovement())
            ) and not (globals.sphereActive or lounging or mcontroller.zeroG())
        then
            local movementParameters = {}

            local vars = {
                flying = not fezzedTechVars.shadowRun
                    and (groundDist and fezzedTechVars.jumpSpeedMult > 0 and self.running),
                velMag = math.abs(mcontroller.xVelocity()) / 5,
                adjJumpSpeedMult = math.min(fezzedTechVars.jumpSpeedMult, ((fezzedTechVars.jumpSpeedMult + 1) / 2)),
                groundJumpSpeedMult = math.max(1, fezzedTechVars.jumpSpeedMult),
                gravMod = mcontroller.baseParameters().gravityMultiplier,
            }
            if not (mcontroller.onGround()) then
                movementParameters.walkSpeed = (
                    globals.flyboardActive
                    or fezzedTechVars.shadowRun
                    or (fezzedTechVars.avosiFlight and not (fezzedTechVars.safetyFlight or globals.gliderActive))
                )
                        and 20
                    or 10
                movementParameters.runSpeed = (
                    globals.flyboardActive
                    or fezzedTechVars.shadowRun
                    or (fezzedTechVars.avosiFlight and not (fezzedTechVars.safetyFlight or globals.gliderActive))
                )
                        and (fezzedTechVars.avosiWingedArms and 75 or 50)
                    or 25
            end
            if fezzedTechVars.swimmingFlight or gliding then
                local flying = (
                    (
                        (fezzedTechVars.paramotor and globals.gliderActive)
                        or fezzedTechVars.parkourThrusters
                        or fezzedTechVars.avosiFlight
                    ) and (math.abs(mcontroller.xVelocity() / 22.5) >= 1)
                ) and not fezzedTechVars.shadowRun
                movementParameters.airJumpProfile = {
                    jumpSpeed = (flying and 5 or 10),
                    jumpControlForce = 400,
                    jumpInitialPercentage = 0.75,
                    jumpHoldTime = 0.25,
                    multiJump = self.collision or flying or (fezzedTechVars.soarHop and self.soarDt >= 0.2),
                    reJumpDelay = 0.25,
                    autoJump = true,
                    collisionCancelled = false,
                }
            elseif fezzedTechVars.avosiFlight then
                local jumpAdder = (self.moves[6] and self.running)
                        and (groundJump and vars.groundJumpSpeedMult or vars.adjJumpSpeedMult)
                    or (self.moves[7] and 1 or 0.45)
                if self.collision then jumpAdder = math.max(1, jumpAdder) end
                movementParameters.airJumpProfile = {
                    jumpSpeed = 10 * jumpAdder,
                    jumpControlForce = 400,
                    jumpInitialPercentage = 0.75,
                    jumpHoldTime = 0.05,
                    multiJump = self.collision or vars.flying or (fezzedTechVars.soarHop and self.soarDt >= 0.2),
                    reJumpDelay = 0.05, -- self.collision and 0.05 or math.max(0.4 - (vars.velMag * 0.05), 0.05),
                    autoJump = true,
                    collisionCancelled = false,
                }
            elseif fezzedTechVars.windSailing then
                local jumpAdder = (self.moves[6] and self.running)
                        and (groundJump and vars.groundJumpSpeedMult or vars.adjJumpSpeedMult)
                    or (self.moves[7] and 1 or 0.45)
                movementParameters.airJumpProfile = {
                    jumpSpeed = 10 * jumpAdder,
                    jumpHoldTime = 0.25,
                    multiJump = fezzedTechVars.soarHop and self.soarDt >= 0.2,
                    reJumpDelay = 0.25,
                    collisionCancelled = false,
                }
            elseif not (itemL or itemR) then
                movementParameters.airJumpProfile = {
                    jumpSpeed = 25,
                    jumpHoldTime = 0.25,
                    multiJump = fezzedTechVars.soarHop and self.soarDt >= 0.2,
                    reJumpDelay = 0.25,
                    collisionCancelled = false,
                }
            end
            if globals.flyboardActive then
                movementParameters.airJumpProfile = {
                    jumpSpeed = 25,
                    jumpHoldTime = 0.25,
                    multiJump = fezzedTechVars.soarHop and self.soarDt >= 0.2,
                    reJumpDelay = 0.25,
                    collisionCancelled = false,
                }
            end
            local wind = (windTileOcc or globals.grappled or world.underground(mcontroller.position())) and 0
                or world.windLevel(mcontroller.position())
            if fezzedTechVars.fezTech or globals.onWall or lounging then wind = 0 end
            if not (mcontroller.groundMovement()) then
                local windDiv = (self.moves[2] or self.moves[3]) and 10 or 7.5
                local xVel = math.abs(mcontroller.xVelocity())
                local windV = math.abs(wind)
                local airMovement = (
                    globals.flyboardActive
                    or (usingGlider and (fezzedTechVars.parkourThrusters or fezzedTechVars.avosiGlider or fezzedTechVars.shadowRun))
                    or (fezzedTechVars.parkourThrusters and fezzedTechVars.upgradedThrusters)
                )
                if self.moves[5] then
                    mcontroller.controlAcceleration({
                        wind / windDiv,
                        globals.flyboardActive and -6
                            or (fezzedTechVars.shadowRun and (mcontroller.liquidMovement() and -60 or -30) or -1),
                    })
                elseif self.moves[1] and airMovement or (fezzedTechVars.shadowRun and self.upgradedThrusters) then
                    mcontroller.controlAcceleration({
                        wind / windDiv,
                        (windV / 25)
                            + (xVel / 25)
                            + (
                                fezzedTechVars.invisibleFlyer and math.max(0, 5 - xVel / 25)
                                or (fezzedTechVars.shadowRun and 45 or 25)
                            ),
                    })
                elseif self.moves[4] and airMovement or (fezzedTechVars.shadowRun and self.upgradedThrusters) then
                    mcontroller.controlAcceleration({ wind / windDiv, (windV / 25) + (xVel / 25) + 10 })
                elseif self.moves[1] and fezzedTechVars.windSailing and not (gliding or globals.flyboardActive) then
                    mcontroller.controlAcceleration({ wind / windDiv, (windV / 25) + (xVel / 40) + 25 })
                else
                    if globals.flyboardActive or (gliding and self.hovering) then
                        mcontroller.controlAcceleration({ wind / windDiv, (xVel / 25) + 4.75 })
                    else
                        local velDiv = (fezzedTechVars.avosiFlight and not globals.gliderActive)
                                and ((groundDist and self.running) and 15 or 20)
                            or 10
                        mcontroller.controlAcceleration({ wind / windDiv, (windV / 25) + (xVel / velDiv) })
                    end
                end
            end
            local glideDiv = (
                fezzedTechVars.swimmingFlight
                or (gliding and (fezzedTechVars.paramotor or fezzedTechVars.parkourThrusters))
            )
                    and 15
                or 30
            local glideVel = math.max(1 - math.abs(mcontroller.xVelocity() / glideDiv), 0)
            local avosiGliding = fezzedTechVars.avosiFlight
                and (fezzedTechVars.jumpSpeedMult <= 0 or not self.running or not groundDist)
                and not self.collision
            local usingAvosiGlider = fezzedTechVars.avosiGlider and globals.gliderActive
            if
                not (mcontroller.groundMovement())
                and (
                    fezzedTechVars.swimmingFlight
                    or fezzedTechVars.avosiFlight
                    or usingGlider
                    or fezzedTechVars.windSailing
                    or (fezzedTechVars.parkourThrusters and fezzedTechVars.upgradedThrusters)
                    or globals.flyboardActive
                    or not (itemL or itemR)
                )
            then
                local gravMin = fezzedTechVars.soarHop and 0.4
                    or (avosiGliding and ((groundDist and fezzedTechVars.rawAvosiFlight) and 0.05 or 0.2) or 0.45)
                local gravMax = fezzedTechVars.soarHop and 0.5 or 0.55
                local gravMult = (
                    fezzedTechVars.swimmingFlight
                    or fezzedTechVars.paramotor
                    or usingAvosiGlider
                    or usingGlider
                )
                        and math.max(vars.gravMod * 0.05 * glideVel, 0.01)
                    or (
                        globals.flyboardActive and (vars.gravMod * 0.04)
                        or math.min(math.max(vars.gravMod * 0.75 * glideVel, gravMin), gravMax)
                    )
                movementParameters.gravityMultiplier = gravMult * fezzedTechVars.gravityModifier
            end
            if
                fezzedTechVars.swimmingFlight
                or (fezzedTechVars.flyboard and globals.flyboardActive)
                or (fezzedTechVars.shadowRun and self.thrustersActive)
                or fezzedTechVars.bouncy
            then
                status.addEphemeralEffect("nofalldamage", 0.5)
            end

            if
                fezzedTechVars.avosiWingedArms
                and not (itemL or itemR or mcontroller.liquidMovement() or mcontroller.groundMovement())
            then
                if (self.moves[2] or self.moves[3]) and self.running then mcontroller.controlJump() end
            end

            mcontroller.controlParameters(movementParameters)

            if globals.flyboardActive and not lounging then
                self.flyboardTimer = math.max(0, self.flyboardTimer - dt)
                local scale = fezzedTechVars.charScale or 1
                if self.flyboardTimer == 0 then
                    -- not (self.flyboardProjectileId and world.entityExists(self.flyboardProjectileId))
                    local vars = {
                        adj = fezzedTechVars.mertail and 0 or -2,
                        mOffset = {
                            0,
                            (
                                ((globals.noLegs and not fezzedTechVars.largePotted) and (-1.625 + adj / 8) or -2.5)
                                * scale
                            )
                                + -1.6785
                                + (1.6785 * scale)
                                + 1.75,
                        },
                        flyboardDirs = "",
                    }
                    vars.backItem = player.equippedItem and player.equippedItem("back") or nil
                    vars.adjPos = vec2.add(mPos, vars.mOffset)
                    if vars.backItem then
                        vars.flyboardDirs = vars.backItem.parameters.flyboardDirectives
                            or vars.backItem.parameters.directives
                            or self.defaultParagliderDirs
                    else
                        vars.flyboardDirs = self.defaultParagliderDirs
                    end
                    self.flyboard.processing = self.flyboardBaseDirs
                        .. vars.flyboardDirs
                        .. "?scalenearest="
                        .. tostring(scale)

                    self.flyboardProjectileId = world.spawnProjectile(
                        "invisibleprojectile",
                        vars.adjPos,
                        entity.id(),
                        { 1, 0 },
                        true,
                        self.flyboard
                    )

                    self.flyboardTimer = self.flyboard.timeToLive
                end
                local nearGround = getClosestBlockYDistance(
                    mPos,
                    vec2.add(mPos, { 0, ((globals.noLegs and -3 or -3.5) * scale) }),
                    self.moves[5]
                )
                local yVel = mcontroller.yVelocity()
                if nearGround and yVel < 0 then mcontroller.setYVelocity(0) end
                if math.abs(yVel) <= 5 then
                    mcontroller.addMomentum({ math.random() * 0.5 - 0.25, math.random() * 0.5 - 0.25 })
                    mcontroller.controlApproachVelocity({ 0, 0 }, 5)
                end
                if mcontroller.groundMovement() then mcontroller.setYVelocity(2.5) end
                if xsb and player.setOverrideState then
                    player.setOverrideState("idle")
                elseif tech then
                    setParentState("Stand")
                end
            end
        end

        if
            not fezzedTechVars.flyboard
            or not globals.flyboardActive
            or lounging
            or mcontroller.zeroG()
            or globals.sphereActive
        then
            if self.flyboardProjectileId then
                if world.entityExists(self.flyboardProjectileId) then
                    -- sb.logInfo("Projectile kill status: %s", world.sendEntityMessage(self.flyboardProjectileId, "kill"):succeeded())
                end
                self.flyboardProjectileId = nil
                if not (xsb and player.setOverrideState) then setParentState() end
            end
            globals.flyboardActive = false
        end

        if fezzedTechVars.flyboard then self.flyboardTap:update(dt, self.moves) end

        local nightVision = fezzedTechVars.nightVision or fezzedTechVars.darkNightVision or fezzedTechVars.shadowVision

        if nightVision then
            world.sendEntityMessage(entity.id(), "clearLightSources")
            if not world.pointTileCollision(mPos, { "Block", "Dynamic", "Slippery" }) then
                local lightColour
                if xsb then
                    lightColour = fezzedTechVars.shadowVision and { 150, 150, 170 } or { 50, 120, 80 } -- {65, 65, 65} for shadowVision.
                    if status.statPositive("shadowVision") then
                        world.setLightMultiplier({ 1.5, 1.5, 1.5 })
                        world.setShaderParameters({ 0.0, 0.0, 0.75 }, { 0.7, 0.8, 1.0 }, { 1.0, 0.0, 0.0 })
                    elseif status.statPositive("nightVision") or status.statPositive("darkNightVision") then
                        world.setLightMultiplier({ 5, 5, 5 })
                        world.setShaderParameters({ 0.4, 0.2, 1.0 }, { 0.4, 1.0, 0.3 }, { 1.0, 0.0, 0.0 })
                    end
                else
                    lightColour = fezzedTechVars.shadowVision and { 200, 200, 200 } or { 120, 225, 180 }
                end
                if fezzedTechVars.nightVision or fezzedTechVars.shadowVision then
                    world.sendEntityMessage(
                        entity.id(),
                        "addLightSource",
                        { position = mPos, color = lightColour, pointLight = true }
                    )
                end
                if not xsb and not fezzedTechVars.darkNightVision then
                    local aimP = aimPosition()
                    aimP = world.lineCollision(mPos, aimP, { "Block", "Dynamic", "Slippery" }) or aimP
                    world.sendEntityMessage(entity.id(), "addLightSource", {
                        position = aimP,
                        color = fezzedTechVars.shadowVision and { 200, 200, 200 } or { 120, 225, 180 },
                        pointLight = true,
                    })
                end
            end
        else
            if nightVision ~= self.nightVision then
                if xsb then
                    world.setLightMultiplier()
                    world.resetShaderParameters()
                end
                world.sendEntityMessage(entity.id(), "clearLightSources")
            end
        end
        self.nightVision = nightVision
        -- world.sendEntityMessage(entity.id(), "clearDrawables")

        if
            (fezzedTechVars.avosiWings and not (mcontroller.liquidMovement() or mcontroller.groundMovement()))
            and not globals.sphereActive
        then
            local jumping = mcontroller.jumping()
            if jumping and not self.lastJumping then -- self.moves[1] and not self.lastJump
                globals.wingFlap = true
            end
            -- self.lastJump = self.moves[1]
            self.lastJumping = jumping
        end

        if (not self.isSkating) and self.lastSkating then
            if not (xsb and player.setOverrideState) then setParentState() end
        end

        self.lastSkating = self.isSkating

        local rpMovement = false
        local canWalk = false

        if fezzedTechVars.roleplayMode then
            rpMovement = not (
                fezzedTechVars.flightEnabled
                or fezzedTechVars.opTail
                or fezzedTechVars.ghostTail
                or fezzedTechVars.swimmingFlight
                or fezzedTechVars.soarHop
                or (fezzedTechVars.fireworks and fezzedTechVars.legless)
                or fezzedTechVars.potted
                or fezzedTechVars.largePotted
                or fezzedTechVars.avosiWings
                or globals.gliderActive
                or (fezzedTechVars.parkourThrusters and not mcontroller.groundMovement())
                or fezzedTechVars.fezTech
                or fezzedTechVars.garyTech
                or (fezzedTechVars.flyboard and globals.flyboardActive)
                or globals.sphereActive
            )
            local baseRunSpeed = mcontroller.baseParameters().runSpeed
            local runMul = (self.running or fezzedTechVars.runSpeedMult == 0) and fezzedTechVars.runSpeedMult
                or math.sqrt(fezzedTechVars.runSpeedMult)
            local wingSpeed = (
                (fezzedTechVars.avosiWings and not (itemL or itemR))
                or (fezzedTechVars.avosiFlight and not fezzedTechVars.safetyFlight)
            ) and not (mcontroller.groundMovement() or mcontroller.liquidMovement())
            local wingedArmFlying = (fezzedTechVars.avosiWingedArms or fezzedTechVars.avosiFlight)
                and not (
                    globals.gliderActive
                    or mcontroller.groundMovement()
                    or mcontroller.liquidMovement()
                    or globals.onWall
                    or (itemL or itemR)
                )
            local slowAir = (fezzedTechVars.avosiWingedArms or fezzedTechVars.avosiJetpack)
                and not (
                    wingedArmFlying
                    or mcontroller.groundMovement()
                    or mcontroller.liquidMovement()
                    or globals.onWall
                )
            local runningSpeed = (slowAir and fezzedTechVars.avosiJetpack) and 0.45 or 1
            local joggingSpeed = (slowAir and fezzedTechVars.avosiJetpack) and 0.45 or 0.6
            local walkParameters = {
                walkSpeed = (fezzedTechVars.isLame and not self.moves[7]) and 2 or 4,
                runSpeed = baseRunSpeed
                    * runMul
                    * (((fezzedTechVars.shadowRun and self.shadowFlight and self.running) or wingSpeed) and (wingedArmFlying and 5 or 2.5) or 1)
                    * ((self.running or wingedArmFlying) and runningSpeed or joggingSpeed),
            }
            canWalk = not (
                fezzedTechVars.opTail
                or fezzedTechVars.ghostTail
                or fezzedTechVars.scarecrowPole
                or fezzedTechVars.soarHop
                or (fezzedTechVars.fireworks and fezzedTechVars.legless)
                or fezzedTechVars.canHop
                or fezzedTechVars.noLegs
                or fezzedTechVars.leglessSmallColBox
                or (fezzedTechVars.flyboard and globals.flyboardActive)
                or globals.sphereActive
            )
            if
                canWalk
                and (mcontroller.groundMovement() or not (globals.gliderActive or fezzedTechVars.parkourThrusters))
            then
                mcontroller.controlParameters(walkParameters)
            end
        end

        if
            fezzedTechVars.shadowRun
            and not (mcontroller.groundMovement() or mcontroller.liquidMovement() or globals.gliderActive)
        then
            local airParameters = { runSpeed = 35 }
            mcontroller.controlParameters(airParameters)
        end

        globals.rpMovement = rpMovement

        if fezzedTechVars.roleplayMode then
            self.collision = nil
            local face = mcontroller.facingDirection()
            local colTime = 0.15
            local noReset = false
            local pAdd = fezzedTechVars.noLegs and 2 or 0
            for i = 2 + pAdd, 3 + pAdd, 1 do
                local left, right = vec2.add(mPos, { -0.5 * face, i - 1 }), vec2.add(mPos, { 1.5 * face, i - 1 })
                local leftShort, rightShort =
                    vec2.add(mPos, { -0.5 * face, i - 1 }), vec2.add(mPos, { 0.5 * face, i - 1 })
                if
                    world.lineTileCollisionPoint(left, right, { "block", "dynamic" })
                    and not world.lineTileCollisionPoint(leftShort, rightShort, { "platform" })
                then
                    noReset = checkDistRaw ~= -1
                    break
                end
            end
            for i = 0, 1 + pAdd, 1 do
                local left, right = vec2.add(mPos, { -0.5 * face, i - 1 }), vec2.add(mPos, { 1.5 * face, i - 1 })
                local leftShort, rightShort =
                    vec2.add(mPos, { -0.5 * face, i - 1 }), vec2.add(mPos, { 0.5 * face, i - 1 })
                if
                    world.lineTileCollisionPoint(left, right, { "block", "dynamic" })
                    or world.lineTileCollisionPoint(leftShort, rightShort, { "platform" })
                then
                    self.collision = true
                    if not noReset then self.collisionTimer = colTime end
                    break
                end
            end
            if noReset then self.collision = false end
            for i = 0, 1 + pAdd, 1 do
                local left, right = vec2.add(mPos, { -0.5 * face, i - 1 }), vec2.add(mPos, { 0.5 * face, i - 1 })
                local leftUp, rightUp = vec2.add(mPos, { -0.5 * face, i }), vec2.add(mPos, { 0.5 * face, i })
                if
                    world.lineTileCollisionPoint(left, right, { "platform" })
                    and not world.lineTileCollisionPoint(leftUp, rightUp, { "block", "dynamic" })
                then
                    self.collision = true
                    if not noReset then self.collisionTimer = colTime end
                    break
                end
            end

            -- local avosiDelay = math.max(0.5 - (math.abs(mcontroller.xVelocity() / 5) * 0.05), 0.05)

            local vars = {}
            if fezzedTechVars.scarecrowPole or fezzedTechVars.avosiFlight then
                vars.isColliding = self.collisionTimer > 0
            else
                vars.isColliding = self.collision
            end
            vars.bouncyJumpSpeedMult = fezzedTechVars.bouncy and math.max(((fezzedTechVars.jumpSpeedMult + 1) / 2), 1)
                or 1
            vars.adjJumpSpeedMult = (self.running and self.moves[1] and not vars.isColliding)
                    and math.max(1, fezzedTechVars.jumpSpeedMult)
                or vars.bouncyJumpSpeedMult

            vars.absXVel = math.abs(mcontroller.xVelocity())
            vars.runningMod = math.sqrt(vars.absXVel)
            vars.groundJumpSpeed = (
                (fezzedTechVars.avosiJetpack or fezzedTechVars.avosiWingedArms)
                and self.onGroundTimer == 0
                and not vars.isColliding
            )
                    and 3.5
                or 7.5
            if
                (fezzedTechVars.avosiWingedArms and not fezzedTechVars.avosiJetpack)
                and checkDistRaw == -2
                and ((fezzedTechVars.avosiJetpack or itemL or itemR) and self.moves[7])
                and not (mcontroller.liquidMovement() or globals.sphereActive or globals.gliderActive)
            then
                vars.groundJumpSpeed = 13
            end
            -- and fezzedTechVars.avosiJetpack
            vars.airJumpSpeed = self.onGroundTimer == 0 and 0 or 3.5
            vars.jetpackGliding = (fezzedTechVars.avosiWingedArms or fezzedTechVars.avosiJetpack)
                and checkDistRaw == -2
                and fezzedTechVars.paragliderPack
                and globals.gliderActive
                and not (mcontroller.liquidMovement() or globals.sphereActive or lounging)
            local jumpParameters = {
                airJumpProfile = {
                    jumpSpeed = (
                        ((self.moves[7] and self.moves[1]) and vars.groundJumpSpeed or vars.airJumpSpeed)
                        * vars.adjJumpSpeedMult
                    ) + vars.runningMod,
                    multiJump = vars.isColliding
                        or (fezzedTechVars.avosiFlight and tileOcc)
                        or vars.jetpackGliding
                        or (fezzedTechVars.avosiJetpack and self.moves[7]),
                    autoJump = fezzedTechVars.scarecrowPole
                        or vars.isColliding
                        or tileOcc
                        or vars.jetpackGliding
                        or (fezzedTechVars.avosiJetpack and self.moves[7]),
                    reJumpDelay = (
                        vars.isColliding
                        or (self.moves[1] and not fezzedTechVars.noLegs)
                        or fezzedTechVars.avosiFlight
                    )
                            and 0.05
                        or 0.5,
                },
            }
            if fezzedTechVars.avosiWingedArms and checkDistRaw ~= -2 and not (vars.isColliding or globals.isGlider) then
                jumpParameters.airJumpProfile.multiJump = false
                jumpParameters.airJumpProfile.autoJump = fezzedTechVars.scarecrowPole
            end

            -- sb.logInfo("jumpParameters.airJumpProfile.multiJump = %s", jumpParameters.airJumpProfile.multiJump)
            if not self.collisionTimer then self.collisionTimer = 0 end
            if not self.collision then self.collisionTimer = math.max(self.collisionTimer - dt, 0) end
            if not self.onGroundTimer then self.onGroundTimer = 0 end
            if not (mcontroller.groundMovement() or globals.onWall) then
                self.onGroundTimer = math.max(self.onGroundTimer - dt, 0)
            else
                self.onGroundTimer = 0.1
            end
            if rpMovement or vars.jetpackGliding or fezzedTechVars.avosiWingedArms or self.collisionTimer > 0 then
                mcontroller.controlParameters(jumpParameters)
            end
        else
            self.collisionTimer = 0
            self.onGroundTimer = 0
            local jetpackGliding = (fezzedTechVars.avosiWingedArms or fezzedTechVars.avosiJetpack)
                and checkDistRaw == -2
                and fezzedTechVars.paragliderPack
                and globals.gliderActive
                and not (mcontroller.liquidMovement() or globals.sphereActive or lounging)
            local jumpParameters = {
                airJumpProfile = {
                    multiJump = (fezzedTechVars.avosiFlight and tileOcc)
                        or jetpackGliding
                        or checkDistRaw == -2
                        or (fezzedTechVars.avosiJetpack and self.moves[7]),
                    autoJump = tileOcc
                        or jetpackGliding
                        or checkDistRaw == -2
                        or (fezzedTechVars.avosiJetpack and self.moves[7]),
                    reJumpDelay = 0.05,
                },
            }
            if self.moves[1] or not fezzedTechVars.isLeglessChar then
                local smallJump = fezzedTechVars.avosiJetpack
                    or checkDistRaw <= -1
                    or (fezzedTechVars.bouncy and not self.moves[1])
                    or fezzedTechVars.noLegs
                local jumpSpeed = smallJump and 10 or 35
                jumpParameters.airJumpProfile.jumpSpeed = jumpSpeed * fezzedTechVars.jumpSpeedMult
            else
                jumpParameters.airJumpProfile.jumpSpeed = 15 * fezzedTechVars.jumpSpeedMult
            end
            if fezzedTechVars.bouncy and inLiquid and self.moves[5] then
                mcontroller.controlApproachYVelocity(-10, 150)
            end
            if fezzedTechVars.avosiWingedArms and checkDistRaw ~= -2 and not globals.isGlider then
                jumpParameters.airJumpProfile.multiJump = false
                jumpParameters.airJumpProfile.autoJump = fezzedTechVars.scarecrowPole
            end
            if fezzedTechVars.noLegs and mcontroller.groundMovement() then
                jumpParameters.runSpeed = 2.0
                jumpParameters.walkSpeed = 0.8
            end
            if
                (
                    fezzedTechVars.avosiJetpack
                    or fezzedTechVars.avosiWingedArms
                    or fezzedTechVars.avosiFlight
                    or fezzedTechVars.noLegs
                    or fezzedTechVars.scarecrowPole
                ) and not globals.gliderActive
            then
                mcontroller.controlParameters(jumpParameters)
            end
        end

        local flight = fezzedTechVars.avosiFlight
            or fezzedTechVars.avosiWings
            or fezzedTechVars.swimmingFlight
            or fezzedTechVars.fezTech
            or fezzedTechVars.garyTech
            or (fezzedTechVars.flyboard and globals.flyboardActive)
            or globals.gliderActive
            or globals.sphereActive
            or lounging

        if fezzedTechVars.isLame and (mcontroller.groundMovement() or not flight) then
            self.lameTimer = self.lameTimer + dt
            local lameMove
            if self.lameTimer >= 0.65 then
                lameMove = mcontroller.crouching() or self.crouching
                if self.lameTimer >= 0.75 then self.lameTimer = 0 end
            else
                lameMove = true
            end
            local lameModifiers = { movementSuppressed = not lameMove, runningSuppressed = true }
            mcontroller.controlModifiers(lameModifiers)
        else
            self.lameTimer = 0
        end

        if fezzedTechVars.bouncy and not mcontroller.zeroG() then
            local velocity = mcontroller.velocity()
            local absVel = math.abs(math.sqrt(velocity[1] ^ 2 + velocity[2] ^ 2))
            local bounceFactor = math.max(0.05, math.min(0.8, 0.8 - absVel / 100))
            -- local bobTime = 3
            -- self.bobTimer = math.min(self.bobTimer + dt, bobTime)
            local bouncyParams = {
                bounceFactor = bounceFactor, -- 0.8
                normalGroundFriction = globals.isStable and 7 or 3.5,
                ambulatingGroundFriction = globals.isStable and 2 or 1,
                liquidBuoyancy = self.moves[5] and 0.2 or 0.9,
                slopeSlidingFactor = globals.isStable and 1 or 5,
            }
            if mcontroller.groundMovement() then
                bouncyParams.walkSpeed = 0
                bouncyParams.runSpeed = 0
            end
            mcontroller.controlParameters(bouncyParams)

            if
                (mcontroller.groundMovement() or world.liquidAt(fezzedTechVars.liqCheckPosDown))
                and not (lounging or globals.sphereActive or globals.isStable)
            then
                -- local xVel = mcontroller.xVelocity()
                -- if math.abs(xVel) <= 2.5 then
                --     mcontroller.controlApproachVelocity({0, 0}, 5)
                -- end
                if self.currentAngle < -0.05 * math.pi then
                    mcontroller.controlAcceleration({ -2, 0 })
                elseif self.currentAngle > 0.05 * math.pi then
                    mcontroller.controlAcceleration({ 2, 0 })
                end
                local wind = (windTileOcc or world.underground(mcontroller.position())) and 0 or world.windLevel(mPos)
                local windDiv = 15
                -- local bobDir = (self.bobTimer >= (bobTime / 2)) and -1 or 1
                local velMod = 1 + absVel / 5
                if (self.moves[2] or self.moves[3]) and ((not self.moves[7]) or not self.running) then
                    local dir = self.moves[2] and -1 or 1
                    local running
                    local windAbs = math.abs(wind)
                    if fezzedTechVars.windSailing and not windTileOcc then
                        running = self.moves[7] and (0.65 * (windAbs * 0.5 + 25)) or (0.35 * (windAbs * 0.5 + 25))
                    else
                        running = self.moves[7] and 2.5 or 1.5
                    end
                    local windMul = fezzedTechVars.windSailing and (windAbs * 0.1 + 1) or 1
                    mcontroller.controlAcceleration({
                        ((velMod * 20 * windMul * math.random()) - (velMod * 10 * windMul) + running * dir)
                            + (wind / windDiv),
                        0,
                    })
                else
                    mcontroller.controlAcceleration({
                        ((velMod * 20 * math.random()) - velMod * 10) + (wind / windDiv),
                        0,
                    })
                end
            end

            if world.liquidAt(fezzedTechVars.liqCheckPos) and not (lounging or globals.sphereActive) then
                mcontroller.controlAcceleration({ 0, self.moves[1] and 250 or 80 })
            end

            -- if self.bobTimer >= bobTime then self.bobTimer = 0 end
            -- else
            --     self.bobTimer = 0
        end

        if
            (fezzedTechVars.avosiJetpack or fezzedTechVars.avosiFlight)
            and not (
                mcontroller.groundMovement()
                or mcontroller.liquidMovement()
                or mcontroller.zeroG()
                or lounging
                or globals.sphereActive
                or globals.gliderActive
                or globals.onWall
            )
        then
            local wind = (windTileOcc or world.underground(mcontroller.position())) and 0
                or world.windLevel(mcontroller.position())
            local windDiv = 15
            local velocity = mcontroller.velocity()
            local absVelocity = math.abs(math.sqrt(velocity[1] ^ 2 + velocity[2] ^ 2))
            if fezzedTechVars.tailless then
                local xWindMod = 1 + math.abs(wind / 16)
                local yWindMod = 1 + math.abs(wind / 8)
                local yWindModAug = 1 + math.abs(wind / 8) * 1.15
                local xMaxVariance = 25 + absVelocity * 1.5
                local xVariance = xMaxVariance * 2 * xWindMod * math.random() - xMaxVariance * xWindMod
                local yVariance = math.random() * absVelocity * yWindMod - 0.5 * absVelocity * yWindModAug
                mcontroller.controlAcceleration({ xVariance + (wind / windDiv), yVariance })
            else
                mcontroller.controlAcceleration({ wind / windDiv, 0 })
            end
        end

        if
            (
                fezzedTechVars.mertail
                or ((fezzedTechVars.potted or fezzedTechVars.largePotted) and not fezzedTechVars.gettingOverIt)
            ) and (smallColBox or fezzedTechVars.potted or fezzedTechVars.largePotted)
        then
            local isMoving = (self.moves[2] or self.moves[3]) and mcontroller.groundMovement()
            if isMoving then
                local maxVariance = 150
                local variantVelocity = (maxVariance * math.random() - maxVariance * 0.2) * (self.moves[2] and -1 or 1)
                mcontroller.controlAcceleration({
                    scarecrowWalking and variantVelocity or 0,
                    scarecrowWalking and 0 or 150,
                })
                mcontroller.controlFace(self.moves[2] and -1 or 1)
            elseif (not isMoving) and self.lastIsMoving and fezzedTechVars.collisionMatch then
                local gravity = world.gravity(mPos)
                mcontroller.setYVelocity(15 * math.sqrt(gravity / 80))
            end
            self.lastIsMoving = isMoving and fezzedTechVars.collisionMatch
        else
            self.lastIsMoving = false
        end

        local bouncyOnGround = false
        if fezzedTechVars.bouncy then
            local bouncingOnLiquid = world.liquidAt(fezzedTechVars.liqCheckPosDown)
                and not world.liquidAt(fezzedTechVars.liqCheckPosUp)
            bouncyOnGround = (mcontroller.groundMovement() or bouncingOnLiquid)
                and not (lounging or globals.sphereActive)

            if
                mcontroller.groundMovement()
                and (self.moves[2] or self.moves[3] or self.moves[1])
                and fezzedTechVars.pottedRaw
                and not (
                    mcontroller.liquidMovement()
                    or globals.gliderActive
                    or fezzedTechVars.avosiJetpack
                    or fezzedTechVars.avosiWings
                    or fezzedTechVars.avosiWingedArms
                    or fezzedTechVars.avosiFlight
                    or self.collision
                )
            then
                mcontroller.controlModifiers({ movementSuppressed = true })
            end
        end

        -- local pottedClimbing = (fezzedTechVars.potted or largePotted)
        --     and self.collision
        --     and not (
        --         lounging
        --         or mcontroller.groundMovement()
        --         or mcontroller.liquidMovement()
        --         or activeMovementAbilities
        --     )

        local largePottedOnGround = fezzedTechVars.largePotted and scarecrowWalking and mcontroller.groundMovement()

        if largePottedOnGround then
            local notUsingThrusters = not (
                fezzedTechVars.avosiJetpack
                or ((fezzedTechVars.garyTech or fezzedTechVars.fezTech or fezzedTechVars.upgradedThrusters) and self.thrustersActive)
                or (fezzedTechVars.avosiWingedArms or (fezzedTechVars.avosiFlight and checkDistRaw == -2))
                or globals.gliderActive
            )
            local standingPoly = mcontroller.baseParameters().standingPoly
            local crouchingPoly = mcontroller.baseParameters().crouchingPoly
            if fezzedTechVars.charScale and fezzedTechVars.charScale ~= 1 then
                standingPoly = poly.scale(standingPoly, fezzedTechVars.charScale)
                crouchingPoly = poly.scale(crouchingPoly, fezzedTechVars.charScale)
            end
            smallColBox = polyEqual(mcontroller.collisionPoly(), standingPoly)
                or polyEqual(mcontroller.collisionPoly(), crouchingPoly)
            if
                self.moves[1]
                and not (mcontroller.liquidMovement() or self.collision)
                and notUsingThrusters
                and smallColBox
            then
                mcontroller.controlModifiers({ movementSuppressed = true })
            end
        end

        if tech then
            local aXVel = math.abs(mcontroller.xVelocity())
            local aVel = vec2.mag(mcontroller.velocity())
            if xsb and player.setOverrideState then
                if fezzedTechVars.ghostTail then
                    local crouchState = mcontroller.groundMovement() and "duck" or "swimIdle"
                    local destState = ((self.moves[5] or self.crouching) and mcontroller.groundMovement())
                            and crouchState
                        or "idle"
                    player.setOverrideState(self.isSitting and "sit" or destState)
                elseif bouncyOnGround then
                    player.setOverrideState(
                        (fezzedTechVars.bouncyCrouch and (self.moves[5] or self.crouching)) and "duck"
                            or (aXVel > 1.5 and "idle" or "idle")
                    )
                elseif largePottedOnGround and not fezzedTechVars.scarecrowPoleRaw then
                    player.setOverrideState("idle")
                elseif fezzedTechVars.pottedClimbing then
                    player.setOverrideState("swimIdle")
                elseif self.lastPoseOverriding then
                    player.setOverrideState()
                end
            else
                if fezzedTechVars.ghostTail then
                    local destState = ((self.moves[5] or self.crouching) and mcontroller.groundMovement()) and "Duck"
                        or "Stand"
                    setParentState(self.isSitting and "Sit" or destState)
                elseif bouncyOnGround then
                    setParentState(
                        (fezzedTechVars.bouncyCrouch and (self.moves[5] or self.crouching)) and "Duck"
                            or (aXVel > 1.5 and "Stand" or "Stand")
                    ) -- "Walk" or "Stand"
                elseif largePottedOnGround and not fezzedTechVars.scarecrowPoleRaw then
                    setParentState("Stand")
                elseif fezzedTechVars.pottedClimbing then
                    setParentState("Fall")
                elseif self.lastPoseOverriding then
                    setParentState()
                end
            end
        end

        self.lastPoseOverriding = bouncyOnGround
            or fezzedTechVars.pottedClimbing
            or largePottedOnGround
            or fezzedTechVars.ghostTail

        globals.rpJumping = self.collisionTimer ~= 0

        globals.doSkateSound = false

        if thermalSoaring and not (mcontroller.groundMovement() or mcontroller.liquidMovement()) then
            local thermalParams = { gravityMultiplier = 0.1 * fezzedTechVars.gravityModifier }
            mcontroller.controlParameters(thermalParams)
            mcontroller.controlAcceleration({ 0, 10 })
        end

        if
            globals.grappled
            and (fezzedTechVars.avosiWings or fezzedTechVars.avosiFlight or fezzedTechVars.avosiWingedArms or fezzedTechVars.swimmingFlight)
            and not (mcontroller.groundMovement() or mcontroller.liquidMovement() or lounging or windTileOcc)
        then
            local vars = {}
            vars.wind = world.underground(mcontroller.position()) and 0 or world.windLevel(mcontroller.position())
            vars.windAbs = math.abs(vars.wind)
            vars.kiting = vec2.mag(mcontroller.velocity()) <= 10 and not (self.moves[1] or self.moves[4])
            vars.maxUp = world.gravity(mPos) * 0.3
            local thermalParams = { gravityMultiplier = 0.3 * fezzedTechVars.gravityModifier }
            mcontroller.controlParameters(thermalParams)
            if tonumber(globals.grappled) <= 1 then
                mcontroller.controlAcceleration({
                    vars.wind / 20,
                    vars.kiting and 0 or math.min(vars.maxUp, (1 + vars.windAbs / 5)),
                })
            end
            if vars.kiting then mcontroller.controlApproachVelocity({ 0, 0 }, 25 + vars.windAbs / 5) end
        end

        -- if fezzedTechVars.shadowRun and self.shadowFlight and mcontroller.liquidMovement() then
        --     local swimParams = {liquidImpedance = 0, liquidForce = 25, liquidFriction = 0}
        --     if not mcontroller.groundMovement() then
        --         swimParams.walkSpeed = 15
        --         swimParams.runSpeed = 45
        --     end
        --     mcontroller.controlParameters(swimParams)
        -- end

        if
            (fezzedTechVars.skates or fezzedTechVars.fezTech)
            and self.isSkating
            and not (globals.sphereActive or lounging)
        then
            if tech then
                if mcontroller.groundMovement() and not mcontroller.liquidMovement() then
                    local skatingParameters = (not fezzedTechVars.skates) and { walkSpeed = 15, runSpeed = 60 }
                        or { walkSpeed = 10, runSpeed = 25, normalGroundFriction = 1, slopeSlidingFactor = 0.6 }
                    if fezzedTechVars.skates then
                        if xsb and player.setOverrideState then
                            player.setOverrideState(
                                (self.moves[5] or self.crouching) and "duck"
                                    or (self.moves[2] or self.moves[3]) and "walk"
                                    or "idle"
                            )
                        else
                            setParentState(
                                (self.moves[5] or self.crouching) and "Duck"
                                    or (self.moves[2] or self.moves[3]) and "Walk"
                                    or "Stand"
                            )
                        end
                    end
                    if math.abs(mcontroller.xVelocity()) >= 2 then globals.doSkateSound = true end
                    mcontroller.controlParameters(skatingParameters)
                end
            else
                self.isSkating = false
            end
        else
            self.isSkating = false
        end

        local isSitting = self.isSitting
            or (
                mcontroller.groundMovement()
                and (fezzedTechVars.mertail or fezzedTechVars.potted or fezzedTechVars.largePotted)
                and (
                    fezzedTechVars.mertail
                    or (
                        (fezzedTechVars.potted or fezzedTechVars.largePotted)
                        and scarecrowWalking
                        and (self.moves[2] or self.moves[3])
                        and not fezzedTechVars.gettingOverIt
                    )
                )
            )
        local isOffset = (
            isSitting
            and (
                (self.crouching and self.isSitting)
                or ((fezzedTechVars.largePotted and scarecrowWalking) and fezzedTechVars.collisionMatch)
            )
        ) or globals.upsideDown
        if xsb and player.setOverrideState then
            if isSitting then
                if (not self.isSitting) and (self.moves[2] or self.moves[3]) then
                    player.setOverrideState(globals.holdingGlider and "stand" or "swim")
                else
                    if (self.moves[5] or self.crouching) and not self.isSitting then
                        mcontroller.controlCrouch()
                        player.setOverrideState("duck")
                    else
                        player.setOverrideState(
                            fezzedTechVars.collisionMatch and "sit" or (self.isSitting and "sit" or "stand")
                        )
                    end
                end
            else
                if self.lastIsSitting ~= isSitting then player.setOverrideState() end
            end
            if isOffset then
                if globals.upsideDown then
                    setParentOffset({ 0, -1.275 * fezzedTechVars.charScale })
                else
                    local potFlopping = isFlopping and fezzedTechVars.largePotted and fezzedTechVars.collisionMatch
                    setParentOffset({ 0, (potFlopping and -0.3 or -1) * fezzedTechVars.charScale })
                end
            elseif tech then
                if self.lastIsOffset ~= isOffset then setParentOffset({ 0, 0 }) end
            end
        elseif not xsb then
            if isSitting then
                if (not self.isSitting) and (self.moves[2] or self.moves[3]) then
                    setToolUsageSuppressed(true)
                    setParentState(globals.holdingGlider and "Stand" or "Swim")
                else
                    setToolUsageSuppressed()
                    if (self.moves[5] or self.crouching) and not self.isSitting then
                        mcontroller.controlCrouch()
                        setParentState("Duck")
                    else
                        setParentState(fezzedTechVars.collisionMatch and "Sit" or (self.isSitting and "sit" or "Stand"))
                    end
                end
            else
                if self.lastIsSitting ~= isSitting then
                    setToolUsageSuppressed()
                    setParentState()
                end
            end
            if isOffset then
                if globals.upsideDown then
                    setParentOffset({ 0, -1.275 * fezzedTechVars.charScale })
                else
                    local potFlopping = isFlopping and fezzedTechVars.largePotted and fezzedTechVars.collisionMatch
                    setParentOffset({ 0, (potFlopping and -0.3 or -1) * fezzedTechVars.charScale })
                end
            else
                if self.lastIsOffset ~= isOffset then setParentOffset({ 0, 0 }) end
            end
        end

        if fezzedTechVars.gettingOverIt then
            mcontroller.controlModifiers({
                movementSuppressed = mcontroller.groundMovement()
                    and not (mcontroller.liquidMovement() or mcontroller.zeroG())
                    and fezzedTechVars.collisionMatch,
            })
        end

        self.lastIsSitting = isSitting
        self.lastIsOffset = isOffset

        self.lastIsLame = fezzedTechVars.isLame

        globals.isGlider = nil
        globals.firingGrapple = nil
        globals.weaponFiring = nil
        globals.canGrabWall = nil

        status.setStatusProperty("isRunBoosting", self.isRunBoosting)
        status.setStatusProperty("shadowFlight", self.shadowFlight)
        status.setStatusProperty("thrustersActive", self.thrustersActive)
        status.setStatusProperty("runningMode", self.running)
    end
end

function renoUninit()
    if xsb then
        world.setLightMultiplier()
        world.resetShaderParameters()
    end
    if status.statusProperty("ignoreFezzedTech") then
        globals.fezzedTechLoaded = true
    else
        globals.fezzedTechLoaded = false
    end
    status.clearPersistentEffects("rpTech")
end

attachHook("init", renoInit)
attachHook("update", renoUpdate)
attachHook("uninit", renoUninit)

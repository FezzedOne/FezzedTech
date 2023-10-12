require "/tech/jump/multijump.lua"
require "/scripts/vec2.lua"
require "/scripts/poly.lua"

function init()
    movementArray = {false, false, false, false, false, false, true}
    message.setHandler("checkJumping", function(_, sameClient) if sameClient then return movementArray end end)

    math.__tech = tech
    math.__tech.args = {moves = {}}
    math.__status = status

    math.__isParkourTech = true

    self.multiJumpCount = config.getParameter("multiJumpCount")
    self.multiJumpModifier = config.getParameter("multiJumpModifier")

    self.wallSlideParameters = config.getParameter("wallSlideParameters")
    self.wallJumpXVelocity = config.getParameter("wallJumpXVelocity")
    self.wallGrabFreezeTime = config.getParameter("wallGrabFreezeTime")
    self.wallGrabFreezeTimer = 0
    self.wallReleaseTime = config.getParameter("wallReleaseTime")
    self.wallReleaseTimer = 0

    buildSensors()
    self.wallDetectThreshold = config.getParameter("wallDetectThreshold")
    self.wallCollisionSet = {"Dynamic", "Block"}

    self.thrusterSoundPlaying = false
    self.resetSounds = false
    self.previousJump = false
    self.lastSitting = false
    self.lastShadowed = false
    self.lastShadowJumping = false
    self.shiftHeld = false
    self.shiftLocked = false

    math.__onWall = false

    math.__upsideDown = false
    self.canCling = false

    self.jumpTimer = 0
    self.shadowTimer = 0
    self.highXVelTimer = 0
    self.prevHXVel = false

    refreshJumps()
    releaseWall()
end

function uninit()
    releaseWall()
    math.__isParkourTech = nil
end

function update(args)
    if not status.statusProperty("ignoreFezzedTech") then -- Don't run the update loop here if FezzedTech is disabled by another script.
        local lounging = tech.parentLounging() or math.__sitting

        local highXVel = math.abs(mcontroller.xVelocity()) >= 5 or (mcontroller.liquidMovement() and math.abs(mcontroller.yVelocity()) >= 5)
        if highXVel and args.moves.run then
            self.highXVelTimer = 0.5
        else
            self.highXVelTimer = math.max(self.highXVelTimer - args.dt, 0)
        end
        local hXVel = self.highXVelTimer ~= 0

        if math.__shadowRun and mcontroller.liquidMovement() and highXVel then
            tech.setParentState("Swim")
        else
            if self.prevHXVel then tech.setParentState() end
        end

        self.prevHXVel = math.__shadowRun and mcontroller.liquidMovement() and highXVel

        local shadowed = math.__shadowRun and ((math.__shadowFlight and math.__runBoost and hXVel) or (math.__gliderActive))
        local shadowJumping = math.__shadowRun and math.__parkourThrusters and
                                (mcontroller.jumping() or mcontroller.falling() or
                                  (mcontroller.liquidMovement() and hXVel and (not mcontroller.groundMovement()))) and (not math.__rpJumping)

        local newDirectives = ""
        if shadowed then
            newDirectives = "?border=3;00000060;00000020?multiply=303030a0"
        elseif shadowJumping then
            newDirectives = "?border=2;00000020;00000010"
        end

        if math.__upsideDown then newDirectives = newDirectives .. "?flipy" end

        if newDirectives ~= self.directives then tech.setParentDirectives(newDirectives) end

        self.shadowTimer = self.shadowTimer + args.dt
        if self.shadowTimer >= 0.125 then
            if shadowed or shadowJumping then
                local shadowAnimParams = {
                    damageType = "NoDamage",
                    damageTeam = {type = "ghostly"},
                    power = 0,
                    timeToLive = 0.01,
                    actionOnReap = {
                        {
                            action = "loop",
                            count = 3,
                            body = {
                                {
                                    action = "option",
                                    options = {
                                        {
                                            action = "particle",
                                            specification = {
                                                type = "textured",
                                                angularVelocity = math.random() * 180,
                                                light = {0, 0, 0},
                                                layer = "front",
                                                destructionAction = "shrink",
                                                destructionTime = 0.2,
                                                size = 1 / 3,
                                                timeToLive = 0.5,
                                                image = "/particles/sandcloud/1.png?multiply=0003" .. "",
                                                variance = {rotation = 180, position = {2.5, 2.5}, initialVelocity = {2, 2}}
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                world.spawnProjectile("invisibleprojectile", mcontroller.position(), entity.id(), {0, 0}, false, shadowAnimParams)
            end
        end

        self.lastShadowed = shadowed
        self.lastShadowJumping = shadowJumping

        self.multiJumpCount = math.__fezTech and 3 or config.getParameter("multiJumpCount")

        math.__isParkourTech = true

        math.__onWall = self.wall

        math.__tech.args = args
        movementArray = {
            args.moves.jump and not args.moves.down, args.moves.left, args.moves.right, args.moves.up, args.moves.down, args.moves.jump, args.moves.run
        }
        self.shiftHeld = math.__parkour and (not args.moves.run)

        local jumpActivated = args.moves["jump"] and not self.lastJump
        self.lastJump = args.moves["jump"]

        updateJumpModifier()

        local lrInput
        if args.moves["left"] and not args.moves["right"] then
            lrInput = "left"
        elseif args.moves["right"] and not args.moves["left"] then
            lrInput = "right"
        end

        if math.__resetJumps then
            math.__resetJumps = false
            refreshJumps()
        end

        if math.__fezTech then
            if not (mcontroller.groundMovement() or mcontroller.liquidMovement() or self.wall) then
                self.jumpTimer = self.jumpTimer + args.dt
            else
                self.jumpTimer = 0
            end

            if self.jumpTimer >= 5 then
                self.multiJumps = math.min(self.multiJumps + 1, self.multiJumpCount)
                self.jumpTimer = 0
            end
        end

        if math.__sphereActive then self.wall = nil end

        local wallGrabKeys = (args.moves.up and not (args.moves.left or args.moves.right or (not args.moves.run)))

        if (mcontroller.groundMovement() and not wallGrabKeys) or mcontroller.liquidMovement() then
            refreshJumps()
            if self.wall then releaseWall() end
        elseif self.wall then
            local lockingKeys = self.shiftLocked or args.moves.up or args.moves.down
            local breakOut = false

            if math.__fezTech then refreshJumps() end

            if not math.__sitting then mcontroller.controlParameters(self.wallSlideParameters) end

            if (math.__parkour and mcontroller.zeroG()) then self.wall = "background" end

            if mcontroller.zeroG() and math.__basicParkour then
                releaseWall()
                breakOut = true
            end

            if not breakOut then
                if self.wall == "background" and ((math.__parkour and (not lockingKeys)) or math.bouncy) then
                    doWallJump()
                    breakOut = true
                end
            end

            if not breakOut then
                if ((not checkWall(self.wall)) or status.statPositive("activeMovementAbilities")) or math.__jumpDisabled then
                    if math.__parkour and checkWall("background") then
                        self.wall = "background"
                    else
                        releaseWall()
                    end
                elseif jumpActivated then
                    doWallJump()
                else
                    if (lrInput and lrInput ~= self.wall) and (not math.__parkour and (not math.__bouncy)) then
                        self.wallReleaseTimer = self.wallReleaseTimer + args.dt
                    else
                        self.wallReleaseTimer = 0
                    end

                    local wallReleaseTime = math.__bouncy and 0.05 or self.wallReleaseTime
                    local grabbingWall = math.__parkour and (not math.__bouncy) and lockingKeys
                    if (self.wallReleaseTimer > wallReleaseTime) or math.__sitting or math.__grappled or math.__flyboardActive then
                        if (math.__bouncy or (not self.shiftLocked)) and args.moves.jump then
                            doWallJump()
                        else
                            releaseWall()
                        end
                        tech.setParentState()
                    else
                        if self.wall ~= "background" then
                            if mcontroller.groundMovement() and not wallGrabKeys then
                                releaseWall()
                                tech.setParentState()
                            else
                                mcontroller.controlFace(self.wall == "left" and 1 or -1)
                            end
                        elseif mcontroller.groundMovement() and not wallGrabKeys then
                            releaseWall()
                            tech.setParentState()
                        end
                        if math.__parkour and not args.moves.down then
                            if self.wall ~= "background" then mcontroller.controlFace(self.wall == "left" and -1 or 1) end
                        end
                        if self.wallGrabFreezeTimer > 0 or grabbingWall then
                            if not math.__parkour then self.wallGrabFreezeTimer = math.max(0, self.wallGrabFreezeTimer - args.dt) end
                            if (math.__parkour and (not math.__bouncy)) and not args.moves.down then
                                local yVel = (math.__parkour and args.moves.up and ((not math.__basicParkour) or (not math.__noLegs))) and
                                               (math.__basicParkour and 2.5 or 4.5) or 0
                                local xVel = 0
                                if ((args.moves.left or args.moves.right) and not (args.moves.left and args.moves.right)) then
                                    if ((self.wall == "left" and args.moves.right) or (self.wall == "right" and args.moves.left)) and checkWall("background") then
                                        self.wall = "background"
                                    end
                                    local wallWalkVel = math.__noLegs and 0 or 8
                                    xVel = args.moves.left and -wallWalkVel or wallWalkVel
                                    if not math.__sitting then
                                        tech.setParentState((self.wall == "background" and not math.__noLegs) and "Walk" or "Fly")
                                    else
                                        tech.setParentState("Sit")
                                    end
                                else
                                    if not math.__sitting then
                                        if mcontroller.zeroG() and self.canCling then
                                            tech.setParentState("Stand")
                                        else
                                            tech.setParentState("Fly")
                                        end
                                    else
                                        tech.setParentState("Sit")
                                    end
                                end
                                if math.__noLegs and (args.moves.left or args.moves.right) and not args.moves.jump then
                                    mcontroller.controlModifiers({movementSuppressed = true})
                                end
                                if not math.__sitting then mcontroller.controlApproachVelocity({xVel, yVel}, 1000) end
                            else
                                if math.__parkour and mcontroller.zeroG() then
                                    local yVel = math.__basicParkour and -2.5 or -4.5
                                    local xVel = 0
                                    if not math.__sitting then mcontroller.controlApproachVelocity({xVel, yVel}, 1000) end
                                end
                                if not math.__sitting then
                                    tech.setParentState("Fly")
                                else
                                    tech.setParentState("Sit")
                                end
                            end
                            if self.wallGrabFreezeTimer == 0 or (math.__parkour and args.moves.down and (not (math.__sitting or mcontroller.zeroG()))) then
                                if self.wall == "background" then
                                    animator.setParticleEmitterActive("wallSlide.left", true)
                                    animator.setParticleEmitterActive("wallSlide.right", true)
                                else
                                    animator.setParticleEmitterActive("wallSlide." .. self.wall, true)
                                end
                                animator.setSoundVolume("wallSlideLoop", 1)
                                animator.setSoundPitch("wallSlideLoop", 1)
                                animator.playSound("wallSlideLoop", -1)
                            end
                            if math.__parkour and (mcontroller.zeroG() or math.__sitting or (not args.moves.down)) then
                                animator.setParticleEmitterActive("wallSlide.left", false)
                                animator.setParticleEmitterActive("wallSlide.right", false)
                                animator.stopAllSounds("wallSlideLoop")
                            end
                        end
                    end
                end
            end
        elseif not (status.statPositive("activeMovementAbilities") or math.__jumpDisabled or math.__sitting) then
            if lrInput and not mcontroller.jumping() and checkWall(lrInput) then
                grabWall(lrInput, args.moves)
            elseif math.__parkour and (jumpActivated or wallGrabKeys or (self.lastSitting and not math.__sitting)) and checkWall("background") and
              (not (math.__isGlider or ((math.__shadowFlight --[[ or math.__noLegs ]] ) and args.moves.run))) then
                if ((not mcontroller.groundMovement()) or wallGrabKeys) and not (math.__firingGrapple or math.__grappled) then
                    grabWall("background", args.moves)
                end
            elseif jumpActivated and canMultiJump() and (not (math.__parkour and not math.__fezTech)) and (not (math.__fezTech and args.moves.down)) and
              (not math.__winged) and (not math.__shadowRun) then
                doMultiJump()
                if math.__fezTech then
                    animator.burstParticleEmitter("wallSlide.left")
                    animator.burstParticleEmitter("wallSlide.right")
                end
            end
        end

        math.__upsideDown = false
        self.canCling = false
        if self.wall == "background" and mcontroller.zeroG() then
            local pos = mcontroller.position()
            local wallSensorCount = #self.zeroGWallSensors.background
            local offsetPositions1 = {self.zeroGWallSensors.background[wallSensorCount], self.zeroGWallSensors.background[wallSensorCount - 1]}
            for _, offset in pairs(offsetPositions1) do
                local offsetPos = vec2.add(pos, offset)
                local tilePos = {math.floor(offsetPos[1]), math.floor(offsetPos[2])}
                if world.pointCollision(offsetPos, self.wallCollisionSet) or world.tileIsOccupied(tilePos, true, false) then
                    math.__upsideDown = true
                    self.canCling = true
                end
            end
            local offsetPositions2 = {self.zeroGWallSensors.background[wallSensorCount - 2], self.zeroGWallSensors.background[wallSensorCount - 3]}
            for _, offset in pairs(offsetPositions2) do
                local offsetPos = vec2.add(pos, offset)
                local tilePos = {math.floor(offsetPos[1]), math.floor(offsetPos[2])}
                if world.pointCollision(offsetPos, self.wallCollisionSet) or world.tileIsOccupied(tilePos, true, false) then
                    math.__upsideDown = false
                    self.canCling = false
                end
            end
            local offsetPositions3 = {self.zeroGWallSensors.background[2], self.zeroGWallSensors.background[1]}
            for _, offset in pairs(offsetPositions3) do
                local offsetPos = vec2.add(pos, offset)
                local tilePos = {math.floor(offsetPos[1]), math.floor(offsetPos[2])}
                if world.pointCollision(offsetPos, self.wallCollisionSet) or world.tileIsOccupied(tilePos, true, false) then
                    math.__upsideDown = false
                    self.canCling = true
                end
            end
            local offsetPositions4 = {self.zeroGWallSensors.background[4], self.zeroGWallSensors.background[3]}
            for _, offset in pairs(offsetPositions4) do
                local offsetPos = vec2.add(pos, offset)
                local tilePos = {math.floor(offsetPos[1]), math.floor(offsetPos[2])}
                if world.pointCollision(offsetPos, self.wallCollisionSet) or world.tileIsOccupied(tilePos, true, false) then
                    math.__upsideDown = false
                    self.canCling = false
                end
            end
        end

        self.lastSitting = math.__sitting

        if (math.__doThrusterAnims or shadowed) and (not lounging) and (not math.__flyboardActive) then
            if not (math.__paramotor or math.__fezTech or math.__garyTech or math.__avosiWings) then
                animator.setParticleEmitterActive("wallSlide.left", true)
                animator.setParticleEmitterActive("wallSlide.right", true)
            end
            if not self.thrusterSoundPlaying then
                animator.setSoundPool(
                  "wallSlideLoop", {
                      math.__shadowRun and "/sfx/weather/blizzard.ogg" or (math.__fezTech and "/sfx/tech/tech_hoverloop.ogg" or
                        (math.__garyTech and "/sfx/weather/sandstorm.ogg" or
                          (math.__paramotor and "/sfx/objects/propeller.ogg" or "/sfx/tech/tech_rocketboots.ogg")))
                  }
                )
                animator.setSoundVolume("wallSlideLoop", (math.__paramotor and not (math.__fezTech or math.__garyTech)) and 2.5 or 1)
                animator.setSoundPitch("wallSlideLoop", (math.__fezTech or math.__garyTech) and 1.5 or 1)
                animator.playSound("wallSlideLoop", -1)
                self.thrusterSoundPlaying = true
            end
        else
            if self.lastDoAnims then
                if not math.__paramotor then
                    animator.setParticleEmitterActive("wallSlide.left", false)
                    animator.setParticleEmitterActive("wallSlide.right", false)
                end
                animator.stopAllSounds("wallSlideLoop")
                animator.setSoundPool("wallSlideLoop", {"/sfx/tech/tech_wallslide.ogg"})
                animator.setSoundVolume("wallSlideLoop", 1)
                animator.setSoundPitch("wallSlideLoop", 1)
                self.thrusterSoundPlaying = false
            end
        end

        if self.resetSounds then
            animator.setSoundPool("wallSlideLoop", {"/sfx/tech/tech_wallslide.ogg"})
            self.resetSounds = false
        end

        if math.__wingFlap then
            animator.setSoundPool("wallSlideLoop", {"/sfx/npc/monsters/batong_flap4.ogg"})
            animator.setSoundVolume("wallSlideLoop", 2)
            animator.setSoundPitch("wallSlideLoop", 0.5 + (math.random() / 2))
            animator.playSound("wallSlideLoop", 0)
            self.resetSounds = true
            math.__wingFlap = false
        end

        if math.__doSkateSound and mcontroller.groundMovement() and not lounging then
            if not self.lastDoSkateSound then
                animator.setSoundPool("wallSlideLoop", {math.__fezTech and "/sfx/tech/tech_sprint_loop1.ogg" or "/sfx/projectiles/iceorb_loop.ogg"})
                animator.setSoundVolume("wallSlideLoop", math.__fezTech and 2 or 1)
                animator.setSoundPitch("wallSlideLoop", 0.8)
                animator.playSound("wallSlideLoop", -1)
                if math.__fezTech then
                    animator.setParticleEmitterActive("wallSlide.left", true)
                    animator.setParticleEmitterActive("wallSlide.right", true)
                end
            end
        else
            if self.lastDoSkateSound then
                animator.stopAllSounds("wallSlideLoop")
                animator.setSoundPool("wallSlideLoop", {"/sfx/tech/tech_wallslide.ogg"})
                animator.setSoundVolume("wallSlideLoop", 1)
                animator.setSoundPitch("wallSlideLoop", 1)
                animator.setParticleEmitterActive("wallSlide.left", false)
                animator.setParticleEmitterActive("wallSlide.right", false)
            end
        end

        if math.__flyboardActive and not (lounging or mcontroller.liquidMovement() or mcontroller.zeroG()) then
            if not self.lastFlyboardActive then
                animator.setSoundPool("wallSlideLoop", {"/sfx/tools/chainsaw_idle.ogg"})
                animator.setSoundVolume("wallSlideLoop", 1)
                animator.setSoundPitch("wallSlideLoop", 2.5)
                animator.playSound("wallSlideLoop", -1)
            end
        else
            if self.lastFlyboardActive then
                animator.stopAllSounds("wallSlideLoop")
                animator.setSoundPool("wallSlideLoop", {"/sfx/tech/tech_wallslide.ogg"})
                animator.setSoundVolume("wallSlideLoop", 1)
                animator.setSoundPitch("wallSlideLoop", 1)
                animator.setParticleEmitterActive("wallSlide.left", false)
                animator.setParticleEmitterActive("wallSlide.right", false)
            end
        end

        self.lastDoAnims = (math.__doThrusterAnims or shadowed) and (not lounging) and (not math.__flyboardActive)
        self.lastDoSkateSound = math.__doSkateSound and mcontroller.groundMovement() and not lounging
        self.lastFlyboardActive = math.__flyboardActive and not (lounging or mcontroller.liquidMovement() or mcontroller.zeroG())
        self.previousJump = args.moves.jump
    end
end

function buildSensors()
    local bounds = poly.boundBox(mcontroller.baseParameters().standingPoly)
    self.wallSensors = {right = {}, left = {}, background = {}}
    for _, offset in pairs(config.getParameter("wallSensors")) do
        table.insert(self.wallSensors.left, {bounds[1] - 0.1, bounds[2] + offset})
        table.insert(self.wallSensors.right, {bounds[3] + 0.1, bounds[2] + offset})
        table.insert(self.wallSensors.background, {bounds[1] - 0.1, bounds[2] + offset})
        table.insert(self.wallSensors.background, {bounds[3] + 0.1, bounds[2] + offset})
    end
    self.zeroGWallSensors = {right = {}, left = {}, background = {}}
    for _, offset in pairs(config.getParameter("zeroGWallSensors")) do
        table.insert(self.zeroGWallSensors.left, {bounds[1] - 0.1, bounds[2] + offset})
        table.insert(self.zeroGWallSensors.right, {bounds[3] + 0.1, bounds[2] + offset})
        table.insert(self.zeroGWallSensors.background, {bounds[1] - 0.1, bounds[2] + offset})
        table.insert(self.zeroGWallSensors.background, {bounds[3] + 0.1, bounds[2] + offset})
    end
end

function checkWall(wall)
    if wall then
        local pos = mcontroller.position()
        local wallCheck = 0
        local wallSensors = (math.__parkour and mcontroller.zeroG()) and self.zeroGWallSensors or self.wallSensors
        -- local wallSensorCount = #wallSensors.background
        for n, offset in pairs(wallSensors[wall]) do
            -- world.debugPoint(
            --   vec2.add(pos, offset),
            --   world.pointCollision(vec2.add(pos, offset), self.wallCollisionSet) and ((n == wallSensorCount or n == wallSensorCount - 1) and "green" or "yellow") or
            --     ((n == wallSensorCount or n == wallSensorCount - 1) and "cyan" or "blue")
            -- )
            if wall == "background" then
                -- world.debugPoint(
                --   vec2.add(pos, offset),
                --   world.pointCollision(vec2.add(pos, offset), self.wallCollisionSet) and ((n == 1 or n == 2 or n == 3 or n == 4) and "green" or "yellow") or
                --     ((n == 1 or n == 2 or n == 3 or n == 4) and "cyan" or "blue")
                -- )
                local offsetPos = vec2.add(pos, offset)
                local tilePos = {math.floor(offsetPos[1]), math.floor(offsetPos[2])}
                if world.pointCollision(offsetPos, self.wallCollisionSet) or world.tileIsOccupied(tilePos, false, false) or
                  world.tileIsOccupied(tilePos, true, false) or world.objectAt(tilePos) then wallCheck = wallCheck + 1 end
            else
                if world.pointCollision(vec2.add(pos, offset), self.wallCollisionSet) then wallCheck = wallCheck + 1 end
            end
        end
        return wallCheck >= self.wallDetectThreshold
    else
        return false
    end
end

function doWallJump()
    mcontroller.controlJump(true)
    if math.__shadowRun or math.__parkourThrusters or math.__fezTech then
        local jumpSpeedMult = status.stat("jumpAdder") + 1
        mcontroller.setYVelocity(30 * jumpSpeedMult)
    end
    animator.playSound("wallJumpSound")
    if self.wall == "background" then
        animator.burstParticleEmitter("wallJump.left")
        animator.burstParticleEmitter("wallJump.right")
    else
        animator.burstParticleEmitter("wallJump." .. self.wall)
    end
    if not (math.__parkour and (not math.__parkourThrusters)) then
        if self.wall ~= "background" then mcontroller.setXVelocity(self.wall == "left" and self.wallJumpXVelocity or -self.wallJumpXVelocity) end
    end
    releaseWall()
end

function grabWall(wall, moves)
    if (not math.__sphereActive) then
        local wallGrabKeys = self.shiftHeld or moves.up or moves.down
        self.wall = wall
        self.wallGrabFreezeTimer = (math.__bouncy or (not wallGrabKeys)) and 0.05 or self.wallGrabFreezeTime
        self.shiftLocked = self.shiftHeld
        self.wallReleaseTimer = 0
        mcontroller.setVelocity({0, 0})
        if not math.__parkour then tech.setToolUsageSuppressed(true) end
        tech.setParentState(math.__sitting and "sit" or "fly")
        animator.playSound("wallGrab")
    end
end

function releaseWall()
    self.shiftLocked = false
    self.wall = nil
    tech.setToolUsageSuppressed(false)
    tech.setParentState()
    animator.setParticleEmitterActive("wallSlide.left", false)
    animator.setParticleEmitterActive("wallSlide.right", false)
    animator.stopAllSounds("wallSlideLoop")
end

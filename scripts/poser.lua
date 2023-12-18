function poserInit()
    self.poses = {
        false, true, "idle.1", "idle.2", "idle.3", "idle.4", "idle.5", "walk.1", "walk.2", "walk.3", "walk.4", "walk.5", "run.1", "run.2", "run.3", "run.4",
        "run.5", "jump.1", "jump.2", "jump.3", "jump.4", "fall.1", "fall.2", "fall.3", "fall.4", "swimIdle.1", "swimIdle.2", "swim.1", "swim.2", "swim.3",
        "swim.4", "swim.5", "rotation", "rotation?multiply=00000000"
    }
    self.currentPose = config.getParameter("currentPose") or 1
    self.lockAngle = config.getParameter("lockAngle") or false
    self.keyPressed = false
    self.doubleShiftTimer = 0
    self.prevShift = false
    self.aimAngle = 0
    self.cursorSetsDirection = config.getParameter("cursorSetsDirection") or false
    self.facingDirection2 = config.getParameter("lastFacingDirection") or 1
    self.extraDirectives = config.getParameter("extraDirectives") or "?replace;ffc181=ffc181;d39c6c=d39c6c;c7815b=c7815b"
    self.idlePose = config.getParameter("idlePose") or "idle.1"
    self.alwaysAnimMovement = config.getParameter("alwaysAnimMovement")
    if self.alwaysAnimMovement == nil then self.alwaysAnimMovement = true end
    self.animPoses = {
        idle = {self.idlePose},
        walk = {"walk.1", "walk.2", "walk.3", "walk.4", "walk.5", "walk.4", "walk.3", "walk.2", repeating = true},
        run = {"run.1", "run.2", "run.3", "run.4", "run.5", "run.4", "run.3", "run.2", repeating = true},
        air = {"jump.1"},
        jump = {"jump.1", "jump.2", "jump.3", "jump.4"},
        fall = {"fall.1", "fall.2", "fall.3", "fall.4"},
        swim = {"swim.1", "swim.2", "swim.3", "swim.4", "swim.5", "swimIdle.1"},
        crouch = {"run.3"}
    }
    self.state = "idle"
    self.tick = 0
    self.animFrame = self.idlePose
    self.iconDirectives = ""
end

function getState()
    local previousState = self.state
    local newState = "idle"

    if mcontroller.groundMovement() then -- or (yVelocity >= -0.4 and yVelocity < 0)
        if mcontroller.crouching() then
            newState = "crouch"
        else
            newState = "idle"
        end
        if mcontroller.running() then
            newState = "run"
        elseif mcontroller.walking() then
            newState = "walk"
        end
    elseif mcontroller.liquidMovement() and not mcontroller.groundMovement() then
        newState = "swim"
    elseif mcontroller.jumping() or mcontroller.flying() then
        -- newState = "air"
        newState = "jump"
    elseif mcontroller.falling() then
        newState = "fall"
    else
        newState = "jump"
    end

    if newState ~= previousState then self.tick = 0 end

    return newState
end

function animating(dt)
    local frameLength = 5
    local state = self.animPoses[self.state]
    local intTick = math.floor(self.tick)
    if state then
        if (state.repeating and intTick >= (((#state + 1) * frameLength) - 1)) or intTick < 0 then self.tick = 0 end
        if state[math.ceil(intTick / frameLength)] then self.animFrame = state[math.ceil(intTick / frameLength)] end
    end

    if type(self.animFrame) ~= "string" then self.animFrame = self.idlePose end

    self.tick = self.tick + (dt * 60)
end

function poserUpdate(dt, fireMode, shiftHeld, moves)
    if moves.left and moves.right then
        if not self.prevShift then
            self.prevShift = true
            if shiftHeld then self.cursorSetsDirection = not self.cursorSetsDirection end
        else
            self.prevShift = true
        end
    else
        self.prevShift = false
    end

    self.state = getState();
    animating(dt)

    self.aimingAngle, self.facingDirection = activeItem.aimAngleAndDirection(0, activeItem.ownerAimPosition())
    if not self.oldPosition then self.oldPosition = mcontroller.position() end
    if mcontroller.position()[1] - self.oldPosition[1] ~= 0 then self.facingDirection2 = mcontroller.position()[1] - self.oldPosition[1] end
    -- if ( self.facingDirection == -1 and self.facingDirection2 >= 0 ) or ( self.facingDirection == 1 and self.facingDirection2 <= 0 ) then
    -- self.aimingAngle = ( self.aimingAngle * -1 ) + 180 - 45
    -- end
    self.oldPosition = mcontroller.position()
    if self.cursorSetsDirection then
        activeItem.setFacingDirection(self.facingDirection)
    else
        activeItem.setFacingDirection(self.facingDirection2)
    end
    if type(self.lockAngle) == "number" then
        self.aimAngle = self.lockAngle
        self.iconDirectives = "?multiply=ff55ff"
    elseif self.lockAngle == false then
        self.aimAngle = self.aimingAngle
        self.iconDirectives = "?multiply=55ffff"
    elseif self.lockAngle == true then
        self.aimAngle = 0
        self.iconDirectives = ""
    end
    local inventoryIcon = "/humanoid/novakid/" ..
                            (((self.facingDirection2 >= 0 and activeItem.hand() == "alt") or (self.facingDirection2 <= 0 and activeItem.hand() == "primary")) and
                              "frontarm.png:" or "backarm.png:")
    if self.poses[self.currentPose] == true then
        activeItem.setHoldingItem(true)
        activeItem.setFrontArmFrame(self.animFrame .. self.extraDirectives)
        activeItem.setBackArmFrame(self.animFrame .. self.extraDirectives)
        activeItem.setArmAngle(0)
        activeItem.setInventoryIcon(inventoryIcon .. self.animFrame .. "?saturation=-100")
    else
        if self.poses[self.currentPose] then
            if self.alwaysAnimMovement and self.state ~= "idle" and self.state ~= "crouch" then
                activeItem.setHoldingItem(true)
                activeItem.setFrontArmFrame(self.animFrame .. self.extraDirectives)
                activeItem.setBackArmFrame(self.animFrame .. self.extraDirectives)
                activeItem.setArmAngle(0)
                activeItem.setInventoryIcon(inventoryIcon .. self.animFrame .. "?saturation=-100")
            else
                activeItem.setHoldingItem(true)
                activeItem.setFrontArmFrame(self.poses[self.currentPose] .. self.extraDirectives)
                activeItem.setBackArmFrame(self.poses[self.currentPose] .. self.extraDirectives)
                activeItem.setArmAngle(self.aimAngle)
                activeItem.setInventoryIcon(inventoryIcon .. self.poses[self.currentPose] .. self.iconDirectives)
            end
        else
            activeItem.setHoldingItem(false)
            activeItem.setInventoryIcon(inventoryIcon .. "idle.1?saturation=-100?multiply=ffffff99")
        end
    end
    handleKeys(shiftHeld, moves)
end

function toRadians(degrees) return (degrees / 180) * math.pi end

function handleKeys(shiftHeld, moves)
    local rightCursor = (activeItem.ownerAimPosition()[1] - mcontroller.position()[1] >= 0 and activeItem.hand() == "alt") or
                          (activeItem.ownerAimPosition()[1] - mcontroller.position()[1] <= 0 and activeItem.hand() == "primary")
    if not self.keyPressed then
        if (moves.up or moves.down) then self.keyPressed = true end
    else
        if not (moves.up or moves.down) then
            self.keyPressed = false
        else
            moves.up = false;
            moves.down = false
        end
    end
    if rightCursor then
        if shiftHeld then
            if moves.up then
                if self.currentPose >= #self.poses then
                    self.currentPose = 1
                else
                    self.currentPose = self.currentPose + 1
                end
            end
            if moves.down then
                if self.currentPose <= 1 then
                    self.currentPose = #self.poses
                else
                    self.currentPose = self.currentPose - 1
                end
            end
        else
            if moves.up then
                if self.lockAngle == false then
                    self.lockAngle = true
                elseif self.lockAngle == true then
                    self.lockAngle = self.aimingAngle
                else
                    self.lockAngle = false
                end
            end
        end
    end
end

function poserUninit()
    activeItem.setInstanceValue("cursorSetsDirection", self.cursorSetsDirection)
    activeItem.setInstanceValue("lockAngle", self.lockAngle)
    activeItem.setInstanceValue("currentPose", self.currentPose)
    activeItem.setInstanceValue("lastFacingDirection", self.facingDirection2)
    activeItem.setInstanceValue("extraDirectives", self.extraDirectives)
    activeItem.setInstanceValue("idlePose", self.idlePose)
    activeItem.setInstanceValue("alwaysAnimMovement", self.alwaysAnimMovement)
    activeItem.setInventoryIcon("/interface/statuses/nude.png?saturation=-100")
end

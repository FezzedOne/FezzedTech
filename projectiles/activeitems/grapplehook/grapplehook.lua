require "/scripts/vec2.lua"

function init()
    self.ownerId = projectile.sourceEntity()
    self.breakOnSlipperyCollision = config.getParameter("breakOnSlipperyCollision")
    self.targetPosition = config.getParameter("targetPosition")
    self.checkBackground = config.getParameter("checkBackground")
    self.noBack = config.getParameter("noBack")
    self.targetDistance = config.getParameter("targetDistance")
    self.timeToLive = config.getParameter("timeToLive")
end

function nearTarget()
    if self.targetPosition then
        local xDist, yDist = table.unpack(world.distance(self.targetPosition, mcontroller.position()))
        local dist = math.sqrt(xDist ^ 2 + yDist ^ 2)
        if dist < 1.5 then
            return true
        else
            return false
        end
    else
        return false
    end
end

function checkBackground()
    local intPos = self.targetPosition or mcontroller.position()
    intPos = {math.floor(intPos[1] + 0.5), math.floor(intPos[2] + 0.5)}
    return self.noBack or (world.tileIsOccupied(intPos, false, true) or world.tileIsOccupied(intPos, true, true))
end

function checkPlatforms()
    local intPos = mcontroller.position()
    intPos = {math.floor(intPos[1] + 0.5), math.floor(intPos[2] + 0.5)}
    return world.tileIsOccupied(intPos, true, true)
end

function update(dt)
    if not self.timeToLiveTimer then self.timeToLiveTimer = self.timeToLive end
    self.timeToLiveTimer = math.max(self.timeToLiveTimer - dt, 0)
    if self.targetPosition and ((not self.checkBackground) or checkBackground()) then projectile.setTimeToLive(0.5) end
    if self.ownerId and world.entityExists(self.ownerId) then
        if self.targetPosition and (not self.checkBackground) then mcontroller.applyParameters({collisionEnabled = false}) end
        if nearTarget() and ((not self.checkBackground) or checkBackground()) then
            mcontroller.setVelocity({0, 0})
            -- mcontroller.approachVelocity({0, 0}, 125)
        end
        if mcontroller.stickingDirection() then
            projectile.setTimeToLive(0.5)
        elseif nearTarget() and ((not self.checkBackground) or checkBackground()) then
            projectile.setTimeToLive(0.5)
        elseif self.breakOnSlipperyCollision and mcontroller.isColliding() then
            kill()
        else
            if self.timeToLiveTimer == 0 then
                projectile.setTimeToLive(0.5)
                mcontroller.setVelocity({0, 0})
                if not ((not self.checkBackground) or checkBackground()) then
                    kill()
                end
            end
            -- Inferion's homing grapple script
            -- local dir = math.atan(mcontroller.velocity()[2],mcontroller.velocity()[1])
            -- local speed = vec2.mag(mcontroller.velocity())
            -- local ttl = projectile.timeToLive()
            -- local endPoint = vec2.add(vec2.mul({math.cos(dir),math.sin(dir)},speed * ttl),mcontroller.position())
            -- if not world.lineCollision(mcontroller.position(),endPoint) then
            --   local i = 1
            --   local maxChecks = 400
            --   local dirChange = 0.025
            --   local newDir = dir
            --   while not world.lineCollision(mcontroller.position(),endPoint) do
            --     if i % 2 == 0 then
            --       newDir = dir + dirChange * i
            --     else
            --       newDir = dir - dirChange * i
            --     end
            --     endPoint = vec2.add(vec2.mul({math.cos(newDir),math.sin(newDir)},speed * ttl),mcontroller.position())
            --     if i > maxChecks then
            --       kill()
            --       break
            --     end
            --     i = i + 1
            --   end
            --   local controlAmount = 0.1
            --   newVel = vec2.mul({math.cos(newDir),math.sin(newDir)},speed)
            --   mcontroller.setVelocity(newVel)
            -- end
            -- world.debugLine(mcontroller.position(),endPoint,"green")
        end
    else
        kill()
    end
end

function anchored(checkNearTarget, checkBack)
    if checkNearTarget then
        return mcontroller.stickingDirection() or nearTarget() or self.timeToLiveTimer == 0
    elseif checkBack then
        return mcontroller.stickingDirection() or ((nearTarget() or self.timeToLiveTimer == 0) and checkBackground())
    else
        return mcontroller.stickingDirection()
    end
end

function kill() self.dead = true end

function shouldDestroy()
    if self.targetPosition then
        if checkBackground() or not self.checkBackground then
            return self.dead
        else
            return self.dead or projectile.timeToLive() <= 0
        end
    else
        return self.dead or projectile.timeToLive() <= 0
    end
end

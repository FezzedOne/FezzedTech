require "/scripts/util.lua"
require "/scripts/status.lua"

function init()
  self.debug = true

  self.aimAngle = 0
  self.aimDirection = 1

  self.active = false
  self.cooldownTimer = config.getParameter("cooldownTime")
  self.activeTimer = 0

  self.level = config.getParameter("level", 1)
  self.baseShieldHealth = config.getParameter("baseShieldHealth", 1)
  self.knockback = config.getParameter("knockback", 0)
  self.perfectBlockDirectives = config.getParameter("perfectBlockDirectives", "")
  self.perfectBlockTime = config.getParameter("perfectBlockTime", 0.2)
  self.minActiveTime = config.getParameter("minActiveTime", 0)
  self.cooldownTime = config.getParameter("cooldownTime")
  self.forceWalk = config.getParameter("forceWalk", false)
  self.jumpFireMode = config.getParameter("jumpFireMode") or nil

  animator.setGlobalTag("directives", "")
  animator.setAnimationState("shield", "idle")
  activeItem.setOutsideOfHand(true)

  self.stances = config.getParameter("stances")
  setStance(self.stances.idle)

  updateAim()
end

function update(dt, fireMode, shiftHeld)
  if fireMode ~= "primary" and fireMode ~= "alt" then
    if math.__jumpFiring and self.jumpFireMode then
      fireMode = self.jumpFireMode
    end
  end

  if fireMode == "primary" or fireMode == "alt" then
    math.__weaponFiring = true
  end

  self.cooldownTimer = math.max(0, self.cooldownTimer - dt)

  if not self.active
      and fireMode == "primary"
      and self.cooldownTimer == 0
      and status.resourcePositive("shieldStamina") then
    raiseShield()
  end

  if self.active then
    self.activeTimer = self.activeTimer + dt

    self.damageListener:update()

    if status.resourcePositive("perfectBlock") then
      animator.setGlobalTag("directives", self.perfectBlockDirectives)
    else
      animator.setGlobalTag("directives", "")
    end

    if self.forceWalk then
      mcontroller.controlModifiers({ runningSuppressed = true })
    end

    if (fireMode ~= "primary" and self.activeTimer >= self.minActiveTime) or not status.resourcePositive("shieldStamina") then
      lowerShield()
    end
  end

  updateAim()
  if self.stance then
    if self.stance.invisible then
      activeItem.setHoldingItem(false)
    else
      activeItem.setHoldingItem(true)
    end
    math.__canFlyWithItem = self.stance.canFlyWithItem and (activeItem.callOtherHandScript("dwCanFlyWithItem") ~= false)
    math.__isStable = self.stance.isStable or activeItem.callOtherHandScript("dwIsStable")
  else
    math.__canFlyWithItem = false
    math.__isStable = activeItem.callOtherHandScript("dwIsStable")
  end
end

function uninit()
  status.clearPersistentEffects(activeItem.hand() .. "Shield")
  activeItem.setItemShieldPolys({})
  activeItem.setItemDamageSources({})
  math.__isStable = nil
  math.__canFlyWithItem = nil
end

function updateAim()
  local isPrimary = activeItem.hand() == "primary"
  local otherHandAiming = false
  local altAiming = false
  local altIsInvisible = false
  local aimAngle, aimDirection = activeItem.aimAngleAndDirection(0, activeItem.ownerAimPosition())

  if self.stance.allowRotate then
    self.aimAngle = aimAngle
  end
  activeItem.setArmAngle(self.aimAngle + self.relativeArmRotation)

  if isPrimary then
    -- Slave the shield to the primary hand item by default.
    if self.stance.allowFlip then
      local altAimDirection = activeItem.callOtherHandScript("dwAimDirection")
      if activeItem.callOtherHandScript("dwDisallowFlip") or (not self.stance.primaryFlip) then
        if altAimDirection then
          otherHandAiming = true
          self.aimDirection = altAimDirection
        else
          otherHandAiming = false
          self.aimDirection = aimDirection
        end
      else
        altAiming = altAimDirection or true
        self.aimDirection = aimDirection
      end
    end
    altIsInvisible = activeItem.callOtherHandScript("dwIsInvisible") or (not player.altHandItem())
  elseif self.stance.allowFlip then
    -- Slave the shield to the primary hand item.
    local primaryAimDirection = activeItem.callOtherHandScript("dwAimDirection")
    if primaryAimDirection then
      otherHandAiming = true
      self.aimDirection = primaryAimDirection
    else
      self.aimDirection = aimDirection
    end
  end

  local rawXVel = mcontroller.xVelocity()
  local xVel = math.abs(rawXVel)
  local moving = xVel ~= 0

  if self.stance.invisible then
    if not otherHandAiming then
      if altAiming and (not altIsInvisible) then
        activeItem.setFacingDirection(aimDirection)
        if type(altAiming) == "number" then
          self.aimDirection = altAiming
        end
      elseif moving then
        local movingAimDirection = rawXVel >= 0 and 1 or -1
        activeItem.setFacingDirection(movingAimDirection)
        self.aimDirection = movingAimDirection
      end
    else
      activeItem.setFacingDirection(self.aimDirection)
      if altAiming then
        self.aimDirection = altAiming
      elseif moving then
        local movingAimDirection = rawXVel >= 0 and 1 or -1
        self.aimDirection = movingAimDirection
      end
    end
  else
    activeItem.setFacingDirection(self.aimDirection)

    activeItem.setFrontArmFrame(self.stance.frontArmFrame or "rotation")
    activeItem.setBackArmFrame(self.stance.backArmFrame or "rotation")
  end

  animator.setGlobalTag("hand", isNearHand() and "near" or "far")
  activeItem.setOutsideOfHand(not self.active or isNearHand())
end

function isNearHand()
  return (activeItem.hand() == "primary") == (self.aimDirection < 0)
end

function setStance(stance)
  self.stance = stance
  self.relativeShieldRotation = util.toRadians(stance.shieldRotation) or 0
  self.relativeArmRotation = util.toRadians(stance.armRotation) or 0
end

function raiseShield()
  setStance(self.stances.raised)
  animator.setAnimationState("shield", "raised")
  animator.playSound("raiseShield")
  self.active = true
  self.activeTimer = 0
  status.setPersistentEffects(activeItem.hand() .. "Shield", { { stat = "shieldHealth", amount = shieldHealth() } })
  local shieldPoly = animator.partPoly("shield", "shieldPoly")
  activeItem.setItemShieldPolys({ shieldPoly })

  if self.knockback > 0 then
    local knockbackDamageSource = {
      poly = shieldPoly,
      damage = 0,
      damageType = "Knockback",
      sourceEntity = activeItem.ownerEntityId(),
      team = activeItem.ownerTeam(),
      knockback = self.knockback,
      rayCheck = true,
      damageRepeatTimeout = 0.25
    }
    activeItem.setItemDamageSources({ knockbackDamageSource })
  end

  self.damageListener = damageListener("damageTaken", function(notifications)
    for _, notification in pairs(notifications) do
      if notification.hitType == "ShieldHit" then
        if status.resourcePositive("perfectBlock") then
          animator.playSound("perfectBlock")
          animator.burstParticleEmitter("perfectBlock")
          refreshPerfectBlock()
        elseif status.resourcePositive("shieldStamina") then
          animator.playSound("block")
        else
          animator.playSound("break")
        end
        animator.setAnimationState("shield", "block")
        return
      end
    end
  end)

  refreshPerfectBlock()
end

function refreshPerfectBlock()
  local perfectBlockTimeAdded = math.max(0,
    math.min(status.resource("perfectBlockLimit"), self.perfectBlockTime - status.resource("perfectBlock")))
  status.overConsumeResource("perfectBlockLimit", perfectBlockTimeAdded)
  status.modifyResource("perfectBlock", perfectBlockTimeAdded)
end

function lowerShield()
  setStance(self.stances.idle)
  animator.setGlobalTag("directives", "")
  animator.setAnimationState("shield", "idle")
  animator.playSound("lowerShield")
  self.active = false
  self.activeTimer = 0
  status.clearPersistentEffects(activeItem.hand() .. "Shield")
  activeItem.setItemShieldPolys({})
  activeItem.setItemDamageSources({})
  self.cooldownTimer = self.cooldownTime
end

function shieldHealth()
  return self.baseShieldHealth * root.evalFunction("shieldLevelMultiplier", self.level)
end

-- used for cross-hand communication while dual wielding
function dwAimDirection()
  if self then
    return self.aimDirection
  end
end

function dwDisallowFlip()
  if self and self.stance then
    return not self.stance.allowFlip
  end

  return false
end

function dwIsInvisible()
  if self and self.stance then
    return self.stance.invisible
  end

  return false
end

function dwIsStable()
  if self and self.stance then
    return self.stance.isStable
  end

  return nil
end

function dwCanFlyWithItem()
  if self and self.stance then
    return self.stance.canFlyWithItem or false
  end

  return false
end

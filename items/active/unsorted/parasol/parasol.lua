function init()
  if config.getParameter("isPoser") then
    require("/scripts/poser.lua");
    poserInit(); update = poserUpdate; uninit = poserUninit
  else
    self.switchTime = config.getParameter("switchTime")
    self.switchTimer = 0
    animator.rotateGroup("parasol", toRadians(-65), true)
    updateAim()
  end
end

function update(dt, fireMode, shiftHeld)
  if not ( mcontroller.groundMovement() or mcontroller.liquidMovement() ) then
    self.switchTimer = math.min(self.switchTimer + dt, self.switchTime)
  else
    self.switchTimer = math.max(0, self.switchTimer - dt)
  end
  if self.switchTimer == self.switchTime then
    animator.setAnimationState("parasol", "open")
    if mcontroller.falling() then
      mcontroller.controlParameters(config.getParameter("fallingParameters"))
      mcontroller.setYVelocity(math.max(mcontroller.yVelocity(), config.getParameter("maxFallSpeed")))
    end
  else
    animator.setAnimationState("parasol", "close")
  end
  updateAim()
end

function updateAim()
  self.oldXPos = self.oldXPos or mcontroller.position()[1]
  _, self.facingDirection = activeItem.aimAngleAndDirection(0, activeItem.ownerAimPosition())
  local posDiff = mcontroller.position()[1] - self.oldXPos
  if math.abs(posDiff) >= 0.01 and (not (mcontroller.groundMovement() or mcontroller.liquidMovement())) then
    self.facingDirection = posDiff >= 0 and 1 or -1
  end
  self.oldXPos = mcontroller.position()[1]
  activeItem.setFacingDirection(self.facingDirection)
  local armAngle = toRadians(interpolateSigmoid(self.switchTimer / self.switchTime, config.getParameter("idleRotation"), config.getParameter("activeRotation")))
  if mcontroller.falling() and self.switchTimer == self.switchTime then
    armAngle = armAngle + mcontroller.velocity()[1] / 100 * self.facingDirection
  end
  activeItem.setArmAngle(armAngle)
end

function toRadians(degrees)
  return (degrees / 180) * math.pi
end

function interpolateSigmoid(offset, value1, value2)
  local sigmoidFactor = sigmoid(12 * (offset - 0.5))
  return value1 + sigmoidFactor * (value2 - value1)
end

function sigmoid(value)
  return 1 / (1 + math.exp(-value));
end

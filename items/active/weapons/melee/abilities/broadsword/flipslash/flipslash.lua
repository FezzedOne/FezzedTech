require "/scripts/util.lua"
require "/scripts/status.lua"
require "/scripts/poly.lua"
require "/items/active/weapons/weapon.lua"

FlipSlash = WeaponAbility:new()

function FlipSlash:init()
    self.cooldownTimer = self.cooldownTime
    if self.isPhantomItem then math.__gliderFiring = false end
    math.__isGlider = self.isGlider or nil
end

function FlipSlash:update(dt, fireMode, shiftHeld)
    math.__isGlider = self.isGlider or nil

    WeaponAbility.update(self, dt, fireMode, shiftHeld)

    self.cooldownTimer = math.max(0, self.cooldownTimer - self.dt)

    if not self.weapon.currentAbility and
      ((self.cooldownTimer == 0 and self.fireMode == (self.activatingFireMode or self.abilitySlot) and (self.energyUsage == 0 or mcontroller.onGround()) and -- "alt"
        not status.statPositive("activeMovementAbilities")) or
        (self.isPhantomItem and (self.isParawing or not (mcontroller.groundMovement() or mcontroller.liquidMovement())))) and
      status.overConsumeResource("energy", self.energyUsage) then self:setState(self.windup) end

    if self.isPhantomItem then
        math.__gliderFiring = fireMode == "alt" or fireMode == "primary"
        if not math.__gliderActive then item.consume(1) end
    end
end

function FlipSlash:windup()
    self.weapon:setStance(self.stances.windup)

    if not self.isPhantomItem then status.setPersistentEffects("weaponMovementAbility", {{stat = "activeMovementAbilities", amount = 1}}) end

    util.wait(self.stances.windup.duration, function(dt) mcontroller.controlCrouch() end)

    self:setState(self.flip)
end

function FlipSlash:flip()
    self.weapon:setStance(self.stances.flip)
    self.weapon:updateAim()

    animator.setAnimationState("swoosh", "flip")
    animator.playSound(self.fireSound or "flipSlash")
    animator.setParticleEmitterActive("flip", true)

    self.flipTime = self.rotations * self.rotationTime
    self.flipTimer = 0

    self.jumpTimer = self.jumpDuration

    while self.flipTimer < self.flipTime do
        math.__holdingGlider = self.energyUsage == 0

        self.flipTimer = self.flipTimer + self.dt

        mcontroller.controlParameters(self.flipMovementParameters)

        if self.jumpTimer > 0 then
            self.jumpTimer = self.jumpTimer - self.dt
            mcontroller.setVelocity({self.jumpVelocity[1] * self.weapon.aimDirection, self.jumpVelocity[2]})
        end

        local damageArea = partDamageArea("swoosh")
        self.weapon:setDamage(self.damageConfig, damageArea, self.fireTime)

        mcontroller.setRotation(-math.pi * 2 * self.weapon.aimDirection * (self.flipTimer / self.rotationTime))

        if self.isPhantomItem and (not self.isParawing) and (mcontroller.groundMovement() or mcontroller.liquidMovement()) then
            self.flipTimer = self.flipTime
        end

        coroutine.yield()
    end

    status.clearPersistentEffects("weaponMovementAbility")

    math.__holdingGlider = false

    animator.setAnimationState("swoosh", "idle")
    mcontroller.setRotation(0)
    animator.setParticleEmitterActive("flip", false)
    self.cooldownTimer = self.cooldownTime
end

function FlipSlash:uninit()
    math.__holdingGlider = false
    status.clearPersistentEffects("weaponMovementAbility")
    animator.setAnimationState("swoosh", "idle")
    mcontroller.setRotation(0)
    animator.setParticleEmitterActive("flip", false)
    if self.isPhantomItem then
        math.__gliderFiring = false
        item.consume(1)
    end
    math.__isGlider = nil
end

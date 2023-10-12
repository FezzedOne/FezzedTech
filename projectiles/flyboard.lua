require("/scripts/vec2.lua")

function init() end

function update(dt)
    if (projectile.sourceEntity() and not world.entityExists(projectile.sourceEntity())) or not math.__flyboardActive then projectile.die() end

    if math.__playerMController then
      local playerPos = math.__playerMController.position()
      local adjPos = vec2.sub(playerPos, {0, 0})
      mcontroller.setPosition(adjPos)
    end
end

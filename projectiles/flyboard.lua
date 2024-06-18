require("/scripts/vec2.lua")

function init()
  require("/scripts/util/globals.lua")
end

function update(dt)
    if (projectile.sourceEntity() and not world.entityExists(projectile.sourceEntity())) or not globals.flyboardActive then projectile.die() end

    if globals.playerMController then
      local playerPos = globals.playerMController.position()
      local adjPos = vec2.sub(playerPos, {0, 0})
      mcontroller.setPosition(adjPos)
    end
end

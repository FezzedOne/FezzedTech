function init()
    require("/scripts/util/globals.lua")

    movementArray = {false, false, false, false, false, false, true}
    message.setHandler("checkJumping", function(_, sameClient) if sameClient then return movementArray end end)

    globals.tech = jobject({ args = jobject({ moves = jarray({}) }) })

    self.multiJumpCount = config.getParameter("multiJumpCount")
    self.multiJumpModifier = config.getParameter("multiJumpModifier")

    refreshJumps()
end

function update(args)
    local techTable = globals.tech
    techTable.args = args
    globals.tech = techTable
    movementArray = {
        args.moves.jump and not args.moves.down, args.moves.left, args.moves.right, args.moves.up, args.moves.down, args.moves.jump, args.moves.run
    }

    local jumpActivated = args.moves["jump"] and not self.lastJump
    self.lastJump = args.moves["jump"]

    updateJumpModifier()

    if jumpActivated and canMultiJump() then
        doMultiJump()
    else
        if mcontroller.groundMovement() or mcontroller.liquidMovement() then refreshJumps() end
    end

    if globals.resetJumps and globals.isParkourTech then
        globals.resetJumps = false
        refreshJumps()
    end
end

-- after the original ground jump has finished, start applying the new jump modifier
function updateJumpModifier()
    if self.multiJumpModifier then
        if not self.applyJumpModifier and not mcontroller.jumping() and not mcontroller.groundMovement() then self.applyJumpModifier = true end

        if self.applyJumpModifier then mcontroller.controlModifiers({airJumpModifier = self.multiJumpModifier}) end
    end
end

function canMultiJump()
    return (not globals.gliderActive) and ((globals.infJumps and globals.isParkourTech) or self.multiJumps > 0) and not mcontroller.jumping() and
             not mcontroller.canJump() and not mcontroller.liquidMovement() and not status.statPositive("activeMovementAbilities") and
             math.abs(world.gravity(mcontroller.position())) > 0
end

function doMultiJump()
    mcontroller.controlJump(true)
    mcontroller.setYVelocity(math.max(0, mcontroller.yVelocity()))
    self.multiJumps = self.multiJumps - 1
    if globals.shadowRun then
        animator.setSoundPool("multiJumpSound", {"/sfx/tech/tech_superjump.ogg"})
    elseif globals.fezTech then
        animator.setSoundPool(
          "multiJumpSound", {
              "/sfx/projectiles/throw_item.ogg", "/sfx/projectiles/throw_item_big.ogg", "/sfx/projectiles/throw_item_huge.ogg",
              "/sfx/projectiles/throw_item_small.ogg"
          }
        )
    else
        animator.setSoundPool("multiJumpSound", {"/sfx/tech/tech_doublejump.ogg"})
        animator.burstParticleEmitter("multiJumpParticles")
    end
    animator.playSound("multiJumpSound")
end

function refreshJumps()
    self.multiJumps = self.multiJumpCount
    self.applyJumpModifier = false
end

-- Script to initialise globals. Intended to be invoked via `require` in `init`.
if not (entity or player or projectile) then
    globals = {}
    goto skipGlobals
end
local uuid = player and player.uniqueId()
    or (projectile.sourceEntity and world.entityUniqueId(projectile.sourceEntity()) or entity.uniqueId())
if not uuid then
    globals = {}
    goto skipGlobals
end
math.__fezTech = type(math.__fezTech) == "table" and math.__fezTech or {}
math.__fezTech[uuid] = type(math.__fezTech[uuid]) == "table" and math.__fezTech[uuid] or {}
globals = math.__fezTech[uuid]
::skipGlobals::
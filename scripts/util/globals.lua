if not (entity or player or projectile) then
	globals = {};
	goto endGlobals;
end;
local uuid = player and player.uniqueId() or (projectile.sourceEntity and world.entityUniqueId(projectile.sourceEntity()) or entity.uniqueId());
if not uuid then
	globals = {};
	goto endGlobals;
end;
if xsb and world.getGlobal then
	goto xSBglobals;
end;
math.__fezTech = type(math.__fezTech) == "table" and math.__fezTech or {};
math.__fezTech[uuid] = type(math.__fezTech[uuid]) == "table" and math.__fezTech[uuid] or {};
globals = math.__fezTech[uuid];
goto endGlobals;
::xSBglobals::;
local newGlobalTable = {};
local newGlobalMetatable = {
	__index = function(_, key)
		local globals = world.getGlobal("fezzedTech");
		globals[uuid] = globals[uuid] or jobject({});
		return globals[uuid][key];
	end,
	__newindex = function(_, key, value)
		local globals = world.getGlobal("fezzedTech");
		globals[uuid] = globals[uuid] or jobject({});
		globals[uuid][key] = value;
		world.setGlobal("fezzedTech", globals);
	end
};
setmetatable(newGlobalTable, newGlobalMetatable);
globals = newGlobalTable;
::endGlobals::;

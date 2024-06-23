if tech then
	message.setHandler({
		name = "setParentOffset",
		passName = false,
		localOnly = true
	}, function(offset)
		tech.setParentOffset(offset);
	end);
end;
if not (entity or player or projectile) then
	globals = {};
	goto endGlobals;
end;
local uuid = player and player.uniqueId() or (projectile and world.entityUniqueId(projectile.sourceEntity()) or entity.uniqueId());
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
		local xSBglobals = world.getGlobal("fezzedTech") or jobject({});
		xSBglobals[uuid] = xSBglobals[uuid] or jobject({});
		return xSBglobals[uuid][key];
	end,
	__newindex = function(_, key, value)
		local xSBglobals = world.getGlobal("fezzedTech") or jobject({});
		xSBglobals[uuid] = xSBglobals[uuid] or jobject({});
		xSBglobals[uuid][key] = value;
		world.setGlobal("fezzedTech", xSBglobals);
	end
};
setmetatable(newGlobalTable, newGlobalMetatable);
globals = newGlobalTable;
::endGlobals::;

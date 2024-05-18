-- Function hook stuff.
function attachHook(target, func)
    local original = type(_ENV[target]) == "function" and _ENV[target] or (function(...) end)
    _ENV[target] = function(...)
        original(...)
        return func(...)
    end
end

function frontHook(target, func)
    local original = type(_ENV[target]) == "function" and _ENV[target] or (function(...) end)
    _ENV[target] = function(...)
        local funcRet = table.pack(func(...))
        original(...)
        return table.unpack(funcRet)
    end
end

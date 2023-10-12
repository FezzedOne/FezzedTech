-- shoutout to Silverfeelin for telling me you can re-define functions lol
function attachHook(target, func)
    local original = type(_ENV[target]) == "function" and _ENV[target] or (function(...) end)
    _ENV[target] = function(...)
        original(...)
        return func(...)
    end
end

function frontHook(target, func)
    local original = type(_ENV[target]) == "function" and _ENV[target] or (function(...) end)
    _ENV[target] = function(...) return original(func(...)) end
end

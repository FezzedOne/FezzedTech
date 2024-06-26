function init()
    require("/scripts/util/globals.lua")

    movementArray = { [1] = false, [2] = false, [3] = false, [4] = false, [5] = false, [6] = false, [7] = true }
    message.setHandler("checkJumping", function(_, sameClient)
        if sameClient then return movementArray end
    end)

    globals.tech = jobject({ args = jobject({ moves = jarray({}) }) })
end
function uninit() end
function update(args)
    local techTable = globals.tech or jobject{}
    techTable.args = args
    globals.tech = techTable

    movementArray = {
        [1] = args.moves.jump and not args.moves.down,
        [2] = args.moves.left,
        [3] = args.moves.right,
        [4] = args.moves.up,
        [5] = args.moves.down,
        [6] = args.moves.jump,
        [7] = args.moves.run,
    }
end

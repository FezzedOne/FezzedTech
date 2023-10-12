function init()
    movementArray = {false, false, false, false, false, false, true}
    message.setHandler(
      "checkJumping", function(_, sameClient)
          if sameClient then
              return movementArray
          end
      end
    )

    math.__tech = tech
    math.__tech.args = { moves = {} }
    math.__status = status
end
function uninit() end
function update(args)
    math.__tech.args = args

    -- jumpMove = (status.statusProperty("flight") and (not (mcontroller.groundMovement() or mcontroller.liquidMovement())) and
    --              (args.moves.left or args.moves.right or args.moves.up or args.moves.down)) or args.moves["jump"]
    movementArray = {args.moves.jump and not args.moves.down, args.moves.left, args.moves.right, args.moves.up, args.moves.down, args.moves.jump, args.moves.run}
end

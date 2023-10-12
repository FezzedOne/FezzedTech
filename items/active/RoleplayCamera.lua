function init()
	
	local Camera = math.__camera

	script.setUpdateDelta(0)

	if Camera and Camera.swapItem then

		activeItem.setCameraFocusEntity(Camera.targetEntity)
		Camera.swapItem()

	end

end
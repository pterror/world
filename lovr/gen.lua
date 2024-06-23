local mod = {}

local sky

mod.sky = function()
	if sky then return sky end
	local parts = {} --[[@type string[] ]]
	local blob = lovr.data.newBlob(table.concat(parts), "sky.hdr")
	sky = lovr.graphics.newTexture(blob)
	return sky
end

return mod

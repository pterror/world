local gen = require("lovr.gen")

--[[make luals happy]]
if false then
	--[[@diagnostic disable-next-line: lowercase-global]]
	lovr = lovr
end

local sky

lovr.load = function()
	sky = lovr.graphics.newTexture(gen.sky())
end

lovr.draw = function(pass)
	pass:skybox(sky)
end

local mod = {}

local plane_thickness = 0.05
local p = plane_thickness
local hp = p / 2

--[[@class world_vr_room]]
local Room = {}
Room.__index = Room

--[[@class world_vr_room_options]]
--[[@field color number]]

--[[@param x number]]
--[[@param y number]]
--[[@param z number]]
--[[@param width number]]
--[[@param height number]]
--[[@param depth number]]
--[[@param options? world_vr_room_options]]
Room.new = function(self, x, y, z, width, height, depth, options)
	options = options or {}
	local color = options.color or 0x808080
	--[[@class world_vr_room]]
	local result = {
		x = x,
		y = y,
		z = z,
		width = width,
		height = height,
		depth = depth,
		color = color,
		colliders = {} --[[@type lovr_collider[] ]]
	}
	return setmetatable(result, self)
end

--[[@param context world_vr_context]]
Room.initialize = function(self, context)
	local world = context.world
	local x, y, z = self.x, self.y, self.z
	local w, h, d = self.width, self.height, self.depth
	--[[@diagnostic disable-next-line: inject-field]]
	self.colliders = {
		world:newBoxCollider(x - hp, y + h / 2, z + d / 2, p, h, d),
		world:newBoxCollider(x + w, y + h / 2, z + d / 2, p, h, d),
		world:newBoxCollider(x + w / 2, y - hp, z + d / 2, w, p, d),
		world:newBoxCollider(x + w / 2, y + h, z + d / 2, w, p, d),
		world:newBoxCollider(x + w / 2, y + h / 2, z - hp, w, h, p),
		world:newBoxCollider(x + w / 2, y + h / 2, z + d, w, h, p),
	}
	for _, collider in ipairs(self.colliders) do
		collider:setKinematic(true)
	end
end

--[[@param pass lovr_pass]]
Room.draw = function(self, pass)
	pass:setColor(self.color)
	local x, y, z = self.x, self.y, self.z
	local w, h, d = self.width, self.height, self.depth
	pass:box(x - hp, y + h / 2, z + d / 2, p, h, d)
	pass:box(x + w, y + h / 2, z + d / 2, p, h, d)
	pass:box(x + w / 2, y - hp, z + d / 2, w, p, d)
	pass:box(x + w / 2, y + h, z + d / 2, w, p, d)
	pass:box(x + w / 2, y + h / 2, z - hp, w, h, p)
	pass:box(x + w / 2, y + h / 2, z + d, w, h, p)
end

--[[@param x number]]
--[[@param y number]]
--[[@param z number]]
--[[@param width number]]
--[[@param height number]]
--[[@param depth number]]
--[[@param options? world_vr_room_options]]
mod.new = function(x, y, z, width, height, depth, options) return Room:new(x, y, z, width, height, depth, options) end

return mod

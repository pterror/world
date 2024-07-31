LovrUIRoot = "deps/"
local UI = require("lovr.ui")
local IK = require("lovr.fabrik")

--[=[
local gen = require("lovr.gen")
local model
function lovr.load()
	local bytes = gen.model_from_tris({
		{ 0, 1, 3 }, --[[-x left]]
		{ 0, 3, 2 },
		{ 0, 1, 5 }, --[[-y bottom]]
		{ 0, 5, 4 },
		{ 0, 2, 6 }, --[[-z back]]
		{ 0, 6, 4 },
		{ 4, 5, 7 }, --[[x right]]
		{ 4, 7, 6 },
		{ 2, 3, 7 }, --[[y top]]
		{ 2, 7, 6 },
		{ 1, 3, 7 }, --[[z front]]
		{ 1, 7, 5 },
	}, {
		{ x = -0.5, y = -0.5, z = -0.5 }, --[[0]]
		{ x = -0.5, y = -0.5, z = 0.5 }, --[[1]]
		{ x = -0.5, y = 0.5,  z = -0.5 }, --[[2]]
		{ x = -0.5, y = 0.5,  z = 0.5 }, --[[3]]
		{ x = 0.5,  y = -0.5, z = -0.5 }, --[[4]]
		{ x = 0.5,  y = -0.5, z = 0.5 }, --[[5]]
		{ x = 0.5,  y = 0.5,  z = -0.5 }, --[[6]]
		{ x = 0.5,  y = 0.5,  z = 0.5 }, --[[7]]
	})
	model = lovr.graphics.newModel(lovr.data.newBlob(bytes, "cube.glb"))
end

function lovr.draw(pass)
	pass:draw(model, 0, 2, -3, 2)
end
]=]

local world --[[@type lovr_world]]
local player --[[@type lovrx_humanoid]]
local shader --[[@type lovr_shader]]
local basic_shader --[[@type lovr_shader]]
local spherical_harmonics --[[@type lovr_buffer]]
local colliders = {} --[[@type table<{[1]: number,[2]: number,[3]: number,[4]: number,[5]: number,[6]: number}, true>]]

local make_collider = function(...)
	local dims = { ... }
	colliders[dims] = true
	world:newBoxCollider(...):setKinematic(true)
end

local plane_thickness = 0.05

--[[@param x number]]
--[[@param y number]]
--[[@param z number]]
--[[@param w number]]
--[[@param h number]]
--[[@param d number]]
local make_room = function(x, y, z, w, h, d)
	local p = plane_thickness
	local hp = p / 2
	make_collider(x - hp, y + h / 2, z + d / 2, p, h, d)
	make_collider(x + w, y + h / 2, z + d / 2, p, h, d)
	make_collider(x + w / 2, y - hp, z + d / 2, w, p, d)
	make_collider(x + w / 2, y + h, z + d / 2, w, p, d)
	make_collider(x + w / 2, y + h / 2, z - hp, w, h, p)
	make_collider(x + w / 2, y + h / 2, z + d, w, h, p)
end

--[[@param model lovr_model]]
--[[@param name string]]
local match_node = function(model, name)
	name = name:lower():gsub("_", " ")
	for i = 1, model:getNodeCount() do
		local node_name = model:getNodeName(i):lower():gsub("_", " ")
		if node_name:match(name) then
			return i
		end
	end
end

--[[@class lovrx_humanoid]]
local Humanoid = {}
Humanoid.__index = Humanoid
--[[@param opts { model: string|lovr_blob|lovr_model_data; position?: lovr_vec3; scale?: number; orientation?: lovr_quat }]]
Humanoid.new = function(self, opts)
	local model = lovr.graphics.newModel(opts.model)
	local left_wrist_id = match_node(model, "left wrist")
	local right_wrist_id = match_node(model, "right wrist")
	local left_ankle_id = match_node(model, "left ankle")
	local right_ankle_id = match_node(model, "right ankle")
	local position = opts.position or Vec3(0, 0, 0)
	local orientation = opts.orientation or Quat(0, 0, 1, 0)
	local scale = opts.scale or 1
	--[[@type table<world_vr_ik_id, world_vr_ik>]]
	local ik = {
		left_arm = {
			dirty = false,
			target = Vec3(vec3(model:getNodePosition(left_wrist_id))),
			start_id = match_node(model, "left arm"),
			end_id = left_wrist_id,
		},
		right_arm = {
			dirty = false,
			target = Vec3(vec3(model:getNodePosition(right_wrist_id))),
			start_id = match_node(model, "right arm"),
			end_id = right_wrist_id,
		},
		left_leg = {
			dirty = false,
			target = Vec3(vec3(model:getNodePosition(left_ankle_id))),
			start_id = match_node(model, "left leg"),
			end_id = left_ankle_id,
		},
		right_leg = {
			dirty = false,
			target = Vec3(vec3(model:getNodePosition(right_ankle_id))),
			start_id = match_node(model, "right leg"),
			end_id = right_ankle_id,
		},
	}
	--[[@class lovrx_humanoid]]
	local result = {
		model = model,
		ik = ik,
		position = position,
		orientation = orientation,
		scale = scale,
		ik_options = {
			max_iterations = 10,
			epsilon = 0.0001,
		},
	}
	return setmetatable(result, self)
end

--[[@alias world_vr_ik_id "left_arm"|"right_arm"|"left_leg"|"right_leg"]]
--[[@class world_vr_ik]]
--[[@field dirty boolean]]
--[[@field target lovr_vec3]]
--[[@field start_id integer]]
--[[@field end_id integer]]

--[[@param limb "left_arm"|"right_arm"|"left_leg"|"right_leg"]]
--[[@param target lovr_vec3]]
Humanoid.poseLimb = function(self, limb, target)
	local ik  = self.ik[limb]
	ik.dirty  = true
	ik.target = Vec3(target)
end

--[[@param pass lovr_pass]]
Humanoid.draw = function(self, pass)
	local target = vec3(lovr.headset.getPosition("hand/left"))
	pass:sphere(target, 0.1)
	local transform = mat4(self.position, self.orientation):scale(self.scale)
	self:poseLimb("left_arm", transform:invert() * target)
	pass:setColor(0x40d0d0)
	local lh = vec3(self.position) + vec3(self.model:getNodePosition("Left wrist")) * self.scale
	pass:sphere(lh, 0.1)
	for _, ik in pairs(self.ik) do
		if ik.dirty then
			ik.dirty = false
			IK.update_model_chain(self.model, ik.target, ik.start_id, ik.end_id, self.ik_options)
		end
	end
	pass:setColor(0xffffff)
	pass:draw(self.model, self.position, self.scale, self.orientation)
end

function lovr.load()
	UI.Init()
	--[[@diagnostic disable-next-line: missing-parameter]]
	world = lovr.physics.newWorld()
	player = Humanoid:new({
		model = "saves/meow.glb",
		position = Vec3(0, 0, -3),
		--[[TODO: temporary just to make sure everything works with scaling.]]
		scale = 2,
	})
	shader = require("lovr.lighting.pbr")()
	--[[FIXME: phong shading has issues with draw order or something]]
	basic_shader = require("lovr.lighting.basic")()

	--[[ground]]
	-- make_collider(0, -plane_thickness, 0, 50, plane_thickness, 50)
	--[[room]]
	do
		make_room(-5, 0, -5, 10, 5, 10)
	end
	spherical_harmonics = lovr.graphics.newBuffer({ "vec3", layout = "std140" }, {
		{ 0.611764907836914,  0.599504590034485,  0.479980736970901 },
		{ 0.659514904022217,  0.665349841117859,  0.567680120468140 },
		{ 0.451633930206299,  0.450751245021820,  0.355226665735245 },
		{ -0.044383134692907, -0.053154513239861, -0.019974749535322 },
		{ -0.053045745939016, -0.057957146316767, -0.011247659102082 },
		{ 0.485697060823441,  0.490428507328033,  0.397530466318130 },
		{ -0.023690477013588, -0.024272611364722, -0.021886156871915 },
		{ -0.179465517401695, -0.181243389844894, -0.141314014792442 },
		{ -0.144527092576027, -0.143508568406105, -0.122757166624069 }
	})
end

function lovr.update()
	UI.InputInfo()
end

function lovr.draw(pass)
	pass:setColor(0xffffff)
	pass:setCullMode("back")
	pass:setViewCull(true)
	pass:setShader(shader)
	pass:send("sphericalHarmonics", spherical_harmonics)
	player:draw(pass)

	pass:setColor(0x808080)

	pass:setShader(basic_shader)
	for collider in pairs(colliders) do
		local x, y, z, width, height, depth = unpack(collider)
		pass:box(x, y, z, width, height, depth)
	end

	for _, hand in ipairs(lovr.headset.getHands()) do
		local x, y, z = lovr.headset.getPosition(hand)
		pass:sphere(x, y, z, .1)
	end

	local lh_pose = lovr.math.newMat4(player.model:getNodeTransform("Left wrist"))
	lh_pose:rotate(-math.pi / 2, 1, 0, 0)
	UI.NewFrame(pass)
	UI.Begin("window", lh_pose)
	--[[FIXME: where is this :skull:]]
	UI.Label("left wrist")
	UI.End(pass)
	local ui_passes = UI.RenderFrame(pass)
	table.insert(ui_passes, pass)
	return lovr.graphics.submit(ui_passes)
end

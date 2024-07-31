local IK = require("lovr.fabrik")

--[[@diagnostic disable: inject-field]]
local quat_left = Quat(math.pi / 2, 0, 1, 0)

--[[@class world_vr_humanoid_options]]
--[[@field model string|lovr_blob|lovr_model_data]]
--[[@field position? lovr_vec3]]
--[[@field scale? number]]
--[[@field orientation? lovr_quat]]

local mod = {}

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

--[[@class world_vr_humanoid]]
local Humanoid = {}
Humanoid.__index = Humanoid
--[[@param options world_vr_humanoid_options]]
Humanoid.new = function(self, options)
	local model = lovr.graphics.newModel(options.model)
	local left_wrist_id = match_node(model, "left wrist")
	local right_wrist_id = match_node(model, "right wrist")
	local left_ankle_id = match_node(model, "left ankle")
	local right_ankle_id = match_node(model, "right ankle")
	local position = options.position or Vec3(0, 0, 0)
	local orientation = options.orientation or Quat(0, 0, 1, 0)
	local scale = options.scale or 1
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
	--[[@class world_vr_humanoid]]
	local result = {
		model = model,
		ik = ik,
		position = position,
		orientation = orientation,
		scale = scale,
		speed = { walk = 3, strafe = 3, sprint = 10, },
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

--[[@param dt number]]
--[[@param context world_vr_context]]
Humanoid.update = function(self, dt, context)
	--[[player behavior]]
	--[[TODO: rebindable inputs]]
	--[[TODO: move towards camera, not forwards]]
	if context.has_keyboard then
		local is_sprinting = lovr.system.isKeyDown("space")
		local speed = is_sprinting and self.speed.sprint or self.speed.walk
		local strafe_speed = self.speed.strafe
		local facing = self.orientation:direction()
		local left = (quat(self.orientation) * quat_left):direction()
		local delta = vec3()
		if lovr.system.isKeyDown("w") then
			delta = delta + facing * speed * -dt
		end
		if lovr.system.isKeyDown("s") then
			delta = delta + facing * speed * dt
		end
		if lovr.system.isKeyDown("a") then
			delta = delta + left * strafe_speed * -dt
		end
		if lovr.system.isKeyDown("d") then
			delta = delta + left * strafe_speed * dt
		end
		if delta:length() > 0 then
			self.position = Vec3(self.position + delta)
		end
	end
	--[[end player behavior]]
end

--[[@param pass lovr_pass]]
Humanoid.draw = function(self, pass)
	--[[TODO: behaviors]]
	--[[ik behavior]]
	local target = vec3(lovr.headset.getPosition("hand/left"))
	local transform = mat4(self.position, self.orientation):scale(self.scale)
	self:poseLimb("left_arm", transform:invert() * target)
	for _, ik in pairs(self.ik) do
		if ik.dirty then
			ik.dirty = false
			IK.update_model_chain(self.model, ik.target, ik.start_id, ik.end_id, self.ik_options)
		end
	end
	--[[end ik behavior]]
	pass:setColor(0xffffff)
	pass:draw(self.model, self.position, self.scale, self.orientation)
end

--[[@param options world_vr_humanoid_options]]
mod.new = function(options) return Humanoid:new(options) end

return mod

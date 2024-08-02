local IK = require("lovr.fabrik")

--[[FIXME: how to receive the model?]]
--[[conventional ECS says components should hold their own data]]
--[[the issue is that the json has no way of having two references]]
--[[to the same data. { temporaries, objects }?]]

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

--[[@class world_vr_headset_ik]]
local HeadsetIK = {}
HeadsetIK.__index = HeadsetIK
--[[@param options world_vr_headset_ik_options]]
HeadsetIK.new = function(self, options)
	local model = lovr.graphics.newModel(options.model)
	local left_wrist_id = match_node(model, "left wrist")
	local right_wrist_id = match_node(model, "right wrist")
	local left_ankle_id = match_node(model, "left ankle")
	local right_ankle_id = match_node(model, "right ankle")
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
	--[[@class world_vr_headset_ik]]
	local result = {
		model = model,
		ik = ik,
		transform = options.transform or Mat4():identity(),
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
HeadsetIK.poseLimb = function(self, limb, target)
	local ik  = self.ik[limb]
	ik.dirty  = true
	ik.target = Vec3(target)
end

HeadsetIK.update = function(self)
	--[[ik behavior]]
	local left_hand = vec3(lovr.headset.getPosition("hand/left"))
	self:poseLimb("left_arm", mat4(self.transform):invert() * left_hand)
	local right_hand = vec3(lovr.headset.getPosition("hand/right"))
	self:poseLimb("right_arm", mat4(self.transform):invert() * right_hand)
	for _, ik in pairs(self.ik) do
		if ik.dirty then
			ik.dirty = false
			IK.update_model_chain(self.model, ik.target, ik.start_id, ik.end_id, self.ik_options)
		end
	end
	--[[end ik behavior]]
end

--[[@param pass lovr_pass]]
HeadsetIK.draw = function(self, pass)
	pass:setColor(0xffffff)
	pass:draw(self.model, self.transform)
end

--[[@param options world_vr_headset_ik_options]]
mod.new = function(options) return HeadsetIK:new(options) end

return mod

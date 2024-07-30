--[[
	Original GDScript code:
	https://github.com/R3X-G1L6AME5H/FBIKM/
	FBIKM - Inverse Kinematics Manager
	by Nemo Czanderlitch/Nino Čandrlić
	https://godotengine.org/asset-library/asset?user=R3X_G1L
	https://github.com/R3X-G1L6AME5H
]]

local mod = {}

--[[@enum lovrx_fabrik_modifier_flag]]
local modifier     = {
	none = 0,
	bind = 1,
	fork_bind = 2,
	cage_bind = 4,
	solid = 8,
	damped_transform = 16,
	look_at = 32,
}
mod.modifier       = modifier

local quat_zero    = Quat()
local vec3_zero    = Vec3()
local vec3_up      = Vec3(0, 1, 0)
local vec3_forward = Vec3(0, 0, 1)
local vec3_back    = Vec3(0, 0, -1)
local vec3_right   = Vec3(1, 0, 0)
local vec3_left    = Vec3(-1, 0, 0)

--[[@class lovrx_fabrik]]
local Fabrik   = {}
mod.Fabrik     = Fabrik
Fabrik.__index = Fabrik
--[[@param model lovr_model]]
--[[@param nodes lovrx_fabrik_node[] ]]
Fabrik.new = function(self, model, nodes)
	--[[@class lovrx_fabrik]]
	local init = {
		name             = "fabrik",
		skeleton         = model, --[[skeleton to which the changes are applied]]
		position         = vec3_zero,
		bones            = {}, --[[@type table<number, lovrx_fabrik_bone>]]
		roots            = {}, --[[@type number[] ]]
		--[[binds and drivers are solved in hierarchical order]]
		nodes            = nodes, --[[@type lovrx_fabrik_node[] ]]
		--[[all the posible drivers that need to be run]]
		drivers          = {
			chains     = {}, --[[@type lovrx_fabrik_chain_node[] ]]
			poles      = {}, --[[@type lovrx_fabrik_pole_node[] ]]
			look_ats   = {}, --[[@type lovrx_fabrik_look_at_node[] ]]
			binds      = {}, --[[@type lovrx_fabrik_bind_node[] ]]
			fork_binds = {}, --[[@type lovrx_fabrik_fork_bind_node[] ]]
			cage_binds = {}, --[[@type lovrx_fabrik_cage_bind_node[] ]]
		},
		max_iterations   = 5, --[[bigger = more precise = less performant]]
		minimal_distance = 0.01, --[[smaller = more precise = less performant]]
	}
	local result = setmetatable(init, self)
	for id = 1, model:getNodeCount() do result:addBone(model, id) end
	for _, root_id in ipairs(result.roots) do
		for _, child_id in ipairs(model:getNodeChildren(root_id)) do
			result:initializeBoneDirection(child_id)
		end
	end
	result:initialize()
	return result
end
--[[@param model lovr_model]]
--[[@param nodes lovrx_fabrik_node[] ]]
mod.new = function(model, nodes)
	return Fabrik:new(model, nodes)
end

--[[@param bone_id number]]
Fabrik.initializeBoneDirection = function(self, bone_id)
	self.bones[bone_id].start_direction = Vec3(vec3(self.skeleton:getNodePosition(bone_id)) -
		vec3(self.skeleton:getNodePosition(self.skeleton:getNodeParent(bone_id))))
	for _, child_id in ipairs(self.skeleton:getNodeChildren(bone_id)) do
		self:initializeBoneDirection(child_id)
	end
end

--[[@param model lovr_model]]
--[[@param bone_id number]]
Fabrik.addBone = function(self, model, bone_id)
	local parent_id = model:getNodeParent(bone_id)
	local position = Vec3(model:getNodePosition(bone_id))
	local rotation = Quat(model:getNodeOrientation(bone_id))
	local direction = vec3_zero
	local preexisting_children = {} --[[@type number[] ]]
	--[[If a parent exists, immediately solve the distance from it to child, as well as link them]]
	if self.bones[parent_id] then
		direction = vec3(position) - self.bones[parent_id].position
		table.insert(self.bones[parent_id].children, bone_id)
	end
	for child_id, bone in pairs(self.bones) do
		if bone.parent == bone_id then
			table.insert(preexisting_children, child_id)
			bone.start_direction = Vec3(vec3(bone.position) - position)
			bone.length = bone.start_direction:length()
		end
	end
	self.bones[bone_id] = {
		parent              = parent_id,
		children            = preexisting_children,
		position            = position,
		length              = direction:length(),
		length_multiplier   = 1.0,
		rotation            = rotation,
		start_rotation      = rotation,
		start_direction     = Vec3(direction:normalize()),
		weighted_vector_sum = vec3_zero,
		weight_sum          = 0.0,
		modifier_flags      = modifier.none,
	}
	if bone_id == self.skeleton:getRootNode() then
		table.insert(self.roots, bone_id)
		self.bones[bone_id].initial_position = position
	end
end

local deg2rad  = math.pi / 180

--[[@param from lovr_vec3]]
--[[@param to lovr_vec3]]
--[[@param axis lovr_vec3]]
local signed_angle = function(from, to, axis)
	local normal        = vec3(axis):cross(from)
	local d             = 0
	local is_point_over = normal:dot(to) > d
	if is_point_over then
		return from:angle(to)
	else
		return -from:angle(to)
	end
end

--[[@param from lovr_vec3]]
--[[@param to lovr_vec3]]
--[[@param length number]]
local calc_next = function(from, to, length)
	return from + ((to - from):normalize() * length)
end

--[[@param from lovr_vec3]]
--[[@param to lovr_vec3]]
local from_to_rotation = function(from, to)
	local k_cos_theta = from:dot(to)
	local k = math.sqrt(math.pow(from:length(), 2.0) * math.pow(to:length(), 2.0))
	local axis = vec3(from):cross(to)

	if k_cos_theta == -1 then
		--[[180 degree rotation around any orthogonal vector]]
		return quat(1, 0, 0, 0)
	elseif k_cos_theta == 1 then
		return quat(0, 0, 0, 1)
	end

	return quat(axis.x, axis.y, axis.z, k_cos_theta + k):normalize()
end

local rotate_vecs      = { forward = vec3_forward, backward = vec3_back, right = vec3_right, left = vec3_left }
--[[@param pivot lovr_vec3]]
--[[@param target lovr_vec3]]
--[[@param side "forward"|"backward"|"right"|"left"]]
local rotate_along_axis = function(rotation, pivot, target, side)
	local normal = vec3(rotation) * vec3_up
	local d = normal:dot(pivot)
	local p = vec3(target)
	local proj_p = p - vec3(normal) * (normal:dot(p) - d)
	p = vec3(rotation) * rotate_vecs[side] + pivot
	local proj_v = p - vec3(normal) * (normal:dot(p) - d)
	local angle = signed_angle(proj_v - pivot, proj_p - pivot, normal)
	return quat(normal, angle) * rotation
end

--[[@type table<lovrx_fabrik_node_type, fun(self: lovrx_fabrik, node: lovrx_fabrik_node)>]]
local evaluators = {}

--[[@param self lovrx_fabrik]]
--[[@param chain lovrx_fabrik_chain_node]]
evaluators.chain = function(self, chain)
	table.insert(self.drivers.chains, chain)
end

--[[@param self lovrx_fabrik]]
--[[@param pole lovrx_fabrik_pole_node]]
evaluators.pole = function(self, pole)
	table.insert(self.drivers.poles, pole)
end

--[[@param self lovrx_fabrik]]
--[[@param look_at lovrx_fabrik_look_at_node]]
evaluators.look_at = function(self, look_at)
	table.insert(self.drivers.look_ats, look_at)
	self:setBoneModifier(look_at.bone_id, modifier.look_at)
end

--[[no action is needed?]]
evaluators.exaggerator = function() end

--[[@param self lovrx_fabrik]]
--[[@param solidifier lovrx_fabrik_solidifier_node]]
evaluators.solidifier = function(self, solidifier)
	self:setBoneModifier(solidifier.bone_id, modifier.solid)
end

--[[@param self lovrx_fabrik]]
--[[@param damped_transform lovrx_fabrik_damped_transform_node]]
evaluators.damped_transform = function(self, damped_transform)
	self:setBoneModifier(damped_transform.bone_id, modifier.damped_transform,
		damped_transform)
end

--[[@param self lovrx_fabrik]]
--[[@param bind lovrx_fabrik_bind_node]]
evaluators.bind = function(self, bind)
	bind.length_12 = (vec3(self.bones[bind.bone_1].position) - self.bones[bind.bone_2].position)
			:length()
	bind.length_23 = (vec3(self.bones[bind.bone_2].position) - self.bones[bind.bone_3].position)
			:length()
	bind.length_31 = (vec3(self.bones[bind.bone_3].position) - self.bones[bind.bone_1].position)
			:length()

	--[[Calculate correction bone lengths]]
	--[[Pass through binds and find those which share bones 2 & 3, and set their correction to be the adjecent bone]]
	for _, b in ipairs(self.drivers.binds) do
		--[[Correction bone 2]]
		if bind.bone_2 == b.bone_2 then
			bind.bone_2_correction = b.bone_3
			bind.lock_correction_bone_2 = true
			b.bone_2_correction = bind.bone_3
			b.lock_correction_bone_2 = true
		elseif bind.bone_2 == b.bone_3 then
			bind.bone_2_correction = b.bone_2
			bind.lock_correction_bone_2 = true
			b.bone_3_correction = bind.bone_3
			b.lock_correction_bone_3 = true
			--Correction bone 3
		elseif bind.bone_3 == b.bone_2 then
			bind.bone_3_correction = b.bone_3
			bind.lock_correction_bone_3 = true
			b.bone_2_correction = bind.bone_2
			b.lock_correction_bone_2 = true
		elseif bind.bone_3 == b.bone_3 then
			bind.bone_3_correction = b.bone_2
			bind.lock_correction_bone_3 = true
			b.bone_3_correction = bind.bone_2
			b.lock_correction_bone_3 = true
		end
	end

	if self:hasBone(bind.bone_1_correction) then
		bind.correction_length_1 = (vec3(self.bones[bind.bone_1_correction].position) - self.bones[bind.bone_1].position)
				:length()
	end
	if self:hasBone(bind.bone_2_correction) then
		bind.correction_length_2 = (vec3(self.bones[bind.bone_2_correction].position) - self.bones[bind.bone_2].position)
				:length()
	end
	if self:hasBone(bind.bone_3_correction) then
		bind.correction_length_3 = (vec3(self.bones[bind.bone_3_correction].position) - self.bones[bind.bone_3].position)
				:length()
	end

	bind.bind_id = #self.drivers.binds
	table.insert(self.drivers.binds, bind)
	self:setBoneModifier(nil, modifier.bind, bind)
end

--[[@param self lovrx_fabrik]]
--[[@param fork_bind lovrx_fabrik_fork_bind_node]]
evaluators.fork_bind = function(self, fork_bind)
	fork_bind.length_1 = (vec3(self.bones[fork_bind.bone_1].position) - self.bones[fork_bind.bone_target].position)
			:length()
	fork_bind.length_2 = (vec3(self.bones[fork_bind.bone_2].position) - self.bones[fork_bind.bone_target].position)
			:length()
	fork_bind.length_3 = (vec3(self.bones[fork_bind.bone_3].position) - self.bones[fork_bind.bone_target].position)
			:length()

	fork_bind.bind_id = #self.drivers.fork_binds
	table.insert(self.drivers.fork_binds, fork_bind)
	self:setBoneModifier(nil, modifier.fork_bind, fork_bind)
end

--[[@param self lovrx_fabrik]]
--[[@param cage lovrx_fabrik_cage_bind_node]]
evaluators.cage_bind = function(self, cage)
	cage.b1b2_length = (vec3(self.bones[cage.backbone_1].position) - self.bones[cage.backbone_2].position)
			:length()
	cage.b1t1_length = (vec3(self.bones[cage.backbone_1].position) - self.bones[cage.target_bone_1].position)
			:length()
	cage.b1t2_length = (vec3(self.bones[cage.backbone_1].position) - self.bones[cage.target_bone_2].position)
			:length()
	cage.b2t1_length = (vec3(self.bones[cage.backbone_2].position) - self.bones[cage.target_bone_1].position)
			:length()
	cage.b2t2_length = (vec3(self.bones[cage.backbone_2].position) - self.bones[cage.target_bone_2].position)
			:length()
	cage.t1t2_length = (vec3(self.bones[cage.target_bone_1].position) - self.bones[cage.target_bone_2].position)
			:length()

	cage.b2_correction_length = (vec3(self.bones[cage.backbone_2].position) - self.bones[cage.backbone_2_correction].position)
			:length()
	cage.t1_correction_length = (vec3(self.bones[cage.target_bone_1].position) - self.bones[cage.target_bone_1_correction].position)
			:length()
	cage.t2_correction_length = (vec3(self.bones[cage.target_bone_2].position) - self.bones[cage.target_bone_2_correction].position)
			:length()

	cage.bind_id = #self.drivers.cage_binds
	table.insert(self.drivers.cage_binds, cage)
	self:setBoneModifier(nil, modifier.cage_bind, cage)
end

--[[@param transform lovr_mat4]]
Fabrik.update = function(self, transform)
	--[[affine inverse]]
	local inverse_transform = mat4(transform):invert()
	self:solveChains(inverse_transform)
	self:solvePoles(inverse_transform)
	self:solveLookAts(inverse_transform)
	self:totalPass()
	--[[commit]]
	for bone_id, bone in pairs(self.bones) do
		--[[works on serial joints but a modification is needed for subbases]]
		local bone_transform = mat4(bone.position, bone.rotation)
		local parent = self.bones[bone.parent]
		if parent then
			local parent_transform = mat4(parent.position, parent.rotation)
			bone_transform = parent_transform:invert() * bone_transform
		end
		self.skeleton:setNodeTransform(bone_id, bone_transform)
	end
end

--[[@param bone_id number]]
Fabrik.hasBone = function(self, bone_id)
	return bone_id >= 1 and bone_id <= self.skeleton:getNodeCount()
end

--[[@param bone_id? number]]
--[[@param modifier_ lovrx_fabrik_modifier_flag]]
--[[@param node? lovrx_fabrik_node]]
Fabrik.setBoneModifier = function(self, bone_id, modifier_, node)
	if bone_id then
		self.bones[bone_id] = self.bones[bone_id] or { modifiers = { flags = 0 } }
		self.bones[bone_id].modifier_flags = bit.bor(self.bones[bone_id].modifier_flags, modifier_)
		if modifier == modifier.bind then
			if node then
				--[[later make the bind_ids appendable for interlinking binds]]
				if not self.bones[node.bone_1].bind_ids then
					self.bones[node.bone_1].bind_ids = {}
				end
				table.insert(self.bones[node.bone_1].bind_ids, node.bind_id)
			end
		elseif modifier == modifier.fork_bind then
			if node then
				if not self.bones[node.bone_1].fork_bind_ids then
					self.bones[node.bone_1].fork_bind_ids = {}
				end
				table.insert(self.bones[node.bone_1].fork_bind_ids, node.bind_id)
			end
		elseif modifier == modifier.cage_bind then
			if node then
				self.bones[node.backbone_1].modifier_flags = bit.bor(self.bones[node.backbone_1].modifier_flags, modifier_)
				self.bones[node.backbone_1].cage_bind_id = node.bind_id
			end
		elseif modifier == modifier.damped_transform then
			--[[@diagnostic disable-next-line: param-type-mismatch]]
			self:updateBoneDampedTransform(bone_id, node, bone_id)
		end
	end
end

--[[@param bone_id number]]
--[[@param node lovrx_fabrik_damped_transform_node]]
--[[@param master_bone_id number]]
Fabrik.updateBoneDampedTransform = function(self, bone_id, node, master_bone_id)
	local bone = self.bones[bone_id]
	local parent_transform = self.bones[bone.parent].damped_transform
	bone.modifier_flags = bit.bor(bone.modifier_flags, modifier.damped_transform)
	bone.modifier_master = bone_id
	if parent_transform then
		bone.damped_transform = {
			stiffness = math.min(1.0, math.max(0.0, parent_transform.stiffness * node.stiffness_passed_down)),
			damping = math.min(1.0, math.max(0.0, parent_transform.damping * node.damping_passed_down)),
			mass = math.min(1.0, math.max(0.0, parent_transform.mass * node.mass_passed_down)),
			gravity = node.gravity,
		}
	else
		bone.damped_transform = {
			stiffness = node.stiffness,
			damping = node.damping,
			mass = node.mass,
			gravity = node.gravity
		}
	end
	for _, child_id in bone.children do
		self:updateBoneDampedTransform(child_id, node, master_bone_id)
	end
end

Fabrik.wipeWeights = function(self)
	for _, bone in pairs(self.bones) do
		bone.weight_sum = 0
		bone.weighted_vector_sum = vec3_zero
	end
end

Fabrik.wipeModifiers = function(self)
	for _, bone in pairs(self.bones) do
		bone.modifier_flags = modifier.none
		bone.bind_ids = nil
		bone.fork_bind_ids = nil
		bone.cage_bind_id = nil
		bone.modifier_master = nil
		bone.velocity = nil
		bone.damped_transform = nil
	end
end

--[[@param inverse_transform lovr_mat4]]
Fabrik.solveChains = function(self, inverse_transform)
	local diff = 0
	--[[No need to solve if distance is closed]]
	for _, d in ipairs(self.drivers.chains) do
		diff = diff +
				math.pow(self.bones[d.tip_bone_id].position:distance(inverse_transform * d.target), 2)
	end

	local iterations_left = self.max_iterations
	while iterations_left > 0 and diff > self.minimal_distance * self.minimal_distance * #self.drivers.chains do
		--[[Solve Backwards]]
		for _, d in ipairs(self.drivers.chains) do
			self:solveBackwards(d.root_bone_id, d.tip_bone_id, mat4(inverse_transform) * mat4(d.target), d.pull_strength)
		end
		--[[Solve Forwards]]
		self:totalPass()
		--[[Measure Distance]]
		diff = 0
		for _, d in ipairs(self.drivers.chains) do
			diff = diff + math.pow(self.bones[d.tip_bone_id].position:distance(mat4(inverse_transform) * d.target), 2)
		end
		iterations_left = iterations_left - 1
	end
end

--[[@param inverse_transform lovr_mat4]]
Fabrik.solvePoles = function(self, inverse_transform)
	for _, p in ipairs(self.drivers.poles) do
		self:solvePole(p.root_bone_id, p.tip_bone_id, p.target * inverse_transform, p.turn_to)
	end
end

--[[@param inverse_transform lovr_mat4]]
Fabrik.solveLookAts = function(self, inverse_transform)
	for _, l in ipairs(self.drivers.look_ats) do
		self:solveLookAt(l.bone_id,
			l.target * inverse_transform,
			l.look_from_side)
	end
end

--[[@param bone_id number]]
Fabrik.solveBinds = function(self, bone_id)
	local modifier_flags = self.bones[bone_id].modifier_flags

	--[[First - only solve Reverse forks]]
	if bit.band(modifier_flags, modifier.fork_bind) ~= 0 then
		local ids = self.bones[bone_id].fork_bind_ids
		if ids then
			for _, i in ipairs(ids) do
				if self.drivers.fork_binds[i].reverse_fork then
					self:solveFork(self.drivers.fork_binds[i].bone_1, self.drivers.fork_binds[i].bone_2,
						self.drivers.fork_binds[i].bone_3, self.drivers.fork_binds[i].bone_target,
						self.drivers.fork_binds[i].length_1, self.drivers.fork_binds[i].length_2, self.drivers.fork_binds[i]
						.length_3,
						true)
				end
			end
		end
	end

	--[[N/A - the cage shouldn't interact with any other bind, however it works like a complex loop solver so it goes before binds]]
	if bit.band(modifier_flags, modifier.cage_bind) ~= 0 then
		local id = self.bones[bone_id].cage_bind_id
		local c = self.drivers.cage_binds[id]
		self:solveLoop(c.target_bone_2, c.backbone_2, c.target_bone_1,
			c.target_bone_2_correction, c.backbone_2_correction, c.target_bone_1_correction,
			c.t1t2_length, c.b2t1_length, c.b1t1_length,
			c.t2_correction_length, c.b2_correction_length, c.t1_correction_length)

		self:solveLoop(c.backbone_1, c.backbone_2, c.target_bone_1,
			nil, c.backbone_2_correction, c.target_bone_1_correction,
			c.b1b2_length, c.b2t1_length, c.b1t1_length,
			0, c.b2_correction_length, c.t1_correction_length)

		self:solveLoop(c.backbone_1, c.target_bone_1, c.target_bone_2,
			nil, c.target_bone_1_correction, c.target_bone_2_correction,
			c.b1b2_length, c.b1t1_length, c.t1t2_length,
			0, c.t1_correction_length, c.t2_correction_length)

		self:solveLoop(c.backbone_1, c.target_bone_2, c.backbone_2,
			nil, c.target_bone_2_correction, c.backbone_2_correction,
			c.b1b2_length, c.t1t2_length, c.b2t1_length,
			0, c.t2_correction_length, c.b2_correction_length)

		self:solveLoop(c.target_bone_2, c.backbone_2, c.target_bone_1,
			nil, nil, nil,
			c.t1t2_length, c.b2t1_length, c.b1t1_length,
			c.t2_correction_length, c.b2_correction_length, c.t1_correction_length)
	end

	--[[Second - solve binds]]
	if bit.band(modifier_flags, modifier.bind) ~= 0 then
		local ids = self.bones[bone_id].bind_ids
		if ids then
			--[[TODO: handle deps]]
			for _, i in ipairs(ids) do
				self:solveLoop(self.drivers.binds[i].bone_1, self.drivers.binds[i].bone_2, self.drivers.binds[i].bone_3,
					self.drivers.binds[i].bone_1_correction, self.drivers.binds[i].bone_2_correction,
					self.drivers.binds[i].bone_3_correction,
					self.drivers.binds[i].length_12, self.drivers.binds[i].length_23, self.drivers.binds[i].length_31,
					self.drivers.binds[i].correction_length_1, self.drivers.binds[i].correction_length_2,
					self.drivers.binds[i].correction_length_3)
			end
		end
	end

	--[[Third - solve all forks as normal forks]]
	if bit.band(modifier_flags, modifier.fork_bind) ~= 0 then
		local ids = self.bones[bone_id].fork_bind_ids
		if ids then
			for _, i in ipairs(ids) do
				self:solveFork(self.drivers.fork_binds[i].bone_1, self.drivers.fork_binds[i].bone_2,
					self.drivers.fork_binds[i].bone_3,
					self.drivers.fork_binds[i].bone_target,
					self.drivers.fork_binds[i].length_1, self.drivers.fork_binds[i].length_2, self.drivers.fork_binds[i].length_3,
					false)
			end
		end
	end
end


Fabrik.totalPass = function(self)
	for _, chain in ipairs(self.drivers.chains) do
		self:solveBackwards(chain.root_bone_id,
			chain.tip_bone_id,
			mat4(self.bones[chain.tip_bone_id].position, self.bones[chain.tip_bone_id].rotation),
			chain.pull_strength)
	end
	for _, root_id in ipairs(self.roots) do
		self:solveForwards(root_id, self.bones[root_id].initial_position)
	end
end

--[[@param bone_id number]]
--[[@param target lovr_vec3]]
--[[@param side lovrx_fabrik_look_from_side]]
--[[@param spin_override? number]]
Fabrik.solveLookAt = function(self, bone_id, target, side, spin_override)
	local pivot = self.bones[self.bones[bone_id].parent].position
	local start_dir = self.bones[bone_id].start_direction
	local target_dir = (target - pivot) --[[@type lovr_vec3]]
	local rotation --[[@type lovr_quat]]
	spin_override = spin_override or 0
	local spin_angle

	--[[for some reason, target_dir is only normalized for up/down/forward]]
	if side == "up" then
		rotation = from_to_rotation(start_dir, target_dir:normalize()) *
				self.bones[self.bones[bone_id].parent].start_rotation
		spin_angle = spin_override * deg2rad
	elseif side == "down" then
		rotation = from_to_rotation(start_dir, target_dir:normalize() * -1) *
				self.bones[self.bones[bone_id].parent].start_rotation
		spin_angle = spin_override * deg2rad
	else
		local rot_axis = vec3(start_dir):cross(target_dir):normalize()
		local a = self.bones[bone_id].length / 2.0
		local b = target_dir:length()
		local rot_angle = -math.acos(math.max(-1.0, math.min(a / b, 1.0)))
		--[[Solve bone rotation around the pivot]]

		rotation = from_to_rotation(start_dir, quat(rot_angle, unpack(rot_axis)) * target_dir) *
				self.bones[self.bones[bone_id].parent].start_rotation

		local normal = rotation * vec3_up
		if side == "forward" then
			local p = target_dir:normalize()
			local proj = p - normal * normal:dot(p)
			spin_angle = signed_angle(rotation * vec3_forward, proj, normal)
		elseif side == "left" then
			local p = target_dir
			local proj = p - normal * normal:dot(p)
			spin_angle = signed_angle(rotation * vec3_left, proj, normal)
		elseif side == "back" then
			local p = target_dir
			local proj = p - normal * normal:dot(p)
			spin_angle = signed_angle(rotation * vec3_back, proj, normal)
		elseif side == "right" then
			local p = target_dir
			local proj = p - normal * normal:dot(p)
			spin_angle = signed_angle(rotation * vec3_right, proj, normal)
		end
	end
	self.bones[self.bones[bone_id].parent].rotation =
			Quat(quat(rotation * vec3_up, spin_angle) * rotation)
	self.bones[bone_id].position =
			Vec3(pivot +
				(rotation * vec3(self.bones[bone_id].start_direction):normalize()) *
				self.bones[bone_id].length)
end

--[[@param b1_id number]]
--[[@param b2_id number]]
--[[@param b3_id number]]
--[[@param b1_correction? number]]
--[[@param b2_correction? number]]
--[[@param b3_correction? number]]
--[[@param b1_b2_length number]]
--[[@param b2_b3_length number]]
--[[@param b3_b1_length number]]
--[[@param b1_correction_length number]]
--[[@param b2_correction_length number]]
--[[@param b3_correction_length number]]
Fabrik.solveLoop = function(self, b1_id, b2_id, b3_id,
														b1_correction, b2_correction, b3_correction,
														b1_b2_length, b2_b3_length, b3_b1_length,
														b1_correction_length, b2_correction_length, b3_correction_length)
	--[[PHASE 1]]
	--[[Step 1]]
	self.bones[b2_id].position =
			Vec3(calc_next(self.bones[b1_id].position, self.bones[b2_id].position,
				b1_b2_length))
	--[[Step 2]]
	self.bones[b3_id].position =
			Vec3(calc_next(self.bones[b2_id].position, self.bones[b3_id].position,
				b2_b3_length))
	--[[Step 3]]
	if b1_correction ~= nil then
		self.bones[b1_id].position =
				Vec3(calc_next(self.bones[b3_id].position, self.bones[b1_id].position,
					b3_b1_length))
		--[[Step 4 (same as 1)]]
		self.bones[b2_id].position =
				Vec3(calc_next(self.bones[b1_id].position, self.bones[b2_id].position,
					b1_b2_length))
	end

	--[[PHASE 2]]
	--[[Step 5]]
	self.bones[b3_id].position =
			Vec3(calc_next(self.bones[b1_id].position, self.bones[b3_id].position,
				b3_b1_length))
	--[[Step 6]]
	self.bones[b2_id].position =
			Vec3(calc_next(self.bones[b3_id].position, self.bones[b2_id].position,
				b2_b3_length))

	--[[PHASE 3  TODO: FIX]]
	--[[b1 correction]]
	if b1_correction ~= nil then
		self.bones[b1_id].position =
				Vec3(calc_next(self.bones[b1_correction].position, self.bones[b1_id].position,
					b1_correction_length))
	end

	if b2_correction ~= nil then
		--[[Step 7 (same as 1)]]
		self.bones[b2_id].position =
				Vec3(calc_next(self.bones[b1_id].position, self.bones[b2_id].position,
					b1_b2_length))
		--[[Step 8]]
		self.bones[b2_id].position =
				Vec3(calc_next(self.bones[b2_correction].position, self.bones[b2_id].position,
					b2_correction_length))
	end

	if b3_correction ~= nil then
		--[[Step 9 (same 5)]]
		self.bones[b3_id].position =
				Vec3(calc_next(self.bones[b1_id].position, self.bones[b3_id].position,
					b3_b1_length))
		--[[Step 10]]
		self.bones[b3_id].position =
				Vec3(calc_next(self.bones[b3_correction].position, self.bones[b3_id].position,
					b3_correction_length))
	end

	--[[PHASE 4 (CUSTOM)]]
	--[[SOLVE CLOCKWISE]]
	self.bones[b2_id].position =
			Vec3(calc_next(self.bones[b1_id].position, self.bones[b2_id].position,
				b1_b2_length))
	self.bones[b3_id].position =
			Vec3(calc_next(self.bones[b2_id].position, self.bones[b3_id].position,
				b2_b3_length))

	--[[SOLVE COUNTER CLOCKWISE]]
	self.bones[b3_id].position =
			Vec3(calc_next(self.bones[b1_id].position, self.bones[b3_id].position,
				b3_b1_length))
	self.bones[b2_id].position =
			Vec3(calc_next(self.bones[b3_id].position, self.bones[b2_id].position,
				b2_b3_length))
	self.bones[b2_id].position =
			Vec3(calc_next(self.bones[b1_id].position, self.bones[b2_id].position,
				b1_b2_length))
end

--[[@param bone_1_id number]]
--[[@param bone_2_id number]]
--[[@param bone_3_id number]]
--[[@param bone_target_id number]]
--[[@param length_1 number]]
--[[@param length_2 number]]
--[[@param length_3 number]]
--[[@param reverse_fork unknown]]
Fabrik.solveFork = function(self, bone_1_id, bone_2_id, bone_3_id, bone_target_id, length_1, length_2, length_3,
														reverse_fork)
	--[[Correct target // bone 1's position isn't altered]]
	self.bones[bone_target_id].position =
			Vec3(calc_next(self.bones[bone_1_id].position, self.bones[bone_target_id].position,
				length_1))

	if reverse_fork then
		self.bones[bone_2_id].position =
				Vec3(calc_next(self.bones[bone_target_id].position,
					self.bones[bone_2_id].position, length_2))
		self.bones[bone_3_id].position =
				Vec3(calc_next(self.bones[bone_target_id].position,
					self.bones[bone_3_id].position, length_3))
	else
		self.bones[bone_target_id].position =
				Vec3(calc_next(self.bones[bone_2_id].position,
					self.bones[bone_target_id].position, length_2))
		self.bones[bone_target_id].position =
				Vec3(calc_next(self.bones[bone_3_id].position,
					self.bones[bone_target_id].position, length_3))
	end
end

--[[@param root_id number]]
--[[@param tip_id number]]
--[[@param target lovr_vec3]]
--[[@param side "backward"|"forward"|"left"|"right"]]
Fabrik.solvePole = function(self, root_id, tip_id, target, side)
	if not self:hasBone(root_id) and root_id ~= nil then
		return
	end
	local stop_bone = self.bones[root_id].parent
	local previous_bone = tip_id
	local current_bone = self.bones[previous_bone].parent
	local next_bone = self.bones[current_bone].parent
	local rot_quat
	local start_dir
	local target_dir

	while next_bone ~= stop_bone and current_bone ~= root_id do
		local normal = (vec3(self.bones[previous_bone].position) - self.bones[previous_bone].position)
				:normalize()
		local d = normal:dot(self.bones[previous_bone].position)
		local p = vec3(target)
		local proj_p = p - normal * (normal:dot(p) - d)
		p = vec3(self.bones[current_bone].position)
		local proj_v = p - normal * (normal:dot(p) - d)
		local angle = signed_angle(proj_v - self.bones[previous_bone].position,
			proj_p - self.bones[previous_bone].position,
			normal)
		self.bones[current_bone].position =
				Vec3(quat(normal, angle) *
					(vec3(self.bones[current_bone].position) - self.bones[previous_bone].position) +
					self.bones[previous_bone].position)

		--[[Calc bone rotation]]
		--[[Point vector Y at the next bone]]
		start_dir = self.bones[current_bone].start_direction
		target_dir = (vec3(self.bones[next_bone].position) - self.bones[current_bone].position):normalize()
		rot_quat = from_to_rotation(start_dir, target_dir)

		--[[Point side vector towards the target]]
		self.bones[current_bone].rotation =
				Quat(rotate_along_axis(rot_quat, self.bones[current_bone].position, target, side))

		previous_bone = current_bone
		current_bone = next_bone
		next_bone = self.bones[next_bone].parent
	end
end

--[[@param root_id number]]
--[[@param origin lovr_vec3]]
Fabrik.solveForwards = function(self, root_id, origin)
	if not self:hasBone(root_id) and root_id ~= nil then return end
	local subbase_queue = {} --[[@type number[] ]]
	for _, child in pairs(self.skeleton:getNodeChildren(root_id)) do
		table.insert(subbase_queue, child)
	end
	local modifier_flags
	self.bones[root_id].position = Vec3(origin)
	local previous_bone = root_id
	local current_bone = subbase_queue[1] --[[@type number?]]

	--[[UNHANDLED INSTANCE]]
	if bit.band(self.bones[previous_bone].modifier_flags, bit.bor(modifier.bind, modifier.fork_bind, modifier.cage_bind)) then
		self:solveBinds(previous_bone)
	end

	while #subbase_queue > 0 do
		current_bone = subbase_queue[1]
		previous_bone = self.bones[current_bone].parent
		table.remove(subbase_queue, 1)
		--[[CALC CURRENT'S POSITION]]
		modifier_flags = self.bones[current_bone].modifier_flags
		if modifier_flags == modifier.none then
			self.bones[current_bone].position =
					Vec3(calc_next(self.bones[previous_bone].position,
						self.bones[current_bone].position,
						self.bones[current_bone].length))
		elseif bit.band(modifier_flags, bit.bor(modifier.bind, modifier.fork_bind, modifier.cage_bind)) ~= 0 then
			self.bones[current_bone].position =
					Vec3(calc_next(self.bones[previous_bone].position,
						self.bones[current_bone].position,
						self.bones[current_bone].length))
			self:solveBinds(current_bone)
		end

		if bit.band(modifier_flags, modifier.solid) ~= 0 then
			self.bones[current_bone].position = Vec3(self.bones[previous_bone].position +
				(
					(self.bones[self.bones[self.bones[current_bone].modifier_master].parent].rotation * self.bones[current_bone].start_direction)
					*
					self.bones[current_bone].length
				))
		elseif bit.band(modifier_flags, modifier.damped_transform) ~= 0 then
			if self.bones[current_bone].modifier_master ~= current_bone then
				local data = assert(self.bones[current_bone].damped_transform)
				local target = vec3(self.bones[previous_bone].position) +
						((vec3(self.bones[self.bones[self.bones[current_bone].modifier_master].parent].rotation) * vec3(self.bones[current_bone].start_direction):normalize()) *
							self.bones[current_bone].length)
				local force = (target - self.bones[current_bone].position) * data.stiffness
				force.y = force.y - data.gravity
				local acceleration = force / data.mass
				self.bones[current_bone].velocity = Vec3(vec3(self.bones[current_bone].velocity) +
					acceleration * (1.0 - data.damping))
				self.bones[current_bone].position =
						Vec3(calc_next(self.bones[previous_bone].position,
							vec3(self.bones[current_bone].position) + self.bones[current_bone].velocity + force,
							self.bones[current_bone].length))
			end
		end


		--[[CALC OWN ROTATION]]
		if previous_bone ~= nil and bit.band(modifier_flags, modifier.look_at) == 0 then --[[and self.bones[previous_bone].parent ~= nil then]]
			local rotation = quat()
			if #self.bones[previous_bone].children > 1 then
				local wsum = 0.0
				local weight
				for _, child_id in ipairs(self.bones[previous_bone].children) do
					weight = self.bones[child_id].weight_sum
					if weight == 0 then weight = 1 end
					wsum = wsum + weight
					local delta = (vec3(self.bones[child_id].position) - self.bones[previous_bone].position):normalize()
					local new_rotation = from_to_rotation(self.bones[previous_bone].start_direction, delta)
					--[[dunno why this one was + but the one at the end of the block was already *]]
					rotation = rotation * new_rotation:slerp(quat_zero, 1 - weight) --[[rotation, then new_rotation * weight]]
				end
				rotation = rotation:slerp(quat_zero, 1 - 1 / wsum) --[[rotation / wsum]]
			else
				local delta = (vec3(self.bones[current_bone].position) - self.bones[previous_bone].position):normalize()
				rotation = from_to_rotation(self.bones[current_bone].start_direction, delta)
			end
			self.bones[previous_bone].rotation = Quat(rotation * self.bones[previous_bone].start_rotation)
		end

		--[[QUEUE UP THE CURRENTS' CHILDREN]]
		--[[Push branch on the queue so it can be solved later]]
		for _, child in ipairs(self.bones[current_bone].children) do
			table.insert(subbase_queue, child)
		end
	end
	--[[Remove weights so that they do not obstruct future backwards solve]]
	self:wipeWeights()
end

--[[@param root_id number]]
--[[@param tip_id number]]
--[[@param target lovr_mat4]]
--[[@param weight number]]
Fabrik.solveBackwards = function(self, root_id, tip_id, target, weight)
	if not self:hasBone(tip_id) then return end
	if #self.bones[tip_id].children == 0 then
		self.bones[tip_id].rotation = Quat(target)
	end
	local current_bone   = tip_id
	local current_target = vec3(target:getPosition())
	local stop_bone      = self.bones[root_id].parent
	while current_bone ~= stop_bone and self.bones[current_bone].parent ~= nil do
		--[[set biased bone position]]
		local bone = self.bones[current_bone]
		bone.weight_sum = bone.weight_sum + weight --[[current_weight]]
		bone.weighted_vector_sum = Vec3(bone.weighted_vector_sum + current_target * weight) --[[current_weight]]
		bone.position = Vec3(bone.weighted_vector_sum / bone.weight_sum)
		--[[end set biased bone position]]
		current_target = calc_next(self.bones[current_bone].position,
			self.bones[self.bones[current_bone].parent].position,
			self.bones[current_bone].length)
		current_bone = self.bones[current_bone].parent
	end
end

Fabrik.solveSolidifier = function(self, bone_id)
	local rotation = self.bones[self.bones[bone_id].parent].rotation
	--[[Iterating through the chain stuff]]
	local bone_queue = {} --[[@type integer[] ]]
	local current_bone = bone_id
	while true do
		local children = self.bones[current_bone].children
		if #children == 0 and #bone_queue == 0 then
			return
		else
			for _, child in ipairs(children) do
				table.insert(bone_queue, child)
			end
		end
		current_bone = bone_queue[0]
		table.remove(bone_queue, 1)
		self.bones[current_bone].rotation = Quat(rotation * self.bones[current_bone].start_rotation)
	end
end

Fabrik.initialize = function(self)
	self.drivers.chains = {}
	self.drivers.poles = {}
	self.drivers.look_ats = {}
	self.drivers.binds = {}
	self:wipeModifiers()
	for _, node in ipairs(self.nodes) do
		evaluators[node.type](self, node)
	end
end

--[[@param chain lovrx_fabrik_chain_node]]
mod.chain = function(chain) return chain end
--[[@param bind lovrx_fabrik_bind_node]]
mod.bind = function(bind) return bind end
--[[@param fork_bind lovrx_fabrik_fork_bind_node]]
mod.fork_bind = function(fork_bind) return fork_bind end
--[[@param cage_bind lovrx_fabrik_cage_bind_node]]
mod.cage_bind = function(cage_bind) return cage_bind end
--[[@param damped_transform lovrx_fabrik_damped_transform_node]]
mod.damped_transform = function(damped_transform) return damped_transform end
--[[@param pole lovrx_fabrik_pole_node]]
mod.pole = function(pole) return pole end
--[[@param look_at lovrx_fabrik_look_at_node]]
mod.look_at = function(look_at) return look_at end
--[[@param solidifier lovrx_fabrik_solidifier_node]]
mod.solidifier = function(solidifier) return solidifier end

return mod

--[[@alias lovrx_fabrik_node_type "chain"|"pole"|"look_at"|"exaggerator"|"solidifier"|"damped_transform"|"bind"|"fork_bind"|"cage_bind"]]
--[[@alias lovrx_fabrik_node lovrx_fabrik_chain_node|lovrx_fabrik_pole_node|lovrx_fabrik_look_at_node|lovrx_fabrik_bind_node|lovrx_fabrik_fork_bind_node|lovrx_fabrik_cage_bind_node|lovrx_fabrik_damped_transform_node]]

--[[@class lovrx_fabrik_chain_node]]
--[[@field type "chain"]]
--[[@field target lovr_vec3]]
--[[@field tip_bone_id integer]]
--[[@field root_bone_id integer]]
--[[@field pull_strength number]]

--[[@class lovrx_fabrik_pole_node]]
--[[@field type "pole"]]
--[[@field target lovr_vec3]]
--[[@field tip_bone_id integer]]
--[[@field root_bone_id integer]]
--[[@field turn_to "forward"|"backward"|"left"|"right"]]

--[[@alias lovrx_fabrik_look_from_side "up"|"down"|"left"|"right"|"forward"|"back"]]

--[[@class lovrx_fabrik_look_at_node]]
--[[@field type "look_at"]]
--[[@field bone_id integer]]
--[[@field target lovr_vec3]]
--[[@field look_from_side lovrx_fabrik_look_from_side]]

--[[@class lovrx_fabrik_bind_node]]
--[[@field type "bind"]]
--[[@field bind_id integer]]
--[[@field bone_1 integer]]
--[[@field bone_2 integer]]
--[[@field bone_3 integer]]
--[[@field bone_1_correction integer]]
--[[@field bone_2_correction integer]]
--[[@field bone_3_correction integer]]
--[[@field length_23_multiplier number]]
--[[@field length_12 number]]
--[[@field length_23 number]]
--[[@field length_31 number]]
--[[@field correction_length_1 number]]
--[[@field correction_length_2 number]]
--[[@field correction_length_3 number]]
--[[@field lock_correction_bone_2? boolean]]
--[[@field lock_correction_bone_3? boolean]]

--[[@class lovrx_fabrik_fork_bind_node]]
--[[@field type "fork_bind"]]
--[[@field bind_id integer]]
--[[@field bone_1 integer]]
--[[@field bone_2 integer]]
--[[@field bone_3 integer]]
--[[@field bone_target integer]]
--[[@field length_1 number]]
--[[@field length_2 number]]
--[[@field length_3 number]]
--[[@field reverse_fork? boolean]]

--[[@class lovrx_fabrik_cage_bind_node]]
--[[@field type "cage_bind"]]
--[[@field bind_id integer]]
--[[@field backbone_1 integer]]
--[[@field backbone_2 integer]]
--[[@field backbone_2_correction integer]]
--[[@field target_bone_1 integer]]
--[[@field target_bone_1_correction integer]]
--[[@field target_bone_2 integer]]
--[[@field target_bone_2_correction integer]]
--[[@field b1b2_length number]]
--[[@field b1t1_length number]]
--[[@field b1t2_length number]]
--[[@field b2t1_length number]]
--[[@field b2t2_length number]]
--[[@field t1t2_length number]]
--[[@field b2_correction_length number]]
--[[@field t1_correction_length number]]
--[[@field t2_correction_length number]]

--[[@class lovrx_fabrik_solidifier_node]]
--[[@field type "solidifier"]]
--[[@field bone_id number]]

--[[@class lovrx_fabrik_damped_transform_node]]
--[[@field type "damped_transform"]]
--[[@field bone_id number]]
--[[@field stiffness number]]
--[[@field damping number]]
--[[@field mass number]]
--[[@field gravity number]]
--[[@field stiffness_passed_down number]]
--[[@field damping_passed_down number]]
--[[@field mass_passed_down number]]

--[[@class lovrx_fabrik_bone]]
--[[@field parent number]]
--[[@field children number[] ]]
--[[@field position lovr_vec3]]
--[[@field initial_position? lovr_vec3 only present on roots]]
--[[@field length number]]
--[[@field length_multiplier number]]
--[[@field rotation lovr_quat]]
--[[@field start_rotation lovr_quat]]
--[[@field start_direction lovr_vec3]]
--[[@field weighted_vector_sum lovr_vec3]]
--[[@field weight_sum number]]
--[[@field modifier_flags lovrx_fabrik_modifier_flag]]
--[[@field modifier_master? number]]
--[[@field velocity? lovr_vec3]]
--[[@field damped_transform? {stiffness:number,mass:number,damping:number,gravity:number}]]
--[[@field bind_ids? number[] ]]
--[[@field fork_bind_ids? number[] ]]
--[[@field cage_bind_id? number]]

local mod = {}

--[[@class lovrx_fabrik_options]]
--[[@field max_iterations integer]]
--[[@field epsilon number]]

--[[@param target lovr_vec3]]
--[[@param nodes lovr_vec3[] ]]
--[[@param options? lovrx_fabrik_options]]
local solve_chain = function(target, nodes, options)
	local total_length = 0
	local lengths = {} --[[@type number]]
	local new_nodes = { unpack(nodes) }
	for i = 1, #nodes - 1 do
		local current = nodes[i]
		local next = nodes[i + 1]
		local new_length = next:distance(current)
		total_length = total_length + new_length
		lengths[#lengths + 1] = new_length
	end
	local total_distance = target:distance(new_nodes[1])
	if total_distance >= total_length then
		local direction = (target - new_nodes[1]):normalize()
		for i = 1, #new_nodes - 1 do
			new_nodes[i + 1] = new_nodes[i] + direction * lengths[i]
		end
		return new_nodes
	end
	options = options or {}
	local max_iterations = options.max_iterations or 5
	local epsilon = options.epsilon or 0.01
	local i = 0
	local segment_count = #new_nodes - 1
	while i < max_iterations and target:distance(new_nodes[#new_nodes]) > epsilon do
		i = i + 1
		local current_target = target
		new_nodes[#new_nodes] = current_target
		--[[forward pass]]
		for j = segment_count, 1, -1 do
			local next_node = new_nodes[j + 1]
			local current_node = new_nodes[j]
			new_nodes[j] = next_node - (next_node - current_node):normalize() * lengths[j]
		end
		new_nodes[1] = nodes[1]
		--[[backward pass]]
		for j = 1, segment_count do
			local previous_node = new_nodes[j]
			local current_node = new_nodes[j + 1]
			new_nodes[j + 1] = previous_node + (current_node - previous_node):normalize() * lengths[j]
		end
	end
	return new_nodes
end

--[[@param model lovr_model]]
--[[@param target lovr_vec3]]
--[[@param start_id number|string]]
--[[@param end_id number|string]]
--[[@param options? lovrx_fabrik_options]]
mod.update_model_chain = function(model, target, start_id, end_id, options)
	local distance = (vec3(model:getNodePosition(end_id)) - target):length()
	local epsilon = (options and options.epsilon) or 0.01
	if distance <= epsilon then return end
	local reversed_nodes = {} --[[@type lovr_vec3[] ]]
	local reversed_ids = {} --[[@type (string|number)[] ]]
	local id = end_id
	while true do
		reversed_nodes[#reversed_nodes + 1] = vec3(model:getNodePosition(id))
		reversed_ids[#reversed_ids + 1] = id
		if id == start_id then break else id = model:getNodeParent(id) end
	end
	local complement = #reversed_nodes + 1
	local nodes = {} --[[@type lovr_vec3[] ]]
	local ids = {} --[[@type (string|number)[] ]]
	for i = 1, #reversed_nodes do
		nodes[complement - i] = reversed_nodes[i]
		ids[complement - i] = reversed_ids[i]
	end
	local new_nodes = solve_chain(target, nodes, options)
	local size = #new_nodes
	for i = 1, size - 1 do
		local current_id = ids[i]
		model:setNodeOrientation(current_id, quat())
		local transform = mat4(model:getNodeTransform(current_id)):invert()
		local initial_direction = vec3(model:getNodePosition(ids[i + 1], "parent"))
		local direction = transform * new_nodes[i + 1] - transform * new_nodes[i]
		local orientation = quat(direction:angle(initial_direction), initial_direction:cross(direction):unpack())
		model:setNodeOrientation(current_id, orientation)
	end
end

return mod

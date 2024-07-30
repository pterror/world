local mod = {}

--[[@param model lovr_model]]
mod.print_model_nodes = function(model)
	for i = 1, model:getNodeCount() do
		print(i, model:getNodeName(i))
	end
end

return mod

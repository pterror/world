LovrUIRoot = "deps/"
local json = require("deps.lunajson")
local UI = require("lovr.ui")

local functions = {
	raw = function(x) return x end,
	room = require("world_vr.room").new,
	humanoid = require("world_vr.humanoid").new,
	vec2 = lovr.math.newVec2,
	vec3 = lovr.math.newVec3,
	vec4 = lovr.math.newVec4,
	mat4 = lovr.math.newMat4,
	quat = lovr.math.newQuat,
	curve = lovr.math.newCurve,
	random_generator = lovr.math.newRandomGenerator,
	blob = lovr.data.newBlob,
	image = lovr.data.newImage,
	model_data = lovr.data.newModelData,
	rasterizer = lovr.data.newRasterizer,
	sound = lovr.data.newSound,
	source = lovr.audio.newSource,

}

--[[@param path string]]
local write_save = function(path, data)
	local f, err = io.open(path, "w")
	if not f then return nil, err end
	f:write(json.value_to_json(data))
end

--[[@generic t]]
--[[@param ... t]]
--[[@return t ...]]
local drop_first = function(_, ...) return ... end

local hydrate
hydrate = function(data)
	if type(data) == "table" then
		for k, v in pairs(data) do
			if type(v) == "table" then
				data[k] = hydrate(v)
			end
		end
		local class_name = data[1]
		if type(class_name) == "string" then
			local class = functions[class_name]
			if class then
				return class(drop_first(unpack(data)))
			end
		end
	end
	return data
end

--[[@param path string]]
local read_save = function(path)
	local f, err = io.open(path, "r")
	if not f then return nil, err end
	local data = json.json_to_value(f:read("*all"))
	f:close()
	hydrate(data)
	return data
end

local save_path = arg[1]
local save_data

--[[@class world_vr_context]]
--[[@field has_keyboard boolean]]
--[[@field world lovr_world]]

local context --[[@type world_vr_context]]
local shader --[[@type lovr_shader]]
local basic_shader --[[@type lovr_shader]]
local spherical_harmonics --[[@type lovr_buffer]]

function lovr.load()
	UI.Init()
	--[[@diagnostic disable-next-line: missing-parameter]]
	local world = lovr.physics.newWorld()
	context = { world = world, has_keyboard = false }
	local err
	save_data, err = read_save(save_path)
	if not save_data then
		save_data = {}
		io.stderr:write(err)
	end

	for i = 1, #save_data.objects do
		local obj = save_data.objects[i]
		if obj.initialize then obj:initialize(context) end
	end
	shader = require("lovr.lighting.pbr")()
	--[[FIXME: phong shading has issues with draw order or something]]
	basic_shader = require("lovr.lighting.basic")()
	--[[ground]]
	-- make_collider(0, -plane_thickness, 0, 50, plane_thickness, 50)
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

function lovr.keypressed() context.has_keyboard = true end

function lovr.update(dt)
	UI.InputInfo()
	for i = 1, #save_data.objects do
		local obj = save_data.objects[i]
		if obj.update then obj:update(dt, context) end
	end
end

function lovr.draw(pass)
	pass:setCullMode("back")
	pass:setViewCull(true)
	pass:setShader(shader)
	pass:send("sphericalHarmonics", spherical_harmonics)

	for i = 1, #save_data.objects do
		local obj = save_data.objects[i]
		if obj.draw then obj:draw(pass) end
	end

	pass:setShader(basic_shader)

	for _, hand in ipairs(lovr.headset.getHands()) do
		local x, y, z = lovr.headset.getPosition(hand)
		pass:sphere(x, y, z, .1)
	end

	local lh_pose = lovr.math.newMat4(lovr.headset.getPosition("hand/left"))
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

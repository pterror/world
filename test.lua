return function(ctx)
	local nested = {}
	local objects = {}
	local game = { objects = objects, }
	ctx.game = game
	nested[1] = {}
	nested[2] = { d = "owo", e = false, c = 1, }
	nested[3] = { nested[2], nested[2], }
	objects[1] = {
		b = nested[3],
		c = ctx.function_("function (_, foo) return foo + 1 end"),
		d = nested[1],
		e = ctx
				.function_(
					"function (ctx) ctx.game.objects[2] = { 3, 4 }; ctx.save(); ctx.game.objects[3] = { 3, true }; ctx.save() end"),
		a = 1,
	}
	objects[2] = { 3, 4, }
	objects[3] = { 3, true, }
	return ctx
end

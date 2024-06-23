if [ "$(uname -s)" = "Linux" ]
then
	deps/lovr world_vr.lua
else
	# assume macos
	echo TODO
fi

mkdir -p bin/
if [ "$(uname -s)" = "Linux" ]
then
	bin/lovr world_vr.lua
else
	# assume macos
	echo TODO
fi

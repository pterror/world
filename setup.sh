mkdir -p bin/
V=v0.17.1
NAME=lovr
if [ "$(uname -s)" = "Linux" ]
then
	F=lovr-$V-x86_64.AppImage
	if [ ! -f bin/$F ]
	then
		curl -L https://github.com/bjornbytes/lovr/releases/download/$V/$F -o bin/$F
		uname -v | grep NixOS >/dev/null 2>&1
		if [ "$?" -eq 0 ]
		then
			cat <<END > bin/$NAME
#!/bin/sh
nix run nixpkgs#appimage-run $(dirname $(realpath "$0"))/bin/$F \$@
END
			chmod +x bin/$NAME
		else
			chmod +x bin/$F
			ln -s ./$F bin/$NAME
		fi
	fi
else
	# assume macos
	curl -L https://github.com/bjornbytes/lovr/releases/download/$V/lovr-$V.app.zip -o bin/
	# TODO
fi

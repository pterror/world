with import <nixpkgs> { };
mkShell {
  nativeBuildInputs = [
    luajit
  ];
  buildInputs = [
  ];
}

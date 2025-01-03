{
  lib,
  stdenvNoCC,
  buildPackages,
  self,
}:
stdenvNoCC.mkDerivation {
  pname = "nulibc";
  version = self.shortRev or "dirty";

  src = lib.cleanSource self;

  nativeBuildInputs = [
    buildPackages.zig
    buildPackages.zig.hook
  ];

  doCheck = true;

  postUnpack = ''
    export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)
  '';

  checkPhase = ''
    zig build -Dlinkage=dynamic test
  '';
}

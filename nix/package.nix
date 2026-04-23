{
  lib,
  stdenv,
  zig_0_15,
  src ? lib.cleanSource ../.,
  version ? lib.removeSuffix "\n" (builtins.readFile ../VERSION),
}:

stdenv.mkDerivation {
  pname = "sloc";
  inherit version src;

  strictDeps = true;
  nativeBuildInputs = [ zig_0_15 ];
  dontConfigure = true;
  doCheck = true;

  buildPhase = ''
    runHook preBuild
    zig build -Doptimize=ReleaseFast -Dversion="${version}"
    runHook postBuild
  '';

  checkPhase = ''
    runHook preCheck
    zig build test -Dversion="${version}"
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    zig build -Doptimize=ReleaseFast -Dversion="${version}" --prefix "$out"
    runHook postInstall
  '';

  meta = {
    description = "Fast source-lines-of-code counter with separate code and test totals";
    license = lib.licenses.mit;
    mainProgram = "sloc";
    platforms = lib.platforms.unix;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
  };
}

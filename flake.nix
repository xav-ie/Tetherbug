{
  description = "Instant Hotspot for Android phones and Macs: a BLE control link to turn the phone's hotspot on/off, with iPhone-style Personal Hotspot advertising";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      forAll =
        f:
        nixpkgs.lib.genAttrs [
          "aarch64-darwin"
          "x86_64-darwin"
          "aarch64-linux"
          "x86_64-linux"
        ] (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAll (pkgs: {
        softap-ie = pkgs.callPackage ./cli/softap-ie/package.nix { };
      });
    };
}

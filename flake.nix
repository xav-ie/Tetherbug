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

      # Android app toolchain: `nix develop`, then `cd android && ./gradlew assembleDebug`.
      devShells = forAll (
        pkgs:
        let
          unfree = import nixpkgs {
            inherit (pkgs) system;
            config = {
              allowUnfree = true;
              android_sdk.accept_license = true;
            };
          };
          sdk =
            (unfree.androidenv.composeAndroidPackages {
              platformVersions = [ "37.0" ];
              buildToolsVersions = [ "36.0.0" ];
              includeEmulator = false;
              includeSystemImages = false;
            }).androidsdk;
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.zulu21
              sdk
            ];
            # Both, so a preinstalled SDK (e.g. on GitHub's runners) can't point Gradle elsewhere.
            ANDROID_HOME = "${sdk}/libexec/android-sdk";
            ANDROID_SDK_ROOT = "${sdk}/libexec/android-sdk";
            JAVA_HOME = pkgs.zulu21.home;
            # JDK >= 21 SIGBUSes at startup on Macs booted with SIP off; inject
            # github.com/dazi2011/macos-java-sigbus-codeheap-allocate-fix's libjitfix if present.
            shellHook = ''
              jitfix="$HOME/Projects/macos-java-sigbus-codeheap-allocate-fix/libjitfix.dylib"
              [ -e "$jitfix" ] && export DYLD_INSERT_LIBRARIES="$jitfix"
            '';
          };
        }
      );
    };
}

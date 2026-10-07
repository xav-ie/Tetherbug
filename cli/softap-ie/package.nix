{
  android-tools,
  fetchurl,
  jdk17,
  runCommand,
  writeShellApplication,
}:
let
  # D8 (shipped inside R8) turns the class into dex so `app_process` can load it.
  r8 = fetchurl {
    url = "https://dl.google.com/android/maven2/com/android/tools/r8/9.5.23/r8-9.5.23.jar";
    hash = "sha256-dIqw72boW1TOxa2D0WiZnbnj2tjI9jFw6Dbv8ZXL0Js=";
  };
  dex = runCommand "softap-ie.dex" { nativeBuildInputs = [ jdk17 ]; } ''
    cp ${./SoftApIe.java} SoftApIe.java
    javac --release 11 -d classes SoftApIe.java
    java -cp ${r8} com.android.tools.r8.D8 --min-api 33 --output . classes/SoftApIe.class
    cp classes.dex $out
  '';
in
writeShellApplication {
  name = "softap-ie";
  runtimeInputs = [ android-tools ];
  text = ''
    if ! out=$(adb push ${dex} /data/local/tmp/softap-ie.dex 2>&1); then
      echo "$out" >&2
      exit 1
    fi
    adb shell CLASSPATH=/data/local/tmp/softap-ie.dex app_process / SoftApIe "$@" |
      sed -E 's/(Passphrase = )[^,]*/\1<redacted>/'
  '';
}

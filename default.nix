{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  cmake,
  gcc-arm-embedded,
  picotool,
  python3,
  pico-sdk,

  # Options
  picoBoard ? "pico",
  vidpid ? null,
  usbVID ? null,
  usbPID ? null,
  eddsa ? false,
  secureBootPKey ? null,
  extraCmakeFlags ? null,
}:

assert lib.assertMsg (
  !(vidpid != null && (usbVID != null || usbPID != null))
) "pico-fido: Arguments 'vidpid' and 'usbVID/usbPID' could not be set at the same time.";

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "pico-fido";
  version = "7.2";

  src = fetchFromGitHub {
    owner = "polhenarejos";
    repo = "pico-fido";
    rev = "v${finalAttrs.version}";
    hash = "sha256-PKuIFfyIULlq9xSjcYtMTVm+r+5JjIJTtscxvlCxKdE=";
    fetchSubmodules = true;
  };

  # --- FIX: Manually fetch the fork containing 'eddsa.c' ---
  mbedtlsFork = fetchFromGitHub {
    owner = "polhenarejos";
    repo = "mbedtls";
    rev = "mbedtls-3.6-eddsa";
    hash = "sha256-a2edwKskmOKMy34xsD29OW/TlfHCn5PtUKDliDGUXi8=";
  };

  strictDeps = true;

  nativeBuildInputs = [
    cmake
    gcc-arm-embedded
    picotool
    python3
  ];

  PICO_SDK_PATH = "${pico-sdk.override { withSubmodules = true; }}/lib/pico-sdk/";

  postPatch = ''
    echo "--- Patching: Neutralizing Git Commands (Global) ---"

    find . -name "*.cmake" -o -name "CMakeLists.txt" -print0 | xargs -0 sed -i 's/git submodule update/echo "Nix: Skipped git submodule update"/g'
    find . -name "*.cmake" -o -name "CMakeLists.txt" -print0 | xargs -0 sed -i 's/git checkout/echo "Nix: Skipped git checkout"/g'

    ${lib.optionalString eddsa ''
      echo "--- Patching: Injecting EdDSA mbedtls fork (eddsa=true) ---"
      rm -rf pico-keys-sdk/mbedtls
      cp -r --no-preserve=mode ${finalAttrs.mbedtlsFork} pico-keys-sdk/mbedtls
      chmod -R u+w pico-keys-sdk/mbedtls
    ''}

    echo "--- Patching Complete ---"
  '';

  cmakeFlags = [
    "-DCMAKE_C_COMPILER=${lib.getExe' gcc-arm-embedded "arm-none-eabi-gcc"}"
    "-DCMAKE_CXX_COMPILER=${lib.getExe' gcc-arm-embedded "arm-none-eabi-g++"}"
    "-DCMAKE_BUILD_TYPE=Release"
  ]
  ++ lib.optionals (picoBoard != null) [ "-DPICO_BOARD=${picoBoard}" ]
  ++ lib.optionals (vidpid != null) [ "-DVIDPID=${vidpid}" ]
  ++ lib.optionals (usbVID != null && usbPID != null) [
    "-DUSB_VID=${usbVID}"
    "-DUSB_PID=${usbPID}"
  ]
  ++ lib.optionals eddsa [ "-DENABLE_EDDSA=ON" ]
  ++ lib.optionals (secureBootPKey != null) [ "-DSECURE_BOOT_PKEY=${secureBootPKey}" ]
  ++ lib.optionals (extraCmakeFlags != null) extraCmakeFlags;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/pico-fido
    install pico_fido.uf2 $out/share/pico-fido/pico-fido-${picoBoard}-${
      if (vidpid != null) then vidpid else "none"
    }${if eddsa then "-eddsa" else ""}.uf2
    runHook postInstall
  '';

  meta = {
    changelog = "https://github.com/polhenarejos/pico-fido/releases/tag/v${finalAttrs.version}";
    description = "FIDO Passkey for Raspberry Pico and ESP32";
    homepage = "https://github.com/polhenarejos/pico-fido";
    license = lib.licenses.agpl3Only;
  };
})

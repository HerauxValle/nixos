# &desc: "gamdl (Apple Music downloader) -- not in nixpkgs; builds from GitHub via maturin/pyo3 for its Rust ammuxer extension, plus dataclass-click which nixpkgs also lacks. Also pins pymp4 to the original beardypig PyPI release (1.4.0) + construct 2.8.8: nixpkgs ships the devine-dl pymp4 fork patched for construct 2.10.70, but that combo still throws StringError building type=b\"pssh\" inside pywidevine's PSSH box construction. beardypig pymp4 1.4.0 + construct 2.8.8 is the combo verified working (tested in ~/.impure/python-venvs/widevine)."

{
  pkgs,
  python3Packages,
  fetchFromGitHub,
  rustPlatform,
  lib,
}:

let
  construct288 = python3Packages.buildPythonPackage rec {
    pname = "construct";
    version = "2.8.8";
    format = "setuptools";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/b6/2c/66bab4fef920ef8caa3e180ea601475b2cbbe196255b18f1c58215940607/construct-2.8.8.tar.gz";
      hash = "sha256-G4S4FH9v0VvPZLc3w+isUQCBGtgMgwy0slRRQFEcQVc=";
    };

    doCheck = false;
    pythonImportsCheck = [ "construct" ];

    meta = {
      description = "Powerful declarative parser (and builder) for binary data (legacy 2.8 API)";
      homepage = "https://construct.readthedocs.org/";
      license = lib.licenses.mit;
    };
  };

  pymp4Old = python3Packages.buildPythonPackage rec {
    pname = "pymp4";
    version = "1.4.0";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/aa/a2/27fea39af627c0ce5dbf6108bf969ea8f5fc9376d29f11282a80e3426f1d/pymp4-1.4.0-py3-none-any.whl";
      hash = "sha256-NAFmbB4ql6yU3/sYxaXcvUbQpDbaUnLTeKb59lBt0S0=";
    };

    format = "wheel";
    dependencies = [ construct288 ];

    pythonImportsCheck = [ "pymp4" ];

    meta = {
      description = "Python library for parsing and manipulating MP4 files (pre-2.10 construct API)";
      homepage = "https://github.com/beardypig/pymp4";
      license = lib.licenses.asl20;
    };
  };

  pywidevineFixed = python3Packages.pywidevine.overridePythonAttrs (old: {
    patches = [ ];
    dependencies = (builtins.filter (p: (p.pname or "") != "pymp4") old.dependencies) ++ [
      pymp4Old
    ];
  });

  dataclass-click = python3Packages.buildPythonPackage rec {
    pname = "dataclass-click";
    version = "1.0.4";
    pyproject = true;

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/89/82/5b6035efd90621771fa039960eab3e1ec7ff2a8625033272856843e8bd27/dataclass_click-1.0.4.tar.gz";
      hash = "sha256-EOfeY43Z5orpq9UIb2HY3e5CsYc6cPX9n9IWeFavrBE=";
    };

    build-system = [ python3Packages.poetry-core ];

    dependencies = [ python3Packages.click ];

    pythonImportsCheck = [ "dataclass_click" ];

    meta = {
      description = "Use PEP 593 annotations to define click options and arguments";
      homepage = "https://github.com/couling/dataclass-click";
      license = lib.licenses.bsd3;
    };
  };
in
python3Packages.buildPythonApplication rec {
  pname = "gamdl";
  version = "3.8.5";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "glomatico";
    repo = "gamdl";
    tag = version;
    hash = "sha256-aP0M1ZDX/TuxXbJFrfjlZ8G71eV/BlWpNRaXVFkzLzs=";
  };

  cargoRoot = "gamdl/downloader/ammuxer";
  cargoDeps = rustPlatform.importCargoLock {
    lockFile = "${src}/gamdl/downloader/ammuxer/Cargo.lock";
  };

  build-system = [ pkgs.maturin ];

  nativeBuildInputs = with rustPlatform; [
    cargoSetupHook
    maturinBuildHook
  ];

  dependencies = with python3Packages; [
    async-lru
    click
    colorama
    dataclass-click
    httpx
    httpx-retries
    inquirerpy
    m3u8
    mutagen
    pillow
    pywidevineFixed
    structlog
    yt-dlp
  ];

  pythonImportsCheck = [ "gamdl" ];

  meta = {
    description = "Command-line app for downloading Apple Music songs, music videos and post videos";
    homepage = "https://github.com/glomatico/gamdl";
    license = lib.licenses.mit;
    mainProgram = "gamdl";
  };
}

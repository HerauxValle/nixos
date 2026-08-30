# &desc: "gamdl (Apple Music downloader) -- not in nixpkgs; builds from GitHub via maturin/pyo3 for its Rust ammuxer extension, plus dataclass-click which nixpkgs also lacks."

{
  pkgs,
  python3Packages,
  fetchFromGitHub,
  rustPlatform,
  lib,
}:

let
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
    pywidevine
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

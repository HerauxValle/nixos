# &desc: "VS Code custom marketplace extensions -- fetched directly by publisher/name/version, not packaged in nixpkgs."

{ config, pkgs, ... }:

{
  config.home-manager.users.${config.vars.identity.username}.programs.vscode.profiles.default.extensions =
    [
      (pkgs.vscode-utils.extensionFromVscodeMarketplace {
        publisher = "dustypomerleau";
        name = "rust-syntax";
        version = "0.6.1";
        sha256 = "0rccp8njr13jzsbr2jl9hqn74w7ji7b2spfd4ml6r2i43hz9gn53";
      })
      (pkgs.vscode-utils.extensionFromVscodeMarketplace {
        publisher = "coopermaruyama";
        name = "nix-embedded-languages";
        version = "2.1.0";
        sha256 = "1vr5njvzxck2nx6gqw0zfghnjpwcmvli9fwx8cqj3sgk9283ya9r";
      })
    ];
}

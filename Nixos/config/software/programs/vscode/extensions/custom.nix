# &desc: "VS Code custom marketplace extensions -- fetched directly by publisher/name/version, not packaged in nixpkgs."

{ config, pkgs, ... }:

{
  config.home-manager.users.${config.vars.identity.username}.programs.vscode.profiles.default.extensions =
    [
      (pkgs.vscode-utils.extensionFromVscodeMarketplace {
        publisher = "coopermaruyama";
        name = "nix-embedded-languages";
        version = "2.1.0";
        sha256 = "1vr5njvzxck2nx6gqw0zfghnjpwcmvli9fwx8cqj3sgk9283ya9r";
      })
      (pkgs.vscode-utils.extensionFromVscodeMarketplace {
        publisher = "dustypomerleau";
        name = "rust-syntax";
        version = "0.6.1";
        sha256 = "0rccp8njr13jzsbr2jl9hqn74w7ji7b2spfd4ml6r2i43hz9gn53";
      })
      # Auto-start docker-compose services for a workspace
      (pkgs.vscode-utils.extensionFromVscodeMarketplace {
        publisher = "george3447";
        name = "docker-run";
        version = "1.1.0";
        sha256 = "182nshcszawyrrkdnvhph6015m59jr8aa3xyqdl5z5g9bws43syk";
      })
      # Prettier formatting for .sql files (base prettier-vscode doesn't cover SQL)
      (pkgs.vscode-utils.extensionFromVscodeMarketplace {
        publisher = "inferrinizzard";
        name = "prettier-sql-vscode";
        version = "1.6.0";
        sha256 = "1d4vf3gh2x4ycf8ppvvb5d6rsg2ayckd05rkp3w1kw5gxgzmzalp";
      })
      # Rustdoc viewer -- opens generated docs for the item under the cursor
      (pkgs.vscode-utils.extensionFromVscodeMarketplace {
        publisher = "JScearcy";
        name = "rust-doc-viewer";
        version = "4.2.0";
        sha256 = "0fizwx057nghy8k0xz66f1narxps47d5asl26jr7aq1h1ypncnn7";
      })
      # cpptools-extension-pack member -- not packaged in nixpkgs, see c_cpp.nix
      (pkgs.vscode-utils.extensionFromVscodeMarketplace {
        publisher = "ms-vscode";
        name = "cpp-devtools";
        version = "0.6.9";
        sha256 = "08rkb3cpvq8d3jpi54jxpkgyh59rwqqxdc5628m31xh2c3m6f2h2";
      })
      # cpptools-extension-pack member -- not packaged in nixpkgs, see c_cpp.nix
      (pkgs.vscode-utils.extensionFromVscodeMarketplace {
        publisher = "ms-vscode";
        name = "cpptools-themes";
        version = "2.0.0";
        sha256 = "05r7hfphhlns2i7zdplzrad2224vdkgzb0dbxg40nwiyq193jq31";
      })
      # Generates mod.rs boilerplate for a new Rust module
      (pkgs.vscode-utils.extensionFromVscodeMarketplace {
        publisher = "ZhangYue";
        name = "rust-mod-generator";
        version = "1.0.12";
        sha256 = "048ds2mvmihvz5rqz9b2igrpkn1bmjq7xs7pci29n4m9g1n1r5j8";
      })
    ];
}

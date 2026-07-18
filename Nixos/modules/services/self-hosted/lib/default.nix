# &desc: "Self-hosted service library imports -- plain function imports (service/, venv/, mk-from-native/), acl-traversal/ with real options."

{ ... }:

# lib/ itself is mostly plain functions (./service/, ./venv/,
# ./mk-from-native/ -- none of those have options/config, only ever
# consumed via plain `import` calls from self-hosted.nix, never listed
# here). ./acl-traversal/ is the one exception with real options/config
# of its own (vars.selfHosted.aclTraversal) -- imported here, one folder
# down, same as every other default.nix in this tree only ever
# reaching one level into its own children.
{
  imports = [ ./acl-traversal ];
}


{ ... }:

# &desc: "UUIDs of the devices actually hidden from udisks2/Dolphin on this machine -- data only."

# Real values -- schema + the udev-rule generation live in
# ../../modules/system/hidden-devices.nix. Data only, same reasoning as
# every config/<category>/<name>.nix file.
{
  config.vars.system.hiddenDevices = [
    "16dab0c7-d947-4a28-8db7-de8f2c82fb6f" # root filesystem (decrypted, label "nixos")
    "80b7960d-fb8d-4dc3-8b01-329770c6e027" # root's LUKS container (sda2, locked view)
    "88426A11426A03F2" # Windows "Basic data partition" (nvme0n1p3, unlabeled NTFS)
    "45c06c40-9610-45ef-8d47-5938d6129e7e" # Vaults vault -- raw LUKS container (the .img duplicate)
    "3f6f7485-0ac4-49f1-aafb-5430bc39d21f" # Davinci vault -- raw LUKS container
    "35b91a19-68aa-4856-8538-df295e12ab1d" # Tor vault -- raw LUKS container
    "28dcfdfb-9e78-41a2-910a-4a132617e7b9" # SelfHosted vault -- raw LUKS container
    "1912efe3-08fc-4ef3-8c36-40b6ea629c1b" # Modrinth vault -- raw LUKS container
    "e8db5655-bafc-450e-8fb1-bfdc983c3ea5" # Media vault -- raw LUKS container
  ];
}

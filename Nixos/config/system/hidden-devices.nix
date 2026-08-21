
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
    "e7a00110-6fc4-4d44-b7ce-28cbd9fe3d16" # Vaults vault -- raw LUKS container (the .img duplicate)
    "35b91a19-68aa-4856-8538-df295e12ab1d" # Tor vault -- raw LUKS container
    "1f06e9b3-01f3-4663-bf03-50857e075bac" # SelfHosted vault -- raw LUKS container
    "7c0c6661-6339-4fda-8cf6-7bff2a49294e" # Media vault -- raw LUKS container
    "fbc05a0b-f324-44bf-af90-b3027163cb84" # Minecraft vault -- raw LUKS container (the .img duplicate)
  ];
}

# &desc: "Turns on Prism Launcher's portable data dir (schema + activation logic in modules/services/minecraft-prism) and picks its location."

{ ... }:

{
  vars.minecraft.prism = {
    portable = true;
    location = "/home/herauxvalle/Images/Minecraft/prism";
  };
}

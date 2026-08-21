# &desc: "Mountpoint LABEL/NAME resolver bash function -- lsblk live queries (label/name/auto modes), shared by all mount-entry snippets, called per-entry."

{ lsblk }:

# Bash function shared by every entry's ../mount-entry/ snippet -- reads
# the disk's own LABEL/NAME live, which eval time can't reliably do (see
# ../../mountpoints.nix for why). Emitted once in the activation script
# preamble, called once per entry that needs it.
#
# resolve-leaf.sh is a real standalone bash file -- @LSBLK_BIN@ is the
# only dynamic bit, substituted in verbatim below.
builtins.replaceStrings [ "@LSBLK_BIN@" ] [ "${lsblk}" ] (builtins.readFile ./resolve-leaf.sh)

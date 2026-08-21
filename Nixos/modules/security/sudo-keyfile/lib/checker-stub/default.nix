# &desc: "Setuid-root C stub -- execve()s bash directly (bypasses binfmt_script) with -p (keeps euid=0 despite ruid!=euid) running the real checker script."

{ pkgs, checker }:

# security.wrappers' setuid stub calls execve() on its `source` file
# directly. If that's a shebang script (which writeShellApplication's
# output always is), the kernel's binfmt_script handler strips the
# elevated privilege before running it -- this is a hard, deliberate
# Linux restriction against the classic setuid-script vulnerability
# class, applied unconditionally, even when the calling process is
# *already* root via its own (separate) setuid bit.
#
# Fix: this tiny compiled stub is what actually gets wrapped instead.
# It execve()s the real bash binary directly (a plain ELF, no shebang
# involved at the kernel level) with the checker script as bash's own
# argument -- bash then just reads/interprets that file as data, never
# triggering binfmt_script.
#
# That alone still wasn't enough (confirmed live: euid was still 1000
# inside the script) -- bash itself has a SEPARATE safety behavior:
# whenever real uid != effective uid at startup (exactly this setuid
# scenario: ruid=1000 from the calling user, euid=0 from the setuid
# wrapper), bash silently resets its effective uid back to the real uid
# unless started with `-p`. `sudo <stub>` alone "worked" in testing only
# because real sudo sets ruid=euid=0 (no mismatch, so the auto-drop
# never triggers there) -- masking this exact issue.
#
# check-stub.c is a real standalone C file -- @BASH_BIN@/@CHECKER_BIN@
# are the only two dynamic bits (both Nix store paths), substituted in
# verbatim below.
pkgs.writeCBin "sudo-keyfile-check-stub" (
  builtins.replaceStrings [ "@BASH_BIN@" "@CHECKER_BIN@" ] [
    "${pkgs.bash}/bin/bash"
    "${checker}/bin/sudo-keyfile-check"
  ] (builtins.readFile ./check-stub.c)
)

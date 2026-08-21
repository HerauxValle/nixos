# --- INTERACTIVE SHELLS ---
function :b:; exec bash -i; end  #&help:"Switch to interactive Bash session"
function :n:; exec nu; end       #&help:"Switch to interactive Nushell session"
function :p:; exec pwsh -NoLogo; end #&help:"Switch to interactive PowerShell session"
function :f:; exec fish; end     #&help:"Restart interactive Fish session"

# --- EXPLICIT TARGETS ---
function :f; eval "$argv"; end   #&help:"Run command in Fish"
function :b; bash -ic "$argv"; end #&help:"Run command in Bash"
function :n; nu -c "$argv"; end  #&help:"Run command in Nushell"
function :p; pwsh -NoLogo -NoProfile -Command "$argv"; end #&help:"Run command in PowerShell"
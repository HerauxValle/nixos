# Starship for Pwsh (Argument must be 'powershell')
Invoke-Expression (&starship init powershell)

# Back to fish alias
Set-Alias -Name f -Value fish

function :b: { bash -i }
function :n: { nu }
function :p: { pwsh -NoLogo }
function :f: { fish }
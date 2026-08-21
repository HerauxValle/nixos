#&help:"Executes a script in .dtmp temp path"
function dtmp --description "Run a command using ~/.dtmp as the temp folder"
    set -l tmp_dir $HOME/.dtmp
    # Create the folder if it doesn't exist
    mkdir -p $tmp_dir
    
    # Run the command with the redirected TMPDIR
    env TMPDIR=$tmp_dir $argv
end
#&help:"Executes Tree and Cat the path"
function cats --description "Tree and cat everything with smart clipboard options"
    # 1. Show usage
    if test (count $argv) -eq 0
        set_color cyan; echo "Usage: cats <path> [options]"
        set_color normal; echo "Options:"
        echo "  -depth:<n>      Set max search depth (default: 999)"
        echo "  -in:<path>      Save output to a file"
        echo "  -cp / -cp:text  Copy generated text content"
        echo "  -cp:file        Copy as a file (overwrites previous temp copy)"
        echo ""
        echo "Example: cats ~/Dotfiles -depth:2 -cp:file"
        return 0
    end

    # --- CONFIGURATION ---
    set -l target ""
    set -l depth 999
    set -l out ""
    set -l copy_text false
    set -l copy_file false

    # 2. Manual Parser
    for arg in $argv
        if string match -q -- "-depth:*" "$arg"
            set depth (string split -- ":" "$arg")[2]
        else if string match -q -- "-in:*" "$arg"
            set -l raw (string split -- ":" "$arg")[2]
            set out (string replace -r -- '^~' "$HOME" "$raw")
        else if string match -q -- "-cp" "$arg"; or string match -q -- "-cp:text" "$arg"
            set copy_text true
        else if string match -q -- "-cp:file" "$arg"
            set copy_file true
        else
            set -l expanded (string replace -r -- '^~' "$HOME" "$arg")
            if test -e "$expanded"
                set target "$expanded"
            else
                set_color yellow; echo "Unknown path or option: $arg"
                set_color normal; echo "Try 'cats' without arguments for usage."
                return 0
            end
        end
    end

    if test -z "$target"; set target "."; end

    # 3. Output Path Formatting
    if test -n "$out"
        set out (string replace -r -- '^~' "$HOME" "$out")
        if test -d "$out"
            set out (string trim -c / "$out")"/outputCat.txt"
        else
            set -l ext (path extension "$out")
            if test "$ext" != ".txt"; set out "$out.txt"; end
        end
    end

    # 4. Create the Temp File
    # We use a fixed name so we don't spam /tmp with random strings
    set -l tmp_clipboard "/tmp/cats_last_output.txt"
    set -l tmp_working (mktemp)

    # 5. Execute Logic
    begin
        echo "--- FOLDER STRUCTURE ---"
        tree -a -L "$depth" -I ".git|node_modules|.cache" "$target" 2>/dev/null
        echo -e "\n--- FILE CONTENTS ---"
        find "$target" -maxdepth "$depth" -not -path '*/.*' -type f -readable 2>/dev/null | while read -l f
            if file --mime "$f" | grep -q "text/"
                echo "------------------------------------------------"
                echo "FILE: $f"
                echo "------------------------------------------------"
                cat "$f"
                echo ""
            end
        end
    end > $tmp_working

    # 6. Final Delivery

    # Action: Copy Text
    if test "$copy_text" = true
        if type -q wl-copy
            wl-copy -t text/plain < $tmp_working
            echo "✓ Text content copied to clipboard"
        end
    end

    # Action: Copy File
    if test "$copy_file" = true
        # Move working file to the fixed clipboard path
        cp $tmp_working $tmp_clipboard
        
        # If -in was specified, also copy it there
        if test -n "$out"
            mkdir -p (dirname "$out")
            cp $tmp_working "$out"
            echo "✓ File saved and copied: $out"
            wl-copy --type text/uri-list "file://$out"
        else
            wl-copy --type text/uri-list "file://$tmp_clipboard"
            echo "✓ File copied to clipboard: $tmp_clipboard"
        end
    end

    # Action: Save to File (if not handled by cp:file)
    if test -n "$out"; and not test "$copy_file" = true
        mkdir -p (dirname "$out")
        cp $tmp_working "$out"
        echo "✓ Successfully saved to: $out"
    end

    # Action: Print to Terminal
    if test -z "$out"; and test "$copy_text" = false; and test "$copy_file" = false
        cat $tmp_working
    end

    # Cleanup the working file
    rm -f $tmp_working
end
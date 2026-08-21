#&help:"Convert .md to .pdf via pandoc (preset: legal)"
function mdf
    set file $argv[1]
    set preset $argv[3]

    if test -z "$file"
        read -P "Path to .md file: " file
    end

    if not test -f "$file"
        echo "File not found"
        return 1
    end

    set out (string replace -r '\.md$' '.pdf' "$file")

    # engine selection
    if test "$preset" = "legal"; and command -v xelatex >/dev/null
        set engine xelatex
        pandoc "$file" -o "$out" \
            --pdf-engine=$engine \
            -V geometry:margin=12mm \
            -V fontsize=10pt \
            -V linestretch=1.15 \
            -V mainfont="TeX Gyre Termes"
    else if command -v pdflatex >/dev/null
        set engine pdflatex
        pandoc "$file" -o "$out" \
            --pdf-engine=$engine \
            -V geometry:margin=12mm \
            -V fontsize=10pt \
            -V linestretch=1.15
    else
        pandoc "$file" -o "$out" --pdf-engine=wkhtmltopdf
    end

    echo "Created: $out"
end
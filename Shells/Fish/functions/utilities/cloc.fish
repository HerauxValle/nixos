#&help:"Uses cloc with exclude dirs"
function clo --wraps cloc --description "cloc with sane excludes"
    cloc $argv \
        --exclude-dir=.git,.hg,.svn,.jj,node_modules,vendor,target,build,dist,out,result,results,bin,obj,__pycache__,.mypy_cache,.pytest_cache,.ruff_cache,.tox,.nox,.venv,venv,env,.env,.direnv,.cache,.gradle,.idea,.vscode,.vs,.dart_tool,.next,.nuxt,.svelte-kit,.parcel-cache,.turbo,coverage,htmlcov,.terraform,.terragrunt-cache,.zig-cache,zig-out \
        --exclude-ext=lock,png,jpg,jpeg,gif,webp,svg,ico,pdf,zip,tar,gz,xz,7z,bin,exe,dll,so,dylib,class,o,a,pyc,pyo
end

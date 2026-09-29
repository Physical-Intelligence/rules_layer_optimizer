function trim_slash(path) {
    sub(/\/$/, "", path)
    return path
}

# Package directory of prefix "my/pkg/app" is "my/pkg". A root binary has none.
function package_dir(pref,    n, parts, pkg, i) {
    n = split(pref, parts, "/")
    if (n < 2) return ""
    pkg = parts[1]
    for (i = 2; i < n; i++) pkg = pkg "/" parts[i]
    return pkg
}

function is_runfiles(path, pref,    root) {
    root = pref ".runfiles"
    return path == root || index(path, root "/") == 1
}

BEGIN {
    while ((getline line < classification) > 0) {
        split(line, fields, " ")
        kinds[fields[2]] = fields[1]
    }
    close(classification)
    print "#mtree" > source
    print "#mtree" > interpreter
}
/^#/ { next }
{
    # The entrypoint is rewritten to ./app. Parent directories of the binary,
    # and package files that are not the binary or its runfiles, would make a
    # root directory named like that file (package "app" vs entrypoint ./app).
    # Those sources are already in the runfiles tree.
    path = trim_slash($1)
    pkg = package_dir(prefix)
    if (pkg != "" && path != prefix && index(prefix, path "/") == 1) next
    if (pkg != "" && index(path, pkg "/") == 1 && path != prefix && !is_runfiles(path, prefix)) next
    kind = "source"
    for (i = 2; i <= NF; i++) {
        if ($i ~ /^contents?=/) {
            content = $i
            sub(/^contents?=/, "", content)
            if (content in kinds) kind = kinds[content]
        }
    }
    if (kind == "pip") next
    if ($1 == prefix || index($1, prefix ".runfiles/") == 1) {
        $1 = "./app" substr($1, length(prefix) + 1)
    }
    if (kind == "interpreter") print > interpreter
    else print > source
}

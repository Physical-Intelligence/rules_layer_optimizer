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

BEGIN { print "#mtree" > source }
ARGIND == 1 {
    split($0, fields, "\t")
    destination = fields[1]
    if (destination != "-" && !(destination in initialized)) {
        print "#mtree" > destination
        initialized[destination] = 1
    }
    if (fields[2] != "") {
        destinations[++count] = destination
        patterns[count] = fields[2]
    }
    next
}
/^#/ { next }
{
    # The entrypoint is rewritten to ./app. Parent directories of the binary,
    # and package files that are not the binary or its runfiles, would make a
    # root directory named like that file. Those sources are already in runfiles.
    path = trim_slash($1)
    pkg = package_dir(prefix)
    if (pkg != "" && path != prefix && index(prefix, path "/") == 1) next
    if (pkg != "" && index(path, pkg "/") == 1 && path != prefix && !is_runfiles(path, prefix)) next
    if ($1 == prefix || $1 == prefix ".runfiles" || index($1, prefix ".runfiles/") == 1) {
        $0 = "./app" substr($0, length(prefix) + 1)
    }
    destination = source
    for (i = 1; i <= count; i++) {
        if ($1 ~ patterns[i]) {
            destination = destinations[i]
            break
        }
    }
    if (destination != "-") print $0 >> destination
}

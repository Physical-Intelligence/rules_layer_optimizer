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

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

# Drops mtree rows whose path is layered separately as a PyO3 extension. The key
# is everything before the first literal space, matching the mtree row format.
#
# Variables (-v): excluded_file, out

BEGIN {
    while ((getline entry < excluded_file) > 0) excluded[entry]
}
{
    space = index($0, " ")
    key = (space ? substr($0, 1, space - 1) : $0)
    if (!(key in excluded)) print > out
}

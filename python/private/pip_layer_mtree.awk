# Emits an mtree spec for one wheel's site-packages payload.
#
# `filelist` holds Bazel's expansion of the wheel TreeArtifact, one path per
# line. Row order fixes tar entry order and therefore the layer digest, and
# Bazel documents no ordering for the expansion, so the rows are sorted here.
# LC_ALL=C makes that sort byte-wise rather than locale-dependent.
#
# Variables (-v): filelist, src, prefix, out
BEGIN {
    n = 0
    while ((getline path < filelist) > 0) paths[++n] = path
    PROCINFO["sorted_in"] = "@val_str_asc"

    print "#mtree" > out
    for (i in paths) {
        f = paths[i]
        rel = substr(f, length(src) + 2)

        if (index(rel, "/site-packages/") == 0) continue

        entry = prefix "/" rel
        gsub(/ /, "\\040", entry)
        contents = f
        gsub(/ /, "\\040", contents)

        print entry " type=file mode=0755 uid=0 gid=0 time=1672560000 contents=" contents > out
    }
}

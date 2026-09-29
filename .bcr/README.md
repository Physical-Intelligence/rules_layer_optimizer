# Releases

Update the version in `MODULE.bazel` and the README installation example, then push a matching
`vX.Y.Z` tag on the release commit. The [Release workflow](../.github/workflows/release.yaml)
uses the shared Bazel ruleset workflow to test, package, attest, and publish the
source archive, checksum metadata, and installation snippet. Tags containing a
hyphen produce prereleases. Packaging rejects tags that do not match the module
version, as well as placeholder versions.

The repository's **Release tags** ruleset restricts creation, updates, and deletion
of `v*` tags to maintainers and administrators. Release authority is managed in
GitHub repository settings.

The BCR templates use that release asset. Registry submission is a separate step;
these templates follow [publish-to-bcr](https://github.com/bazel-contrib/publish-to-bcr/tree/main/templates/.bcr).

For a local rehearsal:

```sh
bazel run //tools:release -- --output /tmp/rules_layer_optimizer_release --verify
```

This creates a deterministic archive, `source.json`, and
`installation.MODULE.bazel`. Verification runs independent smoke and image
consumers against the archive. Archives use `git archive` and the exclusions in `.gitattributes`. Local
preparation packages **committed HEAD**, excluding dirty and untracked changes.
Commit changes before rehearsing a release. Release automation archives the
version tag itself and reads its module version. Test consumers omit the version
and use checkout overrides, so they need no version edits. Verification fixtures remain
in the checkout and consume the resulting archive.

For local archive installation, copy the generated `installation.MODULE.bazel`
into your consumer's module setup. It includes `bazel_dep` and `archive_override`
with a file URL and checksum. Release assets contain the equivalent GitHub URL.

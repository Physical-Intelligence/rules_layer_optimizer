# Query the resolved graph, not the requested versions in MODULE.bazel.
def selected($name): [.. | objects | select(.name? == $name) | .version] | unique;
selected("aspect_rules_py") == ["2.0.0-alpha.4"] and
selected("rules_python") == ["1.9.0"] and
selected("rules_oci") == ["1.1.0"] and
selected("rules_img") == ["0.3.12"]

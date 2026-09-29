"""Python-aware inference adapters for configured pip hubs."""

# buildifier: disable=bzl-visibility
load("//apt/private:inferred_apt_deps.bzl", "make_inferred_apt_deps", _apt_inference = "apt_inference")

# buildifier: disable=bzl-visibility
load("//inference/private:inferred_env.bzl", "make_env_file", _env_inference = "env_inference")

# buildifier: disable=bzl-visibility
load("//inference/private:inferred_layers.bzl", "make_inferred_layers", _layer_inference = "layer_inference")
load("//python/private:pip_deps.bzl", "pip_deps_aspect")
load("//python/private:pip_utils.bzl", "configured_pip_package", "pip_inference_key")

inferred_layers = make_inferred_layers([pip_deps_aspect])
inferred_apt_deps = make_inferred_apt_deps([pip_deps_aspect])
env_file = make_env_file([pip_deps_aspect])

def layer_inference(name, for_deps, layers, **kwargs):
    """Register layer inference with logical pip-package matching."""
    triggers = _triggers(for_deps)
    _layer_inference(name = name, for_deps = triggers.labels, for_keys = triggers.keys, layers = layers, **kwargs)

def apt_inference(name, for_deps = [], packages = [], tars = [], **kwargs):
    """Register APT inference with logical pip-package matching."""
    triggers = _triggers(for_deps)
    _apt_inference(name = name, for_deps = triggers.labels, for_keys = triggers.keys, packages = packages, tars = tars, **kwargs)

def env_inference(name, env, for_deps = [], **kwargs):
    """Register environment inference with logical pip-package matching."""
    triggers = _triggers(for_deps)
    _env_inference(name = name, for_deps = triggers.labels, for_keys = triggers.keys, env = env, **kwargs)

def _triggers(for_deps):
    labels = []
    keys = []
    for dep in for_deps:
        label = native.package_relative_label(dep)
        package = configured_pip_package(label)
        labels.append(str(label))
        if package != None:
            keys.append(pip_inference_key(package))
    return struct(labels = labels, keys = keys)

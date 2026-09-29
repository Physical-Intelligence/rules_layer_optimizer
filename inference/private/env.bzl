"""Utility functions for working with operating system attributes."""

DEFAULT_ENV_SEPARATORS = {"PATH": ":", "LD_LIBRARY_PATH": ":", "PYTHONPATH": ":"}

def merge_env(env1, env2, separators = DEFAULT_ENV_SEPARATORS):
    """Merges two environment dictionaries.

    If a key exists in both dictionaries and merging is supported, the value from env2 is appended to the value from env1.

    Args:
        env1: The first environment dictionary.
        env2: The second environment dictionary.
        separators: Variables allowed to merge, mapped to their joining separator.

    Returns:
        A new environment dictionary with the merged values.
    """
    if not env1:
        return env2
    if not env2:
        return env1

    new_env = {}
    new_env.update(env1)

    for key, value in env2.items():
        if key in new_env:
            if key in separators:
                new_env[key] = new_env[key] + separators[key] + value
            else:
                fail("Unsupported merge of environment variable '{}' between env1 ({}) and env2 ({}).".format(key, env1, env2))
        else:
            new_env[key] = value

    return new_env

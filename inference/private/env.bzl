"""Utility functions for working with operating system attributes."""

def merge_env(env1, env2):
    """Merges two environment dictionaries.

    If a key exists in both dictionaries and merging is supported, the value from env2 is appended to the value from env1.

    Args:
        env1: The first environment dictionary.
        env2: The second environment dictionary.

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
            if key in _COLON_DELIMITED_ENV_VARS:
                new_env[key] = new_env[key] + ":" + value
            elif key in _SPACE_DELIMITED_ENV_VARS:
                new_env[key] = new_env[key] + " " + value
            else:
                fail("Unsupported merge of environment variable '{}' between env1 ({}) and env2 ({}).".format(key, env1, env2))
        else:
            new_env[key] = value

    return new_env

_COLON_DELIMITED_ENV_VARS = [
    "PATH",
    "LD_LIBRARY_PATH",
    "PYTHONPATH",
]

_SPACE_DELIMITED_ENV_VARS = [
    "XLA_FLAGS",
]

"""Exercise an extracted rules_python runtime with package metadata and data."""

import importlib.metadata
import os

import colorama
import dateutil.parser


def main() -> None:
    assert importlib.metadata.version("colorama") == "0.4.6"
    assert os.environ["COLORAMA_AVAILABLE"] == "1"
    assert dateutil.parser.parse("2026-09-29").year == 2026
    assert importlib.metadata.version("six") == "1.17.0"
    assert colorama.Fore.GREEN
    print("standalone rules_python layers work")


if __name__ == "__main__":
    main()

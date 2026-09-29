"""Small application used to inspect Python image layers."""

import importlib.metadata
import os

import colorama


def main() -> None:
    assert importlib.metadata.version("colorama") == "0.4.6"
    assert os.environ["COLORAMA_AVAILABLE"] == "1"
    print(colorama.Fore.GREEN + "hello from reusable layers" + colorama.Style.RESET_ALL)


if __name__ == "__main__":
    main()

"""Small application packaged by the two-argument py_image macro."""

import importlib.metadata
import os

import backports.strenum
import backports.tarfile
import colorama
import google_crc32c


def main() -> None:
    assert importlib.metadata.version("colorama") == "0.4.6"
    assert google_crc32c.implementation == "c"
    assert google_crc32c.value(b"123456789") == 0xE3069283
    assert backports.tarfile.TarInfo("fixture").name == "fixture"
    assert issubclass(backports.strenum.StrEnum, str)
    assert importlib.metadata.version("google-crc32c") == "1.7.1"
    assert os.environ["COLORAMA_AVAILABLE"] == "1"
    print(colorama.Fore.GREEN + "hello from py_image" + colorama.Style.RESET_ALL)


if __name__ == "__main__":
    main()

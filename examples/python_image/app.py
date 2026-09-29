"""Small application used to inspect Python image layers."""

import colorama


def main() -> None:
    print(colorama.Fore.GREEN + "hello from reusable layers" + colorama.Style.RESET_ALL)


if __name__ == "__main__":
    main()

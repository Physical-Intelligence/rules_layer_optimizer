"""Load the py_image into Docker and run its Python entrypoint."""

import subprocess
import sys


def _run(args: list[str]) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, check=False, capture_output=True, text=True)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    return result


def _image_ref(load_stdout: str) -> str:
    for line in load_stdout.splitlines():
        if line.startswith("Loaded image: "):
            return line.removeprefix("Loaded image: ").strip()
        if line.startswith("Loaded image ID: "):
            return line.removeprefix("Loaded image ID: ").strip()
    raise AssertionError("docker load did not report an image:\n{}".format(load_stdout))


def _check(result: subprocess.CompletedProcess[str], what: str) -> None:
    assert result.returncode == 0, "{} failed ({}):\n{}".format(what, result.returncode, result.stderr)


def test_image(load_script: str, python: str) -> None:
    loaded = _run([load_script])
    _check(loaded, "docker load")
    image = _image_ref(loaded.stdout)

    ran = _run(["docker", "run", "--rm", "--network", "none", image])
    _check(ran, "image entrypoint")
    assert "hello from py_image" in ran.stdout

    printed = _run([
        "docker",
        "run",
        "--rm",
        "--network",
        "none",
        "--entrypoint",
        python,
        image,
        "-c",
        "print('py_image python ok')",
    ])
    _check(printed, "python -c")
    assert printed.stdout.strip() == "py_image python ok"


if __name__ == "__main__":
    test_image(sys.argv[1], sys.argv[2])

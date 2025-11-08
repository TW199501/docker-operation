import pathlib
import shlex
import shutil
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]


def _detect_wsl() -> bool:
    try:
        result = subprocess.run(
            ["bash", "-lc", "command -v wslpath >/dev/null"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="ignore",
        )
        return result.returncode == 0
    except FileNotFoundError:
        return False


WSL_EXE = shutil.which("wsl.exe")
USE_WSL = _detect_wsl() and WSL_EXE is not None


def to_bash_path(path: pathlib.Path) -> str:
    posix_path = path.as_posix()
    if len(posix_path) > 2 and posix_path[1] == ":" and posix_path[0].isalpha():
        drive = posix_path[0].lower()
        remainder = posix_path[3:]
        return f"/mnt/{drive}/{remainder}" if USE_WSL else posix_path
    return posix_path


def run_tests(*args: str) -> subprocess.CompletedProcess:
    quoted_args = " ".join(shlex.quote(arg) for arg in args)
    script_rel = "tests/run_all_tests.sh"
    if USE_WSL:
        wsl_root = to_bash_path(ROOT)
        script_cmd = f"bash {script_rel}"
        if quoted_args:
            script_cmd = f"{script_cmd} {quoted_args}"
        wsl_command = f"cd {shlex.quote(wsl_root)} && {script_cmd}"
        return subprocess.run(
            [WSL_EXE, "--", "bash", "-lc", wsl_command],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )

    script_path = ROOT / script_rel
    return subprocess.run(
        ["bash", str(script_path), *args],
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


class TestNginxScripts(unittest.TestCase):
    def test_all(self) -> None:
        result = run_tests("all")
        self.assertEqual(
            result.returncode,
            0,
            msg=f"run_all_tests.sh all failed:\n{result.stdout}\n{result.stderr}",
        )

    def test_unit(self) -> None:
        result = run_tests("unit")
        self.assertEqual(
            result.returncode,
            0,
            msg=f"run_all_tests.sh unit failed:\n{result.stdout}\n{result.stderr}",
        )

    def test_integration(self) -> None:
        result = run_tests("integration")
        self.assertEqual(
            result.returncode,
            0,
            msg=f"run_all_tests.sh integration failed:\n{result.stdout}\n{result.stderr}",
        )


if __name__ == "__main__":
    unittest.main()

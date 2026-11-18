"""Exercise the real embedded resolver and distro matcher without network/install."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = (Path(__file__).resolve().parents[1] / "install.sh").read_text()
RESOLVER = SCRIPT.split("<<'PYVERSIONS'\n", 1)[1].split("\nPYVERSIONS", 1)[0]
DISTRO_CASE = 'case " $ID ${ID_LIKE:-} " in' + SCRIPT.split(
    'case " $ID ${ID_LIKE:-} " in', 1
)[1].split("\nesac", 1)[0] + "\nesac\nprintf '%s' \"$distro\""


class UpstreamVersions(unittest.TestCase):
    def resolve(self, html="Latest Python 3 Release - Python 3.15.2</a>", nodes=None,
                with_python=True):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "node-index.json").write_text(json.dumps(nodes if nodes is not None else [
                {"version": "v24.99.0", "lts": "Example"},
                {"version": "v28.9.0", "lts": False},
                {"version": "v28.10.0", "lts": False},
                {"version": "v29.0.0-rc.1", "lts": False},
                {"version": "v30.0.0-nightly-test", "lts": False},
            ]))
            (root / "go-index.json").write_text(json.dumps([
                {"version": "go1.27.9", "stable": True},
                {"version": "go1.27.10", "stable": True},
                {"version": "go1.28rc1", "stable": False},
                {"version": "go1.29.0", "stable": False},
            ]))
            if html is not None:
                (root / "python-source.html").write_text(html)
            return subprocess.run(
                ["python3", "-c", RESOLVER, directory, "1" if with_python else "0"],
                text=True, capture_output=True, check=False,
            )

    def test_newest_stable_not_lts_or_prerelease(self):
        result = self.resolve()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "28.10.0 1.27.10 3.15.2")

    def test_default_does_not_require_python_metadata(self):
        result = self.resolve(html=None, with_python=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "28.10.0 1.27.10 -")

    def test_python_is_opt_in_and_flags_accept_either_order(self):
        options = "usage() {" + SCRIPT.split("usage() {", 1)[1].split(
            '[[ $(uname -s)', 1
        )[0]
        for args, expected in (([], "0 0"), (["--yes"], "1 0"),
                               (["--with-python"], "0 1"),
                               (["--yes", "--with-python"], "1 1"),
                               (["--with-python", "--yes"], "1 1")):
            with self.subTest(args=args):
                result = subprocess.run(
                    ["bash", "-c", options + '\nprintf "%s %s" "$assume_yes" "$install_python"',
                     "test", *args], text=True, capture_output=True, check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, expected)

    def test_python_layout_change_fails_closed(self):
        result = self.resolve("Python 3.16.0rc1</a>")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot determine latest stable Python", result.stderr)

    def test_missing_stable_node_fails_closed(self):
        result = self.resolve(nodes=[{"version": "v29.0.0-rc.1"}])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No stable release", result.stderr)

    def test_linux_mint_and_lmde_use_apt(self):
        for related in ("ubuntu debian", "debian", ""):
            with self.subTest(id_like=related):
                result = subprocess.run(
                    ["bash", "-c", 'ID=linuxmint; ID_LIKE="$1"; ' + DISTRO_CASE,
                     "test", related], text=True, capture_output=True, check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "debian")


if __name__ == "__main__":
    unittest.main()

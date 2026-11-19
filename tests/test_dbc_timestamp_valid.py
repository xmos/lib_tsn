"""Simulator test for the 1722 DBC and timestamp checks of talker packets.

The test application (dbc_timestamp_valid/main.xc) builds talker packets for
several channel counts and sample rates and exits with status 1 on the first
invalid packet. Its output is compared line by line against
dbc_timestamp_valid.expect.

Requires the XTC Tools environment (xcc, xmake, xsim) and the test_support
Pyxsim package on PYTHONPATH; see requirements.txt.
"""
import subprocess
from pathlib import Path

import pytest
from Pyxsim import run_on_simulator_
from Pyxsim.testers import ComparisonTester

TESTS_DIR = Path(__file__).resolve().parent
APP_DIR = TESTS_DIR / "dbc_timestamp_valid"
BUILD_DIR = APP_DIR / "build"
XE_PATH = APP_DIR / "bin" / "dbc_timestamp_valid.xe"
EXPECT_PATH = TESTS_DIR / "dbc_timestamp_valid.expect"


@pytest.fixture(scope="session")
def xe_path():
    """Build the test application with XCommon CMake and return the .xe path."""
    subprocess.run(
        ["cmake", "-G", "Unix Makefiles", "-S", str(APP_DIR), "-B", str(BUILD_DIR)],
        check=True,
    )
    subprocess.run(["xmake", "-C", str(BUILD_DIR)], check=True)
    assert XE_PATH.exists(), f"build did not produce {XE_PATH}"
    return XE_PATH


def test_dbc_timestamp_valid(xe_path, capfd):
    expected = EXPECT_PATH.read_text().splitlines()
    tester = ComparisonTester(expected)

    result = run_on_simulator_(str(xe_path), tester=tester, capfd=capfd, timeout=300)

    assert result is True

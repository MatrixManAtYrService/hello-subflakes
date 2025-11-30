"""Unit tests for the hello_py library."""

import pytest
from hello_py import hello


def test_hello_basic():
    """Test basic hello functionality."""
    result = hello("world")
    assert result == "hello world"

def test_hello_empty_string():
    """Test hello with an empty string."""
    result = hello("")
    assert result == "hello "

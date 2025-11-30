"""Python library with FFI bindings to hello-rs Rust library."""

from hello_py._rust import hello

__all__ = ["hello"]

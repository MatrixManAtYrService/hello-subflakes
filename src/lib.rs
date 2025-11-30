use pyo3::prelude::*;

// Import the Rust library
use hello_rs;

/// A Python wrapper around the Rust hello function
#[pyfunction]
fn hello(name: &str) -> String {
    hello_rs::hello(name)
}

/// The Python module that exposes the Rust functions
#[pymodule]
#[pyo3(name = "_rust")]
fn hello_py(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(hello, m)?)?;
    Ok(())
}

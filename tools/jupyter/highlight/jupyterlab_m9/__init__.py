"""M9 syntax highlighting for JupyterLab: a prebuilt extension (see
../pyproject.toml); this package only tells Jupyter where it is."""


def _jupyter_labextension_paths():
    return [{"src": "labextension", "dest": "jupyterlab-m9"}]

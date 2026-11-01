"""Load kebab-case *.test.py files, which unittest discovery cannot import."""
import importlib.util
from pathlib import Path
import sys
import unittest

suite = unittest.TestSuite()
for path in sorted(Path(__file__).resolve().parents[1].glob('*.test.py')):
    name = path.name.replace('-', '_').replace('.', '_')
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    suite.addTests(unittest.defaultTestLoader.loadTestsFromModule(module))
sys.exit(not unittest.TextTestRunner(verbosity=1).run(suite).wasSuccessful())

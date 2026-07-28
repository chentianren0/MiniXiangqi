#!/usr/bin/env python3
"""Agent-A scratch driver: loads a-probe.py as a module and runs ad-hoc cases
passed as a python snippet file argument. Research-only."""
import importlib.util, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("aprobe", os.path.join(HERE, "a-probe.py"))
aprobe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(aprobe)
aprobe.load()
g = {k: getattr(aprobe, k) for k in dir(aprobe) if not k.startswith("__")}
exec(open(sys.argv[1]).read(), g)

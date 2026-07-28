#!/usr/bin/env python3
"""Agent-A scratch driver #2: loads pyffish plus two scratch AXF children
(one with perpetual check disabled, used only as a discriminator oracle)."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "evidence", "pyffish-build"))
import pyffish
CONFIG = """
[minixiangqiaxf:minixiangqi]
chasingRule = axf
nMoveRule = 0
[minixiangqiaxfnochk:minixiangqi]
chasingRule = axf
nMoveRule = 0
perpetualCheckIllegal = false
"""
pyffish.load_variant_config(CONFIG)
assert "minixiangqiaxf" in pyffish.variants() and "minixiangqiaxfnochk" in pyffish.variants()
g = {"pyffish": pyffish}
exec(open(sys.argv[1]).read(), g)

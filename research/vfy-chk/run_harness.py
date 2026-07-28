import pathlib, sys, runpy, types, json
src = pathlib.Path('/Users/tianren/coding/minixiangqi/discussion-drafts/engine-fixture-check.py').read_text()
mod = types.ModuleType('h'); mod.__file__='h'
exec(compile(src.replace('if __name__ == "__main__":\n    sys.exit(main())',''), 'engine-fixture-check.py','exec'), mod.__dict__)
mod.FIXTURES = pathlib.Path('/Users/tianren/coding/minixiangqi/fx-perpetual-check/fixtures/rules')
sys.argv = ['x', '/Users/tianren/coding/minixiangqi/discussion-drafts/w-base']
sys.exit(mod.main())

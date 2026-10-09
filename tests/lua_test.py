"""Compatibility entry point for the current Lua regression suite."""
from pathlib import Path
import runpy
context=runpy.run_path(str(Path(__file__).with_name("composition_test.py")), run_name="__main__")
runpy.run_path(str(Path(__file__).with_name("game_widgets_test.py")),init_globals=context)
runpy.run_path(str(Path(__file__).with_name("live_network_test.py")),run_name="__main__")

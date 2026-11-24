import importlib.util
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

@unittest.skipUnless(importlib.util.find_spec("PySide6"), "Qt runtime required")
class PerchTests(unittest.TestCase):
    def test_seated_pet_moves_immediately_and_departure_tracks_the_ledge(self):
        from PySide6.QtCore import QPoint
        from companion import Companion
        positions = []
        old, new = QPoint(150, 200), QPoint(450, 230)
        pet = SimpleNamespace(move=positions.append)
        state = SimpleNamespace(motion=("perched", old, old, 10, 45), pending=[("jumping", old+QPoint(20,-5), .25)],
                                pet=pet, ledge=42, ledge_origin=old, ledge_point=lambda handle:new)
        self.assertEqual(Companion.moving_pose(state, 10.1), "perched")
        self.assertEqual(positions[-1], new)
        self.assertEqual(state.pending[0][1], new+QPoint(20,-5))
        Companion.moving_pose(state, 11)
        self.assertEqual(state.pending[0][1], new+QPoint(20,-5))

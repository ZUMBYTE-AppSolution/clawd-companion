"""Render both desktop appearances from an isolated, English-language profile."""
import sys
from pathlib import Path
from tempfile import TemporaryDirectory

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QApplication

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Desktop"))
from companion import Companion
from appearance import PALETTES

def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    QApplication.setAttribute(Qt.ApplicationAttribute.AA_ShareOpenGLContexts)
    app = QApplication([])
    with TemporaryDirectory() as folder:
        companion = Companion(app, Path(folder))
        companion.language.select("en")
        companion.show_settings(0)
        companion.dialog.resize(640, 660)
        for mode in ("dark", "light"):
            companion.set_pref("appearance", mode)
            app.processEvents()
            shot = companion.dialog.grab().toImage()
            # Check the rendered surface, catching inherited background rules on labels.
            image = shot.scaled(160, 165)
            colors = {image.pixelColor(x, y).name() for x in range(image.width()) for y in range(image.height())}
            for role in ("sky", "window", "surface", "button", "ink"):
                assert PALETTES[mode][role] in colors, (mode, role)
            if not shot.save(str(out / f"Clawd-Linux-{mode}.png")):
                raise OSError("Cannot save appearance capture")
        companion.close()

if __name__ == "__main__":
    main()

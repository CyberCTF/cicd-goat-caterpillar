"""The Caterpillar's mushroom.

"One side will make you grow taller, and the other side will make you grow
shorter." This is that mushroom, modelled as a tiny, pure helper: a bite from
the left side doubles your height, a bite from the right halves it.
"""

from dataclasses import dataclass

LEFT = "left"
RIGHT = "right"


@dataclass
class Mushroom:
    """Tracks a height in centimetres as bites are taken from either side."""

    height_cm: float = 7.5

    def bite(self, side: str) -> float:
        """Take a bite from ``side`` and return the new height.

        A bite from the left makes you taller; a bite from the right, shorter.
        Any other side is nonsense, even in Wonderland.
        """
        if side == LEFT:
            self.height_cm *= 2.0
        elif side == RIGHT:
            self.height_cm /= 2.0
        else:
            raise ValueError("the Caterpillar only offers 'left' or 'right'")
        return self.height_cm

    def is_alice_sized(self, target_cm: float = 7.5, tolerance_cm: float = 0.1) -> bool:
        """Return True when the current height is back within ``tolerance_cm`` of ``target_cm``."""
        return abs(self.height_cm - target_cm) <= tolerance_cm

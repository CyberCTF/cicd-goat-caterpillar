from caterpillar.mushroom import Mushroom


def test_left_makes_taller():
    mushroom = Mushroom(height_cm=7.5)
    assert mushroom.bite("left") == 15.0


def test_right_makes_shorter():
    mushroom = Mushroom(height_cm=7.5)
    assert mushroom.bite("right") == 3.75


def test_left_then_right_returns_to_alice_size():
    mushroom = Mushroom(height_cm=7.5)
    mushroom.bite("left")
    mushroom.bite("right")
    assert mushroom.is_alice_sized()


def test_unknown_side_is_nonsense():
    mushroom = Mushroom()
    try:
        mushroom.bite("sideways")
    except ValueError:
        return
    raise AssertionError("expected a ValueError for an unknown side")

# caterpillar

A tiny helper for Wonderland's size-management service. "One side will make you
grow taller, and the other side will make you grow shorter," says the
Caterpillar — so this package is that mushroom.

```python
from caterpillar.mushroom import Mushroom

mushroom = Mushroom(height_cm=7.5)
mushroom.bite("left")    # -> 15.0  (taller)
mushroom.bite("right")   # -> 7.5   (back to Alice's size)
```

## Development

```bash
python3 -m venv venv && . venv/bin/activate
pytest
```

CI runs on Wonderland's Jenkins from the `Jenkinsfile` in this repository: a
*test* pipeline builds every pull request, and a *prod* pipeline builds `main`.

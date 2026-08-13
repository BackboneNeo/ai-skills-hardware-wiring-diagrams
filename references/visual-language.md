# Visual language

Use one stable mapping across the sheet:

| Function | Preferred color | Hex |
| --- | --- | --- |
| Positive power / VBAT / 5V | red | `#e2443a` |
| Ground | charcoal | `#252a2e` |
| TX | blue | `#3276ca` |
| RX | cyan | `#2f9fd0` |
| I2C | green | `#42a06a` |
| Analog / 4V5 | orange | `#e88a2a` |
| PWM | purple | `#a46ec2` |
| Video | teal | `#318b8b` |
| Service / debug | gray | `#7a8790` |

Do not depend on color alone. Put the signal name inside or next to each terminal. Use white text on dark terminal fills.

Keep all connection routes the same thickness. Use a neutral background-colored halo to separate a route from unrelated graphics, but never use a halo to hide another route. A junction requires an explicit filled node; a simple crossing is never a junction.

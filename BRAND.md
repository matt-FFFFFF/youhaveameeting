# Brand

The app interrupts you. The mark should not.

Everything here follows from that: the resting states are quiet and
system-native, and emphasis is spent only where something is actually
happening. Nothing shouts by default, so when the icon does change it means
something.

## The mark

A bell — the thing the app does, and the one shape that reads as "you cannot
ignore this" without needing a word.

It is a single closed silhouette: rim flare, walls, dome, and a small crown nub
on top. Below the rim hangs a detached clapper. That clapper is the only
element that ever carries colour, and it is the only piece that changes
material between the menu bar and the app icon.

The geometry lives once, in
`Sources/YouHaveAMeetingCore/Branding/BellGlyph.swift`, on a 24×24 grid with the
origin at the bottom left. Both the menu-bar glyph and the app icon are drawn
from it, so the two cannot drift apart. Callers fit the mark to a rectangle
rather than positioning it: `BellGlyph.bounds` is what the bell occupies with
its stroke included, and `ringedBounds` is the same once the ring arcs are
drawn. Fitting to the wider box is what stops the glyph changing size when the
arcs appear.

If you change the paths, keep both boxes accurate. `BellGlyphTests` checks the
mark stays inside them and that the ringed state is within 5% of the plain
one's scale — a visible resize would make the menu bar jump.

## Menu bar

Template images only. Pure monochrome, no tint, ever. macOS inverts them for
dark menu bars and for the highlighted state, and a coloured status icon fights
whatever wallpaper the user has. State is carried by shape and fill weight
alone, which survives all of that.

| State | Glyph | Means |
| --- | --- | --- |
| Idle | Outline bell | Nothing due soon |
| Imminent | Filled bell | Inside the five minutes before the alarm |
| Alerting | Filled bell with two ring arcs | An alert is on screen and undismissed |
| Quiet | Outline bell with a slash | Presenting, in a call, or sharing — the next alert will be a banner |
| Forced | Outline bell with two ring arcs | Full Screen mode is pinned on — the next alert takes over whatever the sensors think |

Precedence, when more than one could apply, is alerting → quiet → imminent →
forced → idle. An alert on screen is the loudest fact about the app, so it wins
outright. Quiet beats imminent because it changes what the next alarm will
*do*, which matters more than knowing one is coming. Forced sits below imminent
for the same reason read the other way: it only guarantees the outcome the app
would have reached anyway, so an approaching meeting is the better thing to
show.

Fill and arcs are two independent axes, which is what keeps five states legible
with one mark. Fill says *now* — imminent and alerting are filled, idle and
forced are not. The arcs say *will ring*. So forced is an outline bell that
rings, and alerting is a filled one; at 18pt the two never collapse into each
other.

The five-minute warning is fixed rather than derived from the lead offset: the
lead offset says when to interrupt, the warning says when to give a heads-up
first, and someone who sets the offset to zero still wants the heads-up.

Two details are deliberate and easy to undo by accident:

- The slash stops inside the bell's own footprint. Run corner to corner and it
  collides with the rim flare and the clapper; at 18pt the three together read
  as damage rather than as a slash.
- The gap between slash and bell is punched into the alpha channel, because a
  template image has no background colour to knock out with.

## App icon

Graphite, with a single spark.

The body is a graphite squircle — `#4A4F58` down to `#1E2126` — carrying a
Liquid Glass treatment: a broad sheen from the upper left, a bright lip along
the top edge, a darkening at the foot, and a lit rim. The bell sits above it in
near-white with its own shadow, so it reads as a layer rather than as print.
The clapper is amber, `#FFD46B` to `#F29E0C`, with a warm glow. It is the only
colour in the icon and should stay that way.

The layout is the macOS grid: an 824×824 body centred on a 1024 canvas, which
is what makes the icon sit level with system ones in Finder. The rounded square
is a superellipse rather than a rounded rectangle — circular corners visibly
disagree with the continuous curve macOS uses, and the difference shows most at
the sizes people actually see.

Because the app is `LSUIElement`, this icon never appears in the Dock. It is
what Finder, Spotlight, the login-items list and the system permission prompts
show, so it still does real work.

### Regenerating

```sh
make icons
```

That compiles `Scripts/GenerateAppIcon.swift` against `BellGlyph.swift`, writes
a full `.iconset`, and packs it into `Resources/AppIcon.icns`, which is
committed. A plain `make` never draws anything.

Icon Composer would be the native way to author a Liquid Glass icon on macOS 26,
but it ships with full Xcode and this project builds with Command Line Tools
alone. The glass treatment is therefore painted by hand and baked into the
`.icns`. The look holds; what is lost is the system's tinted and clear icon
modes, which only a real `.icon` bundle can follow. If the project ever takes a
dependency on full Xcode, that is the upgrade to make.

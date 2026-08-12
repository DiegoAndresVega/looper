#!/usr/bin/env python3
"""Genera el logo de Looper por código, como todo lo demás en este proyecto.

La marca es la grilla del instrumento: 4x4 pads redondeados sobre el fondo
oscuro de la app, con la diagonal encendida en los cuatro colores de familia
(percusión, voz, tono, textura) y un anillo de loop en el pad de la voz.

Produce:
  assets/icon/icon.png        1024x1024, fondo incluido (iOS y fuente general)
  assets/icon/icon_fg.png     1024x1024, transparente, dibujo al 62% (capa
                              frontal del icono adaptativo de Android)

Tras cambiar algo aquí:  python3 tool/make_icon.py && dart run flutter_launcher_icons
"""

from PIL import Image, ImageDraw

SIZE = 1024

# La paleta de lib/core/palette.dart, calcada.
GROUND = (11, 15, 14, 255)        # 0xFF0B0F0E
PANEL_HIGH = (28, 35, 33, 255)    # 0xFF1C2321
LINE = (38, 46, 44, 255)          # 0xFF262E2C
PERCUSSION = (224, 87, 74, 255)   # 0xFFE0574A
VOICE = (242, 167, 59, 255)       # 0xFFF2A73B
TONE = (79, 195, 217, 255)        # 0xFF4FC3D9
TEXTURE = (169, 139, 224, 255)    # 0xFFA98BE0

DIAGONAL = {0: PERCUSSION, 5: VOICE, 10: TONE, 15: TEXTURE}
RING_PAD = 5  # el pad de la voz lleva el anillo de loop

# Antialias barato: se dibuja a 4x y se reduce.
SS = 4


def draw_mark(draw: ImageDraw.ImageDraw, origin: float, span: float) -> None:
    """La grilla 4x4 dentro de un cuadrado de lado span con esquina en origin."""
    gap = span * 0.055
    pad = (span - 3 * gap) / 4

    for row in range(4):
        for col in range(4):
            index = row * 4 + col
            x = origin + col * (pad + gap)
            y = origin + row * (pad + gap)
            color = DIAGONAL.get(index)
            radius = pad * 0.22

            if color is None:
                draw.rounded_rectangle(
                    [x, y, x + pad, y + pad],
                    radius=radius,
                    fill=PANEL_HIGH,
                    outline=LINE,
                    width=int(pad * 0.035),
                )
            else:
                draw.rounded_rectangle(
                    [x, y, x + pad, y + pad], radius=radius, fill=color
                )

            if index == RING_PAD:
                inset = pad * 0.14
                draw.rounded_rectangle(
                    [x + inset, y + inset, x + pad - inset, y + pad - inset],
                    radius=radius * 0.7,
                    outline=GROUND,
                    width=int(pad * 0.075),
                )


def render(with_background: bool, mark_share: float) -> Image.Image:
    size = SIZE * SS
    image = Image.new(
        "RGBA", (size, size), GROUND if with_background else (0, 0, 0, 0)
    )
    draw = ImageDraw.Draw(image)
    span = size * mark_share
    draw_mark(draw, (size - span) / 2, span)
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    render(True, 0.60).save("assets/icon/icon.png")
    render(False, 0.62).save("assets/icon/icon_fg.png")
    print("assets/icon/icon.png y icon_fg.png regenerados")


if __name__ == "__main__":
    main()

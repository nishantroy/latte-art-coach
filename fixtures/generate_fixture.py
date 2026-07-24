from PIL import Image, ImageDraw

SIZE = 900
image = Image.new("RGB", (SIZE, SIZE), "#b9a697")
draw = ImageDraw.Draw(image)
draw.ellipse((65, 65, 835, 835), fill="#f4efe5")
draw.ellipse((115, 115, 785, 785), fill="#6b351f")

draw.polygon(
    [(450, 700), (315, 585), (245, 485), (235, 375), (275, 295), (350, 270),
     (410, 300), (450, 355), (490, 300), (550, 270), (625, 295), (665, 375),
     (655, 485), (585, 585)],
    fill="#f4e8d3",
)
draw.ellipse((235, 265, 455, 490), fill="#f4e8d3")
draw.ellipse((445, 265, 665, 490), fill="#f4e8d3")
draw.polygon([(421, 322), (450, 355), (479, 322), (450, 430)], fill="#6b351f")

image.save("fixtures/synthetic-heart.png")

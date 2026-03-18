Pixel :: Vector(4, u8, .["r", "g", "b", "a"]);

Image_Data :: struct {
    pixels:   []Pixel;
    width:    s32;
    height:   s32;
    channels: s32;
}

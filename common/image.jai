Pixel :: struct {
    r: u8;
    g: u8;
    b: u8;
    a: u8;
}

Image_Data :: struct {
    pixels:   []Pixel;
    width:    s32;
    height:   s32;
    channels: s32;
}

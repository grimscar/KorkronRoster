-- The Kor'kron look: where each piece sits in Media/Art.tga, in pixels { x, y, width, height }.
-- Written by Kor'kron Hub's tools/make_art.py (and copied to the other mods by its tools/copy_style.py):
-- change that and run it again, don't edit this.
local _, ns = ...

ns.STYLE_ART = {
    width = 512, height = 256,
    button_l = { 0, 104, 12, 48 },
    button_m = { 18, 104, 4, 48 },
    button_r = { 28, 104, 12, 48 },
    buttonline_l = { 44, 104, 12, 48 },
    buttonline_m = { 62, 104, 4, 48 },
    buttonline_r = { 72, 104, 12, 48 },
    checkbox = { 88, 104, 32, 32 },
    close = { 112, 0, 36, 36 },
    diamond = { 150, 0, 12, 12 },
    disc = { 256, 128, 128, 128 },
    glow = { 384, 0, 128, 128 },
    ring = { 256, 0, 128, 128 },
    spike = { 70, 0, 40, 40 },
    tick = { 124, 104, 32, 32 },
    win_b = { 30, 76, 4, 24 },
    win_bl = { 0, 76, 24, 24 },
    win_br = { 40, 76, 24, 24 },
    win_l = { 0, 66, 24, 4 },
    win_r = { 40, 66, 24, 4 },
    win_t = { 30, 0, 4, 60 },
    win_tl = { 0, 0, 24, 60 },
    win_tr = { 40, 0, 24, 60 },
}

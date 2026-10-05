const cart = @import("cart-api");
comptime {
    cart.export_start_code();

    assert(160 == cart.screen_width);
    assert(128 == cart.screen_height);
}

const border_width = 3;

var last_controls: cart.Controls = .none;

pub fn start() void {
    draw();
}

pub fn update() void {
    const controls = cart.controls.*;
    defer {
        last_controls = controls;
    }
}

const black = rgb256(0, 0, 0);
const white = rgb256(0xff, 0xff, 0xff);
const yellow = rgb256(0xff, 0xff, 0x54);
fn rgb256(r: u8, g: u8, b: u8) cart.DisplayColor {
    return .{
        .r = @intCast(r >> 3),
        .g = @intCast(g >> 2),
        .b = @intCast(b >> 3),
    };
}

fn draw() void {
    cart.rect(.{
        .x = 0,
        .y = 0,
        .width = cart.screen_width,
        .height = cart.screen_height,
        .fill_color = black,
    });

    cart.vline(.{ .x = 0, .y = 0, .len = 128, .color = yellow });
    cart.vline(.{ .x = 1, .y = 0, .len = 128, .color = yellow });
    cart.vline(.{ .x = 158, .y = 0, .len = 128, .color = yellow });
    cart.vline(.{ .x = 159, .y = 0, .len = 128, .color = yellow });
    cart.hline(.{ .x = 2, .y = 0, .len = 160 - 4, .color = yellow });
    cart.hline(.{ .x = 2, .y = 1, .len = 160 - 4, .color = yellow });
    cart.hline(.{ .x = 2, .y = 126, .len = 160 - 4, .color = yellow });
    cart.hline(.{ .x = 2, .y = 127, .len = 160 - 4, .color = yellow });

    cart.text(.{
        .str = "hell",
        .x = 3,
        .y = 3,
        .scale = 1,
        .text_color = white,
    });
}

fn assert(b: bool) void {
    if (!b) unreachable;
}

const std = @import("std");
const cart = @import("cart-api");
comptime {
    cart.export_start_code();

    assert(160 == cart.screen_width);
    assert(128 == cart.screen_height);
}

const border_width = 3;

pub fn start() void {
    draw();
}

var last_controls: cart.Controls = .none;
var state: struct {
    pos: struct { x: u8, y: u8 } = .{ .x = 0, .y = 0 },
    dots: std.StaticBitSet(8 * 10) = .empty,

    fn getDot(s: @This(), x: usize, y: usize) bool {
        return s.dots.isSet(x * 8 + y);
    }
    fn setDot(s: *@This(), x: usize, y: usize, v: bool) void {
        s.dots.setValue(x * 8 + y, v);
    }
} = .{};

pub fn update() void {
    defer draw();
    const controls = cart.controls.*;
    const new_controls: cart.Controls = @fromBackingInt(@backingInt(controls) & ~@backingInt(last_controls));
    defer {
        last_controls = controls;
    }

    if (new_controls.left and state.pos.x > 0) {
        state.pos.x -= 1;
    } else if (new_controls.right and state.pos.x < 9) {
        state.pos.x += 1;
    } else if (new_controls.up and state.pos.y > 0) {
        state.pos.y -= 1;
    } else if (new_controls.down and state.pos.y < 7) {
        state.pos.y += 1;
    }
    state.setDot(state.pos.x, state.pos.y, true);
}

const black = rgb256(0, 0, 0);
const white = rgb256(0xff, 0xff, 0xff);
const yellow = rgb256(0xff, 0xff, 0x54);
const blue = rgb256(0x88, 0x88, 0xff);
/// Brain is easier typing in a familiar format. It's all an approximation anyway.
fn rgb256(r: u8, g: u8, b: u8) cart.DisplayColor {
    return .{
        .r = @intCast(r >> 3),
        .g = @intCast(g >> 2),
        .b = @intCast(b >> 3),
    };
}

fn draw() void {
    const pos_left = state.pos.x * 16 + 3;
    const pos_right = state.pos.x * 16 + 13;
    const pos_top = state.pos.y * 16 + 3;
    const pos_bottom = state.pos.y * 16 + 13;
    for (0..160) |x| {
        for (0..128) |y| {
            cart.framebuffer[x][y] = if ((x + 1) % 16 <= 1 or (y + 1) % 16 <= 1)
                // Grid border
                yellow
            else if (pos_left <= x and x < pos_right and
                pos_top <= y and y < pos_bottom)
                // Cursor
                blue
            else if ((x + 10) % 16 < 4 and (y + 10) % 16 < 4 and state.getDot(x >> 4, y >> 4))
                // Center dots
                yellow
            else
                black;
        }
    }
}

fn assert(b: bool) void {
    if (!b) unreachable;
}

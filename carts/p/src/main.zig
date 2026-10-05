const sin = @import("std").math.sin;
const cart = @import("cart-api");
comptime {
    cart.export_start_code();

    assert(160 == cart.screen_width);
    assert(128 == cart.screen_height);
}

pub fn start() void {
    checkDots();
    draw();
}

var last_controls: cart.Controls = @fromBackingInt(0xffff);
var state: struct {
    pos: packed struct(u16) { x: u8, y: u8 } = .{ .x = 0, .y = 0 },
    dots: [10][8]enum { off, mid, high } = @splat(@splat(.off)),
} = .{};
var animation: union(enum) {
    none,
    high_zap: struct { x: u8, y: u8, ttl: u64 },
} = .none;
var background_animation_start: ?u64 = null;

pub fn update() void {
    const controls = cart.controls.*;
    const new_controls: cart.Controls = @fromBackingInt(@backingInt(controls) & ~@backingInt(last_controls));
    defer {
        last_controls = controls;
    }
    defer draw();
    if (background_animation_start) |t0| {
        const now = cart.micros_since_boot();
        const t = (now - t0) / 10_000;
        if (t > 160 + 128 + 50) {
            background_animation_start = null;
            animation = .none;
            state = .{};
            updateWinCondition();
        } else return;
    }

    const old_pos = state.pos;
    if (new_controls.left and state.pos.x > 0) state.pos.x -= 1;
    if (new_controls.right and state.pos.x < 9) state.pos.x += 1;
    if (new_controls.up and state.pos.y > 0) state.pos.y -= 1;
    if (new_controls.down and state.pos.y < 7) state.pos.y += 1;
    if (old_pos != state.pos) {
        checkDots();
    }
}

fn checkDots() void {
    const dot = &state.dots[state.pos.x][state.pos.y];
    var check_for_zap = true;
    switch (dot.*) {
        .off => {
            dot.* = .mid;
        },
        .mid => {
            dot.* = .off;
        },
        .high => {
            dot.* = .off;
            check_for_zap = false;
        },
    }

    for (1..9) |x| {
        for (1..7) |y| {
            if (check_for_zap and
                state.dots[x][y] == .off and
                state.dots[x - 1][y] == .mid and
                state.dots[x + 1][y] == .mid and
                state.dots[x][y - 1] == .mid and
                state.dots[x][y + 1] == .mid)
            {
                state.dots[x][y] = .high;
                animation = .{ .high_zap = .{
                    .x = @intCast(x),
                    .y = @intCast(y),
                    .ttl = cart.micros_since_boot() + 200_000,
                } };
            }
        }
    }

    updateWinCondition();
}

fn updateWinCondition() void {
    var high_count: u16 = 0;
    for (1..9) |x| {
        for (1..7) |y| {
            if (state.dots[x][y] == .high) {
                high_count += 1;
            }
        }
    }
    for (cart.neopixels, 0..) |*neopixel, i| {
        if (i < high_count) {
            neopixel.* = .{ .r = 0xff, .g = 0x0, .b = 0xff };
        } else {
            neopixel.* = .{ .r = 0x0, .g = 0x0, .b = 0x0 };
        }
    }

    if (high_count >= 5) {
        background_animation_start = cart.micros_since_boot();
    }
}

const black = rgb256(0, 0, 0);
const white = rgb256(0xff, 0xff, 0xff);
const yellow = rgb256(0xff, 0xff, 0x54);
const blue = rgb256(0x88, 0x88, 0xff);
const purple = rgb256(0xaa, 0x0, 0xaa);
/// Brain is easier typing in a familiar format. It's all an approximation anyway.
fn rgb256(r: u8, g: u8, b: u8) cart.DisplayColor {
    return .{
        .r = @intCast(r >> 3),
        .g = @intCast(g >> 2),
        .b = @intCast(b >> 3),
    };
}

fn draw() void {
    const now = cart.micros_since_boot();
    for (0..160) |x| {
        for (0..128) |y| {
            cart.framebuffer[x][y] = if (state.pos.x * 16 + 3 <= x and x < state.pos.x * 16 + 13 and
                state.pos.y * 16 + 3 <= y and y < state.pos.y * 16 + 13)
                // Cursor
                blue
            else if (switch (animation) {
                else => false,
                .high_zap => |z| now < z.ttl and
                    (z.x * 16 + 7 <= x and x < z.x * 16 + 9 and z.y * 16 - 7 <= y and y < z.y * 16 + 23 or
                        z.y * 16 + 7 <= y and y < z.y * 16 + 9 and z.x * 16 - 7 <= x and x < z.x * 16 + 23),
            })
                // Zap animation
                purple
            else if ((x + 1) % 16 <= 1 or (y + 1) % 16 <= 1)
                // Grid border
                yellow
            else if ((x + 10) % 16 < 4 and (y + 10) % 16 < 4) switch (state.dots[x >> 4][y >> 4]) {
                // Center dots
                .off => black,
                .mid => yellow,
                .high => purple,
            } else if (background_animation_start) |t0| blk: {
                const t = (now - t0) / 10_000;
                if (t < x + y) break :blk black;
                const f: f32 = @floatFromInt((t - (x + y)) / 10);
                break :blk rgb256(
                    0x80 + @as(u8, @intFromFloat(0x7f * sin(f))),
                    0x80 + @as(u8, @intFromFloat(0x7f * sin(f + 1))),
                    0x80 + @as(u8, @intFromFloat(0x7f * sin(f + 2))),
                );
            } else
                // Background
                black;
        }
    }
}

fn assert(b: bool) void {
    if (!b) unreachable;
}

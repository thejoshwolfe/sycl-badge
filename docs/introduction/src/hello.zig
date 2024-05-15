const std = @import("std");
const cart = @import("cart-api");

export fn start() void {}

var scene: enum { intro, game } = .intro;

export fn update() void {
    switch (scene) {
        .intro => scene_intro(),
        .game => scene_game(),
    }
}

const lines = &[_][]const u8{
    "Auguste Rame",
    "~AOE4 Player",

    "",

    "aurame",
    "SuperAuguste",

    "",

    "SYCL24",
    "Press START",
};
const spacing = (cart.font_height * 4 / 3);

var ticks: u8 = 0;

fn scene_intro() void {
    set_background();

    @memset(cart.neopixels, .{
        .r = 0,
        .g = 0,
        .b = 0,
    });

    if (ticks / 128 == 0) {
        // Make the neopixel 24-bit color LEDs a nice Zig orange
        @memset(cart.neopixels, .{
            .r = 247,
            .g = 164,
            .b = 29,
        });
    }

    const y_start = (cart.screen_height - (cart.font_height + spacing * (lines.len - 1))) / 2;

    // Write it out!
    for (lines, 0..) |line, i| {
        cart.text(.{
            .text_color = .{ .r = 31, .g = 63, .b = 31 },
            .str = line,
            .x = @intCast((cart.screen_width - cart.font_width * line.len) / 2),
            .y = @intCast(y_start + spacing * i),
        });
    }

    if (ticks == 0) cart.red_led.* = !cart.red_led.*;
    if (cart.controls.start) scene = .game;

    ticks +%= 4;
}

const Player = enum(u8) { x = 0, o = 1, none = std.math.maxInt(u8) };

var selected_x: u8 = 0;
var selected_y: u8 = 0;
var cooldown_left_right: bool = false;
var cooldown_up_down: bool = false;
var cooldown_select: bool = false;

var turn: Player = .x;
var state: [3][3]Player = @bitCast([1]Player{.none} ** 9);

fn scene_game() void {
    set_background();

    const title = "TIC-TAC-TOE";
    cart.text(.{
        .text_color = .{ .r = 31, .g = 63, .b = 31 },
        .str = title,
        .x = @intCast((cart.screen_width - cart.font_width * title.len) / 2),
        .y = 10,
    });

    const instructions = "D-PAD + SELECT";
    cart.text(.{
        .text_color = .{ .r = 31, .g = 63, .b = 31 },
        .str = instructions,
        .x = @intCast((cart.screen_width - cart.font_width * instructions.len) / 2),
        .y = cart.screen_height - cart.font_height - 10,
    });

    for (0..3) |y| {
        for (0..3) |x| {
            cart.rect(.{
                .stroke_color = .{ .r = 31, .g = 63, .b = 31 },
                .fill_color = if (x == selected_x and y == selected_y) .{ .r = 31 / 2, .g = 63 / 2, .b = 31 / 2 } else null,
                .x = @intCast(cart.screen_width / 2 + x * 19 - 10 * 3),
                .y = @intCast(cart.screen_height / 2 + y * 19 - 10 * 3),
                .width = 20,
                .height = 20,
            });

            cart.text(.{
                .text_color = .{ .r = 31, .g = 63, .b = 31 },
                .str = switch (state[y][x]) {
                    .x => "X",
                    .o => "O",
                    .none => "",
                },
                .x = @intCast(cart.screen_width / 2 + x * 19 - 10 * 3 + 7),
                .y = @intCast(cart.screen_height / 2 + y * 19 - 10 * 3 + 7),
            });
        }
    }

    if (cart.controls.left) {
        if (selected_x > 0 and !cooldown_left_right) {
            selected_x -= 1;
        }
        cooldown_left_right = true;
    } else if (cart.controls.right) {
        if (selected_x < 2 and !cooldown_left_right) {
            selected_x += 1;
        }
        cooldown_left_right = true;
    } else {
        cooldown_left_right = false;
    }
    if (cart.controls.up) {
        if (selected_y > 0 and !cooldown_up_down) {
            selected_y -= 1;
        }
        cooldown_up_down = true;
    } else if (cart.controls.down) {
        if (selected_y < 2 and !cooldown_up_down) {
            selected_y += 1;
        }
        cooldown_up_down = true;
    } else {
        cooldown_up_down = false;
    }
    if (cart.controls.select) {
        if (!cooldown_select) {
            state[selected_y][selected_x] = turn;
            turn = switch (turn) {
                .x => .o,
                .o => .x,
                else => unreachable,
            };

            if (check_win()) {
                turn = .x;
                @memset(@as(*[9]Player, @ptrCast(&state)), .none);
                scene = .intro;
                selected_x = 0;
                selected_y = 0;
            }
        }
        cooldown_select = true;
    } else {
        cooldown_select = false;
    }
}

fn set_background() void {
    const ratio = (4095 - @as(f32, @floatFromInt(cart.light_level.*))) / 4095 * 0.2;

    @memset(cart.framebuffer, cart.DisplayColor{
        .r = @intFromFloat(ratio * 31),
        .g = @intFromFloat(ratio * 63),
        .b = @intFromFloat(ratio * 31),
    });
}

fn check_win() bool {
    for (0..3) |i| {
        // column
        if (state[i][0] != .none and state[i][0] == state[i][1] and state[i][1] == state[i][2]) return true;
        // row
        if (state[0][i] != .none and state[0][i] == state[1][i] and state[1][i] == state[2][i]) return true;
    }

    // diagonal
    if (state[0][0] != .none and state[0][0] == state[1][1] and state[1][1] == state[2][2]) return true;
    if (state[0][2] != .none and state[0][2] == state[1][1] and state[1][1] == state[2][0]) return true;

    return false;
}

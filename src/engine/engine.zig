pub const tower = @import("tower.zig");
pub const creep = @import("creep.zig");
pub const renderer = @import("renderer.zig");
pub const gamestate = @import("game-state.zig");
pub const projectile = @import("projectile.zig");
pub const canvas = @import("canvas.zig");
pub const framer = @import("framer.zig");
pub const stdout = @import("stdout_output.zig");
pub const input = @import("input.zig");
pub const time = @import("time.zig");

test { _ = tower; }
test { _ = creep; }
test { _ = renderer; }
test { _ = gamestate; }
test { _ = projectile; }
test { _ = canvas; }
test { _ = framer; }
test { _ = stdout; }
test { _ = input; }
test { _ = time; }

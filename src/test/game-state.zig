const std = @import("std");
const objects = @import("objects");
const engine = @import("vengine");
const Params = @import("params.zig");

const GS = objects.gamestate.GameState;
const gamestate = engine.gamestate;

pub const Spawner = struct {
    gs: *GS,
    lastSpawn: isize = 0,
    currentTime: isize = 0,
    spawnRate: isize,
    params: *Params,

    pub fn init(params: *Params, gs: *GS) Spawner {
        return .{
            .spawnRate = @intCast(params.creepRate),
            .gs = gs,
            .params = params,
        };
    }

    pub fn tick(self: *Spawner, deltaUS: isize) !void {
        self.currentTime += deltaUS;
        if (self.currentTime - self.lastSpawn > self.spawnRate) {
            self.lastSpawn = self.currentTime;

            const row = self.params.rand(usize) % self.gs.values.rows;
            try gamestate.placeCreep(self.gs, .{
                .col = 0,
                .row = row,
            });
        }
    }
};

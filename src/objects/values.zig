const std = @import("std");
const assert = @import("../assert/assert.zig").assert;
const scratchBuf = @import("../scratch/scratch.zig").scratchBuf;
const RndGen = std.rand.DefaultPrng;

pub const TEAM_ONE = '1';
pub const TEAM_TWO = '2';
pub const ROUND_TIME = 3_000_000;

pub const TowerValues = struct {
    ammo: usize = 50,
    fireRateUS: i64 = 1_000_000,
    firingDurationUS: i64 = 200_000,
};

pub const CreepValues = struct {
    life: usize = 5,
    speed: f64 = 1,
};

pub const ProjectorValues = struct {
    speed: f64 = 4,
};

rows: usize = 0,
cols: usize = 0,
size: usize = 0,
roundTimeUS: i64 = ROUND_TIME,
debug: bool = false,
tower: TowerValues = .{},
creep: CreepValues = .{},
projectile: ProjectorValues = .{},
seed: usize = 69420,
removeNoBuild: usize = 3,

_rand: ?RndGen = null,

const Self = @This();

pub fn init(v: *Self) void {
    assert(v.rows > 0, "must set rows");
    assert(v.cols > 0, "must set cols");

    v.size = v.rows * v.cols;
    v._rand = RndGen.init(@intCast(v.seed));
}

pub fn copyInto(v: *const Self, other: *Self) void {
    other.rows = v.rows;
    other.cols = v.cols;
    other.size = v.size;

    other._rand = v._rand;
}

pub fn rand(self: *Self, comptime T: type) T {
    return self._rand.?.random().int(T);
}

pub fn randRange(self: *Self, comptime T: type, start: T, end: T) T {
    assert(start < end, "end must be greater than start");
    return start + self._rand.?.random().int(T) % (end - start);
}

pub fn string(v: *const Self) ![]u8 {
    return std.fmt.bufPrint(scratchBuf(75), "rows = {}, cols = {}, size = {}", .{v.rows, v.cols, v.size});
}

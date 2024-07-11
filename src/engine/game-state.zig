const std = @import("std");

const objects = @import("../objects/objects.zig");
const math = @import("../math/math.zig");
const a = @import("../assert/assert.zig");
const assert = a.assert;
const towers = @import("tower.zig");
const creeps = @import("creep.zig");
const projectiles = @import("projectile.zig");

const never = a.never;
const Values = objects.Values;
const AABB = math.AABB;
const GS = objects.gamestate.GameState;
const Message = objects.message.Message;
const Tower = objects.tower.Tower;
const Creep = objects.creep.Creep;
const Projectile = objects.projectile.Projectile;
const Vec2 = math.Vec2;
const Allocator = std.mem.Allocator;

pub fn update(state: *GS, delta: i64) !void {
    state.updates += 1;

    const changed = state.boardChanged;

    const diff: isize = @intCast(state.one - state.two);
    assert(diff >= -1 and diff <= 1, "some how we have multiple updates to one side but not the other");

    state.loopDeltaUS = delta;

    if (!state.playing) {
        return;
    }

    state.time += delta;

    for (state.towers.items) |*t| {
        try towers.update(t, state);
    }

    for (state.creeps.items) |*c| {
        creeps.update(c, state);

        if (creeps.completed(c) and c.alive) {
            creeps.kill(c, state);
            if (getRandomTower(state, c.team)) |tid| {
                towers.killById(tid, state);
            }
        }
    }

    for (state.projectile.items) |*p| {
        try projectiles.update(p, state);
    }

    if (state.boardChanged > changed) {
        updateBoard(state);
        for (state.creeps.items) |*c| {
            creeps.calculatePath(c, state.board);
        }
    }

    if (!state.values.debug) {
        return;
    }

    if (state.towers.items.len < 2 or state.creeps.items.len < 1) {
        return;
    }

    const one = &state.towers.items[1];
    const c = state.creeps.items[0];

    std.debug.print("within: {} -- creep: {s} tower: {s}\n", .{
        towers.contains(one, c.pos),
        a.u(c.pos.string()),
        a.u(one.pos.string()),
    });
}

fn getRandomTower(self: *GS, team: u8) ?usize {
    switch (team) {
        Values.TEAM_ONE => {
            if (self.oneTowerCount == 0) {
                return null;
            }
        },
        Values.TEAM_TWO => {
            if (self.twoTowerCount == 0) {
                return null;
            }
        },
        else => never("invalid team"),
    }

    // TODO: Such a bad way to do this
    // i am sure there is a better way...
    while (true) {
        for (self.towers.items, 0..) |*t, idx| {
            // 50% chance is not really random especially given the order...
            if (t.alive and t.team == team and self.values.randBool()) {
                return idx;
            }
        }
    }

    never("i should select a tower");
    return null;
}

pub fn init(self: *GS) void {
    self.fns = &.{
        .placeProjectile = placeProjectile,
        .towerDied = towerDied,
        .creepKilled = creepKilled,
        .shot = shot,
        .strike = strike,
    };

    const rows = self.values.rows;
    const teamSpace = rows / 3;

    self.oneCreepRange.endRow = teamSpace;
    self.oneNoBuildTowerRange = self.oneCreepRange;

    self.twoCreepRange.startRow = rows - teamSpace;
    self.twoCreepRange.endRow = rows;
    self.twoNoBuildTowerRange = self.twoCreepRange;

    self.noBuildRange.startRow = self.oneCreepRange.endRow;
    self.noBuildRange.endRow = self.twoCreepRange.startRow;
}

pub fn towerDied(self: *GS, t: *Tower) void {
    if (t.team == objects.Values.TEAM_ONE) {
        self.oneStats.towersLost += 1;
        self.oneTowerCount -= 1;
    } else {
        self.twoStats.towersLost += 1;
        self.twoTowerCount -= 1;
    }

    self.boardChanged += 1;
}

pub fn creepKilled(self: *GS, c: *Creep) void {
    if (c.team == objects.Values.TEAM_ONE) {
        self.oneStats.creepsKilled += 1;
    } else {
        self.twoStats.creepsKilled += 1;
    }
}

pub fn shot(self: *GS, t: *Tower) void {
    if (t.team == objects.Values.TEAM_ONE) {
        self.oneStats.shots += 1;
    } else {
        self.twoStats.shots += 1;
    }
}

pub fn strike(self: *GS, p: *Projectile) void {
    switch (p.target) {
        .creep => |c| self.creeps.items[c].life -|= p.damage,
        .tower => |t| self.towers.items[t].ammo -|= p.damage,
    }
}

pub fn completed(self: *GS) bool {
    return !self.noBuildZone and
        (self.oneTowerCount == 0 or self.twoTowerCount == 0);
}

pub fn roundPlayed(state: *GS) bool {
    return !state.playing and state.round == state.one and state.round == state.two;
}

pub fn roundOver(state: *GS) bool {
    return state.playing and
        state.playingStartUS + state.values.roundTimeUS < state.time;
}

pub fn play(state: *GS) void {
    assert(state.one == state.two, "player one and two must have same play count");
    assert(state.one == state.round, "the round and the played moves are not the same");

    state.playing = true;
    state.playingStartUS = state.time;
}

pub fn pause(state: *GS) void {
    assert(state.one == state.two, "player one and two must have same play count");
    assert(state.one == state.round, "the round and the played moves are not the same");

    state.playing = false;
    state.round += 1;

    if (state.round > state.values.removeNoBuild) {
        state.noBuildZone = false;
    }
}

pub fn message(state: *GS, msg: Message) !void {
    switch (msg) {
        .coord => |c| {

            if (c.team == objects.Values.TEAM_ONE) {
                state.one += 1;
            } else {
                state.two += 1;
            }

            const aabb = towers.placementAABB(c.pos.vec2());
            if (towerByAABB(state, aabb)) |idx| {
                if (state.towers.items[idx].team == c.team) {
                    towers.upgrade(&state.towers.items[idx]);
                    return;
                }
                a.never("haven't programmed this yet");
            }

            if (try placeTower(state, aabb, c.team)) |_| {
            } else {
                var count: usize = 0;
                while (creepByAABB(state, aabb)) |id| : (count += 1) {
                    creeps.kill(&state.creeps.items[id], state);
                }

                if (count > 0) {
                    return;
                }

                std.debug.print("could not place tower: {s} {s}\n", .{try aabb.string(), try c.string()});
                a.never("haven't programmed this yet also");
            }
        },
        .round => |_| {
            // not sure what to do here...
            // probably need to think about "playing/pausing"
            // play(state);
        },
    }
}

pub fn clone(self: *GS) !GS {
    const diff: isize = @intCast(self.one - self.two);
    assert(diff == 0, "next round can only be called once both players have played their turns.");

    var board = try self.alloc.alloc(bool, self.board.len);
    std.mem.copyForwards(bool, board[0..], self.board);

    return .{
        .round = self.round,
        .values = self.values,

        .one = self.one,
        .oneCoords = self.oneCoords,

        .two = self.two,
        .twoCoords = self.twoCoords,

        .time = self.time,
        .loopDeltaUS = self.time,

        .towers = try self.towers.clone(),
        .creeps = try self.creeps.clone(),
        .projectile = try self.projectile.clone(),
        .board = board,
        .alloc = self.alloc,
    };
}

pub fn towerByAABB(self: *GS, aabb: AABB) ?usize {
    for (self.towers.items, 0..) |*t, i| {
        if (t.alive and t.aabb.overlaps(aabb)) {
            return i;
        }
    }
    return null;
}

pub fn creepByAABB(self: *GS, aabb: AABB) ?usize {
    for (self.creeps.items, 0..) |*c, i| {
        if (c.alive and c.aabb.overlaps(aabb)) {
            return i;
        }
    }
    return null;
}

pub fn tower(self: *GS, pos: Vec2) ?usize {
    for (self.towers.items, 0..) |*t, i| {
        if (towers.contains(t, pos)) {
            return i;
        }
    }
    return null;
}

pub fn creep(self: *GS, pos: Vec2) ?usize {
    for (self.creeps.items, 0..) |*c, i| {
        if (creeps.contains(c, pos)) {
            return i;
        }
    }
    return null;
}

pub fn calculateBoard(self: *GS) void {
    for (self.board, 0..) |_, idx| {
        self.board[idx] = true;
    }

    for (self.towers.items) |*t| {
        const cells = t.rCells;
        const sized = t.rSized;

        for (cells, 0..) |_, idx| {
            const col = idx % sized.cols;
            const row = idx / sized.cols;
            const offset = (sized.pos.row + row) * self.values.cols + sized.pos.col + col;
            self.board[offset] = true;
        }
    }
}

pub fn placeCreep(self: *GS, pos: math.Position, team: u8) !usize {
    switch (team) {
        objects.Values.TEAM_ONE => assert(self.oneCreepRange.contains(pos), "invalid team one position"),
        objects.Values.TEAM_TWO => assert(self.twoCreepRange.contains(pos), "invalid team one position"),
        else => a.never("invalid team"),
    }

    const id = self.creeps.items.len;
    var c = try creeps.create(
        self.alloc, id, team, self.values, pos.vec2()
    );

    errdefer c.deinit();
    try self.creeps.append(c);

    creeps.calculatePath(&self.creeps.items[id], self.board);
    creeps.scale(&self.creeps.items[id], self.round);

    return id;
}

pub fn updateBoard(self: *GS) void {
    for (0..self.board.len) |i| {
        self.board[i] = true;
    }

    for (self.towers.items) |*t| {
        if (!t.alive) {
            continue;
        }

        const start = t.rSized.pos.row * self.values.cols + t.rSized.pos.col;

        for (0..t.rows) |r| {
            const rowStart = start + r * self.values.cols;
            for (0..t.cols) |c| {
                self.board[rowStart + c] = false;
            }
        }
    }
}

fn canPlaceTower(self: *GS, aabb: math.AABB, team: u8) bool {
    const pos = aabb.min.position();
    if (self.noBuildZone) {
        const range = switch (team) {
            '1' => self.oneNoBuildTowerRange,
            '2' => self.twoNoBuildTowerRange,
            else => {
                a.never("inTeam is an invalid value");
                unreachable;
            }
        };

        if (!range.contains(pos)) {
            std.debug.print("outside range\n", .{});
            return false;
        }
    }

    if (pos.col <= 0 or pos.col >= self.values.cols - objects.tower.TowerSize) {
        std.debug.print("on outside of accepted range: col <= 0, col => {}\n", .{self.values.cols - objects.tower.TowerSize});
        return false;
    }

    if (creepByAABB(self, aabb)) |_| {
        return false;
    }

    return true;
}

pub fn placeTower(self: *GS, aabb: math.AABB, team: u8) !?usize {
    Values.assertTeam(team);

    const pos = aabb.min;
    assert(aabb.min.closeEnough(pos, 0.0001), "you must place towers on natural numbers");

    if (!canPlaceTower(self, aabb, team)) {
        return null;
    }

    const id = self.towers.items.len;
    const t = towers.TowerBuilder.start()
        .pos(pos.position())
        .team(team)
        .id(id)
        .tower(self.values);

    try self.towers.append(t);
    if (team == Values.TEAM_ONE) {
        self.oneTowerCount += 1;
    } else {
        self.twoTowerCount += 1;
    }

    updateBoard(self);

    for (self.creeps.items) |*c| {
        creeps.calculatePath(c, self.board);
    }

    return id;
}

pub fn placeProjectile(self: *GS, t: *Tower, target: objects.Target) Allocator.Error!usize {
    const id = self.projectile.items.len;
    const projectile = objects.projectile.Projectile {
        .pos = t.pos,
        .target = target,
        .id = id,
        .damage = t.damage,
        .speed = self.values.projectile.speed,
    };

    try self.projectile.append(projectile);
    shot(self, t);

    return id;
}

pub fn towerById(self: *GS, id: usize) *Tower {
    assert(self.towers.items.len > id, "grabbing a tower outside the size of the tower list");

    const t = &self.towers.items[id];
    assert(t.alive, "cannot retrieve a dead tower");
    return t;
}


pub fn validateState(self: *GS) void {
    for (self.creeps.items) |*c| {
        if (!c.alive) {
            continue;
        }

        if (towerByAABB(self, c.aabb)) |t| {
            std.debug.print("tower: {s} collided with creep {s}\n", .{a.u(self.towers.items[t].pos.string()), a.u(c.string())});
            assert(false, "a creep is within a tower");
        }
    }

    var one: usize = 0;
    var tuwu: usize = 0;

    for (self.towers.items) |*t| {
        if (!t.alive) {
            continue;
        }

        switch (t.team) {
            Values.TEAM_ONE => one += 1,
            Values.TEAM_TWO => tuwu += 1,
            else => never("how tf did i get here?"),
        }

    }

    assert(one == self.oneTowerCount, "one's tower count does not equal the alive towers");
    assert(tuwu == self.twoTowerCount, "two's tower count does not equal the alive towers");
}

const testing = std.testing;
test "calculate the board" {
    var values = objects.Values{.rows = 3, .cols = 3};
    values.init();

    var gs = try GS.init(testing.allocator, &values);
    defer gs.deinit();

    calculateBoard(&gs);

    try testing.expectEqualSlices(bool, &.{
        true, true, true,
        true, true, true,
        true, true, true,
    }, gs.board);
}

test "place creep calculates positions" {
    var values = objects.Values{.rows = 3, .cols = 3};
    values.init();

    var gs = try GS.init(testing.allocator, &values);
    defer gs.deinit();
    calculateBoard(&gs);
    init(&gs);

    _ = try placeCreep(&gs, .{.row = 0, .col = 0}, objects.Values.TEAM_ONE);
    try testing.expect(gs.creeps.items[0].pathLen == 2);
}

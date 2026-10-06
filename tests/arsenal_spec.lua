package.path = "./?.lua;./?/init.lua;" .. package.path
local Sim = require("game.sim")
local autopilot = require("game.autopilot")
local total = 0
local function equal(a, b, label)
    assert(a == b, (label or "values differ") .. ": got " .. tostring(a) .. ", expected " .. tostring(b))
end
local function near(a, b, tolerance)
    assert(math.abs(a - b) <= (tolerance or 0.00001), "got " .. tostring(a) .. ", expected " .. tostring(b))
end
local function test(name, fn)
    fn(); total = total + 1; print("PASS " .. name)
end
local function isolated()
    local sim = Sim.new(3)
    sim.bossSpawned = true -- Disable the campaign director for unit fixtures.
    sim.player.x, sim.player.y, sim.player.invulnerable = 150, 180, 0
    sim:drainEvents()
    return sim
end
local function collect(sim, kind)
    sim.player.x, sim.player.y = 150, 180
    sim:_spawnPickup(kind, 150, 180)
    sim:update(1 / 60, {})
end
local function events(sim, kind, field, value)
    local count = 0
    for _, e in ipairs(sim:drainEvents()) do
        if e.kind == kind and (not field or e[field] == value) then count = count + 1 end
    end
    return count
end

test("the arsenal starts clean and numeric primary power survives mode changes", function()
    local sim = isolated()
    equal(sim.player.primary, "pulse")
    equal(sim.player.shield, 0)
    equal(sim.player.nitro, 0)
    equal(sim.player.overdrive, 0)
    equal(sim.player.secondary, nil)
    equal(sim.player.ammo.rocket, 0)
    equal(sim.player.ammo.mega, 0)
    collect(sim, "weapon"); collect(sim, "ion")
    equal(sim.player.weapon, 2)
    equal(sim.player.primary, "ion")
    sim:update(12, {})
    equal(sim.player.primary, "ion", "primary mode must persist")
    collect(sim, "prism"); collect(sim, "weapon")
    equal(sim.player.primary, "prism")
    equal(sim.player.weapon, 3)
    local fresh = Sim.new(3)
    equal(fresh.player.primary, "pulse")
    equal(fresh.player.weapon, 1)
    equal(fresh.player.shield, 0)
    equal(fresh.player.secondary, nil)
end)

test("prism power adds a symmetric spread and ion power increases piercing damage", function()
    local sim = isolated()
    collect(sim, "prism")
    sim:_firePlayer()
    equal(#sim.bullets, 3)
    near(sim.bullets[1].angle, -sim.bullets[3].angle)
    near(sim.bullets[2].angle, 0)
    equal(sim.bullets[1].kind, "prism")
    sim.bullets = {}; sim.player.weapon = 3
    sim:_firePlayer()
    equal(#sim.bullets, 7)
    near(sim.bullets[1].angle, -sim.bullets[7].angle)
    near(sim.bullets[4].angle, 0)
    sim.bullets = {}; collect(sim, "ion")
    sim:_firePlayer()
    local beam = sim.bullets[1]
    equal(#sim.bullets, 1)
    equal(beam.kind, "ion")
    assert(beam.piercing and beam.length == 52 and beam.damage > 5)
    equal(sim.player.weapon, 3)
end)

test("ion sweeps through a row and damages each enemy only once", function()
    local sim = isolated()
    sim.player.primary, sim.player.weapon = "ion", 3
    local a = sim:_spawnEnemy("scout", 180, { x = 235, motionPhase = 0 })
    local b = sim:_spawnEnemy("scout", 180, { x = 290, motionPhase = 0 })
    a.speed, b.speed, a.hp, b.hp = 0, 0, 100, 100
    sim:_firePlayer()
    local beam = sim.bullets[1]
    sim:update(0.2, {})
    near(a.hp, 94.6)
    near(b.hp, 94.6)
    assert(beam.hitEnemies[a.id] and beam.hitEnemies[b.id])
    sim:update(0.2, {})
    near(a.hp, 94.6)
    near(b.hp, 94.6)
end)

test("mega pierces multiple enemies and cannot repeatedly damage an overlap", function()
    local sim = isolated()
    collect(sim, "mega")
    local a = sim:_spawnEnemy("scout", 180, { x = 208, motionPhase = 0 })
    local b = sim:_spawnEnemy("scout", 180, { x = 216, motionPhase = 0 })
    a.speed, b.speed, a.hp, b.hp = 0, 0, 100, 100
    sim:_fireSecondary()
    local mega = sim.bullets[1]
    mega.x, mega.prevX, mega.vx = 200, 200, 0 -- Keep its footprint over both test targets.
    sim:update(0.2, {})
    near(a.hp, 76)
    near(b.hp, 76)
    assert(mega.hitEnemies[a.id] and mega.hitEnemies[b.id])
    equal(mega.radius, 13)
    equal(events(sim, "secondary", "type", "mega"), 1)
end)

test("secondary ammo caps, selects collected types, and falls back without underflow", function()
    local sim = isolated()
    for _ = 1, 4 do collect(sim, "rocket") end
    equal(sim.player.ammo.rocket, 36)
    equal(sim.player.secondary, "rocket")
    for _ = 1, 3 do collect(sim, "mega") end
    equal(sim.player.ammo.mega, 12)
    equal(sim.player.secondary, "mega")
    sim.player.ammo.rocket, sim.player.ammo.mega, sim.player.secondary = 1, 1, "rocket"
    sim:update(1 / 60, { secondary = true })
    equal(sim.player.ammo.rocket, 0)
    equal(sim.player.secondary, "mega")
    sim:update(0.5, { secondary = true })
    equal(sim.player.ammo.mega, 0)
    equal(sim.player.secondary, nil)
    sim:update(3, { secondary = true })
    equal(sim.player.ammo.rocket, 0)
    equal(sim.player.ammo.mega, 0)
    equal(events(sim, "secondary"), 2)
end)

test("holding secondary obeys independent rocket and mega cooldowns", function()
    local rocket, mega = isolated(), isolated()
    collect(rocket, "rocket"); collect(mega, "mega")
    rocket:drainEvents(); mega:drainEvents()
    rocket:update(2, { secondary = true })
    mega:update(2, { secondary = true })
    local rockets, megas = events(rocket, "secondary"), events(mega, "secondary")
    assert(rockets >= 4 and rockets <= 5)
    equal(megas, 3)
    assert(rockets > megas)
end)

test("rockets home, turn within limits, accelerate, and reacquire destroyed targets", function()
    local sim = isolated()
    collect(sim, "rocket")
    local a = sim:_spawnEnemy("scout", 260, { x = 400, motionPhase = 0 })
    local b = sim:_spawnEnemy("scout", 100, { x = 450, motionPhase = 0 })
    sim:update(1 / 60, { secondary = true })
    local missile = sim.bullets[1]
    equal(missile.targetId, a.id)
    assert(missile.angle > 0 and missile.angle <= 2.8 / 60 + 0.00001)
    assert(missile.vy > 0 and missile.speed > 355 and missile.speed <= 465)
    local oldAngle = missile.angle
    a.dead = true
    sim:update(1 / 60, {})
    equal(missile.targetId, b.id)
    assert(missile.angle < oldAngle)
    assert(math.abs(missile.angle - oldAngle) <= 2.8 / 60 + 0.00001)
end)

test("a rocket detonates once with direct damage and neighboring splash", function()
    local sim = isolated()
    collect(sim, "rocket")
    local direct = sim:_spawnEnemy("scout", 180, { x = 300, motionPhase = 0 })
    local neighbor = sim:_spawnEnemy("scout", 180, { x = 330, motionPhase = 0 })
    direct.speed, neighbor.speed = 0, 0
    sim:_fireSecondary()
    local missile = sim.bullets[1]
    sim:update(0.7, {})
    assert(direct.dead)
    assert(neighbor.hp > 0 and neighbor.hp < neighbor.maxHp)
    local hp = neighbor.hp
    sim:_rocketBlast(missile, direct)
    near(neighbor.hp, hp)
    equal(events(sim, "explosion", "type", "rocket"), 1)
    equal(#sim.bullets, 0)
end)

test("shield charges absorb complete hurts, retain streaks, and respect brief immunity", function()
    local sim = isolated()
    sim.player.shield = 2
    collect(sim, "shield")
    equal(sim.player.shield, 3)
    sim.streak, sim.multiplier, sim.comboTimer = 6, 2, 3
    assert(sim:_hurtPlayer(9))
    equal(sim.player.hp, 5)
    equal(sim.player.shield, 2)
    equal(sim.streak, 6)
    assert(sim.player.invulnerable > 0)
    assert(not sim:_hurtPlayer(1))
    equal(sim.player.shield, 2)
    for _ = 1, 2 do sim:update(0.6, {}); sim:_hurtPlayer(1) end
    equal(sim.player.shield, 0)
    equal(sim.player.hp, 5)
    equal(events(sim, "shield_hit"), 3)
    sim:update(0.6, {}); sim:_hurtPlayer(1)
    equal(sim.player.hp, 4)
    equal(sim.streak, 0)
    equal(events(sim, "hit", "target", "player"), 1)
end)

test("nitro boosts actual movement and scroll for eight seconds without immunity", function()
    local normal, boost = isolated(), isolated()
    collect(boost, "nitro")
    equal(boost.player.nitro, 8)
    equal(boost.player.invulnerable, 0)
    near(boost.scrollSpeed, normal.scrollSpeed + 88)
    normal:update(0.2, { x = 1 }); boost:update(0.2, { x = 1 })
    near((boost.player.x - 150) / (normal.player.x - 150), 1.4)
    near(boost.player.nitro, 7.8)
    assert(boost:_hurtPlayer(1))
    equal(boost.player.hp, 4)
    boost:update(7.81, {})
    equal(boost.player.nitro, 0)
    equal(boost.scrollSpeed, 164)
end)

test("overdrive increases real firing cadence and expires at ten seconds", function()
    local normal, boosted = isolated(), isolated()
    collect(boosted, "overdrive")
    equal(boosted.player.overdrive, 10)
    boosted:drainEvents()
    normal:update(0.8, { fire = true }); boosted:update(0.8, { fire = true })
    local base, rapid = events(normal, "shoot"), events(boosted, "shoot")
    assert(rapid >= base * 1.4)
    near(boosted.player.overdrive, 9.2)
    boosted:update(9.21, {})
    equal(boosted.player.overdrive, 0)
    boosted.player.fireCooldown = 0
    boosted:update(1 / 60, { fire = true })
    near(boosted.player.fireCooldown, 0.105)
end)

test("secondary boss kills preserve terminal protections for both projectile kinds", function()
    for _, kind in ipairs({ "rocket", "mega" }) do
        local sim = isolated()
        collect(sim, kind)
        local boss = sim:_spawnEnemy("boss", 180, { x = 532 })
        boss.hp, boss.entered, boss.phase = 8, true, 3
        sim:_fireSecondary()
        local bullet = sim.bullets[1]
        bullet.x, bullet.prevX, bullet.y, bullet.prevY = 510, 510, 180, 180
        sim:update(1 / 60, {})
        equal(sim.status, "victory")
        equal(#sim.bullets, 0)
        equal(#sim.enemies, 0)
        local ammo, time = sim.player.ammo[kind], sim.time
        sim:update(2, { fire = true, secondary = true })
        equal(sim.player.ammo[kind], ammo)
        equal(sim.time, time)
        equal(events(sim, "victory"), 1)
    end
end)

test("game over freezes secondary ammo and buff timers", function()
    local sim = isolated()
    collect(sim, "rocket"); collect(sim, "nitro"); collect(sim, "overdrive")
    sim.player.hp = 1
    sim:_spawnBullet("enemy", sim.player.x, sim.player.y, 0, 0, "orb", 1, 4)
    sim:update(1 / 60, { secondary = true })
    equal(sim.status, "gameover")
    local ammo, nitro, overdrive, time = sim.player.ammo.rocket, sim.player.nitro, sim.player.overdrive, sim.time
    sim:update(5, { secondary = true, fire = true })
    equal(sim.player.ammo.rocket, ammo)
    equal(sim.player.nitro, nitro)
    equal(sim.player.overdrive, overdrive)
    equal(sim.time, time)
    equal(events(sim, "gameover"), 1)
end)

test("all arsenal modes and homing remain deterministic under normal controller inputs", function()
    local a, b = Sim.new(3), Sim.new(3)
    for _ = 1, 3600 do
        a:update(1 / 60, autopilot(a))
        b:update(1 / 60, autopilot(b))
        equal(a.player.primary, b.player.primary)
        equal(a.player.secondary, b.player.secondary)
        equal(a.player.hp, b.player.hp)
        equal(a.player.shield, b.player.shield)
        equal(a.player.ammo.rocket, b.player.ammo.rocket)
        equal(a.player.ammo.mega, b.player.ammo.mega)
        equal(a.player.nitro, b.player.nitro)
        equal(a.player.overdrive, b.player.overdrive)
        equal(a.score, b.score)
        equal(a.rngState, b.rngState)
        equal(#a.bullets, #b.bullets)
        for i, bullet in ipairs(a.bullets) do
            local other = b.bullets[i]
            equal(bullet.kind, other.kind)
            equal(bullet.x, other.x)
            equal(bullet.y, other.y)
            equal(bullet.angle, other.angle)
            equal(bullet.targetId, other.targetId)
        end
        a:drainEvents(); b:drainEvents()
    end
    assert(a.kills > 40 and a.player.weapon > 1)
end)

test("normal campaign reaches every arsenal supply and uses both secondary weapons", function()
    local sim = Sim.new(3)
    local collected, shots = {}, {}
    local maximumBullets, maximumEnemies = 0, 0
    while sim.status == "playing" and sim.time < 270 do
        sim:update(1 / 60, autopilot(sim))
        maximumBullets = math.max(maximumBullets, #sim.bullets)
        maximumEnemies = math.max(maximumEnemies, #sim.enemies)
        assert(#sim.bullets < 210 and #sim.enemies < 35)
        for _, e in ipairs(sim:drainEvents()) do
            if e.kind == "powerup" then collected[e.type] = (collected[e.type] or 0) + 1 end
            if e.kind == "secondary" then shots[e.type] = (shots[e.type] or 0) + 1 end
        end
    end
    equal(sim.status, "victory")
    for _, kind in ipairs({ "weapon", "repair", "shield", "nitro", "overdrive", "ion", "prism", "rocket", "mega" }) do
        assert(collected[kind] and collected[kind] > 0, "campaign never collected " .. kind)
    end
    assert(shots.rocket and shots.rocket > 0 and shots.mega and shots.mega > 0)
    assert(sim.player.hp > 0 and sim.boss.phase == 3 and sim.boss.hp == 0)
    print(string.format("  Arsenal mission: %.1fs, HP %d, %d rocket / %d mega shots, peaks %d bullets / %d enemies",
        sim.time, sim.player.hp, shots.rocket, shots.mega, maximumBullets, maximumEnemies))
end)

print(string.format("PASS %d arsenal tests", total))

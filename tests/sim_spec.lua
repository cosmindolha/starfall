package.path = "./?.lua;./?/init.lua;" .. package.path
local Sim = require("game.sim")
local autopilot = require("game.autopilot")

local total = 0
local function equal(actual, expected, message)
    assert(actual == expected, (message or "values differ") .. ": got " .. tostring(actual) .. ", expected " .. tostring(expected))
end
local function near(actual, expected, tolerance, message)
    assert(math.abs(actual - expected) <= (tolerance or 0.00001),
        (message or "values differ") .. ": got " .. tostring(actual) .. ", expected " .. tostring(expected))
end
local function countEvents(sim, kind, qualifier, value)
    local count = 0
    for _, e in ipairs(sim:drainEvents()) do
        if e.kind == kind and (not qualifier or e[qualifier] == value) then count = count + 1 end
    end
    return count
end
local function isolated(seed)
    local sim = Sim.new(seed or 10)
    sim.nextWaveTime = 100000
    sim.player.invulnerable = 0
    sim:drainEvents()
    return sim
end
local function test(name, fn)
    fn()
    total = total + 1
    print("PASS " .. name)
end

test("normalized movement, focus speed, and field limits", function()
    local sim = isolated()
    sim:update(0.1, { x = 1, y = 1 })
    near(sim.player.x - 96, 235 * 0.1 / math.sqrt(2))
    near(sim.player.y - 180, 235 * 0.1 / math.sqrt(2))
    local focus = isolated()
    focus:update(0.1, { x = 1, focus = true })
    near(focus.player.x - 96, 12.6)
    focus:update(8, { x = 1, y = -1 })
    equal(focus.player.x, 603)
    equal(focus.player.y, 62)
    focus:update(8, { y = 1 })
    equal(focus.player.y, 302)
end)

test("dash has an edge trigger, cooldown, and damage immunity", function()
    local sim = isolated()
    sim:_spawnBullet("enemy", 150, 180, math.pi, 700, "orb", 1, 4)
    sim:update(0.1, { x = 1, dash = true })
    equal(sim.player.hp, 5)
    assert(sim.player.x > 150 and sim.player.invulnerable > 0)
    equal(countEvents(sim, "dash"), 1)
    sim:update(2, { dash = true })
    equal(countEvents(sim, "dash"), 0, "holding dash must not retrigger")
    near(sim.player.dashCooldown, 0)
    sim:update(1 / 60, {})
    sim:update(1 / 60, { y = -1, dash = true })
    equal(countEvents(sim, "dash"), 1)
    assert(sim.player.dashY == -1)
end)

test("swept enemy bullets hit through a frame without double damage", function()
    local sim = isolated()
    sim:_spawnBullet("enemy", 150, 180, math.pi, 2400, "orb", 1, 4)
    sim:_spawnBullet("enemy", 150, 180, math.pi, 2400, "orb", 1, 4)
    sim:update(1 / 30, {})
    equal(sim.player.hp, 4)
    equal(#sim.bullets, 0)
    equal(countEvents(sim, "hit", "target", "player"), 1)
end)

test("the ship's small core gives fair grazing and a real hit", function()
    local sim = isolated()
    sim:_spawnBullet("enemy", 96, 192, 0, 0, "spark", 1, 3)
    sim:update(1 / 60, {})
    equal(sim.player.hp, 5)
    equal(sim.grazes, 1)
    equal(sim.score, 15)
    sim:update(1 / 60, {})
    equal(sim.grazes, 1, "a bullet may only graze once")
    sim:_spawnBullet("enemy", 96, 187, 0, 0, "spark", 1, 3)
    sim:update(1 / 60, {})
    equal(sim.player.hp, 4)
end)

test("fast player fire collides and scores each enemy once", function()
    local sim = isolated()
    sim:_spawnEnemy("scout", 180, { x = 300, motionPhase = 0 })
    sim:_spawnBullet("player", 255, 180, 0, 3600, "pulse", 5, 3)
    sim:update(1 / 60, {})
    equal(sim.kills, 1)
    equal(sim.score, 100)
    equal(#sim.enemies, 0)
    equal(countEvents(sim, "explosion"), 1)
end)

test("a rapid kill streak raises score and expires", function()
    local sim = isolated()
    for i = 1, 5 do
        local e = sim:_spawnEnemy("scout", 180)
        sim:_killEnemy(e, true)
    end
    equal(sim.streak, 5)
    equal(sim.multiplier, 2)
    equal(sim.score, 600)
    sim:update(3.3, {})
    equal(sim.streak, 0)
    equal(sim.multiplier, 1)
end)

test("weapon, repair, and bomb pickups collect and cap correctly", function()
    local sim = isolated()
    sim.player.x, sim.player.y = 150, 180
    sim.player.hp = 4
    for _ = 1, 3 do
        sim:_spawnPickup("weapon", 150, 180)
        sim:update(1 / 60, {})
    end
    equal(sim.player.weapon, 3)
    sim:_spawnPickup("repair", 150, 180)
    sim:update(1 / 60, {})
    equal(sim.player.hp, 5)
    for _ = 1, 3 do
        sim:_spawnPickup("bomb", 150, 180)
        sim:update(1 / 60, {})
    end
    equal(sim.player.bombs, 5)
    equal(#sim.pickups, 0)
    equal(countEvents(sim, "powerup"), 7)
end)

test("a bomb clears hostile fire, kills visible enemies, and is edge triggered", function()
    local sim = isolated()
    local enemy = sim:_spawnEnemy("bomber", 180, { x = 400 })
    local outside = sim:_spawnEnemy("bomber", 75, { x = 730 })
    sim:_spawnBullet("enemy", 300, 100, math.pi, 0, "orb", 1, 4)
    sim:_spawnBullet("player", 100, 100, 0, 0, "pulse", 1, 3)
    sim:update(1 / 60, { bomb = true })
    assert(enemy.dead)
    equal(outside.hp, outside.maxHp)
    equal(sim.player.bombs, 2)
    equal(#sim.bullets, 1)
    equal(sim.bullets[1].owner, "player")
    assert(sim.player.invulnerable > 1)
    sim:update(1 / 60, { bomb = true })
    equal(sim.player.bombs, 2)
    equal(countEvents(sim, "bomb"), 1)
end)

test("enemy entrances are warned before enemies enter", function()
    local sim = Sim.new(64)
    sim.player.invulnerable = 999
    sim:update(1.12, {})
    assert(#sim.telegraphs >= 3)
    equal(#sim.enemies, 0)
    for _, warning in ipairs(sim.telegraphs) do
        assert(warning.remaining > 0 and warning.duration >= 0.7)
        assert(warning.y >= 36 and warning.y <= 324)
    end
    sim:update(1.5, {})
    assert(#sim.enemies >= 3)
end)

test("fixed 60-second sectors lead to the boss at 180 seconds", function()
    local sim = Sim.new(26)
    sim.player.invulnerable = 999
    sim:update(60, {})
    equal(sim.sector, 2)
    equal(countEvents(sim, "sector"), 2)
    sim:update(60, {})
    equal(sim.sector, 3)
    equal(countEvents(sim, "sector"), 1)
    sim:update(60, {})
    assert(sim.bossSpawned and sim.boss)
    equal(sim.boss.type, "boss")
    equal(#sim.telegraphs, 0)
    equal(countEvents(sim, "boss"), 1)
    near(sim.time, 180, 0.00001)
end)

test("boss entrance immunity, phase transitions, and victory use combat damage", function()
    local sim = isolated()
    sim.player.invulnerable = 999
    local boss = sim:_spawnEnemy("boss", 180)
    sim:_damageEnemy(boss, 100)
    equal(boss.hp, 760, "the boss may not be shot before entering")
    boss.x, boss.y, boss.entered = 532, 180, true
    sim:_spawnBullet("player", 475, boss.y, 0, 2400, "plasma", 300, 4)
    sim:update(1 / 30, {})
    near(boss.hp, 460)
    equal(boss.phase, 2)
    assert(boss.invulnerable > 0)
    sim:update(1, {})
    sim:_spawnBullet("player", 475, boss.y, 0, 2400, "plasma", 250, 4)
    sim:update(1 / 30, {})
    near(boss.hp, 210)
    equal(boss.phase, 3)
    sim:update(1, {})
    sim:_spawnBullet("player", 475, boss.y, 0, 2400, "plasma", 300, 4)
    sim:update(1 / 30, {})
    equal(sim.status, "victory")
    assert(sim.bossDefeated)
    equal(#sim.bullets, 0)
    equal(#sim.enemies, 0)
    equal(countEvents(sim, "victory"), 1)
    local time = sim.time
    sim:update(5, { fire = true, bomb = true })
    equal(sim.time, time)
end)

test("boss fan patterns retain finite bounded projectiles in all phases", function()
    local sim = isolated()
    sim.player.invulnerable = 999
    local boss = sim:_spawnEnemy("boss", 180, { x = 532 })
    for _, hp in ipairs({ 760, 460, 210 }) do
        boss.hp = hp
        sim:update(10, {})
        assert(#sim.bullets > 5 and #sim.bullets < 160)
        for _, bullet in ipairs(sim.bullets) do
            assert(bullet.x == bullet.x and bullet.y == bullet.y)
            assert(math.abs(bullet.vx) <= 225 and math.abs(bullet.vy) <= 225)
        end
        sim:drainEvents()
    end
    equal(boss.phase, 3)
end)

test("a bomb can finish the boss without leaving a frozen ship or fresh gunfire", function()
    local sim = isolated()
    local boss = sim:_spawnEnemy("boss", 180, { x = 532 })
    boss.hp, boss.entered = 40, true
    sim:update(1 / 60, { bomb = true, fire = true })
    equal(sim.status, "victory")
    equal(#sim.enemies, 0)
    equal(#sim.bullets, 0)
    equal(countEvents(sim, "victory"), 1)
end)

test("game over happens once and freezes the completed run", function()
    local sim = isolated()
    sim.player.hp = 1
    sim:_spawnBullet("enemy", 96, 180, 0, 0, "orb", 1, 4)
    sim:update(1 / 60, {})
    equal(sim.status, "gameover")
    equal(sim.player.hp, 0)
    equal(countEvents(sim, "gameover"), 1)
    local time = sim.time
    sim:update(30, { fire = true })
    equal(sim.time, time)
    equal(#sim:drainEvents(), 0)
end)

test("seeded combat is deterministic and new runs fully restart", function()
    local a, b = Sim.new(7263), Sim.new(7263)
    a.player.invulnerable, b.player.invulnerable = 999, 999
    for frame = 1, 1800 do
        local input = { y = math.sin(frame / 73), fire = true,
            focus = frame % 200 < 70, dash = frame % 310 == 0, bomb = frame == 1200 }
        a:update(1 / 60, input)
        b:update(1 / 60, input)
        a:drainEvents()
        b:drainEvents()
    end
    equal(a.rngState, b.rngState)
    equal(a.score, b.score)
    equal(a.kills, b.kills)
    equal(a.time, b.time)
    equal(#a.enemies, #b.enemies)
    equal(#a.bullets, #b.bullets)
    near(a.player.x, b.player.x)
    near(a.player.y, b.player.y)
    for i, enemy in ipairs(a.enemies) do
        equal(enemy.type, b.enemies[i].type)
        near(enemy.x, b.enemies[i].x)
        near(enemy.y, b.enemies[i].y)
        near(enemy.hp, b.enemies[i].hp)
    end
    local fresh = Sim.new(7263)
    equal(fresh.time, 0)
    equal(fresh.score, 0)
    equal(fresh.player.hp, 5)
    equal(fresh.player.bombs, 3)
    equal(fresh.player.weapon, 1)
    equal(#fresh.enemies, 0)
    equal(#fresh.bullets, 0)
    equal(fresh.status, "playing")
    equal(fresh.rngState, 7263)
    local other = Sim.new(7264)
    fresh:update(4, {})
    other:update(4, {})
    assert(fresh.enemies[1].baseY ~= other.enemies[1].baseY)
end)

test("sustained play bounds projectile and enemy populations", function()
    local sim = Sim.new(7263)
    sim.player.invulnerable = 999
    local maxBullets, maxEnemies = 0, 0
    for frame = 1, 13200 do
        sim:update(1 / 60, { y = math.sin(frame / 60) * 0.8, fire = true })
        maxBullets = math.max(maxBullets, #sim.bullets)
        maxEnemies = math.max(maxEnemies, #sim.enemies)
        sim:drainEvents()
        assert(#sim.bullets < 210 and #sim.enemies < 35)
    end
    assert(sim.bossSpawned)
    assert(sim.kills > 20)
    print(string.format("  220-second stress run: max %d bullets, %d enemies; %d kills",
        maxBullets, maxEnemies, sim.kills))
end)

test("a complete mission is winnable with normal damage and real controls", function()
    local sim = Sim.new(3)
    while sim.status == "playing" and sim.time < 270 do
        sim:update(1 / 60, autopilot(sim))
        sim:drainEvents()
    end
    equal(sim.status, "victory")
    equal(sim.sector, 3)
    equal(sim.boss.phase, 3)
    assert(sim.player.hp > 0 and sim.boss.hp == 0 and sim.kills > 100)
    print(string.format("  Normal mission clear: %.1fs; HP %d; %d kills; score %d",
        sim.time, sim.player.hp, sim.kills, sim.score))
end)

test("the test controller is read-only and stops commanding completed runs", function()
    local sim = Sim.new(3)
    sim:update(5, { fire = true })
    local state = { time = sim.time, score = sim.score, rng = sim.rngState,
        x = sim.player.x, y = sim.player.y, hp = sim.player.hp,
        bullets = #sim.bullets, enemies = #sim.enemies, events = #sim.events }
    local input = autopilot(sim)
    equal(sim.time, state.time)
    equal(sim.score, state.score)
    equal(sim.rngState, state.rng)
    equal(sim.player.x, state.x)
    equal(sim.player.y, state.y)
    equal(sim.player.hp, state.hp)
    equal(#sim.bullets, state.bullets)
    equal(#sim.enemies, state.enemies)
    equal(#sim.events, state.events)
    assert(input.fire and input.x == 0 and input.y >= -1 and input.y <= 1)
    sim.status = "victory"
    local stopped = autopilot(sim)
    assert(not stopped.fire and not stopped.dash and not stopped.bomb)
    equal(stopped.x, 0)
    equal(stopped.y, 0)
end)

print(string.format("PASS %d simulation tests", total))

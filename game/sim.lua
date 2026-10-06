-- Pure Lua arcade simulation. The renderer and input/audio adapters live outside it.
-- All positions use the 640 x 360 playfield; update accepts seconds.
local Sim = {}
Sim.__index = Sim

local W, H = 640, 360
local TAU = math.pi * 2
local SECTOR_NAMES = { "THE NEON RIFT", "SHATTER BELT", "IRON HORIZON" }
local SUPPLIES = {
    { 3, "shield" }, { 7, "rocket" }, { 11, "ion" }, { 16, "nitro" },
    { 21, "overdrive" }, { 27, "prism" }, { 33, "mega" }, { 39, "weapon" },
    { 44, "repair" }, { 49, "rocket" }, { 54, "mega" },
}
local DROP_TYPES = { "shield", "rocket", "nitro", "overdrive", "ion", "mega", "prism", "weapon", "bomb", "repair" }
local ENEMY_STATS = {
    scout       = { hp = 3,  radius = 12, speed = 144, score = 100 },
    interceptor = { hp = 5,  radius = 13, speed = 214, score = 180 },
    turret      = { hp = 12, radius = 18, speed = 86,  score = 320 },
    bomber      = { hp = 18, radius = 21, speed = 68,  score = 420 },
    ace         = { hp = 24, radius = 18, speed = 130, score = 650 },
    boss        = { hp = 760, radius = 48, speed = 66, score = 8000 },
}

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function distance2(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy
end
local function angleTo(x, y, tx, ty)
    local dx, dy = tx - x, ty - y
    if math.atan2 then return math.atan2(dy, dx) end
    if dx == 0 then return dy >= 0 and math.pi / 2 or -math.pi / 2 end
    local a = math.atan(dy / dx)
    if dx < 0 then a = a + (dy >= 0 and math.pi or -math.pi) end
    return a
end
local function segmentHits(x1, y1, x2, y2, cx, cy, radius)
    local dx, dy = x2 - x1, y2 - y1
    local len = dx * dx + dy * dy
    local t = len == 0 and 0 or clamp(((cx - x1) * dx + (cy - y1) * dy) / len, 0, 1)
    return distance2(x1 + t * dx, y1 + t * dy, cx, cy) <= radius * radius
end

function Sim.new(seed)
    seed = math.floor(tonumber(seed) or 7349) % 2147483647
    if seed < 1 then seed = seed + 2147483646 end
    local self = setmetatable({
        width = W, height = H, seed = seed, rngState = seed,
        playBounds = { minY = 62, maxY = 302 },
        time = 0, sector = 1, sectorTime = 0, sectorName = SECTOR_NAMES[1],
        sectorDuration = 60, bossAt = 180, scrollSpeed = 164,
        status = "playing", score = 0, kills = 0, grazes = 0,
        streak = 0, multiplier = 1, comboTimer = 0,
        nextWaveTime = 1.1, waveNumber = 0, waveInSector = 0, supplyIndex = 1,
        bullets = {}, enemies = {}, pickups = {}, telegraphs = {}, events = {},
        boss = nil, bossSpawned = false, bossDefeated = false,
        player = {
            x = 96, y = H / 2, hp = 5, maxHp = 5, radius = 5,
            weapon = 1, primary = "pulse", bank = 0, speed = 235, invulnerable = 1.8,
            shield = 0, nitro = 0, overdrive = 0,
            secondary = nil, ammo = { rocket = 0, mega = 0 }, secondaryCooldown = 0,
            dashCooldown = 0, dashTime = 0, dashX = 1, dashY = 0,
            bombs = 3, maxBombs = 5, fireCooldown = 0, flash = 0,
        },
        _dashHeld = false, _bombHeld = false, _id = 0,
    }, Sim)
    self:_emit("sector", { sector = 1, name = self.sectorName })
    return self
end

function Sim:_random(lo, hi)
    self.rngState = (self.rngState * 16807) % 2147483647
    local n = (self.rngState - 1) / 2147483646
    if not lo then return n end
    if not hi then return math.floor(n * lo) + 1 end
    return lo + (hi - lo) * n
end

function Sim:_emit(kind, fields)
    fields = fields or {}
    fields.kind = kind
    self.events[#self.events + 1] = fields
end

function Sim:drainEvents()
    local events = self.events
    self.events = {}
    return events
end

function Sim:_nextId()
    self._id = self._id + 1
    return self._id
end

function Sim:_spawnBullet(owner, x, y, angle, speed, kind, damage, radius)
    local bullet = {
        id = self:_nextId(), owner = owner, x = x, y = y, prevX = x, prevY = y,
        vx = math.cos(angle) * speed, vy = math.sin(angle) * speed,
        kind = kind or (owner == "player" and "pulse" or "orb"),
        damage = damage or 1, radius = radius or (owner == "player" and 3 or 4),
        age = 0, life = 8, angle = angle,
    }
    self.bullets[#self.bullets + 1] = bullet
    return bullet
end

function Sim:_spawnEnemy(kind, y, options)
    options = options or {}
    local stats = assert(ENEMY_STATS[kind], "Unknown enemy: " .. tostring(kind))
    local hp = stats.hp * (kind == "boss" and 1 or (1 + (self.sector - 1) * 0.12))
    local enemy = {
        id = self:_nextId(), type = kind, x = options.x or W + 44,
        y = y or H / 2, baseY = y or H / 2, hp = hp, maxHp = hp,
        radius = stats.radius, speed = stats.speed + (self.sector - 1) * 12,
        score = stats.score, age = 0, bank = 0, flash = 0, phase = 1,
        wave = options.wave or self.waveNumber, variant = options.variant or 1,
        motionPhase = options.motionPhase or self:_random(0, TAU),
        shootTimer = options.shootTimer or self:_random(1.1, 1.8),
        specialTimer = 3.8, sweepAngle = 0, entered = false,
    }
    if kind == "boss" then
        enemy.name = "THE DREADNAUGHT"
        enemy.phaseAge = 0
        enemy.invulnerable = 0
        enemy.shootTimer = 1.8
        enemy.specialTimer = 3.5
        self.boss = enemy
        self.bossSpawned = true
        self:_emit("boss", { x = enemy.x, y = enemy.y, name = enemy.name, phase = 1 })
    end
    self.enemies[#self.enemies + 1] = enemy
    return enemy
end

function Sim:_queueEnemy(kind, y, delay, options)
    self.telegraphs[#self.telegraphs + 1] = {
        x = W - 8, y = clamp(y, 36, H - 36), type = kind,
        remaining = delay or 0.8, duration = delay or 0.8, options = options,
    }
end

function Sim:_spawnPickup(kind, x, y)
    self.pickups[#self.pickups + 1] = {
        id = self:_nextId(), kind = kind, x = clamp(x, 150, W - 28),
        y = clamp(y, 36, H - 30), radius = 10, age = 0, life = 12,
        baseY = y, phase = self:_random(0, TAU),
    }
end

function Sim:_wave()
    self.waveNumber = self.waveNumber + 1
    self.waveInSector = self.waveInSector + 1
    local n, s = self.waveInSector, self.sector
    local lane = self:_random(66, H - 66)
    local variant = (n - 1) % (s == 1 and 6 or 8) + 1
    if variant == 1 or variant == 4 then
        local count = s == 1 and 4 or 5
        for i = 1, count do
            self:_queueEnemy("scout", lane + math.sin(i * 1.4) * 24,
                0.7 + (i - 1) * 0.21, { motionPhase = i * 0.75, wave = self.waveNumber })
        end
    elseif variant == 2 or variant == 5 then
        local count = s == 1 and 3 or 4
        for i = 1, count do
            self:_queueEnemy("interceptor", 55 + (H - 110) * (i - 1) / (count - 1),
                0.9 + (i - 1) * 0.18, { motionPhase = i * 1.5, wave = self.waveNumber })
        end
    elseif variant == 3 then
        self:_queueEnemy("turret", lane, 1.0)
        if s > 1 then self:_queueEnemy("scout", H - lane, 1.3) end
    elseif variant == 6 then
        self:_queueEnemy("bomber", lane, 1.05)
        self:_queueEnemy("scout", lane > H / 2 and 65 or H - 65, 1.35)
    elseif variant == 7 then
        self:_queueEnemy("ace", H / 2, 1.2)
    else
        self:_queueEnemy("turret", 75, 1.0)
        self:_queueEnemy("turret", H - 75, 1.4)
        self:_queueEnemy("interceptor", H / 2, 1.7)
    end
    -- Guaranteed supplies make recovery and upgrades intentional, not pure luck.
    if n == 4 then self:_spawnPickup("weapon", W - 35, lane) end
    if n == 11 then self:_spawnPickup("repair", W - 35, H - lane) end
    if n == 16 and s > 1 then self:_spawnPickup("bomb", W - 35, H / 2) end
    local spacing = (s == 1 and 3.45 or s == 2 and 2.95 or 2.55)
    if self.sectorTime < 12 then spacing = spacing + 0.9 end
    self.nextWaveTime = self.time + spacing + self:_random(-0.22, 0.28)
end

function Sim:_director(dt)
    if not self.bossSpawned then
        local sector = math.min(3, math.floor((self.time + 0.000001) / self.sectorDuration) + 1)
        if sector ~= self.sector then
            self.sector = sector
            self.sectorName = SECTOR_NAMES[sector]
            self.waveInSector, self.supplyIndex = 0, 1
            self.nextWaveTime = self.time + 1.7
            self:_emit("sector", { sector = sector, name = self.sectorName })
            self:_spawnPickup("repair", W - 35, H / 2)
        end
        self.sectorTime = self.time - (self.sector - 1) * self.sectorDuration
        while SUPPLIES[self.supplyIndex] and self.sectorTime >= SUPPLIES[self.supplyIndex][1] do
            local supply = SUPPLIES[self.supplyIndex]
            local y = clamp(self.player.y + self:_random(-65, 65),
                self.playBounds.minY + 10, self.playBounds.maxY - 10)
            self:_spawnPickup(supply[2], 520, y)
            self.supplyIndex = self.supplyIndex + 1
        end
        if self.time + 0.000001 >= self.bossAt then
            self.telegraphs = {}
            self:_spawnEnemy("boss", H / 2, { x = W + 72 })
            -- A clean entry gives the boss its own visual beat.
            for i = #self.bullets, 1, -1 do
                if self.bullets[i].owner == "enemy" then table.remove(self.bullets, i) end
            end
            self:_spawnPickup("bomb", W - 45, H / 2)
            self:_spawnPickup("mega", W - 45, H / 2 + 48)
            self:_spawnPickup("shield", W - 45, H / 2 - 48)
        elseif self.time >= self.nextWaveTime then
            self:_wave()
        end
    end
    for i = #self.telegraphs, 1, -1 do
        local t = self.telegraphs[i]
        t.remaining = t.remaining - dt
        if t.remaining <= 0 then
            self:_spawnEnemy(t.type, t.y, t.options)
            table.remove(self.telegraphs, i)
        end
    end
end

function Sim:_firePlayer()
    local p = self.player
    local interval
    if p.primary == "ion" then
        local b = self:_spawnBullet("player", p.x + 29, p.y, 0, 940, "ion",
            2.8 + (p.weapon - 1) * 1.3, 3.7 + p.weapon * 0.4)
        b.piercing, b.hitEnemies, b.length, b.life = true, {}, 28 + p.weapon * 8, 1.2
        interval = 0.15
    elseif p.primary == "prism" then
        local count = 1 + p.weapon * 2
        for i = 1, count do
            local angle = ((i - 1) / (count - 1) - 0.5) * 0.54
            self:_spawnBullet("player", p.x + 24, p.y, angle, 575, "prism",
                1.15 + p.weapon * 0.1, 3.1)
        end
        interval = 0.135
    else
        self:_spawnBullet("player", p.x + 24, p.y - 5, 0, 610, "pulse", 1, 2.8)
        self:_spawnBullet("player", p.x + 24, p.y + 5, 0, 610, "pulse", 1, 2.8)
        if p.weapon >= 2 then
            self:_spawnBullet("player", p.x + 29, p.y, 0, 660, "plasma", 1.4, 3.8)
        end
        if p.weapon >= 3 then
            self:_spawnBullet("player", p.x + 15, p.y - 10, -0.115, 580, "pulse", 0.9, 2.6)
            self:_spawnBullet("player", p.x + 15, p.y + 10, 0.115, 580, "pulse", 0.9, 2.6)
        end
        interval = p.weapon == 1 and 0.105 or 0.11
    end
    p.fireCooldown = interval * (p.overdrive > 0 and 0.58 or 1)
    self:_emit("shoot", { owner = "player", x = p.x + 25, y = p.y,
        weapon = p.weapon, primary = p.primary, secondary = p.secondary })
end

function Sim:_selectSecondary()
    local p = self.player
    if p.secondary and p.ammo[p.secondary] > 0 then return p.secondary end
    p.secondary = p.ammo.rocket > 0 and "rocket" or p.ammo.mega > 0 and "mega" or nil
    return p.secondary
end

function Sim:_fireSecondary()
    local p = self.player
    local kind = self:_selectSecondary()
    if not kind then return end
    p.ammo[kind] = p.ammo[kind] - 1
    local bullet
    if kind == "rocket" then
        bullet = self:_spawnBullet("player", p.x + 23, p.y, 0, 355, "rocket", 12, 4.4)
        bullet.speed, bullet.turnRate, bullet.splashRadius, bullet.life = 355, 2.8, 44, 3.5
        p.secondaryCooldown = 0.48
    else
        bullet = self:_spawnBullet("player", p.x + 28, p.y, 0, 490, "mega", 24, 13)
        bullet.piercing, bullet.hitEnemies, bullet.length, bullet.life = true, {}, 32, 1.6
        p.secondaryCooldown = 0.85
    end
    self:_emit("secondary", { owner = "player", type = kind, x = bullet.x, y = bullet.y,
        weapon = p.weapon, primary = p.primary, secondary = kind, ammo = p.ammo[kind] })
    self:_selectSecondary()
end

function Sim:_bomb()
    local p = self.player
    if p.bombs <= 0 then return end
    p.bombs = p.bombs - 1
    p.invulnerable = math.max(p.invulnerable, 1.15)
    self:_emit("bomb", { x = p.x, y = p.y })
    for i = #self.bullets, 1, -1 do
        if self.bullets[i].owner == "enemy" then table.remove(self.bullets, i) end
    end
    for _, enemy in ipairs(self.enemies) do
        if not enemy.dead and enemy.x < W + enemy.radius then
            self:_damageEnemy(enemy, enemy.type == "boss" and 58 or 30)
            if self.status ~= "playing" then break end
        end
    end
end

function Sim:_updatePlayer(dt, input)
    local p = self.player
    p.invulnerable = math.max(0, p.invulnerable - dt)
    p.dashCooldown = math.max(0, p.dashCooldown - dt)
    p.fireCooldown = math.max(0, p.fireCooldown - dt)
    p.secondaryCooldown = math.max(0, p.secondaryCooldown - dt)
    p.nitro = math.max(0, p.nitro - dt)
    p.overdrive = math.max(0, p.overdrive - dt)
    p.flash = math.max(0, p.flash - dt)
    local x, y = tonumber(input.x) or 0, tonumber(input.y) or 0
    local len = math.sqrt(x * x + y * y)
    if len > 1 then x, y = x / len, y / len end
    if input.dash and not self._dashHeld and p.dashCooldown <= 0 then
        p.dashX, p.dashY = x, y
        if len < 0.1 then p.dashX, p.dashY = 1, 0 end
        p.dashTime = 0.2
        p.dashCooldown = 1.75
        p.invulnerable = math.max(p.invulnerable, 0.32)
        self:_emit("dash", { x = p.x, y = p.y, vx = p.dashX, vy = p.dashY })
    end
    self._dashHeld = not not input.dash
    if input.bomb and not self._bombHeld then self:_bomb() end
    self._bombHeld = not not input.bomb
    if self.status ~= "playing" then return end
    if p.dashTime > 0 then
        p.x = p.x + p.dashX * 660 * dt
        p.y = p.y + p.dashY * 660 * dt
        p.dashTime = math.max(0, p.dashTime - dt)
    else
        local speed = (input.focus and 126 or p.speed) * (p.nitro > 0 and 1.4 or 1)
        p.x = p.x + x * speed * dt
        p.y = p.y + y * speed * dt
    end
    p.x, p.y = clamp(p.x, 37, W - 37), clamp(p.y, self.playBounds.minY, self.playBounds.maxY)
    p.bank = p.bank + (y * 1.0 - p.bank) * math.min(1, dt * 14)
    if input.fire and p.fireCooldown <= 0 then self:_firePlayer() end
    if input.secondary and p.secondaryCooldown <= 0 then self:_fireSecondary() end
end

function Sim:_enemyFan(enemy, count, spread, speed, kind, radius, angle)
    angle = angle or angleTo(enemy.x - enemy.radius, enemy.y, self.player.x, self.player.y)
    for i = 1, count do
        local offset = count == 1 and 0 or ((i - 1) / (count - 1) - 0.5) * spread
        self:_spawnBullet("enemy", enemy.x - enemy.radius, enemy.y,
            angle + offset, speed, kind or "orb", 1, radius or 4)
    end
    self:_emit("shoot", { owner = "enemy", type = enemy.type, x = enemy.x, y = enemy.y })
end

function Sim:_updateBoss(enemy, dt)
    enemy.invulnerable = math.max(0, enemy.invulnerable - dt)
    enemy.x = math.max(532, enemy.x - 64 * dt)
    enemy.entered = enemy.x <= 535
    if not enemy.entered then return end
    enemy.phaseAge = enemy.phaseAge + dt
    local fraction = enemy.hp / enemy.maxHp
    local phase = fraction > 0.66 and 1 or fraction > 0.33 and 2 or 3
    if phase ~= enemy.phase then
        enemy.phase = phase
        enemy.phaseAge = 0
        enemy.shootTimer, enemy.specialTimer = 1.2, 2.8
        enemy.invulnerable = 0.75
        for i = #self.bullets, 1, -1 do
            if self.bullets[i].owner == "enemy" then table.remove(self.bullets, i) end
        end
        self:_emit("boss", { x = enemy.x, y = enemy.y, name = enemy.name, phase = phase })
    end
    enemy.y = H / 2 + math.sin(enemy.phaseAge * (phase == 3 and 1.9 or 1.1))
        * (phase == 1 and 42 or phase == 2 and 88 or 104)
    enemy.bank = math.cos(enemy.phaseAge * 1.1) * 0.22
    enemy.shootTimer = enemy.shootTimer - dt
    enemy.specialTimer = enemy.specialTimer - dt
    if enemy.shootTimer <= 0 then
        if phase == 1 then
            self:_enemyFan(enemy, 3, 0.4, 168, "orb", 4.5)
            enemy.shootTimer = 0.94
        elseif phase == 2 then
            self:_enemyFan(enemy, 5, 0.84, 175, "orb", 4)
            enemy.shootTimer = 0.84
        else
            -- A moving comb leaves wide escape channels; targeted shots force movement.
            local sweep = math.pi + math.sin(enemy.phaseAge * 1.7) * 0.52
            self:_enemyFan(enemy, 3, 0.34, 192, "spark", 3.5, sweep)
            enemy.shootTimer = 0.32
        end
    end
    if enemy.specialTimer <= 0 then
        if phase == 1 then
            self:_enemyFan(enemy, 9, 1.8, 124, "spark", 3.5, math.pi)
            enemy.specialTimer = 4.2
        elseif phase == 2 then
            -- Alternating broad fans rotate their gap rather than sealing the screen.
            local angle = math.pi + (math.floor(enemy.phaseAge / 3) % 2 == 0 and 0.34 or -0.34)
            self:_enemyFan(enemy, 7, 1.32, 128, "spark", 3.5, angle)
            enemy.specialTimer = 3.4
        else
            self:_enemyFan(enemy, 3, 0.23, 225, "orb", 4.5)
            enemy.specialTimer = 1.6
        end
    end
end

function Sim:_updateEnemies(dt)
    for _, e in ipairs(self.enemies) do
        if not e.dead then
            e.age = e.age + dt
            e.flash = math.max(0, e.flash - dt)
            local oldY = e.y
            if e.type == "boss" then
                self:_updateBoss(e, dt)
            else
                if e.type == "turret" then
                    if e.age < 9.5 then e.x = math.max(510, e.x - e.speed * dt)
                    else e.x = e.x - 120 * dt end
                    e.y = e.baseY + math.sin(e.age * 1.8 + e.motionPhase) * 10
                elseif e.type == "bomber" then
                    if e.age < 8.5 then e.x = math.max(556, e.x - e.speed * dt)
                    else e.x = e.x - 118 * dt end
                    e.y = e.baseY + math.sin(e.age * 1.4 + e.motionPhase) * 20
                elseif e.type == "ace" then
                    if e.age < 10 then e.x = math.max(484, e.x - e.speed * dt)
                    else e.x = e.x - 180 * dt end
                    e.y = e.baseY + math.sin(e.age * 2.1 + e.motionPhase) * 98
                elseif e.type == "interceptor" then
                    e.x = e.x - e.speed * dt
                    e.y = e.baseY + math.sin(e.age * 3.5 + e.motionPhase) * 44
                else
                    e.x = e.x - e.speed * dt
                    e.y = e.baseY + math.sin(e.age * 3 + e.motionPhase) * 18
                end
                e.y = clamp(e.y, 34, H - 34)
                e.bank = clamp((e.y - oldY) / math.max(dt, 0.00001) / 160, -1, 1)
                e.entered = e.x < W - e.radius - 5
                e.shootTimer = e.shootTimer - dt
                if e.entered and e.x > math.max(125, self.player.x + 76)
                    and e.shootTimer <= 0 and self.time > 5 then
                    local s = self.sector
                    if e.type == "scout" then
                        self:_enemyFan(e, 1, 0, 160 + s * 10, "spark", 3.5)
                        e.shootTimer = 2.2 - s * 0.18
                    elseif e.type == "interceptor" then
                        self:_enemyFan(e, s == 3 and 2 or 1, 0.14, 190 + s * 8, "spark", 3.5)
                        e.shootTimer = 1.7
                    elseif e.type == "turret" then
                        self:_enemyFan(e, 3, 0.34, 160 + s * 10, "orb", 4.5)
                        e.shootTimer = 1.65 - s * 0.11
                    elseif e.type == "bomber" then
                        self:_enemyFan(e, 5, 0.84, 138 + s * 6, "orb", 5)
                        e.shootTimer = 2.15
                    elseif e.type == "ace" then
                        self:_enemyFan(e, 3, 0.3, 196 + s * 9, "spark", 3.5)
                        e.shootTimer = 0.95
                    end
                end
            end
        end
    end
end

function Sim:_hurtPlayer(damage, x, y)
    local p = self.player
    if p.invulnerable > 0 or self.status ~= "playing" then return false end
    if p.shield > 0 then
        p.shield = p.shield - 1
        p.invulnerable, p.flash = 0.55, 0.14
        self:_emit("shield_hit", { x = x or p.x, y = y or p.y, shield = p.shield, hp = p.hp })
        return true
    end
    p.hp = math.max(0, p.hp - (damage or 1))
    p.invulnerable = 1.5
    p.flash = 0.2
    self.streak, self.multiplier, self.comboTimer = 0, 1, 0
    self:_emit("hit", { target = "player", x = x or p.x, y = y or p.y, hp = p.hp })
    if p.hp <= 0 then
        self.status = "gameover"
        self:_emit("explosion", { x = p.x, y = p.y, type = "player", radius = 34 })
        self:_emit("gameover", { score = self.score, time = self.time })
    end
    return true
end

function Sim:_damageEnemy(enemy, damage)
    if enemy.dead or (enemy.invulnerable and enemy.invulnerable > 0) then return end
    if enemy.type == "boss" and not enemy.entered then return end
    enemy.hp = math.max(0, enemy.hp - damage)
    enemy.flash = 0.065
    self:_emit("hit", { target = "enemy", type = enemy.type, x = enemy.x, y = enemy.y })
    if enemy.hp <= 0 then self:_killEnemy(enemy, true) end
end

function Sim:_killEnemy(enemy, scored)
    if enemy.dead then return end
    enemy.dead = true
    self:_emit("explosion", { x = enemy.x, y = enemy.y, type = enemy.type,
        radius = enemy.type == "boss" and 90 or enemy.radius * 1.8 })
    if scored then
        self.kills = self.kills + 1
        self.streak = self.comboTimer > 0 and self.streak + 1 or 1
        self.comboTimer = 3.25
        self.multiplier = math.min(5, 1 + math.floor(self.streak / 5))
        self.score = self.score + enemy.score * self.multiplier
        if enemy.type ~= "boss" then
            local roll = self:_random()
            if self.kills % 14 == 0 then
                self:_spawnPickup(self.player.weapon < 3 and "weapon" or "bomb", enemy.x, enemy.y)
            elseif self.kills % 19 == 0 or (self.player.hp < 3 and roll < 0.18) then
                self:_spawnPickup("repair", enemy.x, enemy.y)
            elseif self.kills % 9 == 0 then
                local kind = DROP_TYPES[(math.floor(self.kills / 9) - 1) % #DROP_TYPES + 1]
                self:_spawnPickup(kind, enemy.x, enemy.y)
            elseif roll < 0.075 then
                self:_spawnPickup(DROP_TYPES[self:_random(#DROP_TYPES)], enemy.x, enemy.y)
            end
        end
    end
    if enemy.type == "boss" then
        self.bossDefeated = true
        self.status = "victory"
        self.score = self.score + 5000 + self.player.hp * 1000
        self.bullets, self.enemies, self.telegraphs = {}, {}, {}
        self:_emit("victory", { score = self.score, time = self.time })
    end
end

function Sim:_updateRocket(bullet, dt)
    local target
    if bullet.targetId then
        for _, enemy in ipairs(self.enemies) do
            if enemy.id == bullet.targetId and not enemy.dead and enemy.x > bullet.x - 80 then
                target = enemy
                break
            end
        end
    end
    if not target then
        local nearest = math.huge
        for _, enemy in ipairs(self.enemies) do
            if not enemy.dead and enemy.x > bullet.x - 80 and enemy.x < W + 30
                and (enemy.type ~= "boss" or enemy.entered) then
                local distance = distance2(bullet.x, bullet.y, enemy.x, enemy.y)
                if distance < nearest then target, nearest = enemy, distance end
            end
        end
    end
    bullet.targetId = target and target.id or nil
    if target then
        local desired = angleTo(bullet.x, bullet.y, target.x, target.y)
        local delta = (desired - bullet.angle + math.pi) % TAU - math.pi
        bullet.angle = bullet.angle + clamp(delta, -bullet.turnRate * dt, bullet.turnRate * dt)
    end
    bullet.speed = math.min(465, bullet.speed + 220 * dt)
    bullet.vx, bullet.vy = math.cos(bullet.angle) * bullet.speed, math.sin(bullet.angle) * bullet.speed
end

function Sim:_rocketBlast(bullet, direct)
    if bullet.exploded or self.status ~= "playing" then return end
    bullet.exploded, bullet.dead = true, true
    local x, y = direct and direct.x or bullet.x, direct and direct.y or bullet.y
    self:_emit("explosion", { x = x, y = y, type = "rocket", radius = bullet.splashRadius })
    if direct then self:_damageEnemy(direct, bullet.damage) end
    if self.status ~= "playing" then return end
    for _, enemy in ipairs(self.enemies) do
        if enemy ~= direct and not enemy.dead then
            local distance = math.sqrt(distance2(x, y, enemy.x, enemy.y))
            if distance < bullet.splashRadius + enemy.radius * 0.4 then
                self:_damageEnemy(enemy, math.max(2, 8 * (1 - distance / bullet.splashRadius)))
                if self.status ~= "playing" then return end
            end
        end
    end
end

function Sim:_collisions()
    local p = self.player
    for i = #self.bullets, 1, -1 do
        local b = self.bullets[i]
        if b.owner == "player" then
            for _, e in ipairs(self.enemies) do
                if not e.dead and not (b.hitEnemies and b.hitEnemies[e.id]) and segmentHits(b.prevX, b.prevY, b.x, b.y,
                        e.x, e.y, b.radius + e.radius) then
                    if b.kind == "rocket" then
                        self:_rocketBlast(b, e)
                        break
                    else
                        self:_damageEnemy(e, b.damage)
                        if b.piercing then
                            b.hitEnemies[e.id] = true
                        else
                            b.dead = true
                            break
                        end
                    end
                    if self.status ~= "playing" then return end
                end
            end
        else
            if segmentHits(b.prevX, b.prevY, b.x, b.y, p.x, p.y, p.radius + b.radius) then
                self:_hurtPlayer(b.damage, p.x, p.y)
                b.dead = true
            elseif not b.grazed and p.invulnerable <= 0 and segmentHits(
                    b.prevX, b.prevY, b.x, b.y, p.x, p.y, p.radius + b.radius + 12) then
                b.grazed = true
                self.grazes = self.grazes + 1
                self.score = self.score + 15
            end
        end
        if self.status ~= "playing" then return end
        if b.dead then table.remove(self.bullets, i) end
    end
    for _, e in ipairs(self.enemies) do
        if not e.dead and distance2(p.x, p.y, e.x, e.y) < (p.radius + e.radius * 0.8)^2 then
            if self:_hurtPlayer(1, p.x, p.y) and e.type ~= "boss" then self:_killEnemy(e, false) end
        end
        if self.status ~= "playing" then return end
    end
end

function Sim:_updatePickups(dt)
    local p = self.player
    for i = #self.pickups, 1, -1 do
        local item = self.pickups[i]
        item.age = item.age + dt
        item.life = item.life - dt
        local dx, dy = p.x - item.x, p.y - item.y
        local distance = math.sqrt(dx * dx + dy * dy)
        if distance < 65 and distance > 0 then
            item.x = item.x + dx / distance * 178 * dt
            item.y = item.y + dy / distance * 178 * dt
        else
            item.x = item.x - 78 * dt
            item.y = item.y + math.cos(item.age * 3 + item.phase) * 6 * dt
        end
        if distance2(p.x, p.y, item.x, item.y) < 23 * 23 then
            if item.kind == "weapon" then
                if p.weapon < 3 then p.weapon = p.weapon + 1
                else self.score = self.score + 500 end
            elseif item.kind == "repair" then
                p.hp = math.min(p.maxHp, p.hp + 2)
                p.invulnerable = math.max(p.invulnerable, 0.5)
            elseif item.kind == "bomb" then
                if p.bombs < p.maxBombs then p.bombs = p.bombs + 1
                else self.score = self.score + 500 end
            elseif item.kind == "shield" then
                p.shield = math.min(3, p.shield + 3)
            elseif item.kind == "nitro" then
                p.nitro = 8
            elseif item.kind == "overdrive" then
                p.overdrive = 10
            elseif item.kind == "ion" or item.kind == "prism" then
                p.primary = item.kind
            elseif item.kind == "rocket" or item.kind == "mega" then
                p.ammo[item.kind] = math.min(item.kind == "rocket" and 36 or 12,
                    p.ammo[item.kind] + (item.kind == "rocket" and 12 or 5))
                p.secondary = item.kind
            end
            self.score = self.score + 150
            self:_emit("powerup", { x = item.x, y = item.y, type = item.kind,
                weapon = p.weapon, primary = p.primary, hp = p.hp, bombs = p.bombs,
                shield = p.shield, nitro = p.nitro, overdrive = p.overdrive,
                secondary = p.secondary, ammo = { rocket = p.ammo.rocket, mega = p.ammo.mega } })
            table.remove(self.pickups, i)
        elseif item.x < -25 or item.life <= 0 then
            table.remove(self.pickups, i)
        end
    end
end

function Sim:_step(dt, input)
    self.time = self.time + dt
    self.comboTimer = math.max(0, self.comboTimer - dt)
    if self.comboTimer <= 0 then self.streak, self.multiplier = 0, 1 end
    self:_updatePlayer(dt, input)
    if self.status ~= "playing" then return end
    self:_director(dt)
    self:_updateEnemies(dt)
    for i = #self.bullets, 1, -1 do
        local b = self.bullets[i]
        b.prevX, b.prevY = b.x, b.y
        if b.kind == "rocket" then self:_updateRocket(b, dt) end
        b.x, b.y = b.x + b.vx * dt, b.y + b.vy * dt
        b.age = b.age + dt
        b.life = b.life - dt
        if b.kind == "rocket" and b.life <= 0 and b.x >= 0 and b.x <= W and b.y >= 0 and b.y <= H then
            self:_rocketBlast(b)
            if self.status ~= "playing" then return end
        end
        if b.x < -48 or b.x > W + 80 or b.y < -48 or b.y > H + 48 or b.life <= 0 then
            table.remove(self.bullets, i)
        end
    end
    self:_collisions()
    if self.status == "playing" then self:_updatePickups(dt) end
    self.scrollSpeed = 164 + (self.sector - 1) * 28 + (self.player.dashTime > 0 and 72 or 0)
        + (self.player.nitro > 0 and 88 or 0)
    for i = #self.enemies, 1, -1 do
        local e = self.enemies[i]
        if e.dead or e.x < -80 then table.remove(self.enemies, i) end
    end
end

function Sim:update(dt, input)
    if self.status ~= "playing" then return end
    assert(type(dt) == "number" and dt >= 0 and dt < math.huge, "dt must be finite, non-negative seconds")
    input = input or {}
    -- Normal callers provide fixed 1/60 ticks; substeps also prevent frame hitch tunnelling.
    local remaining = dt
    while remaining > 0.000000001 and self.status == "playing" do
        local step = math.min(remaining, 1 / 60)
        self:_step(step, input)
        remaining = remaining - step
    end
end

return Sim

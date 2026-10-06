package.path = './?.lua;./?/init.lua;' .. package.path

local Sim = require('game.sim')
local held = {}
love = {
    filesystem = {getInfo = function() return false end},
    keyboard = {isDown = function(key) return not not held[key] end},
    joystick = {getJoysticks = function() return {} end},
}
local Input = require('game.input')
local total = 0

local function equal(actual, expected, message)
    assert(actual == expected, (message or 'values differ') .. ': got ' ..
        tostring(actual) .. ', expected ' .. tostring(expected))
end

local function test(name, fn)
    held = {}
    fn()
    total = total + 1
    print('PASS ' .. name)
end

local function terminalCollision(hostileFirst)
    local sim = Sim.new(1)
    sim.player.hp, sim.player.invulnerable = 1, 0
    local boss = sim:_spawnEnemy('boss', 180, {x = 532})
    boss.entered, boss.phase, boss.hp = true, 3, 1
    boss.shootTimer, boss.specialTimer = 100, 100
    local function playerBullet()
        sim:_spawnBullet('player', 532, 180, 0, 0, 'pulse', 2, 3)
    end
    local function hostileBullet()
        sim:_spawnBullet('enemy', 96, 180, 0, 0, 'orb', 1, 4)
    end
    -- Collision traversal is reversed, so append the intended first hit last.
    if hostileFirst then playerBullet(); hostileBullet()
    else hostileBullet(); playerBullet() end
    sim:drainEvents()
    sim:update(1 / 60, {})
    local terminal = {}
    for _, event in ipairs(sim:drainEvents()) do
        if event.kind == 'victory' or event.kind == 'gameover' then
            terminal[#terminal + 1] = event.kind
        end
    end
    equal(#terminal, 1, 'a collision tick must emit only one terminal result')
    equal(terminal[1], sim.status)
    local time, hp, bossHp = sim.time, sim.player.hp, boss.hp
    sim:update(1, {fire = true, bomb = true})
    equal(sim.time, time, 'the terminal run must freeze')
    equal(sim.player.hp, hp)
    equal(boss.hp, bossHp)
    equal(#sim:drainEvents(), 0)
    return sim, boss
end

test('lethal hostile hit prevents a same-tick boss kill from replacing game over', function()
    local sim, boss = terminalCollision(true)
    equal(sim.status, 'gameover')
    equal(sim.player.hp, 0)
    equal(boss.hp, 1)
    equal(sim.bossDefeated, false)
end)

test('boss kill prevents a later same-tick hostile hit from replacing victory', function()
    local sim, boss = terminalCollision(false)
    equal(sim.status, 'victory')
    equal(sim.player.hp, 1)
    equal(boss.hp, 0)
    equal(sim.bossDefeated, true)
end)

test('default keyboard aliases remain available to polling and press events', function()
    local input = Input.new()
    held.w, held.z = true, true
    local controls = input:read()
    equal(controls.y, -1)
    equal(controls.fire, true)
    equal(input:matches('up', 'w'), true)
    equal(input:matches('fire', 'z'), true)
end)

test('rebinding fire to W gives it exclusive ownership of the old upward alias', function()
    local input = Input.new()
    input.bindings.fire = 'w'
    held.w = true
    local controls = input:read()
    equal(controls.fire, true)
    equal(controls.y, 0, 'firing must not also move upward')
    equal(input:matches('fire', 'w'), true)
    equal(input:matches('up', 'w'), false)
    equal(input:matches('up', 'up'), true, 'the primary upward key must still work')
    held.w, held.z = false, true
    equal(input:read().fire, false, 'the customized action must retire its original alias')
    equal(input:matches('fire', 'z'), false)
end)

test('customizing a movement primary retires its original alternate key', function()
    local input = Input.new()
    input.bindings.up = 'q'
    held.w = true
    equal(input:read().y, 0)
    equal(input:matches('up', 'w'), false)
    held.w, held.q = false, true
    equal(input:read().y, -1)
    equal(input:matches('up', 'q'), true)
end)

local function callbackGame(gamepad)
    local buttons = {}
    local joystick = {
        isGamepad = function() return gamepad end,
        getAxisCount = function() return 0 end,
        getHatCount = function() return 0 end,
        getGamepadAxis = function() return 0 end,
        isDown = function(_, button) return not not buttons[button] end,
        isGamepadDown = function(_, button) return not not buttons[button] end,
    }
    love = {
        filesystem = {getInfo = function() return false end},
        keyboard = {isDown = function(key) return not not held[key] end},
        joystick = {getJoysticks = function() return {joystick} end},
    }
    -- Exercise the actual callbacks without creating audio or graphics devices.
    local previousFX, previousRenderer = package.loaded['game.fx'], package.loaded['game.render']
    package.loaded['game.fx'], package.loaded['game.render'] = {}, {}
    dofile('main.lua')
    package.loaded['game.fx'], package.loaded['game.render'] = previousFX, previousRenderer
    local app
    local index = 1
    while true do
        local name, value = debug.getupvalue(love.update, index)
        if not name then break end
        if name == 'app' then app = value; break end
        index = index + 1
    end
    assert(app, 'actual update callback must expose its captured application state')
    app.input = Input.new()
    app.fx = {
        musicMode = function() end, sound = function() end, update = function() end,
        burst = function() end, event = function() end,
    }
    app.sim, app.bgTime, app.mode = Sim.new(1), 0, 'playing'
    local button = gamepad and 'b' or 3
    local function press()
        buttons[button] = true
        if gamepad then love.gamepadpressed(joystick, button)
        else love.joystickpressed(joystick, button) end
    end
    return app, buttons, button, press
end

local function verifyBombAfterResume(gamepad)
    local app, buttons, button, press = callbackGame(gamepad)
    love.keypressed('escape', 'escape', false)
    equal(app.mode, 'paused')
    press()
    equal(app.mode, 'playing', 'B must still resume flight')
    love.update(1 / 60)
    love.update(1 / 60)
    equal(app.sim.player.bombs, 3, 'holding the menu resume button must not spend a bomb')
    equal(app.stats.bombs, 0)
    buttons[button] = false
    love.update(1 / 60)
    press()
    love.update(1 / 60)
    equal(app.sim.player.bombs, 2, 'a new gameplay press after release must spend one bomb')
    equal(app.stats.bombs, 1)
    love.update(1 / 60)
    equal(app.sim.player.bombs, 2, 'continued holding must not repeat the new bomb press')
end

test('held raw B resumes without a bomb until release and a new press', function()
    verifyBombAfterResume(false)
end)

test('held recognized gamepad B resumes without a bomb until release and a new press', function()
    verifyBombAfterResume(true)
end)

test('secondary fire has its own remappable keyboard binding', function()
    local input=Input.new()
    held.v=true
    equal(input:read().secondary,true)
    equal(input:read().fire,false)
    input.bindings.secondary='q'
    equal(input:read().secondary,false)
    held.q=true
    equal(input:read().secondary,true)
    equal(input:matches('secondary','q'),true)
end)

local function verifySecondaryTap(kind)
    local app,buttons,_,_=callbackGame(kind=='gamepad')
    app.sim.player.secondary='rocket'
    app.sim.player.ammo={rocket=2,mega=0}
    local joystick=love.joystick.getJoysticks()[1]
    if kind=='keyboard' then love.keypressed('v','v',false)
    elseif kind=='gamepad' then love.gamepadpressed(joystick,'y')
    else love.joystickpressed(joystick,4) end
    -- All buttons are already released before polling; the callback must retain the tap.
    love.update(1/240)
    equal(app.sim.player.ammo.rocket,2)
    love.update(1/60)
    equal(app.sim.player.ammo.rocket,1,'a short secondary tap must launch exactly once')
    equal(app.stats.rocketShots,1)
    love.update(1/60)
    equal(app.sim.player.ammo.rocket,1,'the consumed tap must not repeat')
    return app,buttons
end

test('short keyboard secondary taps survive a frame with no simulation tick', function()
    verifySecondaryTap('keyboard')
end)

test('short raw uConsole Y taps survive a frame with no simulation tick', function()
    verifySecondaryTap('raw')
end)

test('short recognized gamepad Y taps survive a frame with no simulation tick', function()
    verifySecondaryTap('gamepad')
end)

test('holding raw uConsole Y combines secondary fire with precision movement', function()
    local app,buttons=callbackGame(false)
    buttons[4]=true
    local controls=app.input:read()
    equal(controls.secondary,true)
    equal(controls.focus,true)
    equal(controls.fire,false)
end)

test('adding secondary fire preserves a legacy action already bound to V', function()
    local original=love.filesystem
    local originalJoystick=love.joystick
    love.joystick={getJoysticks=function() return {} end}
    love.filesystem={getInfo=function() return true end,read=function() return 'fire=v\ndash=f\n' end}
    local input=Input.new()
    love.filesystem=original
    equal(input.bindings.fire,'v')
    equal(input.bindings.dash,'f')
    assert(input.bindings.secondary~='v' and input.bindings.secondary~='f')
    held.v=true
    local controls=input:read()
    equal(controls.fire,true)
    equal(controls.secondary,false,'a legacy primary binding must not fire the new secondary')
    held.v=false;held[input.bindings.secondary]=true
    equal(input:read().secondary,true)
    equal(input:read().fire,false)
    love.joystick=originalJoystick
end)

print(string.format('PASS %d review regression tests', total))

package.path = './?.lua;./?/init.lua;' .. package.path

local saved, held = nil, {}
local valid = {}
for _, key in ipairs({'up', 'down', 'left', 'right', 'space', 'v', 'x', 'c', 'lshift',
    'w', 's', 'a', 'd', 'z', 'rshift', 'kp-', 'kp+', 'kp/', 'kp*', 'kp.', '-', '/', ';', '[', ']'}) do
    valid[key] = true
end
love = {
    filesystem = {
        getInfo = function() return saved and {type = 'file'} or nil end,
        read = function() return saved end,
        write = function(_, content) saved = content; return true end,
    },
    keyboard = {isDown = function(key)
        assert(valid[key], 'loaded an invalid keyboard constant: ' .. tostring(key))
        return not not held[key]
    end},
    joystick = {getJoysticks = function() return {} end},
}
local Input = require('game.input')
local total = 0
local function equal(actual, expected, message)
    assert(actual == expected, (message or 'values differ') .. ': got ' ..
        tostring(actual) .. ', expected ' .. tostring(expected))
end
local function test(name, fn)
    saved, held = nil, {}
    fn()
    total = total + 1
    print('PASS ' .. name)
end

test('secondary keypad and punctuation bindings survive saving and reloading', function()
    for _, key in ipairs({'kp-', 'kp+', 'kp/', 'kp*', 'kp.', '-', '/', ';', '[', ']'}) do
        saved, held = nil, {}
        local original = Input.new()
        original.bindings.secondary = key
        original:save()
        local restored = Input.new()
        equal(restored.bindings.secondary, key, 'secondary key must round trip exactly')
        held[key] = true
        equal(restored:read().secondary, true)
        equal(restored:matches('secondary', key), true)
    end
end)

test('legacy punctuation bindings remain playable after adding secondary', function()
    saved = 'fire=kp+\ndash=x\n'
    local input = Input.new()
    equal(input.bindings.fire, 'kp+')
    equal(input.bindings.secondary, 'v')
    held['kp+'] = true
    local controls = input:read()
    equal(controls.fire, true)
    equal(controls.secondary, false)
end)

test('primary and dash punctuation round trip without restoring the customized fire alias', function()
    local original = Input.new()
    original.bindings.fire, original.bindings.dash, original.bindings.secondary = '/', '-', 'kp-'
    original:save()
    local restored = Input.new()
    equal(restored.bindings.fire, '/')
    equal(restored.bindings.dash, '-')
    equal(restored.bindings.secondary, 'kp-')
    held['/'], held['-'], held['kp-'] = true, true, true
    local controls = restored:read()
    equal(controls.fire, true)
    equal(controls.dash, true)
    equal(controls.secondary, true)
    equal(restored:read().dash, false, 'holding the restored dash must retain edge semantics')
    equal(restored:matches('fire', 'z'), false, 'customized fire must keep its old alias disabled')
    held['/'], held['-'], held['kp-'], held.z = false, false, false, true
    controls = restored:read()
    equal(controls.fire, false)
    equal(controls.dash, false)
    equal(controls.secondary, false)
end)

print(string.format('PASS %d upgrade review regression tests', total))

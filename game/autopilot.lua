-- Deterministic, read-only test controller. Call once per 1/60 simulation tick.
-- It clears seed 3 using the same health, weapons, cooldowns, and damage as a player.
return function(sim)
    if sim.status ~= "playing" then
        return { x = 0, y = 0, fire = false, secondary = false, focus = false, dash = false, bomb = false }
    end
    local p, targetY, nearest, target = sim.player, 180, 1000, nil
    for _, enemy in ipairs(sim.enemies) do
        if not enemy.dead and enemy.x > p.x + 70 and enemy.x < nearest then
            nearest, targetY, target = enemy.x, enemy.y, enemy
        end
    end
    local bestSupply = -math.huge
    for _, item in ipairs(sim.pickups) do
        if item.x > p.x - 10 and item.x < p.x + 230 then
            local priority = 0
            if item.kind == "weapon" and p.weapon < 3 then priority = 8
            elseif item.kind == "repair" and p.hp < 4 then priority = 12
            elseif item.kind == "shield" and p.shield < 3 then priority = 10
            elseif item.kind == "nitro" and p.nitro < 1 then priority = 7
            elseif item.kind == "overdrive" and p.overdrive < 2 then priority = 8
            elseif (item.kind == "ion" or item.kind == "prism") and p.primary ~= item.kind then priority = 7
            elseif item.kind == "rocket" and p.ammo.rocket < 24 then priority = 7
            elseif item.kind == "mega" and p.ammo.mega < 9 then priority = 8
            elseif item.kind == "bomb" and p.bombs < 3 then priority = 6 end
            local value = priority - math.abs(item.y - p.y) * 0.014 - (item.x - p.x) * 0.006
            if priority > 0 and value > bestSupply then targetY, bestSupply = item.y, value end
        end
    end
    local moveSpeed = p.speed * (p.nitro > 0 and 1.4 or 1)
    -- Evaluate ordinary vertical inputs against four projectile look-ahead horizons.
    local direction, bestCost = 0, math.huge
    for _, dy in ipairs({ -1, -0.5, 0, 0.5, 1 }) do
        local nextY = math.max(sim.playBounds.minY, math.min(sim.playBounds.maxY, p.y + dy * moveSpeed * 0.35))
        local cost = math.abs(nextY - targetY) * 0.025
        for _, bullet in ipairs(sim.bullets) do
            if bullet.owner == "enemy" then
                for _, t in ipairs({ 0.1, 0.25, 0.5, 0.75 }) do
                    local y = math.max(sim.playBounds.minY, math.min(sim.playBounds.maxY, p.y + dy * moveSpeed * t))
                    local dx = p.x - (bullet.x + bullet.vx * t)
                    local ddy = y - (bullet.y + bullet.vy * t)
                    local distance = math.sqrt(dx * dx + ddy * ddy)
                    if distance < 36 then cost = cost + 120 / (distance + 1) end
                end
            end
        end
        if cost < bestCost then direction, bestCost = dy, cost end
    end
    local danger = false
    for _, bullet in ipairs(sim.bullets) do
        if bullet.owner == "enemy" and bullet.x > p.x - 12 and bullet.x < p.x + 45
            and math.abs(bullet.y - p.y) < 14 then
            danger = true
            break
        end
    end
    return {
        x = 0, y = direction, fire = true, focus = false,
        secondary = target ~= nil and target.entered and p.secondary ~= nil,
        dash = danger and p.dashCooldown <= 0,
        bomb = danger and p.dashCooldown > 0 and p.hp <= 2,
    }
end

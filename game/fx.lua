local FX = {}
FX.__index = FX
local colors = {
    cyan = {0.28, 0.9, 1}, amber = {1, 0.59, 0.2}, pink = {1, 0.28, 0.48},
    green = {0.35, 1, 0.60}, violet = {0.77, 0.47, 1}, blue = {0.37, 0.66, 1},
}
local pickupColors={weapon='cyan',repair='green',bomb='amber',shield='blue',nitro='amber',
    overdrive='pink',ion='cyan',prism='violet',rocket='green',mega='pink'}

function FX.new(settings)
    local self = setmetatable({particles = {}, rings = {}, shake = 0, flash = 0,
        settings = settings, pools = {}, soundsPlayed = 0, timer = 0, lastSound = {}}, FX)
    for _, name in ipairs({'laser', 'enemy_laser', 'hit', 'explosion', 'explosion_large',
        'powerup', 'dash', 'bomb', 'menu', 'boss_warning', 'victory',
        'ion_laser', 'prism_laser', 'rocket', 'mega_blaster', 'shield_hit', 'nitro'}) do
        local source = love.audio.newSource('assets/audio/' .. name .. '.wav', 'static')
        local voices = {source}
        for i = 2, (name:find('laser') and 6 or 3) do voices[i] = source:clone() end
        self.pools[name] = voices
    end
    self.music = love.audio.newSource('assets/audio/commander_whiskers.ogg', 'stream')
    self.music:setLooping(true)
    self.music:setVolume(settings.music)
    return self
end

function FX:sound(name, gain, pitch)
    if self.settings.sfx == 0 or not self.pools[name] then return end
    if name == 'enemy_laser' and self.timer - (self.lastSound[name] or -1) < 0.065 then return end
    self.lastSound[name] = self.timer
    for _, source in ipairs(self.pools[name]) do
        if not source:isPlaying() then
            source:setVolume((gain or 0.65) * self.settings.sfx)
            source:setPitch(pitch or 1)
            source:play()
            self.soundsPlayed = self.soundsPlayed + 1
            return
        end
    end
end

function FX:musicMode(mode)
    if mode == 'stop' then self.music:stop()
    elseif mode == 'pause' then self.music:pause()
    elseif mode == 'restart' then self.music:stop(); self.music:play()
    elseif not self.music:isPlaying() then self.music:play() end
end

function FX:burst(x, y, count, color, speed)
    color = colors[color] or color or colors.amber
    for _ = 1, math.min(count, 900 - #self.particles) do
        local a = love.math.random() * math.pi * 2
        local v = (speed or 90) * (0.2 + love.math.random())
        local life = 0.18 + love.math.random() * 0.6
        self.particles[#self.particles+1] = {x=x,y=y,vx=math.cos(a)*v,vy=math.sin(a)*v,
            life=life,total=life,color=color,size=love.math.random(1,3)}
    end
end

function FX:event(e)
    local k, x, y = e.kind, e.x or 320, e.y or 180
    if k == 'shoot' then
        local name=e.owner=='enemy' and 'enemy_laser' or
            e.primary=='ion' and 'ion_laser' or e.primary=='prism' and 'prism_laser' or 'laser'
        self:sound(name,e.owner=='enemy' and 0.3 or 0.34)
    elseif k == 'secondary' then
        local rocket=e.type=='rocket'
        self:sound(rocket and 'rocket' or 'mega_blaster',rocket and 0.55 or 0.62)
        self:burst(x,y,rocket and 7 or 15,rocket and 'green' or 'pink',85)
        self.shake=math.max(self.shake,rocket and 0.6 or 1.8)
    elseif k == 'shield_hit' then
        self:burst(x,y,28,'blue',140);self:sound('shield_hit',0.65)
        self.rings[#self.rings+1]={x=x,y=y,age=0,max=54,color=colors.blue}
        self.shake=math.max(self.shake,1.6)
    elseif k == 'hit' then
        self:burst(x,y,12,'cyan',100); self:sound('hit',0.7)
        if e.owner == 'player' or e.target == 'player' then self.shake=4; self.flash=0.13 end
    elseif k == 'explosion' then
        local big = e.type == 'boss' or e.large
        self:burst(x,y,big and 100 or 32,'amber',big and 210 or 145)
        self:burst(x,y,12,'pink',80)
        self.rings[#self.rings+1]={x=x,y=y,age=0,max=big and 110 or 35,color=colors.amber}
        self.shake=math.max(self.shake,big and 8 or 2)
        self:sound(big and 'explosion_large' or 'explosion',big and 0.8 or 0.5,0.9+love.math.random()*0.2)
    elseif k == 'powerup' then
        local c=pickupColors[e.type] or 'cyan'
        self:burst(x,y,26,c,100); self:sound(e.type=='nitro' and 'nitro' or 'powerup',0.65)
        self.rings[#self.rings+1]={x=x,y=y,age=0,max=48,color=colors[c]}
    elseif k == 'dash' then
        self:burst(x,y,24,'cyan',170); self:sound('dash',0.55); self.shake=2
    elseif k == 'bomb' then
        self:burst(x,y,100,'cyan',320); self:sound('bomb',0.8)
        self.rings[#self.rings+1]={x=x,y=y,age=0,max=700,color=colors.cyan}
        self.shake=7; self.flash=0.25
    elseif k == 'boss' then self:sound('boss_warning',0.7)
    elseif k == 'victory' then self:sound('victory',0.8)
    elseif k == 'gameover' then self:sound('explosion_large',0.75); self.shake=9 end
end

function FX:update(dt)
    self.timer=self.timer+dt
    self.shake=math.max(0,self.shake-dt*14)
    self.flash=math.max(0,self.flash-dt)
    self.music:setVolume(self.settings.music)
    for i=#self.particles,1,-1 do
        local p=self.particles[i]; p.life=p.life-dt
        if p.life<=0 then table.remove(self.particles,i)
        else p.x=p.x+p.vx*dt; p.y=p.y+p.vy*dt; p.vx=p.vx*(1-dt*1.9);p.vy=p.vy*(1-dt*1.9) end
    end
    for i=#self.rings,1,-1 do
        local p=self.rings[i];p.age=p.age+dt
        if p.age>0.55 then table.remove(self.rings,i) end
    end
end

function FX:draw()
    love.graphics.setBlendMode('add')
    for _,p in ipairs(self.particles) do
        love.graphics.setColor(p.color[1],p.color[2],p.color[3],p.life/p.total)
        love.graphics.rectangle('fill',math.floor(p.x),math.floor(p.y),p.size,p.size)
    end
    for _,p in ipairs(self.rings) do
        local n=p.age/0.55
        love.graphics.setColor(p.color[1],p.color[2],p.color[3],(1-n)*0.65)
        love.graphics.setLineWidth(1)
        love.graphics.circle('line',p.x,p.y,3+p.max*n,48)
    end
    love.graphics.setBlendMode('alpha')
end

return FX

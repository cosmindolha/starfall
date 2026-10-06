local R = {}
R.__index = R
local G = love.graphics
local C = {cyan={0.35,0.9,1}, amber={1,0.65,0.3}, white={0.86,0.91,0.95},
    dim={0.39,0.46,0.57}, ink={0.025,0.038,0.063}, red={1,0.27,0.34},
    green={0.45,1,0.63}, violet={0.74,0.55,1}, mint={0.51,1,0.84}, gold={1,0.82,0.34},
    pink={1,0.43,0.79}, blue={0.37,0.65,1}}
local pickupStyle={
    weapon={color=C.cyan,label='PULSE'}, repair={color=C.green,label='REPAIR'},
    bomb={color=C.amber,label='NOVA'}, shield={color=C.blue,label='SHIELD'},
    nitro={color=C.red,label='NITRO'}, overdrive={color=C.gold,label='BOOST'},
    ion={color=C.violet,label='ION'}, prism={color=C.mint,label='PRISM'},
    rocket={color=C.amber,label='ROCKET'}, mega={color=C.pink,label='MEGA'},
}
local primaryColor={pulse=C.cyan,ion=C.violet,prism=C.mint}
local function color(c,a) G.setColor(c[1],c[2],c[3],a or 1) end
local function text(font,s,x,y,c) G.setFont(font);color(c or C.white);G.print(s,math.floor(x),math.floor(y)) end
local function bar(x,y,w,h,v,c)
    G.setColor(0.13,0.18,0.24,0.9);G.rectangle('fill',x,y,w,h)
    color(c);G.rectangle('fill',x,y,math.max(0,math.min(w,w*v)),h)
end

function R.new(fx)
    local self=setmetatable({fx=fx, stars={},quads={},asteroids={}},R)
    G.setDefaultFilter('nearest','nearest',1)
    self.font={micro=G.newFont('assets/fonts/ShareTechMono-Regular.ttf',9),
        small=G.newFont('assets/fonts/ShareTechMono-Regular.ttf',11),
        body=G.newFont('assets/fonts/Rajdhani-Bold.ttf',18),
        large=G.newFont('assets/fonts/Rajdhani-Bold.ttf',32),
        title=G.newFont('assets/fonts/Rajdhani-Bold.ttf',77)}
    self.atlas=G.newImage('assets/images/ships.png')
    self.meta=require('assets.images.ships')
    for kind,frames in pairs(self.meta.frames) do
        self.quads[kind]={}
        for _,f in ipairs(frames) do
            self.quads[kind][#self.quads[kind]+1]=G.newQuad(f.x,f.y,f.w,f.h,self.atlas:getDimensions())
        end
    end
    self.nebula=G.newImage('assets/images/nebula.png');self.nebula:setWrap('mirroredrepeat','repeat')
    self.bgQuad=G.newQuad(0,0,384,216,self.nebula:getDimensions())
    self.planet=G.newImage('assets/images/planet.png')
    self.asteroid=G.newImage('assets/images/asteroid.png')
    local rng=love.math.newRandomGenerator(21783)
    for i=1,170 do
        self.stars[i]={x=rng:random()*840,y=rng:random()*360,layer=rng:random(1,3),twinkle=rng:random()*6}
    end
    for i=1,11 do
        self.asteroids[i]={x=rng:random()*1250,y=rng:random(45,335),scale=0.15+rng:random()*0.65,
            spin=(rng:random()-0.5)*0.15,angle=rng:random()*6}
    end
    return self
end

function R:ship(kind,x,y,bank,scale,alpha,tint)
    local frames=self.meta.frames[kind]
    assert(frames,'Missing ship atlas group: '..tostring(kind))
    local index=math.floor(((bank or 0)+1)*0.5*(#frames-1)+1.5)
    index=math.max(1,math.min(#frames,index))
    local f=frames[index]
    color(tint or C.white,alpha or 1)
    local renderScale=(scale or 1)*(f.scale or f.renderScale or 1)
    G.draw(self.atlas,self.quads[kind][index],math.floor(x),math.floor(y),0,renderScale,renderScale,f.ox,f.oy)
end

function R:background(t,sector,speed)
    G.clear(0.016,0.021,0.041,1)
    local tones={{0.78,0.75,1},{0.83,0.77,0.66},{0.67,0.75,0.9}}
    color(tones[sector or 1] or tones[3],0.8)
    self.bgQuad:setViewport(t*3.5,0,384,216,self.nebula:getDimensions())
    G.draw(self.nebula,self.bgQuad,0,0,0,640/384,360/216)
    color({0.63,0.67,0.85},0.63)
    G.draw(self.planet,570-(t*4.4%1040),154,0,1.45,1.45,100,100)
    -- Reuse the fleet's actual Blender silhouette as a vast, distant derelict.
    self:ship('boss',800-(t*12%1500),87,0,2.5,0.32,{0.14,0.20,0.30})
    G.setBlendMode('add')
    for _,s in ipairs(self.stars) do
        local v=({9,28,77})[s.layer]
        local x=(s.x-t*v)%840-100
        local a=0.22+s.layer*0.16+math.sin(t*1.1+s.twinkle)*0.08
        G.setColor(0.55,0.72,0.9,a)
        if s.layer==3 then G.rectangle('fill',math.floor(x),s.y,3+(speed or 1)*1.3,1)
        else G.rectangle('fill',math.floor(x),s.y,1,1) end
    end
    G.setBlendMode('alpha')
    for _,a in ipairs(self.asteroids) do
        local x=(a.x-t*(18+a.scale*115))%1250-160
        color({0.39,0.42,0.51},0.8)
        G.draw(self.asteroid,x,a.y,a.angle+t*a.spin,a.scale,a.scale,48,48)
    end
end

function R:engine(x,y,t,scale,left,hot)
    local d=left and 1 or -1
    G.setBlendMode('add')
    local n=(12+math.sin(t*73)*3)*(scale or 1)
    G.setColor(hot and 1 or 0.2,hot and 0.43 or 0.65,hot and 0.18 or 1,0.7)
    G.polygon('fill',x,y-3*(scale or 1),x+d*n,y,x,y+3*(scale or 1))
    G.setColor(0.77,0.96,1,1);G.rectangle('fill',x-1,y-1,3,3)
    G.setBlendMode('alpha')
end

function R:pickup(p,t)
    local style=pickupStyle[p.kind] or pickupStyle.weapon
    local c=style.color
    local x,y=math.floor(p.x),math.floor(p.y+math.sin(p.age*5)*3)
    G.setBlendMode('add')
    color(c,0.11);G.circle('fill',x,y,14+math.sin(t*6)*2,16)
    color(c,0.48);G.circle('line',x,y,14,16)
    G.setBlendMode('alpha')
    color(C.ink,0.94)
    if p.kind=='shield' then
        G.polygon('fill',x-10,y-9,x+10,y-9,x+9,y+3,x,y+12,x-9,y+3)
    elseif p.kind=='nitro' then
        G.polygon('fill',x-7,y-11,x+7,y-11,x+9,y+8,x+5,y+11,x-5,y+11,x-9,y+8)
    elseif p.kind=='rocket' then
        G.polygon('fill',x,y-12,x+5,y-5,x+5,y+5,x+10,y+11,x-10,y+11,x-5,y+5,x-5,y-5)
    elseif p.kind=='ion' or p.kind=='prism' then
        G.polygon('fill',x,y-12,x+12,y,x,y+12,x-12,y)
    elseif p.kind=='mega' then
        G.polygon('fill',x-6,y-11,x+6,y-11,x+12,y,x+6,y+11,x-6,y+11,x-12,y)
    else
        G.rectangle('fill',x-11,y-11,22,22,2,2)
    end
    color(c)
    if p.kind=='repair' then
        G.rectangle('line',x-11,y-11,22,22,2,2)
        G.rectangle('fill',x-2,y-7,4,14);G.rectangle('fill',x-7,y-2,14,4)
    elseif p.kind=='shield' then
        G.polygon('line',x-10,y-9,x+10,y-9,x+9,y+3,x,y+12,x-9,y+3)
        G.polygon('fill',x-6,y-5,x+6,y-5,x+5,y+2,x,y+7,x-5,y+2)
        color(C.white);G.line(x,y-3,x,y+4)
    elseif p.kind=='nitro' then
        G.polygon('line',x-7,y-11,x+7,y-11,x+9,y+8,x+5,y+11,x-5,y+11,x-9,y+8)
        color(C.gold);G.polygon('fill',x+2,y-8,x-5,y+1,x-1,y+1,x-2,y+8,x+5,y-2,x+1,y-2)
    elseif p.kind=='overdrive' then
        for i=0,1 do
            local y0=y-8+i*9
            G.polygon('fill',x-10,y0+3,x,y0-2,x+10,y0+3,x+10,y0+7,x,y0+2,x-10,y0+7)
        end
    elseif p.kind=='ion' then
        G.polygon('line',x,y-12,x+12,y,x,y+12,x-12,y)
        G.rectangle('fill',x-7,y-3,14,2);G.rectangle('fill',x-7,y+1,14,2)
        color(C.white);G.rectangle('fill',x-2,y-5,4,10)
    elseif p.kind=='prism' then
        G.polygon('line',x,y-12,x+12,y,x,y+12,x-12,y)
        G.line(x-6,y,x+7,y-6);G.line(x-6,y,x+8,y);G.line(x-6,y,x+7,y+6)
        color(C.white);G.polygon('fill',x-7,y-4,x-2,y,x-7,y+4)
    elseif p.kind=='rocket' then
        G.polygon('fill',x,y-12,x+4,y-6,x-4,y-6)
        color(C.white);G.rectangle('fill',x-3,y-5,6,11)
        color(c);G.polygon('fill',x-3,y+1,x-9,y+9,x-3,y+7)
        G.polygon('fill',x+3,y+1,x+9,y+9,x+3,y+7)
        color(C.red);G.rectangle('fill',x-2,y+7,4,4)
    elseif p.kind=='mega' then
        G.polygon('line',x-6,y-11,x+6,y-11,x+12,y,x+6,y+11,x-6,y+11,x-12,y)
        G.circle('line',x,y,6,12);color(C.white);G.circle('fill',x,y,3,8)
    elseif p.kind=='bomb' then
        G.circle('line',x,y+1,9,16);G.circle('fill',x,y+1,5,12)
        G.line(x+2,y-7,x+5,y-11,x+8,y-10)
        color(C.white);G.rectangle('fill',x+7,y-12,3,3)
    else
        G.rectangle('line',x-11,y-11,22,22)
        G.polygon('fill',x-7,y+4,x,y-5,x+7,y+4,x+3,y+4,x,y,x-3,y+4)
        G.rectangle('fill',x-6,y+7,3,2);G.rectangle('fill',x-1,y+7,3,2);G.rectangle('fill',x+4,y+7,3,2)
    end
    local label=style.label
    local w=self.font.micro:getWidth(label)+6
    color(C.ink,0.9);G.rectangle('fill',x-w/2,y+15,w,11)
    text(self.font.micro,label,x-w/2+3,y+15,c)
end

function R:playerBullet(b,t)
    local kind=b.kind or 'pulse'
    G.push();G.translate(b.x,b.y);G.rotate(b.angle or math.atan2(b.vy or 0,b.vx or 1))
    if kind=='ion' then
        local length=b.length or 42
        color(C.violet,0.22);G.rectangle('fill',-length, -5,length+9,10)
        color(C.violet,0.85);G.rectangle('fill',-length+5,-2,length,4)
        color(C.white);G.rectangle('fill',-length+10,-1,length-1,2)
        color(C.violet,0.75);G.line(-length+3,-4,-length+3,4)
    elseif kind=='prism' then
        color(C.mint,0.24);G.polygon('fill',-23,-4,7,0,-23,4)
        color(C.mint);G.polygon('fill',-8,0,0,-3,8,0,0,3)
        color(C.white);G.rectangle('fill',-2,-1,5,2)
    elseif kind=='rocket' then
        color(C.amber,0.24);G.polygon('fill',-25,0,-7,-4,-7,4)
        color(C.red,0.85);G.polygon('fill',-14,0,-6,-2,-6,2)
        color(C.white);G.rectangle('fill',-6,-2,11,4)
        color(C.amber);G.polygon('fill',5,-2,9,0,5,2)
        G.polygon('fill',-5,-1,-9,-5,-2,-2);G.polygon('fill',-5,1,-9,5,-2,2)
    elseif kind=='mega' then
        local r=b.radius or 13
        color(C.pink,0.15);G.circle('fill',0,0,r+5,16)
        color(C.pink,0.24);G.polygon('fill',-58,-3,-9,-10,11,0,-9,10,-58,3)
        color(C.pink,0.8);G.polygon('fill',-20,0,-9,-8,10,-8,20,0,10,8,-9,8)
        color(C.white);G.polygon('fill',-10,0,-3,-4,10,0,-3,4)
        color(C.pink,0.9);G.circle('line',0,0,r+math.sin(t*30)*2,16)
    else
        G.setColor(0.16,0.6,1,0.45);G.rectangle('fill',-18,-2,21,4)
        G.setColor(0.59,0.98,1,1);G.rectangle('fill',-7,-1,12,2)
        G.setColor(1,1,1,1);G.rectangle('fill',3,-1,3,2)
    end
    G.pop()
end

function R:entities(sim,t,focus)
    for _,p in ipairs(sim.pickups) do self:pickup(p,t) end
    for _,e in ipairs(sim.enemies) do
        local scale=({scout=0.65,interceptor=0.7,turret=0.9,bomber=1.05,ace=0.9,boss=1.0})[e.type]
        self:engine(e.x+(e.type=='boss' and 75 or 25),e.y,t,scale,true,true)
        self:ship(e.type,e.x,e.y,e.bank,scale,1,e.flash>0 and {1,0.64,0.45} or {1,1,1})
        if e.hp<e.maxHp and e.type~='boss' then bar(e.x-13,e.y-23,26,2,e.hp/e.maxHp,C.amber) end
    end
    G.setBlendMode('add')
    for _,b in ipairs(sim.bullets) do
        if b.owner=='player' then
            self:playerBullet(b,t)
        else
            local c=b.kind=='plasma' and C.red or C.amber
            color(c,0.25);G.circle('fill',b.x,b.y,b.radius+3)
            color(c);G.circle('fill',b.x,b.y,b.radius)
            G.setColor(1,0.93,0.64,1);G.circle('fill',b.x,b.y,math.max(1,b.radius-2))
        end
    end
    G.setBlendMode('alpha')
    local p=sim.player
    if sim.status~='gameover' then
        local nitro=(p.nitro or 0)>0
        local overdrive=(p.overdrive or 0)>0
        local blink=p.invulnerable>0 and (math.floor(t*20)%2==0) and 0.45 or 1
        if p.dashTime>0 then
            for i=1,4 do self:ship('player',p.x-i*17,p.y,p.bank,0.75,(5-i)*0.10,C.cyan) end
        elseif nitro then
            for i=1,3 do self:ship('player',p.x-i*14,p.y,p.bank,0.78,(4-i)*0.06,C.amber) end
        end
        if nitro then
            G.setBlendMode('add')
            for i=1,5 do
                local x=p.x-43-((t*160+i*19)%87)
                local y=p.y+((i%2==0) and 1 or -1)*(13+i*3)
                color(C.amber,0.12+(1-(p.x-x)/140)*0.1);G.rectangle('fill',x,y,13+i*3,1)
            end
            G.setBlendMode('alpha')
        end
        self:engine(p.x-30,p.y+3,t,p.dashTime>0 and 2 or nitro and 2.6 or 1,false,nitro)
        self:ship('player',p.x,p.y,p.bank,0.78,blink,p.flash>0 and {1,0.45,0.45} or {1,1,1})
        if overdrive then
            G.setBlendMode('add')
            color(C.gold,0.15+math.sin(t*18)*0.04);G.circle('fill',p.x+25,p.y,9,12)
            color(C.gold,0.8);G.rectangle('fill',p.x+28,p.y-5,2,3);G.rectangle('fill',p.x+28,p.y+2,2,3)
            color(C.white,0.8);G.rectangle('fill',p.x+31,p.y-1,3,2)
            G.setBlendMode('alpha')
        end
        if (p.shield or 0)>0 then
            G.setBlendMode('add')
            color(C.blue,0.08);G.ellipse('fill',p.x,p.y,39,27,20)
            color(C.blue,0.26+math.sin(t*4)*0.06);G.ellipse('line',p.x,p.y,39,27,20)
            for i=1,p.shield do
                local a=-math.pi/2+(i-1)*0.42
                color(C.cyan,0.75);G.line(p.x+38*math.cos(a-0.12),p.y+27*math.sin(a-0.12),
                    p.x+38*math.cos(a+0.12),p.y+27*math.sin(a+0.12))
            end
            G.setBlendMode('alpha')
        end
        if focus then
            color(C.cyan,0.6);G.circle('line',p.x,p.y,9,16)
            color(C.white);G.circle('fill',p.x,p.y,2,8)
        end
    end
    for _,warning in ipairs(sim.telegraphs) do
        local a=0.35+math.sin(t*22)*0.25
        color(C.amber,a);G.polygon('fill',635,warning.y-5,629,warning.y,635,warning.y+5)
    end
    self.fx:draw()
end

function R:hud(ctx)
    local s,p=ctx.sim,ctx.sim.player
    G.setColor(0.018,0.028,0.043,0.92);G.rectangle('fill',0,0,640,29)
    G.rectangle('fill',0,335,640,25)
    color(C.dim,0.4);G.rectangle('fill',12,28,616,1);G.rectangle('fill',12,334,616,1)
    text(self.font.small,string.format('%08d',s.score),14,8,C.white)
    text(self.font.micro,'SCORE',110,9,C.dim)
    text(self.font.small,'x'..s.multiplier,155,8,C.amber)
    for i=1,p.maxHp do
        color(i<=p.hp and C.cyan or C.dim,i<=p.hp and 1 or 0.25)
        G.polygon('fill',228+(i-1)*13,10,236+(i-1)*13,10,234+(i-1)*13,18,226+(i-1)*13,18)
    end
    for i=1,3 do
        local x=326+(i-1)*10
        color((p.shield or 0)>=i and C.blue or C.dim,(p.shield or 0)>=i and 1 or 0.23)
        G.polygon('fill',x,9,x+7,9,x+6,15,x+3.5,19,x+1,15)
    end
    text(self.font.micro,string.format('SECTOR %02d  /  %s',s.sector,s.sectorName),363,10,C.dim)
    local primary=p.primary or 'pulse'
    text(self.font.micro,primary:upper()..' / '..p.weapon,14,338,primaryColor[primary] or C.cyan)
    local ammo=p.secondary and p.ammo and p.ammo[p.secondary] or 0
    local secondaryLabel=p.secondary and p.secondary:upper()..' '..ammo or 'SECONDARY --'
    text(self.font.micro,secondaryLabel,127,338,ammo>0 and (p.secondary=='mega' and C.pink or C.amber) or C.dim)
    text(self.font.micro,'DASH',255,338,C.dim);bar(286,342,46,3,1-p.dashCooldown/1.75,C.cyan)
    text(self.font.micro,'NOVA '..p.bombs,352,338,C.amber)
    text(self.font.micro,'ESC PAUSE',555,338,C.dim)
    local nitro,overdrive=p.nitro or 0,p.overdrive or 0
    text(self.font.micro,'NITRO',14,349,nitro>0 and C.red or C.dim)
    bar(47,353,66,3,nitro/8,C.red)
    if nitro>0 then text(self.font.micro,string.format('%.1fs',nitro),119,349,C.amber) end
    text(self.font.micro,'BOOST',178,349,overdrive>0 and C.gold or C.dim)
    bar(212,353,66,3,overdrive/10,C.gold)
    if overdrive>0 then text(self.font.micro,string.format('%.1fs',overdrive),284,349,C.gold) end
    local secondaryKey=ctx.input and ctx.input:label('secondary') or 'V'
    text(self.font.micro,secondaryKey..' / Y SECONDARY',352,349,ammo>0 and C.white or C.dim)
    if (p.shield or 0)>0 then text(self.font.micro,'SHIELD '..p.shield,555,349,C.blue) end
    if s.boss then
        local b=s.boss
        text(self.font.micro,b.name..'  /  PHASE '..b.phase,201,34,C.amber)
        bar(201,46,237,3,b.hp/b.maxHp,C.red)
    else
        bar(0,359,640,1,math.min(s.sectorTime/60,1),C.cyan)
    end
    if ctx.banner and ctx.banner.life>0 then
        local a=math.min(ctx.banner.life,1)
        color(C.ink,a*0.8);G.rectangle('fill',168,66,304,42)
        text(self.font.micro,'FLIGHT LOG  /  SECTOR '..s.sector,183,72,C.amber)
        text(self.font.body,ctx.banner.text,183,83,C.white)
    end
    if ctx.notice and ctx.notice.life>0 then
        local a=math.min(ctx.notice.life*2,1)
        local w=math.min(292,self.font.small:getWidth(ctx.notice.text)+24)
        color(C.ink,a*0.93);G.rectangle('fill',(640-w)/2,303,w,22)
        color(C.cyan,a*0.8);G.rectangle('fill',(640-w)/2,303,2,22)
        G.setFont(self.font.small);color(C.white,a);G.printf(ctx.notice.text,(640-w)/2+8,308,w-16,'center')
    end
    if ctx.debug then
        text(self.font.micro,string.format('%d FPS  |  %d HOSTILES  |  %d PROJECTILES',love.timer.getFPS(),#s.enemies,#s.bullets),13,32,C.dim)
    end
end

function R:menu(ctx)
    local t=ctx.t
    self:background(t*0.45,1,0.55)
    self:engine(465,182+math.sin(t)*6,t,2.3,false,false)
    self:ship('player',480,178+math.sin(t)*6,math.sin(t*0.7)*0.65,1.85,1,{1,1,1})
    color(C.ink,0.83);G.polygon('fill',0,0,350,0,299,360,0,360)
    color(C.cyan,0.6);G.line(350,0,299,360)
    text(self.font.micro,'COMMANDER WHISKERS  /  FLIGHT 01',31,32,C.amber)
    text(self.font.title,'STARFALL',27,43,C.white)
    text(self.font.small,'THREE SECTORS. ONE WAY THROUGH.',32,128,C.dim)
    color(C.cyan);G.rectangle('fill',32,153,27,2)
    if ctx.mode=='title' then
        for i,item in ipairs({'DEPLOY','FLIGHT CONTROLS','OPTIONS','QUIT'}) do
            local y=185+(i-1)*31
            if ctx.menu==i then
                color(C.cyan,0.12);G.polygon('fill',27,y-3,273,y-3,267,y+24,27,y+24)
                color(C.cyan);G.rectangle('fill',27,y-3,2,27)
                text(self.font.body,'> '..item,39,y,C.white)
            else text(self.font.body,item,39,y,C.dim) end
        end
        text(self.font.micro,'ENTER / A  DEPLOY       ARROWS  SELECT',32,331,C.dim)
        text(self.font.micro,'PULSE / ION / PRISM  /  HEAVY ARSENAL',383,297,C.dim)
        text(self.font.small,'CW-01  /  RIFT RUNNER',383,278,C.cyan)
        text(self.font.micro,'SHIELDS  /  NITRO  /  OVERDRIVE',383,311,C.dim)
    else
        -- Secondary pages use the entire width for readable control names.
        color(C.ink,0.94);G.rectangle('fill',22,169,594,171)
        if ctx.mode=='controls' then
            text(self.font.body,'FLIGHT CONTROLS',35,175,C.white)
            local labels={up='MOVE UP',down='MOVE DOWN',left='MOVE LEFT',right='MOVE RIGHT',
                fire='PRIMARY FIRE',secondary='SECONDARY',dash='DASH / DODGE',bomb='NOVA BOMB',focus='PRECISION'}
            for i,action in ipairs(ctx.input.actions) do
                local x=35+math.floor((i-1)/3)*196;local y=211+((i-1)%3)*25
                if ctx.menu==i then color(C.cyan,0.14);G.rectangle('fill',x-4,y-2,187,22) end
                text(self.font.micro,labels[action] or action:upper(),x,y+1,ctx.menu==i and C.white or C.dim)
                text(self.font.micro,ctx.binding==action and 'KEY...' or ctx.input:label(action),x+109,y+1,C.cyan)
            end
            text(self.font.micro,'PAD: D-PAD MOVE / A FIRE / X DASH / B NOVA / Y SECONDARY + PRECISION',35,298,C.amber)
            text(self.font.micro,'SHIFT PRECISION  /  HOLD SECONDARY TO FIRE EQUIPPED HEAVY WEAPON',35,312,C.dim)
            text(self.font.micro,'ENTER REMAP   R RESET   ESC BACK     DEFAULTS INCLUDE WASD / Z',35,324,C.dim)
        elseif ctx.mode=='options' then
            text(self.font.body,'OPTIONS',35,176,C.white)
            local names={'MUSIC','SOUND EFFECTS','SCREEN SHAKE','FULLSCREEN','BACK'}
            local values={math.floor(ctx.settings.music*100)..'%',math.floor(ctx.settings.sfx*100)..'%',
                ctx.settings.shake and 'ON' or 'OFF',ctx.settings.fullscreen and 'ON' or 'OFF',''}
            for i,name in ipairs(names) do
                local y=202+(i-1)*23
                if ctx.menu==i then color(C.cyan,0.14);G.rectangle('fill',31,y-2,340,22) end
                text(self.font.small,name,35,y,ctx.menu==i and C.white or C.dim)
                text(self.font.small,values[i],291,y,C.cyan)
            end
            text(self.font.micro,'LEFT / RIGHT ADJUST    ENTER TOGGLE    ESC BACK',35,325,C.dim)
        end
    end
end

function R:overlay(ctx)
    color(C.ink,0.82);G.rectangle('fill',0,29,640,306)
    local mode=ctx.mode
    local title=mode=='paused' and 'FLIGHT PAUSED' or mode=='victory' and 'RIFT CLEARED' or 'SHIP LOST'
    text(self.font.large,title,203,104,mode=='gameover' and C.red or C.cyan)
    if mode=='paused' then
        local rows={'RESUME FLIGHT','RESTART SORTIE','RETURN TO HANGAR'}
        for i,s in ipairs(rows) do text(self.font.body,(ctx.menu==i and '> ' or '  ')..s,205,163+(i-1)*29,ctx.menu==i and C.white or C.dim) end
        text(self.font.micro,'ESC RESUME',274,275,C.dim)
    else
        local s=ctx.sim
        text(self.font.body,string.format('SCORE  %08d',s.score),231,158,C.white)
        text(self.font.small,string.format('%d KILLS  /  %d GRAZES  /  %02d:%02d',s.kills,s.grazes,math.floor(s.time/60),math.floor(s.time%60)),211,191,C.dim)
        text(self.font.micro,mode=='victory' and 'COMMANDER WHISKERS MADE IT HOME.' or 'THE RIFT DOES NOT FORGIVE. TRY AGAIN.',207,216,C.amber)
        text(self.font.body,'ENTER / A   FLY AGAIN',220,257,C.white)
        text(self.font.micro,'ESC   RETURN TO HANGAR',236,287,C.dim)
    end
end

function R:draw(ctx)
    if ctx.mode=='title' or ctx.mode=='options' or ctx.mode=='controls' then self:menu(ctx);return end
    local speed=ctx.sim.player.dashTime>0 and 2.2 or (ctx.sim.player.nitro or 0)>0 and 1.8 or 1
    self:background(ctx.bgTime or ctx.sim.time,ctx.sim.sector,speed)
    G.push()
    if ctx.settings.shake and self.fx.shake>0 then
        G.translate(love.math.random(-100,100)/100*self.fx.shake,love.math.random(-100,100)/100*self.fx.shake)
    end
    self:entities(ctx.sim,ctx.t,ctx.focus)
    G.pop()
    if self.fx.flash>0 then
        G.setColor(0.55,0.9,1,self.fx.flash*0.9);G.rectangle('fill',0,29,640,306)
    end
    self:hud(ctx)
    if ctx.mode~='playing' then self:overlay(ctx) end
end

return R

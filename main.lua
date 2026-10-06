local Sim=require('game.sim')
local Input=require('game.input')
local FX=require('game.fx')
local Renderer=require('game.render')
local app={mode='title',menu=1,t=0,accumulator=0,settings={music=0.48,sfx=0.68,shake=true,fullscreen=false},
    stats={frames=0,elapsed=0,maxDt=0,slowFrames=0,updates=0,joystickEvents=0,keyEvents=0,dashes=0,bombs=0,shots=0,
        rocketShots=0,megaShots=0,shieldHits=0,pickups={}},test={}}
local STEP=1/60
local function saveSettings()
    local s=app.settings
    love.filesystem.write('settings.txt',string.format('music=%.2f\nsfx=%.2f\nshake=%s\nfullscreen=%s\n',s.music,s.sfx,tostring(s.shake),tostring(s.fullscreen)))
end
local function fullscreen(value)
    app.settings.fullscreen=value
    love.window.setFullscreen(value,'desktop')
    saveSettings()
end
local function deploy()
    app.sim=Sim.new(app.test.autoplay and 3 or os.time()%2147483647)
    app.mode='playing';app.menu=1;app.accumulator=0;app.bgTime=0
    app.notice=nil
    app.pendingDash=false;app.pendingBomb=false;app.pendingFire=false;app.pendingSecondary=false;app.input.previous={}
    app.fx.particles={};app.fx.rings={};app.fx.shake=0;app.fx.flash=0
    app.fx:musicMode('restart')
    app.banner={text=app.sim.sectorName,life=3}
    print('SORTIE started seed='..app.sim.seed)
end
local function title()
    app.mode='title';app.menu=1;app.fx:musicMode('play')
end
local function pause()
    if app.mode=='playing' then
        app.mode='paused';app.menu=1;app.fx:musicMode('pause')
        app.pendingDash=false;app.pendingBomb=false;app.pendingFire=false;app.pendingSecondary=false
    elseif app.mode=='paused' then
        app.input:read() -- Menu buttons held on resume must not become new dash/bomb edges.
        app.mode='playing';app.fx:musicMode('play')
    end
end
local function adjustOption(d)
    local i,s=app.menu,app.settings
    if i<=2 then local key=i==1 and 'music' or 'sfx';s[key]=math.max(0,math.min(1,s[key]+d*0.05))
    elseif i==3 then s.shake=not s.shake
    elseif i==4 then fullscreen(not s.fullscreen) end
    saveSettings();app.fx:sound('menu',0.4)
end
local function activate()
    app.fx:sound('menu',0.5)
    if app.mode=='title' then
        if app.menu==1 then deploy()
        elseif app.menu==2 then app.mode='controls';app.menu=1
        elseif app.menu==3 then app.mode='options';app.menu=1
        else love.event.quit() end
    elseif app.mode=='paused' then
        if app.menu==1 then pause() elseif app.menu==2 then deploy() else title() end
    elseif app.mode=='controls' then app.binding=app.input.actions[app.menu]
    elseif app.mode=='options' then
        if app.menu==5 then title() else adjustOption(1) end
    elseif app.mode=='victory' or app.mode=='gameover' then deploy() end
end
local function menuMove(d)
    local n=({title=4,paused=3,controls=#Input.actions,options=5})[app.mode]
    if n then app.menu=(app.menu-1+d)%n+1;app.fx:sound('menu',0.25) end
end
local function back()
    if app.binding then app.binding=nil
    elseif app.mode=='playing' or app.mode=='paused' then pause()
    elseif app.mode=='title' then love.event.quit()
    else title() end
end

function love.load(args)
    for _,v in ipairs(args or {}) do
        local key,value=v:match('^%-%-([%w%-]+)=(.+)$')
        if v=='--test-autoplay' then app.test.autoplay=true
        elseif v=='--fullscreen' then app.test.fullscreen=true
        elseif v=='--mute' then app.test.mute=true
        elseif key=='test-duration' then app.test.duration=assert(tonumber(value))
        elseif key=='test-speed' then app.test.speed=assert(tonumber(value))
        elseif key=='capture' then app.test.capture=value
        elseif key=='capture-at' then app.test.captureAt=assert(tonumber(value))
        elseif key=='report' then app.test.report=value end
    end
    if love.filesystem.getInfo('settings.txt') then
        for k,v in love.filesystem.read('settings.txt'):gmatch('([a-z]+)=([%w%.]+)') do
            if k=='music' or k=='sfx' then app.settings[k]=math.max(0,math.min(1,tonumber(v) or 0.5))
            elseif k=='shake' or k=='fullscreen' then app.settings[k]=v=='true' end
        end
    end
    if app.test.fullscreen then app.settings.fullscreen=true end
    if app.test.mute then app.settings.music=0;app.settings.sfx=0 end
    app.input=Input.new();app.fx=FX.new(app.settings);app.renderer=Renderer.new(app.fx)
    -- Native 720p art retains the extra ship detail; simulation/UI still use 640×360.
    app.canvas=love.graphics.newCanvas(1280,720,{format='rgba8',msaa=0});app.canvas:setFilter('nearest','nearest')
    if app.settings.fullscreen then love.window.setFullscreen(true,'desktop') end
    local name,version,vendor,device=love.graphics.getRendererInfo()
    print(string.format('STARFALL LÖVE=%s OS=%s GPU=%s %s %s %s',love.getVersion(),love.system.getOS(),name,version,vendor,device))
    app.stats.gpu=device;app.stats.renderer=name;app.stats.os=love.system.getOS()
    app.stats.joysticks=#love.joystick.getJoysticks()
    for _,j in ipairs(love.joystick.getJoysticks()) do
        print(string.format('INPUT name=%s gamepad=%s axes=%d buttons=%d hats=%d',j:getName(),tostring(j:isGamepad()),j:getAxisCount(),j:getButtonCount(),j:getHatCount()))
    end
    app.fx:musicMode('play')
    if app.test.autoplay then app.autopilot=require('game.autopilot');deploy() end
end

function love.update(dt)
    app.t=app.t+dt
    app.stats.frames=app.stats.frames+1;app.stats.elapsed=app.stats.elapsed+dt
    app.stats.maxDt=math.max(app.stats.maxDt,dt)
    if app.t>2 and dt>1/55 then app.stats.slowFrames=app.stats.slowFrames+1 end
    app.fx:update(math.min(dt,0.05))
    if app.mode=='playing' then
        app.accumulator=app.accumulator+math.min(dt,0.1)*(app.test.speed or 1)
        if not app.test.autoplay then
            app.liveInput=app.input:read()
            app.pendingDash=app.pendingDash or app.liveInput.dash
            app.pendingBomb=app.pendingBomb or app.liveInput.bomb
            app.focus=app.liveInput.focus
        end
        while app.accumulator>=STEP and app.mode=='playing' do
            local controls
            if app.test.autoplay then controls=app.autopilot(app.sim)
            else
                controls={x=app.liveInput.x,y=app.liveInput.y,fire=app.liveInput.fire or app.pendingFire,
                    secondary=app.liveInput.secondary or app.pendingSecondary,focus=app.liveInput.focus,
                    dash=app.pendingDash,bomb=app.pendingBomb}
                app.pendingDash=false;app.pendingBomb=false;app.pendingFire=false;app.pendingSecondary=false
            end
            app.sim:update(STEP,controls)
            app.bgTime=app.bgTime+STEP*app.sim.scrollSpeed/164
            app.stats.updates=app.stats.updates+1
            for _,e in ipairs(app.sim:drainEvents()) do
                if e.kind=='dash' then app.stats.dashes=app.stats.dashes+1
                elseif e.kind=='bomb' then app.stats.bombs=app.stats.bombs+1
                elseif e.kind=='shoot' and e.owner=='player' then app.stats.shots=app.stats.shots+1
                elseif e.kind=='secondary' then
                    local key=e.type=='rocket' and 'rocketShots' or 'megaShots'
                    app.stats[key]=app.stats[key]+1
                elseif e.kind=='shield_hit' then app.stats.shieldHits=app.stats.shieldHits+1
                elseif e.kind=='powerup' then app.stats.pickups[e.type]=(app.stats.pickups[e.type] or 0)+1 end
                if e.kind=='hit' and e.target=='enemy' then
                    app.fx:burst(e.x,e.y,3,'cyan',70)
                else app.fx:event(e) end
                if e.kind=='sector' then app.banner={text=e.name,life=3}
                elseif e.kind=='boss' and e.phase==1 then app.banner={text='WARNING / '..e.name,life=3}
                elseif e.kind=='powerup' then
                    local names={shield='SHIELD ONLINE',nitro='NITRO / 8 SECONDS',overdrive='OVERDRIVE / 10 SECONDS',
                        ion='ION LASER EQUIPPED',prism='PRISM LASER EQUIPPED',rocket='HOMING ROCKETS / Y OR V',
                        mega='MEGA BLASTER / Y OR V',weapon='WEAPON POWER UP',repair='HULL REPAIRED',bomb='NOVA RELOADED'}
                    app.notice={text=names[e.type] or e.type:upper(),life=2.3}
                end
            end
            if app.sim.status~='playing' then
                app.mode=app.sim.status
                print(string.format('SORTIE %s score=%d time=%.2f hp=%d kills=%d',app.mode,app.sim.score,app.sim.time,app.sim.player.hp,app.sim.kills))
            end
            app.accumulator=app.accumulator-STEP
        end
        if app.banner then app.banner.life=math.max(0,app.banner.life-dt) end
        if app.notice then app.notice.life=math.max(0,app.notice.life-dt) end
    end
    if app.test.duration and app.t>=app.test.duration then love.event.quit() end
end

function love.draw()
    love.graphics.setCanvas(app.canvas)
    love.graphics.push();love.graphics.scale(2,2)
    app.renderer:draw(app)
    love.graphics.pop()
    love.graphics.setCanvas()
    love.graphics.clear(0.008,0.012,0.025,1)
    local w,h=love.graphics.getDimensions()
    local available=math.min(w/640,h/360)
    local scale=available>=1 and math.floor(available) or available
    app.viewport={x=math.floor((w-640*scale)/2),y=math.floor((h-360*scale)/2),scale=scale}
    love.graphics.setColor(1,1,1,1)
    love.graphics.setBlendMode('alpha','premultiplied')
    love.graphics.draw(app.canvas,app.viewport.x,app.viewport.y,0,scale/2,scale/2)
    love.graphics.setBlendMode('alpha','alphamultiply')
    if app.test.capture and not app.test.captured and app.t>=(app.test.captureAt or 3) then
        app.test.captured=true
        love.graphics.captureScreenshot(function(data)
            local file=assert(io.open(app.test.capture,'wb'))
            file:write(data:encode('png'):getString());file:close()
            print('CAPTURE '..app.test.capture)
        end)
    end
end

function love.keypressed(key,scancode,isrepeat)
    app.stats.keyEvents=app.stats.keyEvents+1
    if app.mode=='playing' and not isrepeat then
        if app.input:matches('dash',key) then app.pendingDash=true end
        if app.input:matches('bomb',key) then app.pendingBomb=true end
        if app.input:matches('fire',key) then app.pendingFire=true end
        if app.input:matches('secondary',key) then app.pendingSecondary=true end
    end
    if app.binding then
        if key=='escape' then app.binding=nil;return end
        for action,bound in pairs(app.input.bindings) do
            if bound==key then app.input.bindings[action]=app.input.bindings[app.binding] end
        end
        app.input.bindings[app.binding]=key;app.binding=nil;app.input:save();return
    end
    if key=='escape' then back()
    elseif key=='f11' or (key=='return' and love.keyboard.isDown('lalt','ralt')) then fullscreen(not app.settings.fullscreen)
    elseif key=='f3' then app.debug=not app.debug
    elseif app.mode~='playing' then
        if key=='up' or key=='w' then menuMove(-1)
        elseif key=='down' or key=='s' then menuMove(1)
        elseif key=='return' or key=='space' then activate()
        elseif app.mode=='options' and (key=='left' or key=='right') then adjustOption(key=='left' and -1 or 1)
        elseif app.mode=='controls' and key=='r' then
            for k,v in pairs(Input.defaults) do app.input.bindings[k]=v end;app.input:save()
        end
    end
end

function love.joystickpressed(j,button)
    app.stats.joystickEvents=app.stats.joystickEvents+1
    if not j:isGamepad() then
        if app.mode=='playing' then
            if button==1 then app.pendingDash=true elseif button==2 then app.pendingFire=true
            elseif button==3 then app.pendingBomb=true elseif button==4 then app.pendingSecondary=true end
        else if button==2 then activate() elseif button==3 then back() end end
    end
end
function love.joystickhat(j,hat,direction)
    app.stats.joystickEvents=app.stats.joystickEvents+1
    if not j:isGamepad() and app.mode~='playing' then
        if app.mode=='options' and direction:find('l') then adjustOption(-1)
        elseif app.mode=='options' and direction:find('r') then adjustOption(1)
        elseif direction:find('u') then menuMove(-1) elseif direction:find('d') then menuMove(1) end
    end
end
function love.gamepadpressed(j,button)
    app.stats.joystickEvents=app.stats.joystickEvents+1
    if button=='start' then pause()
    elseif app.mode=='playing' then
        if button=='a' then app.pendingFire=true elseif button=='x' then app.pendingDash=true
        elseif button=='b' then app.pendingBomb=true
        elseif button=='y' or button=='rightshoulder' then app.pendingSecondary=true end
    elseif app.mode~='playing' then
        if button=='a' then activate() elseif button=='b' then back()
        elseif app.mode=='options' and button=='dpleft' then adjustOption(-1)
        elseif app.mode=='options' and button=='dpright' then adjustOption(1)
        elseif button=='dpup' then menuMove(-1) elseif button=='dpdown' then menuMove(1) end
    end
end
function love.focus(focused)
    if not focused and app.mode=='playing' and not app.test.autoplay then pause() end
end
function love.mousemoved(x,y)
    if not app.viewport or app.mode~='title' then return end
    x=(x-app.viewport.x)/app.viewport.scale;y=(y-app.viewport.y)/app.viewport.scale
    if x>27 and x<270 and y>182 and y<306 then app.menu=math.min(4,math.floor((y-182)/31)+1) end
end
function love.mousepressed(x,y,button)
    if button==1 and app.viewport and app.mode=='title' then
        x=(x-app.viewport.x)/app.viewport.scale;y=(y-app.viewport.y)/app.viewport.scale
        if x>27 and x<270 and y>182 and y<306 then activate() end
    end
end

function love.quit()
    if app.fx then app.fx:musicMode('stop') end
    if app.test.report then
        local s=app.stats
        local payload={os=s.os,gpu=s.gpu,renderer=s.renderer,frames=s.frames,seconds=s.elapsed,
            average_fps=s.frames/math.max(0.001,s.elapsed),max_frame_ms=s.maxDt*1000,slow_frames=s.slowFrames,
            simulation_updates=s.updates,sounds_played=app.fx and app.fx.soundsPlayed or 0,
            joystick_count=s.joysticks,joystick_events=s.joystickEvents,key_events=s.keyEvents,
            state=app.mode,score=app.sim and app.sim.score or 0,kills=app.sim and app.sim.kills or 0,
            simulated_seconds=app.sim and app.sim.time or 0,hp=app.sim and app.sim.player.hp or 0,
            music_seconds=app.fx and app.fx.music:getDuration() or 0,autoplay=app.test.autoplay or false,
            dashes=s.dashes,bombs_used=s.bombs,player_shots=s.shots,
            rocket_shots=s.rocketShots,mega_shots=s.megaShots,shield_hits=s.shieldHits,
            primary=app.sim and app.sim.player.primary or 'none',
            secondary=app.sim and app.sim.player.secondary or 'none'}
        for _,kind in ipairs({'shield','nitro','overdrive','ion','prism','rocket','mega','weapon','repair','bomb'}) do
            payload[kind..'_pickups']=s.pickups[kind] or 0
        end
        local keys={};for k in pairs(payload) do keys[#keys+1]=k end;table.sort(keys)
        local out={}
        for _,k in ipairs(keys) do
            local v=payload[k]
            if type(v)=='string' then v=string.format('%q',v):gsub('\\\n','\\n') else v=tostring(v) end
            out[#out+1]=string.format('  %q: %s',k,v)
        end
        local file=assert(io.open(app.test.report,'w'));file:write('{\n'..table.concat(out,',\n')..'\n}\n');file:close()
        print('REPORT '..app.test.report)
    end
end

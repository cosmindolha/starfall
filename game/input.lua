local Input = {}
Input.__index = Input
Input.defaults = {up='up',down='down',left='left',right='right',fire='space',secondary='v',dash='x',bomb='c',focus='lshift'}
Input.actions = {'up','down','left','right','fire','secondary','dash','bomb','focus'}
local alternates = {up='w',down='s',left='a',right='d',fire='z',focus='rshift'}

function Input.new()
    local self=setmetatable({bindings={},edges={},previous={}},Input)
    local savedSecondary=false
    for k,v in pairs(Input.defaults) do self.bindings[k]=v end
    if love.filesystem.getInfo('bindings.txt') then
        for k,v in love.filesystem.read('bindings.txt'):gmatch('([a-z]+)=([^\r\n]+)') do
            if Input.defaults[k] then
                self.bindings[k]=v
                if k=='secondary' then savedSecondary=true end
            end
        end
    end
    -- Older installs may already use V for another action. Preserve that binding.
    if not savedSecondary then
        for _,candidate in ipairs({'v','f','g','b','j','k','l','n','m'}) do
            local available=true
            for action,key in pairs(self.bindings) do
                if action~='secondary' and key==candidate then available=false;break end
            end
            if available then self.bindings.secondary=candidate;break end
        end
    end
    return self
end

function Input:save()
    local lines={}
    for _,k in ipairs(Input.actions) do lines[#lines+1]=k..'='..self.bindings[k] end
    love.filesystem.write('bindings.txt',table.concat(lines,'\n'))
end

function Input:alternate(action)
    local key=alternates[action]
    if not key or self.bindings[action]~=Input.defaults[action] then return nil end
    for other,bound in pairs(self.bindings) do
        if other~=action and bound==key then return nil end
    end
    return key
end

function Input:matches(action,key)
    return self.bindings[action]==key or self:alternate(action)==key
end

function Input:down(action)
    local alt=self:alternate(action)
    return love.keyboard.isDown(self.bindings[action]) or (alt and love.keyboard.isDown(alt) or false)
end

function Input:read()
    local x=(self:down('right') and 1 or 0)-(self:down('left') and 1 or 0)
    local y=(self:down('down') and 1 or 0)-(self:down('up') and 1 or 0)
    local fire,focus,dash,bomb=self:down('fire'),self:down('focus'),self:down('dash'),self:down('bomb')
    local secondary=self:down('secondary')
    for _,j in ipairs(love.joystick.getJoysticks()) do
        if j:isGamepad() then
            local ax,ay=j:getGamepadAxis('leftx'),j:getGamepadAxis('lefty')
            if math.abs(ax)>0.18 then x=ax end
            if math.abs(ay)>0.18 then y=ay end
            if j:isGamepadDown('dpleft') then x=-1 elseif j:isGamepadDown('dpright') then x=1 end
            if j:isGamepadDown('dpup') then y=-1 elseif j:isGamepadDown('dpdown') then y=1 end
            fire=fire or j:isGamepadDown('a');dash=dash or j:isGamepadDown('x')
            bomb=bomb or j:isGamepadDown('b');focus=focus or j:isGamepadDown('leftshoulder') or j:isGamepadDown('y')
            secondary=secondary or j:isGamepadDown('y') or j:isGamepadDown('rightshoulder')
        else
            local axes=j:getAxisCount()
            if axes>=2 then
                local ax,ay=j:getAxis(1),j:getAxis(2)
                if math.abs(ax)>0.18 then x=ax end
                if math.abs(ay)>0.18 then y=ay end
            end
            for h=1,j:getHatCount() do
                local hat=j:getHat(h)
                if hat:find('l') then x=-1 elseif hat:find('r') then x=1 end
                if hat:find('u') then y=-1 elseif hat:find('d') then y=1 end
            end
            -- ClockworkPI firmware: button 1=X, 2=A, 3=B, 4=Y.
            fire=fire or j:isDown(2);dash=dash or j:isDown(1)
            bomb=bomb or j:isDown(3);focus=focus or j:isDown(4)
            secondary=secondary or j:isDown(4)
        end
    end
    local dx,db=dash and not self.previous.dash,bomb and not self.previous.bomb
    self.previous.dash=dash;self.previous.bomb=bomb
    return {x=x,y=y,fire=fire,secondary=secondary,focus=focus,dash=dx,bomb=db}
end

function Input:label(action)
    local name=self.bindings[action]:upper():gsub('LSHIFT','SHIFT'):gsub('RSHIFT','SHIFT')
    return name
end

return Input

function love.conf(t)
    t.identity = 'starfall-commander-whiskers'
    t.version = '11.5'
    t.console = true
    t.window.title = 'STARFALL — Commander Whiskers'
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = true
    t.window.minwidth = 640
    t.window.minheight = 360
    t.window.vsync = 1
    t.window.msaa = 0
    t.window.highdpi = false
    t.modules.physics = false
    t.modules.video = false
end

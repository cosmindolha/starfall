-- Real high-resolution Blender bank renders, pixelated by local Pixelization_512 Core ML.
-- scale=0.5 preserves gameplay size; a 2x canvas displays actual source pixels.
return {image='assets/images/ships.png', frames={
  player={
    {x=0, y=0, w=256, h=192, ox=128, oy=96, bank=-28, scale=0.5},
    {x=256, y=0, w=256, h=192, ox=128, oy=96, bank=-14, scale=0.5},
    {x=512, y=0, w=256, h=192, ox=128, oy=96, bank=0, scale=0.5},
    {x=768, y=0, w=256, h=192, ox=128, oy=96, bank=14, scale=0.5},
    {x=1024, y=0, w=256, h=192, ox=128, oy=96, bank=28, scale=0.5},
  },
  scout={
    {x=1280, y=0, w=256, h=192, ox=128, oy=96, bank=-20, scale=0.5},
    {x=1536, y=0, w=256, h=192, ox=128, oy=96, bank=0, scale=0.5},
    {x=1792, y=0, w=256, h=192, ox=128, oy=96, bank=20, scale=0.5},
  },
  interceptor={
    {x=0, y=192, w=256, h=192, ox=128, oy=96, bank=-20, scale=0.5},
    {x=256, y=192, w=256, h=192, ox=128, oy=96, bank=0, scale=0.5},
    {x=512, y=192, w=256, h=192, ox=128, oy=96, bank=20, scale=0.5},
  },
  turret={
    {x=768, y=192, w=256, h=192, ox=128, oy=96, bank=-16, scale=0.5},
    {x=1024, y=192, w=256, h=192, ox=128, oy=96, bank=0, scale=0.5},
    {x=1280, y=192, w=256, h=192, ox=128, oy=96, bank=16, scale=0.5},
  },
  bomber={
    {x=1536, y=192, w=256, h=192, ox=128, oy=96, bank=-16, scale=0.5},
    {x=1792, y=192, w=256, h=192, ox=128, oy=96, bank=0, scale=0.5},
    {x=0, y=384, w=256, h=192, ox=128, oy=96, bank=16, scale=0.5},
  },
  ace={
    {x=256, y=384, w=256, h=192, ox=128, oy=96, bank=-22, scale=0.5},
    {x=512, y=384, w=256, h=192, ox=128, oy=96, bank=0, scale=0.5},
    {x=768, y=384, w=256, h=192, ox=128, oy=96, bank=22, scale=0.5},
  },
  boss={
    {x=0, y=576, w=512, h=384, ox=256, oy=192, bank=-10, scale=0.5},
    {x=512, y=576, w=512, h=384, ox=256, oy=192, bank=0, scale=0.5},
    {x=1024, y=576, w=512, h=384, ox=256, oy=192, bank=10, scale=0.5},
  },
}}

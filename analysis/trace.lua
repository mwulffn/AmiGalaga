-- Logs visible sprite (tile:colour) and char (tile:colour) sets per frame.
local mode = os.getenv("GMODE") or "attract"
local out = io.open(os.getenv("GOUT") or "trace.txt", "a")
local snap_every = tonumber(os.getenv("GSNAP") or "0")
local dielast = tonumber(os.getenv("GDIE") or "0")
local total = tonumber(os.getenv("GFRAMES") or "6000")
local poke = os.getenv("GPOKE") == "1"
local m = manager.machine
local mem = m.devices[":maincpu"].spaces["program"]
local fields = {}
for _, port in pairs(m.ioport.ports) do
  for name, f in pairs(port.fields) do fields[name] = f end
end
if os.getenv("GLIST") then for n, _ in pairs(fields) do print(n) end end

-- visible tilemap offsets (36x28 view of the 32x32 RAM)
local vis = {}
for row = 0, 27 do
  for col = 0, 35 do
    local r, c = row + 2, col - 2
    local offs
    if (c & 0x20) ~= 0 then offs = r + ((c & 0x1f) << 5) else offs = c + (r << 5) end
    vis[#vis + 1] = offs
  end
end

local function set(name, v) local f = fields[name]; if f then f:set_value(v) end end
local frame, last = 0, ""
local stuck_stage, stuck_since = -1, 0
local rack = fields["Rack Test"]

local function tick()
  frame = frame + 1
  local stage = mem:read_u8(0x9821)
  if mode == "play" then
    set("Coin 1", (frame >= 1200 and frame < 1210) and 1 or 0)
    set("1 Player Start", (frame >= 1400 and frame < 1410) and 1 or 0)
    if frame > 1600 then
      local ph = (frame // 70) % 4
      set("P1 Left", (ph == 0 or ph == 3) and 1 or 0)
      set("P1 Right", (ph == 1 or ph == 2) and 1 or 0)
      set("P1 Button 1", (frame % 6 < 3) and 1 or 0)
      if poke and frame < total - dielast then mem:write_u8(0x9820, 3) end
      if rack and poke then
        if stage ~= stuck_stage then stuck_stage = stage; stuck_since = frame end
        local want = (frame - stuck_since > 5400) and 0x00 or 0x20
        if rack.user_value ~= want then rack.user_value = want end
      end
    end
  end
  local s = {}
  local seen = {}
  for offs = 0, 0x7e, 2 do
    local code = mem:read_u8(0x8b80 + offs) & 0x7f
    local color = mem:read_u8(0x8b81 + offs) & 0x3f
    local y = mem:read_u8(0x9380 + offs)
    local x = mem:read_u8(0x9381 + offs)
    local c0 = mem:read_u8(0x9b80 + offs)
    local c1 = mem:read_u8(0x9b81 + offs)
    local sizex, sizey = (c0 >> 2) & 1, (c0 >> 3) & 1
    local sx = x - 40 + 0x100 * (c1 & 3)
    local sy = ((256 - y + 1 - 16 * sizey) & 0xff) - 32
    if sx > -16 * (sizex + 1) and sx < 288 and sy > -16 * (sizey + 1) and sy < 224 then
      for k = 0, sizex + 2 * sizey + (sizex & sizey) * 0 do end
      for dy = 0, sizey do for dx = 0, sizex do
        local key = string.format("%02x:%02x", (code + dx + 2 * dy) & 0x7f, color)
        if not seen[key] then seen[key] = true; s[#s + 1] = key end
      end end
    end
  end
  table.sort(s)
  local c, cseen = {}, {}
  for i = 1, #vis do
    local o = vis[i]
    local key = (mem:read_u8(0x8000 + o) & 0x7f) * 64 + (mem:read_u8(0x8400 + o) & 0x3f)
    if not cseen[key] then cseen[key] = true; c[#c + 1] = string.format("%02x:%02x", key // 64, key % 64) end
  end
  table.sort(c)
  local line = stage .. "\t" .. mem:read_u8(0x9820) .. "\t" .. table.concat(s, ",") .. "\t" .. table.concat(c, ",")
  if line ~= last then out:write(frame .. "\t" .. line .. "\n"); last = line end
  if snap_every > 0 and frame % snap_every == 0 then m.video:snapshot() end
  if frame >= total then out:close(); m:exit() end
end
_G.__sub = emu.add_machine_frame_notifier(tick)

-- A simulated guild for sync tests: each member runs their own copy of
-- Core/Records.lua and Core/Sync.lua, against one clock, one roster and one
-- "game" that delivers addon messages (with a short delay) the way WoW does:
-- guild and officer messages to everyone online in them (and back to the
-- sender), whispers to one player. A member can have a guild channel that
-- delivers nothing ("broken"), as seen on WoW: Forever.
--
-- Compression is a stand-in (the test can't run the game's Deflate): it
-- shrinks text to COMPRESS_RATIO of its size and remembers the original.
--
--   local Sim = dofile(ROOT .. "/tests/sim.lua")(ROOT)
--   local g = Sim.Guild({ { "Gm Boss", 0, "Guild Master" }, { "Ann", 3, "Member" }, ... })
--   local ann = g:Client("Ann")         -- their copy (offline until Login)
--   g:Login("Ann"); g:Run(60)           -- log in, let a minute pass
--   g.stats.bytes, g.stats.byKind.R ... -- what went over the wire
return function(ROOT)
  local Sim = { COMPRESS_RATIO = 0.35, LATENCY = 0.2, NOW = 1800000000 }

  wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
  IsInGuild = function() return true end

  local clock = 0
  GetTime = function() return clock end

  -- timers: run in time order, as the copy that scheduled them
  local timers, seq, current = {}, 0, nil
  C_Timer = { After = function(delay, fn)
    seq = seq + 1
    timers[#timers + 1] = { at = clock + (delay or 0), seq = seq, fn = fn, owner = current }
  end }
  local function NextTimer()
    local best, bi
    for i, t in ipairs(timers) do
      if not best or t.at < best.at or (t.at == best.at and t.seq < best.seq) then best, bi = t, i end
    end
    return best, bi
  end

  local packed = {}
  C_EncodingUtil = {
    CompressString = function(s)
      packed[#packed + 1] = s
      local tag = "#" .. #packed .. "#"
      return tag .. string.rep("x", math.max(0, math.ceil(#s * Sim.COMPRESS_RATIO) - #tag))
    end,
    DecompressString = function(s)
      local v = packed[tonumber(s:match("^#(%d+)#") or -1)]
      if not v then error("bad data") end
      return v
    end,
    EncodeBase64 = function(s) return s .. string.rep("=", math.floor(#s / 3)) end, -- 4/3 the size
    DecodeBase64 = function(s) return (s:gsub("=+$", "")) end,
  }

  local function CompareVersions(a, b)
    local function parts(v) local t = {} for d in tostring(v):gmatch("%d+") do t[#t + 1] = tonumber(d) end return t end
    local x, y = parts(a), parts(b)
    for i = 1, math.max(#x, #y) do
      local p, q = x[i] or 0, y[i] or 0
      if p ~= q then return p < q and -1 or 1 end
    end
    return 0
  end

  function Sim.Guild(memberList)
    local g = { clients = {}, byName = {}, members = {}, online = {}, inflight = {} }
    g.stats = { bytes = 0, messages = 0, byKind = {}, bySender = {} }
    local rankNames = {}
    for _, m in ipairs(memberList) do
      local e = { full = m[1], rankIndex = m[2], rank = m[3], online = false, hasAddon = false, isSelf = false }
      g.members[#g.members + 1] = e
      g.byName[m[1]] = e
      rankNames[m[2]] = m[3]
    end
    g.ranks = {}
    for i = 0, 20 do if rankNames[i] then g.ranks[#g.ranks + 1] = { index = i, name = rankNames[i] } end end

    function g:Now() return Sim.NOW + clock end
    function g:Clock() return clock end

    -- A member's copy of the addon (with its own saved data).
    function g:Client(name, opts)
      opts = opts or {}
      local me = self.byName[name]
      local ns = { version = opts.version or "2.12.0", handlers = {}, events = {} }
      local saved = { members = {}, sync = { guild = {}, officer = {} } }
      function ns:Fire(ev, ...) for _, fn in ipairs(ns.events[ev] or {}) do fn(...) end end
      function ns:On(ev, fn) ns.events[ev] = ns.events[ev] or {} table.insert(ns.events[ev], fn) end
      function ns:RegisterEvent(ev, fn) ns.handlers[ev] = ns.handlers[ev] or {} table.insert(ns.handlers[ev], fn) end
      function ns:Print(msg) table.insert(g.printed, name .. ": " .. msg) end
      function ns.Debounce(_, _, fn) fn() end
      function ns.Split(s, sep) local t = {} for p in (s .. sep):gmatch("(.-)" .. sep) do t[#t + 1] = p end return t end
      function ns.IsOfficer() return me.rankIndex <= (g.officerRank or 1) end
      function ns.PlayerFullName() return name end
      function ns.NormalizeName(n) return n end
      function ns.ShortName(n) return n end
      function ns.ChatName(n) return n end
      ns.CompareVersions = CompareVersions
      ns.DB = { PERM_BY_TYPE = { M = "links", MS = "profiles", RL = "profiles", MP = "profiles", CN = "profiles" } }
      function ns.DB:Guild() return saved end
      function ns.DB:GuildKey() return "Guild" end
      function ns.DB:Now() return g:Now() end
      function ns.DB:Settings() return { auditDays = 30 } end
      function ns.DB:EnsureMember(f) saved.members[f] = saved.members[f] or {} return saved.members[f] end
      function ns.DB:GetMember(f) return saved.members[f] end
      function ns.DB:PermRanks() return nil end
      function ns.DB:PermDef(k) return k == "ownprofile" and { everyone = true } or {} end
      function ns.DB:IsGuildMaster() return me.rankIndex == 0 end
      function ns.DB:HasPerm(k) return k == "ownprofile" or me.rankIndex <= 1 end
      function ns.DB:GuildRanks() return g.ranks end
      function ns.DB:MyRankIndex() return me.rankIndex end
      ns.Roster = { byName = g.byName, members = g.members, selfRow = name }
      ns.Recruit = { MayRecruit = function() return opts.recruits or me.rankIndex <= 1 end }
      assert(loadfile(ROOT .. "/Core/Records.lua"))("NGM", ns)
      assert(loadfile(ROOT .. "/Core/Sync.lua"))("NGM", ns)
      local c = { name = name, ns = ns, S = ns.Sync, saved = saved, store = saved.sync.guild, officer = saved.sync.officer,
                  entry = me, broken = opts.broken }
      ns.Sync.BYTES_PER_SEC = opts.bytesPerSec or ns.Sync.BYTES_PER_SEC
      self.clients[#self.clients + 1] = c
      self.clients[name] = c
      return c
    end

    -- Logs a member in: their copy starts (prefix, events, version, checks).
    function g:Login(name)
      local c = self.clients[name]
      c.entry.online, c.entry.hasAddon = true, true
      local prev = current
      current = c
      c.S.readyFor = nil
      c.ns.handlers = {}
      c.ns.events = {}
      c.S:Init()
      for _, fn in ipairs(c.ns.handlers.GUILD_ROSTER_UPDATE or {}) do fn() end
      current = prev
    end

    function g:Logout(name)
      local c = self.clients[name]
      c.entry.online = false
      -- what's in flight from them still arrives; their timers stop
      for i = #timers, 1, -1 do if timers[i].owner == c then table.remove(timers, i) end end
      for k in pairs(c.S.queues) do c.S.queues[k] = {} end
      for k in pairs(c.S.waiting) do c.S.waiting[k] = nil end
      c.S.pumping = false
    end

    -- The game: addon messages from `current`.
    C_ChatInfo = {
      RegisterAddonMessagePrefix = function() return true end,
      SendAddonMessage = function(prefix, msg, channel, target)
        local from = current
        if not from or not from.entry.online then return 9 end
        local kind = msg:match("^%w+\t(%u)") or "?"
        if kind == "C" then kind = "C" end
        g.stats.bytes = g.stats.bytes + #msg + #prefix
        g.stats.messages = g.stats.messages + 1
        g.stats.byKind[kind] = (g.stats.byKind[kind] or 0) + 1
        g.stats.bySender[from.name] = (g.stats.bySender[from.name] or 0) + #msg + #prefix
        g.stats.byChannel = g.stats.byChannel or {}
        g.stats.byChannel[channel] = (g.stats.byChannel[channel] or 0) + 1
        table.insert(g.inflight, { at = clock + Sim.LATENCY, from = from, msg = msg, channel = channel, target = target })
        return 0
      end,
    }

    local function Deliver(o)
      local list = {}
      if o.channel == "GUILD" or o.channel == "OFFICER" then
        if o.from.broken then return end -- accepted, delivered to nobody (not even back)
        for _, c in ipairs(g.clients) do
          if c.entry.online and (o.channel == "GUILD" or c.ns.IsOfficer()) then list[#list + 1] = c end
        end
      elseif o.channel == "WHISPER" then
        local c = g.clients[o.target]
        if c and c.entry.online then list[1] = c end
      else
        for _, c in ipairs(g.clients) do if c.entry.online and c ~= o.from then list[#list + 1] = c end end
      end
      for _, c in ipairs(list) do
        current = c
        for _, fn in ipairs(c.ns.handlers.CHAT_MSG_ADDON or {}) do fn(nil, "NootropicGM", o.msg, o.channel, o.from.name) end
      end
      current = nil
    end

    -- Advances the clock `seconds`, running timers and deliveries in order.
    function g:Run(seconds)
      local stop = clock + seconds
      while true do
        local t, ti = NextTimer()
        local d, di
        for i, o in ipairs(self.inflight) do if not d or o.at < d.at then d, di = o, i end end
        local nextAt = math.min(t and t.at or math.huge, d and d.at or math.huge)
        if nextAt > stop then break end
        clock = math.max(clock, nextAt)
        if d and d.at <= (t and t.at or math.huge) then
          table.remove(self.inflight, di)
          Deliver(d)
        else
          table.remove(timers, ti)
          if not t.owner or t.owner.entry.online then
            current = t.owner
            t.fn()
            current = nil
          end
        end
      end
      clock = stop
    end

    -- Runs until nothing is queued, in flight or scheduled (or `max` seconds).
    function g:Settle(max)
      local start = clock
      max = max or 3600
      while clock - start < max do
        local busy = #self.inflight > 0
        for _, c in ipairs(self.clients) do if c.entry.online and c.S:QueueSize() > 0 then busy = true end end
        local t = NextTimer()
        if not busy and not t then break end
        self:Run(1)
      end
      return clock - start
    end

    function g:ResetStats() self.stats = { bytes = 0, messages = 0, byKind = {}, bySender = {} } end
    function g:As(c, fn) local prev = current current = c local r = { fn() } current = prev return unpack(r) end
    g.printed = {}
    return g
  end

  return Sim
end

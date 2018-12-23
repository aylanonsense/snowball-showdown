pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

--[[
render layers:
   1: snowfall (background)
   4: scarf
   5: player
   6: snowball
   7: snow_poof (snowballs)
   9: snowfall (foreground)
  10: game_blinders
  11: score
  12: snowball_pane
  13: speed_indicator
  ...
  18: snow_poof (pane)
  19: start
  20: title_blinders
  21: title
  21: ready_up
]]

-- useful no-op function
function noop() end

-- returns the second argument if condition is truthy, otherwise returns the third argument
function ternary(condition, if_true, if_false)
  return condition and if_true or if_false
end

-- constants
local controllers = { 1, 0 }
local bg_color = 0
local player_animations = {
  get_up = { { 7, 20 }, 1 },
  pause = { { -1, 10 } },
  bow = { { -1, 25 }, { 2, 10 }, { 3, 30 }, { 2, 10 }, { 1, 25 } },
  drop = { { -1, 8 }, { 4, 8 }, { 5, 3 } },
  pack_snow = { { 5, 10 }, { 6, 10 } },
  show_snowball = { { 7, 9 }, 15 },
  celebrate = { 17 },
  stop_celebrating = { { 18, 5 }, 1},
  aim = { { 8, 12 }, 9 },
  throw = { 14 },
  dodge = { { 11, 17 } },
  block = { 12 },
  stop_blocking = { { -1, 15 }, { 13, 20 }, { 1, 10 } }
}
local neck_points = {
  { 7, 6 },
  { 8, 7 },
  { 11, 9 },
  { 8, 10 },
  { 8, 12 },
  { 8, 12 },
  { 9, 9 },
  { 8, 6 },
  { 7, 6 },
  { 8, 6 },
  { 8, 5 },
  { 8, 7 },
  { 8, 6 },
  { 10, 6 },
  { 8, 6 },
  { 10, 6 },
  { 8, 6 },
  { 8, 6 }
}

-- debug vars
local skip_to_start = false
local skip_to_throw = false
local starting_points = { 0, 0 }

-- scene vars
local scene
local scene_frames

-- effect vars
local game_frames
local freeze_frames
local screen_shake_frames

-- input vars
local buttons
local button_presses

-- wind vars
local wind_is_active
local wind_active_frames
local wind_switch_frames
local wind_pressure
local wind_updraft
local wind_target_pressure

-- entity vars
local entities
local players
local title
local start
local speed_indicator
local title_blinders
local entity_classes = {
  player = {
    sprite = 1,
    animation_queue = nil,
    animation_frames = -1,
    on_animation_done = nil,
    showoff_frames_left = 0,
    is_ready_to_throw = false,
    has_taken_action = false,
    has_dodged = false,
    has_been_hit = false,
    init = function(self)
      self.animation_queue = {}
      self.pane = spawn_entity("snowball_pane", ternary(self.is_first_player, 31, 95), 150, {
        player = self,
        is_visible = false
      })
      self.score = spawn_entity("score", ternary(self.is_first_player, 31, 95), 20, {
        player = self,
        is_visible = false,
        points = starting_points and starting_points[self.player_num] or 0
      })
      self.ready = spawn_entity("ready_up", ternary(self.is_first_player, 21, 107), 83, {
        player = self,
        is_visible = true
      })
      self.scarf = spawn_entity("scarf", self.x, self.y, {
        player = self
      })
    end,
    update = function(self)
      decrement_counter_prop(self, "showoff_frames_left")
      -- apply animation
      self:apply_animation()
      local has_pressed_button = any_button_pressed(self.player_num, true)
      if self.ready.is_npc then
        if has_pressed_button then
          self.ready.is_npc = false
          sfx(4, self.channel)
        else
          local difficulty -- scale of 0.0 to 1.0
          local point_diff = self.opponent.score.points - self.score.points
          local most_points = max(self.opponent.score.points, self.score.points)
          local difficulty = mid(0.0, most_points * 0.3 + point_diff * 0.3, 1.0)
          if not self.pane.is_done then
            has_pressed_button = rnd() < (0.13 + 0.26 * difficulty)
          elseif self.is_ready_to_throw and not self.has_taken_action then
            if not self.opponent.pane.is_done then
              has_pressed_button = rnd() < 0.2
            elseif self.opponent.has_taken_action then
              has_pressed_button = rnd() < (0.03 + 0.055 * difficulty)
            else
              has_pressed_button = rnd() < (0.002 - 0.001 * difficulty) * (2 + speed_indicator.speed_level)
            end
          end
        end
      end
      if has_pressed_button then
        if scene == "title" then
          self.ready:activate()
        elseif scene == "game" and not self.has_been_hit then
          if self.is_ready_to_throw and not self.has_taken_action then
            self.has_taken_action = true
            local incoming_snowball = self.opponent.snowball
            -- dodge snowball
            if incoming_snowball then
              local offset = ternary(incoming_snowball.has_updated_this_frame, 0, 1)
              local frames_alive = incoming_snowball.frames_alive + offset
              local frames_to_hit = incoming_snowball.frames_to_hit - offset
              if frames_alive > 1 and frames_to_hit < 10 then
                self.has_dodged = true
                sfx(13, self.channel)
                spawn_entity("dodge", self.x, self.y - 8, {
                  player = self
                })
                self:animate("dodge", function()
                  self:throw_snowball()
                end)
              end
            end
            -- throw snowball
            if not self.has_dodged then
              self:throw_snowball()
            end
          -- finish packing a snowball
          elseif not self.pane.is_done then
            if self.pane:activate() then
              if self.opponent.pane.is_done then
                self.showoff_frames_left = min(max(24, self.opponent.showoff_frames_left + 7), 48)
              else
                self.showoff_frames_left = 48
              end
              sfx(11, self.channel)
              speed_indicator:fill()
              self:animate({ "show_snowball", { -1, self.showoff_frames_left - 9 }, "aim" }, function()
                self.pane.is_visible = false
                self.is_ready_to_throw = true
              end)
            end
          end
        end
      end
      -- update scarf
      local neck_x = self.x + self.facing * (neck_points[self.sprite][1] - 9)
      local neck_y = self.y + neck_points[self.sprite][2] - 1
      self.scarf:set_end_point(neck_x, neck_y)
    end,
    draw = function(self, x, y)
      -- colorize
      pal(3, self.dark_color)
      pal(11, self.color)
      -- draw player sprite
      if self.sprite >= 16 then
        pal(7, self.dark_color)
      end
      if self.sprite == 18 then
        self.sprite = 10
      end
      if self.sprite == 14 or self.sprite == 16 then
        sspr2(102, 18, 19, 16, x - ternary(self.is_first_player, 7, 11), y + 1, not self.is_first_player)
      elseif self.sprite == 15 or self.sprite == 17 then
        sspr2(36, 72, 14, 20, x - ternary(self.is_first_player, 7, 6), y - 3, not self.is_first_player)
      else
        sspr2(17 * ((self.sprite - 1) % 7), 18 * flr((self.sprite - 1) / 7), 17, 18, x - 8, y, not self.is_first_player)
      end
      -- draw "npc"
      if self.ready.is_npc then
        print2_center("npc", self.x + ternary(self.is_first_player, 0, 3), self.y - 9, self.dark_color)
      end
    end,
    reset = function(self)
      self.snowball = nil
      self.showoff_frames_left = 0
      self.is_ready_to_throw = false
      self.has_taken_action = false
      self.has_dodged = false
      self.has_been_hit = false
      self.pane:reset()
    end,
    throw_snowball = function(self)
      sfx(4 + self.player_num, self.channel)
      self:animate({ { 10, mid(1, 7 - flr(speed_indicator.speed_level / 3), 7) } }, function()
        -- snowball speed increases if the wind is in your favor
        local speed = 88 / mid(3, 17 - speed_indicator.speed_level, 17)
        -- throw snowball
        self:animate("throw")
        self.snowball = spawn_entity("snowball", self.x + 11 * self.facing, self.y + 5, {
          player = self,
          vx = speed * self.facing
        })
      end)
    end,
    get_hit = function(self, snowball_speed)
      shake_and_freeze(3 + flr(snowball_speed / 2), 1 + flr(snowball_speed / 4))
      if snowball_speed > 25 then
        sfx(26, self.channel)
      elseif snowball_speed > 9 then
        sfx(27, self.channel)
      else
        sfx(28, self.channel)
      end
      self.has_been_hit = true
      self.pane.is_visible = false
      self:animate("block")
      spawn_entity("snow_poof", self.x, self.y, {
        num_snowflakes = 25
      })
      speed_indicator:drain()
      local opponent = self.opponent
      if not self.has_taken_action or opponent.has_been_hit or opponent.has_dodged then
        end_round()
      end
    end,
    start_packing_snow = function(self)
      self:animate("drop", function()
        self.pane:show()
        self:animate({ { -1, 29 } }, function()
          self:keep_packing_snow()
        end)
      end)
    end,
    keep_packing_snow = function(self)
      self:animate("pack_snow", function()
        self:keep_packing_snow()
      end)
    end,
    animate = function(self, animation, on_done)
      if type(animation) == "string" then
        self.animation_queue = { animation }
      else
        self.animation_queue = animation
      end
      self.animation_frames = -1
      self.on_animation_done = on_done
      self:apply_animation()
    end,
    apply_animation = function(self, on_done)
      if #self.animation_queue > 0 then
        -- progress the animation
        increment_counter_prop(self, "animation_frames")
        -- set the sprite based on the animation data
        local animation = self.animation_queue[1]
        local animation_data
        if type(animation) == "string" then
          animation_data = player_animations[animation]
        else
          animation_data = { animation }
        end
        local total_frames = 0
        local i
        for i = 1, #animation_data do
          local sprite
          local frames
          if type(animation_data[i]) == "number" then
            sprite = animation_data[i]
            frames = 1
          else
            sprite = animation_data[i][1]
            frames = animation_data[i][2] or 1
          end
          total_frames += frames
          if sprite > 0 then
            self.sprite = sprite
          end
          if self.animation_frames < total_frames then
            return
          end
        end
        -- the animation is finished
        local remaining_animations = {}
        for i = 2, #self.animation_queue do
          add(remaining_animations, self.animation_queue[i])
        end
        if #remaining_animations > 0 then
          self:animate(remaining_animations, self.on_animation_done)
        else
          self.animation_queue = {}
          self.animation_frames = 0
          if self.on_animation_done then
            local func = self.on_animation_done
            self.on_animation_done = nil
            func()
          end
        end
      end
    end
  },
  scarf = {
    render_layer = 4,
    init = function(self)
      self.points = {}
      local i
      for i = 1, 7 do
        add(self.points, {
          x = self.x,
          y = self.y,
          vx = 0,
          vy = 0
        })
      end
    end,
    update = function(self)
      local i
      -- apply physics
      for i = 2, #self.points do
        local point = self.points[i]
        local prev_point = self.points[i - 1]
        local dist, dx, dy = calc_distance(prev_point.x, prev_point.y, point.x, point.y)
        if dist > 1 then
          -- point.vx -= 0.01 * (dist - 5) * (dx / dist)
          local force = min(3, dist - 1)
          prev_point.vx += force * (dx / dist)
          prev_point.vy += force * (dy / dist)
          point.vx -= force * (dx / dist)
          point.vy -= force * (dy / dist)
        end
        point.vx += wind_pressure / 10
        point.vy += 0.05 - abs(wind_pressure) * wind_updraft / 20
      end
      -- apply velocity
      for i = 2, #self.points do
        local point = self.points[i]
        point.vx *= 0.8
        point.vy *= 0.8
        point.x += point.vx
        point.y += point.vy
        point.y = min(point.y, 78)
      end
    end,
    draw = function(self)
      local i
      for i = 1, #self.points do
        local point = self.points[i]
        rectfill2(point.x - 1, point.y - 1, 3, 3, self.player.color)
      end
    end,
    set_end_point = function(self, x, y)
      self.points[1].x = x
      self.points[1].y = y
    end
  },
  snowball_pane = {
    render_layer = 12,
    cursor_angle = 0,
    wait_frames = 0,
    is_done = false,
    init = function(self)
      self.lumps = {}
    end,
    update = function(self)
      if self.is_visible then
        -- slide up
        if self.y > 103 then
          self.y -= max(0.5, (self.y - 103) / 4)
          if self.y <= 103 then
            self.y = 103
          end
        end
        -- pause before starting
        decrement_counter_prop(self, "wait_frames")
        if self.wait_frames == 8 then
          start:show()
        end
        -- spin the cursor
        if self.wait_frames <= 0 then
          self.cursor_angle = (self.cursor_angle + 6 * ternary(self.player.is_first_player, 1, -1)) % 360
          if self.cursor_angle < 0 then
            self.cursor_angle += 360
          end
        end
      end
    end,
    reset = function(self)
      self.is_done = false
      self.y = 150
    end,
    show = function(self)
      self.is_visible = true
      self.cursor_angle = 0
      self.wait_frames = 40
      self.lumps = {}
      local i
      for i = 1, 6 do
        local x = -5.5 * cos((i + 0.4) / 6)
        local y = 5.5 * sin((i + 0.4) / 6)
        add(self.lumps, {
          x = x - ternary(self.player.is_first_player, 6.5, 5.5),
          y = y - 6.5,
          size = rnd_int(1, 3),
          variant = rnd_int(1, 2)
        })
      end
    end,
    activate = function(self)
      if self.is_visible and self.wait_frames <= 0 and not self.is_done then
        local lump_index = flr((self.cursor_angle + 30) / 60) % 6 + 1
        local lump = self.lumps[lump_index]
        if lump.size > 0 then
          lump.size -= 1
          sfx(rnd_int(0, 2), self.player.channel)
          spawn_entity("snow_poof", self.x + lump.x + 6, self.y + lump.y + 6, {
            render_layer = 18
          })
        else
          -- sfx(3, self.player.channel)
        end
        -- figure out if we are done making the perfect snowball
        self.is_done = true
        local i
        for i = 1, #self.lumps do
          if self.lumps[i].size > 0 then
            self.is_done = false
          end
        end
        return self.is_done
      end
    end,
    draw = function(self, x, y)
      local is_first = self.player.is_first_player
      pal(4, 0)
      pal(9, 6)
      pal(10, 7)
      -- draw pane
      sspr2(18, 92, 46, 36, x - ternary(is_first, 24, 21), y - 19, not is_first)
      -- draw each color
      self:draw_color(x, y, 11)
      self:draw_color(x, y, 6)
      self:draw_color(x, y, 7)
      -- draw cursor
      if not self.is_done then
        pal()
        pal(11, self.player.color)
        local cursor_x = x + ternary(is_first, 0, 1) - 14.5 * sin(self.cursor_angle / 360)
        local cursor_y = y - 14.5 * cos(self.cursor_angle / 360)
        local sector = flr((self.cursor_angle + 22.5) / 45) % 8
        local cursor_sprite
        if sector == 0 or sector == 4 then
          cursor_sprite = 1
        elseif sector == 2 or sector == 6 then
          cursor_sprite = 3
        else
          cursor_sprite = 2
        end
        sspr2(1, 81 + 5 * cursor_sprite, 5, 5, cursor_x - 2.5, cursor_y - 2.5, sector > 4, 2 < sector and sector < 6)
      end
    end,
    draw_color = function(self, x, y, color)
      local is_first = self.player.is_first_player
      pal()
      pal(11, self.player.color)
      -- make all colors except this one transparent
      local i
      for i = 0, 15 do
        palt(i, i != color)
      end
      -- draw the snowball
      sspr2(18, 92, 46, 36, x - ternary(is_first, 24, 21), y - 19, not is_first)
      -- draw lumps
      local i
      for i = 1, #self.lumps do
        local lump = self.lumps[i]
        if lump.size > 0 then
          sspr2(13 * (3 - lump.size), 23 + 13 * lump.variant, 13, 13, x + lump.x, y + lump.y, not is_first)
        end
      end
    end
  },
  snowball = {
    render_layer = 6,
    frames_to_death = 90,
    init = function(self)
      local dx = abs(self.player.x - self.player.opponent.x)
      self.frames_to_hit = flr((dx - 10) / abs(self.vx))
    end,
    update = function(self)
      self:apply_velocity()
      -- check for snowball hit
      if decrement_counter_prop(self, "frames_to_hit") and not self.player.opponent.has_dodged then
        self.player.opponent:get_hit(abs(self.vx))
        self:die()
      end
    end,
    draw = function(self, x, y)
      local is_first = self.player.is_first_player
      local w = min(max(2, flr(1.2 * abs(self.vx))), 14)
      sspr2(29 - flr(w / 2), 83, w, 2, x - ternary(is_first, w - 1, 0), y, not is_first)
    end
  },
  dodge = {
    frames_to_death = 40,
    draw = function(self, x, y)
      local sprites = { 1, 2, 1, 3, 4, 5 }
      local i
      for i = 1, #sprites do
        local n = ternary(self.player.is_first_player, #sprites + 1 - i, i)
        local f = self.frames_alive - 1 * n
        local y_offset = 0.04 * f * f - f
        if y_offset < 0 then
          sspr2(6 * sprites[i], 85, 6, 7, x + 7 * i - 24, y + y_offset)
        end
      end
    end
  },
  win = {
    frames_to_death = 160,
    draw = function(self, x, y)
      draw_bubble_letters_with_shadow({ 11, 12, 7 }, x, y, self.player.color, self.player.dark_color)
    end
  },
  draw = {
    frames_to_death = 170,
    draw = function(self, x, y)
      draw_bubble_letters_with_shadow({ 3, 5, 6, 11 }, x, y, 13, 1)
    end
  },
  speed_indicator = {
    render_layer = 13,
    speed_level = 0,
    animation = nil,
    animation_frames = 0,
    update = function(self)
      if self.animation == "filling" and decrement_counter_prop(self, "animation_frames") then
        self.speed_level = min(15, self.speed_level + 1)
        if self.speed_level % 2 == 0 then
          sfx(19, -1, 4 * flr(self.speed_level / 2) - 4, 4)
        end
        if self.speed_level >= 15 then
          self.animation = nil
        else
          self.animation_frames = 20 + 2 * self.speed_level
        end
      end
      if self.animation == "draining" and decrement_counter_prop(self, "animation_frames") then
        self.speed_level = max(0, self.speed_level - 1)
        if self.speed_level == 0 then
          self.animation = nil
        else
          self.animation_frames = 5
        end
      end
    end,
    draw = function(self, x, y)
      pal(11, 7)
      local i
      for i = 1, flr(self.speed_level / 2) do
        sspr2(1, 88, 5, 3, x - 2, y + 4 - 4 * i, false, true)
      end
    end,
    fill = function(self)
      if self.animation != "filling" then
        self.animation = "filling"
        self.animation_frames = 60
      end
    end,
    drain = function(self)
      if self.animation != "draining" then
        self.animation = "draining"
        self.animation_frames = 1
      end
    end
  },
  score = {
    points = 2,
    render_layer = 11,
    frames_to_point = 0,
    skip_point_sound = false,
    update = function(self)
      if decrement_counter_prop(self, "frames_to_point") then
        self.points += 1
        if not self.skip_point_sound then
          sfx(8, self.player.channel)
          self.skip_point_sound = false
        end
      end
    end,
    draw = function(self, x, y)
      pal(11, 12)
      local i
      for i = 1, 3 do
        if self.points >= ternary(self.player.is_first_player, i, 4 - i) then
          pal(11, self.player.color)
        else
          pal(11, self.player.dark_color)
        end
        sspr2(50, 72, 3, 20, x - 13 + 6 * i, y - 10)
      end
    end,
    add_point = function(self, frames, skip_sound)
      self.frames_to_point = frames
      self.skip_point_sound = skip_sound
    end,
    reset = function(self)
      self.points = 0
      self.frames_to_point = 0
      self.is_visible = false
    end
  },
  snowfall = {
    min_dist = 0.00,
    max_dist = 0.85,
    spawn_rate = 1.00,
    init = function(self)
      self.snowflakes = {}
      -- get some now on the screen immediately
      local i
      for i = 1, 200 do
        self:update()
      end
    end,
    update = function(self)
      -- add new snowflakes
      if rnd() < self.spawn_rate + speed_indicator.speed_level / 20 then
        self:spawn_snowflake()
      end
      -- update all snowflakes
      local i
      for i = 1, #self.snowflakes do
        local snowflake = self.snowflakes[i]
        snowflake.vx *= 0.6
        snowflake.vx += wind_pressure / 3
        snowflake.x += snowflake.vx * (1 - snowflake.distance_from_camera)
        snowflake.y += 0.6 * (1 - snowflake.distance_from_camera)
      end
      -- remove snowflakes that hit the ground
      filter_list(self.snowflakes, function(snowflake)
        return snowflake.y < 83
      end)
    end,
    draw = function(self)
      -- draw all snowflakes
      local i
      for i = 1, #self.snowflakes do
        local snowflake = self.snowflakes[i]
        sspr2(6, 89 + 3 * snowflake.sprite, 3, 3, snowflake.x, snowflake.y)
      end
    end,
    spawn_snowflake = function(self)
      local distance_from_camera = rnd_num(self.min_dist, self.max_dist)
      local sprite = 1
      if distance_from_camera < 0.4 and rnd() < 0.07 then
        sprite = 2
      elseif distance_from_camera < 0.3 and rnd() < 0.07 then
        sprite = 3
      end
      add(self.snowflakes, {
        x = rnd_int(-15, 141),
        y = 29,
        vx = 0,
        sprite = sprite,
        distance_from_camera = distance_from_camera
      })
    end
  },
  title = {
    render_layer = 20,
    draw = function(self, x, y)
      draw_bubble_letters_with_shadow({ 8, 7, 1, 11, 9, 6, 2, 2 }, x + 2, y, 13, 1)
      draw_bubble_letters_with_shadow({ 8, 10, 1, 11, 3, 1, 11, 7 }, x, y + 16, 13, 1)
      print2_center("created by bridgs", 64, y + 32, 1)
    end
  },
  start = {
    is_visible = false,
    draw = function(self, x, y)
      draw_bubble_letters_with_shadow({ 8, 4, 6, 5, 4}, x, y, 13, 1)
    end,
    show = function(self)
      self.is_visible = true
      self.visible_frames = 60
      sfx(10)
    end
  },
  ready_up = {
    render_layer = 21,
    npc_start_frames = 0,
    is_npc = false,
    activate = function(self)
      self.is_ready = not self.is_ready
      sfx(ternary(self.is_ready, 4, 3), self.player.channel)
      if self.is_ready and self.player.opponent.ready.is_ready then
        remove_title()
      end
    end,
    update = function(self)
      if self.player.opponent.ready.is_ready and not self.is_ready then
        increment_counter_prop(self, "npc_start_frames")
        if self.npc_start_frames >= 75 then
          self:activate()
          self.is_npc = true
        end
      else
        self.npc_start_frames = 0
      end
    end,
    draw = function(self, x, y)
      print2_center("player " .. self.player.player_num, x, y, self.player.color)
      if self.is_ready then
        pal(11, self.player.color)
        sspr2(79, ternary(self.is_npc, 58, 47), 34, 11, x - 17, y + 14)
      else
        if self.frames_alive % 35 < 25 then
          print2_center("press", x, y + 14, 1)
          print2_center("button", x, y + 20)
        end
        if self.npc_start_frames > 0 then
          print2("npc", x - 19, y + 32, 1)
          rect2(x - 6, y + 32, 25, 5)
          rectfill2(x - 6, y + 32, mid(1, 25 * self.npc_start_frames / 75, 25), 5)
        end
      end
    end,
    reset = function(self)
      self.is_visible = true
      self.is_ready = false
      self.is_npc = false
      self.npc_start_frames = 0
    end
  },
  title_blinders = {
    render_layer = 20,
    top_y = 65,
    bottom_y = 73,
    amount_open = 0,
    update = function(self)
      if self.animation == "closing" then
        self.amount_open -= 1
        if self.amount_open <= 0 then
          self.animation = nil
          init_title()
        end
        wind_is_active = false
      elseif self.animation == "opening" then
        self.amount_open += 1
        if self.amount_open >= 80 then
          self.animation = nil
        elseif self.amount_open == 40 then
          start_bows()
        end
      end
    end,
    draw = function(self)
      rectfill2(0, 0, 127, 65 - 34 * (self.amount_open / 40), 0)
      rectfill2(0, 73 + 17 * (self.amount_open / 40), 127, 127)
    end,
    open = function(self)
      self.animation = "opening"
      self.visible_frames = 80
    end,
    close = function(self)
      sfx(25)
      self.is_visible = true
      self.animation = "closing"
    end
  },
  game_blinders = {
    render_layer = 10,
    draw = function(self)
      palt(6, true)
      palt(7, true)
      palt(13, true)
      pal(4, 0)
      sspr2(64, 71, 64, 57, 0, 32) -- snow drifts
      sspr2(64, 71, 64, 57, 63, 32, true) -- snow drifts
      rectfill2(0, 0, 127, 32, 0)
      rectfill2(0, 89, 127, 39)
    end
  },
  snow_poof = {
    render_layer = 7,
    frames_to_death = 60,
    num_snowflakes = 10,
    init = function(self)
      self.snowflakes = {}
      local i
      for i = 1, self.num_snowflakes do
        local angle = rnd_int(1, 360)
        local speed = 2 + rnd(3)
        add(self.snowflakes, {
          x = self.x,
          y = self.y,
          vx = speed * cos(angle / 360),
          vy = speed * sin(angle / 360),
          sprite = max(1, rnd_int(1, 6) - 3)
        })
      end
    end,
    update = function(self)
      local i
      for i = 1, #self.snowflakes do
        local snowflake = self.snowflakes[i]
        snowflake.vx *= 0.85
        snowflake.vy *= 0.85
        snowflake.vy += 0.1
        snowflake.x += snowflake.vx
        snowflake.y += snowflake.vy
      end
    end,
    draw = function(self)
      local i
      for i = 1, #self.snowflakes do
        local snowflake = self.snowflakes[i]
        sspr2(6, 89 + 3 * snowflake.sprite, 3, 3, snowflake.x, snowflake.y)
      end
    end
  }
}

function _init()
  -- init vars
  scene = "title"
  scene_frames = 0
  game_frames = 0
  freeze_frames = 0
  screen_shake_frames = 0
  buttons = { {}, {} }
  button_presses = { {}, {} }
  entities = {}
  wind_is_active = false
  wind_active_frames = 0
  wind_switch_frames = 0
  wind_pressure = 0
  wind_updraft = 0
  wind_target_pressure = 0
  -- spawn players
  players = {
    spawn_entity("player", 20, 65, {
      player_num = 1,
      is_first_player = true,
      facing = 1,
      channel = 0,
      color = 12,
      dark_color = 1
    }),
    spawn_entity("player", 106, 65, {
      player_num = 2,
      is_first_player = false,
      facing = -1,
      channel = 1,
      color = 8,
      dark_color = 2
    })
  }
  players[1].opponent = players[2]
  players[2].opponent = players[1]
  -- wind indicator
  speed_indicator = spawn_entity("speed_indicator", 62, 26)
  -- foreground snowfall
  spawn_entity("snowfall", 0, 0, {
    min_dist = 0.0,
    max_dist = 0.4,
    spawn_rate = 0.25,
    render_layer = 9
  })
  -- background snowfall
  spawn_entity("snowfall", 0, 0, {
    min_dist = 0.4,
    max_dist = 0.8,
    spawn_rate = 0.35,
    render_layer = 1
  })
  -- title screen
  title = spawn_entity("title", 14, 19)
  -- start text
  start = spawn_entity("start", 34, 51)
  -- black out anything that is offscreen
  spawn_entity("game_blinders")
  title_blinders = spawn_entity("title_blinders")
  -- debug, skip to start
  if skip_to_start or skip_to_throw then
    title.is_visible = false
    title_blinders.amount_open = 80
    title_blinders.is_visible = false
    players[1].ready.is_visible = false
    players[2].ready.is_visible = false
    start_round()
  end
  if skip_to_throw then
    wind_active_frames = 100
    players[1].is_ready_to_throw = true
    players[1]:animate("aim")
    players[2].is_ready_to_throw = true
    players[2]:animate("aim")
    players[1].score.is_visible = starting_points and (starting_points[1] > 0 or starting_points[2] > 0)
    players[2].score.is_visible = players[1].score.is_visible
  end
end

function _update()
  -- keep track of counters
  local game_is_running = freeze_frames <= 0
  freeze_frames = decrement_counter(freeze_frames)
  if game_is_running then
    scene_frames = increment_counter(scene_frames)
    game_frames = increment_counter(game_frames)
    screen_shake_frames = decrement_counter(screen_shake_frames)
  end
  -- keep track of button presses
  local p
  for p = 1, 2 do
    local i
    for i = 0, 5 do
      button_presses[p][i] = btn(i, controllers[p]) and not buttons[p][i]
      buttons[p][i] = btn(i, controllers[p])
    end
  end
  -- update the wind
  if wind_is_active then
    wind_active_frames = increment_counter(wind_active_frames)
  else
    wind_active_frames = 0
  end
  wind_switch_frames = decrement_counter(wind_switch_frames)
  local max_wind_pressure = mid(0.5, wind_active_frames / 120, 1.5)
  if wind_switch_frames <= 0 then
    wind_switch_frames = mid(0, 50 - flr(wind_active_frames / 10), 30) + rnd_int(135, 185)
    local dir
    if wind_target_pressure > 0 then
      dir = -1
    elseif wind_target_pressure < 0 then
      dir = 1
    else
      dir = ternary(rnd() < 0.5, -1, 1)
    end
    local wind_speed = max_wind_pressure * rnd_num(0.2, 1.0)
    wind_target_pressure = dir * wind_speed
    wind_updraft = rnd_num(-0.2, 1.0)
    if wind_speed > 1.45 then
      sfx(rnd_int(21, 22))
    elseif wind_speed > 0.5 then
      sfx(rnd_int(20, 21))
    end
  elseif wind_switch_frames % 10 == 0 then
    wind_updraft = rnd_num(-0.2, 1.0)
  end
  wind_target_pressure = mid(-max_wind_pressure, wind_target_pressure, max_wind_pressure)
  local wind_change = (wind_target_pressure - wind_pressure) / 7
  local wind_change_dir = ternary(wind_change < 0, -1, 1)
  wind_change = min(abs(wind_change), 0.3)
  wind_pressure += wind_change_dir * wind_change
  -- update each entity
  local entity
  for entity in all(entities) do
    entity.has_updated_this_frame = false
  end
  for entity in all(entities) do
    entity.has_updated_this_frame = true
    if entity.is_freeze_frame_immune or game_is_running then
      if decrement_counter_prop(entity, "frames_to_death") then
        entity:die()
      else
        increment_counter_prop(entity, "frames_alive")
        if decrement_counter_prop(entity, "visible_frames") then
          entity.is_visible = false
        end
        if decrement_counter_prop(entity, "hidden_frames") then
          entity.is_visible = true
        end
        entity:update()
      end
    end
  end
  -- remove dead entities
  filter_list(entities, function(item)
    return item.is_alive
  end)
  -- sort entities for rendering
  sort_list(entities, is_rendered_on_top_of)
end

function _draw()
  -- shake the screen
  local screen_offet_x = x
  if freeze_frames <= 0 and screen_shake_frames > 0 then
    screen_offet_x = ceil(screen_shake_frames / 3) * (game_frames % 2 * 2 - 1)
  end
  camera(screen_offet_x)
  -- clear the screen
  pal()
  cls(bg_color)
  -- draw the background
  pal(4, 0)
  sspr2(64, 71, 64, 57, 0, 32) -- snow drifts
  sspr2(64, 71, 64, 57, 63, 32, true) -- snow drifts
  sspr2(9, 92, 9, 9, 32, 69) -- distant left tree
  sspr2(53, 69, 11, 23, 0, 53) -- far left tree
  sspr2(2, 101, 16, 27, 111, 49) -- far right tre
  -- draw each entity that is within the main view area
  local entity
  for entity in all(entities) do
    if entity.is_visible then
      pal()
      entity:draw(entity.x, entity.y)
    end
  end
  -- cover up the rightmost column of pixels
  pal()
  line(127, 0, 127, 127, 0)
end

-- spawns an instance of the given class
function spawn_entity(class_name, x, y, args, skip_init)
  local class_def = entity_classes[class_name]
  local entity
  if class_def.extends then
    entity = spawn_entity(class_def.extends, x, y, args, true)
  else
    -- create a default entity
    entity = {
      -- life cycle vars
      is_alive = true,
      frames_alive = 0,
      frames_to_death = 0,
      -- position vars
      x = x or 0,
      y = y or 0,
      vx = 0,
      vy = 0,
      width = 8,
      height = 8,
      -- render vars
      render_layer = 5,
      is_visible = true,
      visible_frames = 0,
      hidden_frames = 0,
      -- functions
      init = noop,
      update = function(self)
        self:apply_velocity()
      end,
      apply_velocity = function(self)
        self.x += self.vx
        self.y += self.vy
      end,
      center_x = function(self)
        return self.x + self.width / 2
      end,
      center_y = function(self)
        return self.y + self.height / 2
      end,
      -- draw functions
      draw = noop,
      draw_outline = function(self, color)
        rect(self.x + 0.5, self.y + 0.5, self.x + self.width - 0.5, self.y + self.height - 0.5, color or 7)
      end,
      -- life cycle functions
      die = function(self)
        if self.is_alive then
          self.is_alive = false
          self:on_death()
        end
      end,
      despawn = function(self)
        self.is_alive = false
      end,
      on_death = noop
    }
  end
  -- add class-specific properties
  entity.class_name = class_name
  local key, value
  for key, value in pairs(class_def) do
    entity[key] = value
  end
  -- override with passed-in arguments
  for key, value in pairs(args or {}) do
    entity[key] = value
  end
  if not skip_init then
    -- add it to the list of entities
    add(entities, entity)
    -- initialize the entitiy
    entity:init()
  end
  -- return the new entity
  return entity
end

function draw_bubble_letters(sprites, x, y)
  local i
  for i = 1, #sprites do
    local sprite = sprites[i]
    local sx = 28 + 11 * (1 + (sprite - 1) % 8)
    local sy = 36 + 11 * flr((sprite - 1) / 8)
    local sw = 11
    if sprite == 11 then
      sw = 13
    elseif sprite == 12 then
      sw = 5
      sx += 2
    end
    sspr2(sx, sy, sw, 11, x, y)
    x += sw + 1
  end
end
function draw_bubble_letters_with_shadow(sprites, x, y, color, shadow_color)
  pal(1, shadow_color)
  pal(13, shadow_color)
  pal(7, shadow_color)
  draw_bubble_letters(sprites, x - 1, y + 1)
  pal(13, color)
  pal(7, 7)
  draw_bubble_letters(sprites, x, y)
end

-- scene vars
function remove_title()
  scene = "removing_title"
  title.visible_frames = 10
  players[1].ready.visible_frames = 20
  players[2].ready.visible_frames = 20
  title_blinders:open()
  sfx(16)
end
function start_bows()
  scene = "bows"
  sfx(15)
  players[1]:animate("bow")
  players[2]:animate("bow", function()
    start_round()
  end)
end
function bows_done()
  scene = "starting_game"
  players[1]:animate({ "bow_up" })
  players[2]:animate({ "bow_up", { -1, 30 } }, function()
    start_round()
  end)
end
function start_round()
  scene = "game"
  wind_is_active = true
  wind_active_frames = 0
  wind_updraft = 0
  wind_target_pressure = 0
  players[1]:start_packing_snow()
  players[2]:start_packing_snow()
  sfx(12)
end
function end_round()
  scene = "round-end"
  wind_updraft = 0
  wind_target_pressure = 0
  -- figure out the winner
  local winner
  if not players[1].has_been_hit and players[2].has_been_hit then
    winner = players[1]
  elseif not players[2].has_been_hit and players[1].has_been_hit then
    winner = players[2]
  end
  -- if there is a winner, give that player a point
  if winner then
    winner:animate({ { -1, 30 } }, function()
      players[1].score.hidden_frames = 20
      players[2].score.hidden_frames = 20
      local is_final_point = (winner.score.points >= 2)
      winner.score:add_point(45, is_final_point)
      sfx(9, winner.channel)
      winner:animate({ "celebrate", { -1, 45 } }, function()
        if is_final_point then
          declare_winner(winner)
        else
          winner:animate("stop_celebrating")
          winner.opponent:animate("stop_blocking", function()
            reset_round()
          end)
        end
      end)
    end)
  -- if there is no winner, show a draw
  else
    players[1]:animate({ { -1, 30 } }, function()
      players[1].score.hidden_frames = 20
      players[2].score.hidden_frames = 20
      local is_final_point = { players[1].score.points >= 2, players[2].score.points >= 2 }
      players[1].score:add_point(45)
      players[2].score:add_point(45)
      players[1]:animate("stop_blocking")
      players[2]:animate({ "stop_blocking", { -1, 50 } }, function()
        if is_final_point[1] and is_final_point[2] then
          declare_draw()
        elseif is_final_point[1] then
          players[1]:animate("celebrate")
          declare_winner(players[1])
        elseif is_final_point[2] then
          players[2]:animate("celebrate")
          declare_winner(players[2])
        else
          reset_round()
        end
      end)
    end)
  end
end
function declare_winner(winner)
  music(0)
  spawn_entity("win", winner.x - 15, winner.y - 18, {
    player = winner
  })
  winner.opponent:animate({ "drop", { -1, 60 } }, function()
    title_blinders:close()
    winner.opponent:animate({ { -1, 100 } }, function()
      winner:animate("stop_celebrating")
      winner.opponent:animate("get_up")
    end)
  end)
end
function declare_draw()
  music(4)
  spawn_entity("draw", 39, 51)
  players[1]:animate({ "drop", { -1, 170 }, "get_up" })
  players[2]:animate({ "drop", { -1, 70 } }, function()
    title_blinders:close()
    players[2]:animate({ { -1, 100 }, "get_up" })
  end)
end
function reset_round()
  players[1]:reset()
  players[2]:reset()
  start_round()
end
function init_title()
  scene = "title"
  wind_is_active = false
  title.is_visible = true
  players[1]:reset()
  players[2]:reset()
  players[1].score:reset()
  players[2].score:reset()
  players[1].ready:reset()
  players[2].ready:reset()
end


-- wrappers for input methods
function btn2(button_num, player_num)
  return buttons[player_num][button_num]
end
function btnp2(button_num, player_num, consume_press)
  if button_presses[player_num][button_num] then
    if consume_press then
      button_presses[player_num][button_num] = false
    end
    return true
  end
end
function any_button_pressed(player_num, consume_press)
  return btnp2(4, player_num, consume_press) or btnp2(5, player_num, consume_press)
end

-- bubble sorts a list
function sort_list(list, func)
  local i
  for i=1, #list do
    local j = i
    while j > 1 and func(list[j - 1], list[j]) do
      list[j], list[j - 1] = list[j - 1], list[j]
      j -= 1
    end
  end
end

-- removes all items in the list that don"t pass the criteria func
function filter_list(list, func)
  local item
  for item in all(list) do
    if not func(item) then
      del(list, item)
    end
  end
end

-- apply camera shake and freeze frames
function shake_and_freeze(s, f)
  screen_shake_frames = max(screen_shake_frames, s)
  freeze_frames = max(freeze_frames, f or 0)
end

-- returns true if a is rendered on top of b
function is_rendered_on_top_of(a, b)
  return ternary(a.render_layer == b.render_layer, a:center_y() > b:center_y(), a.render_layer > b.render_layer)
end

-- check to see if two rectangles are overlapping
function rects_overlapping(x1, y1, w1, h1, x2, y2, w2, h2)
  return x1 < x2 + w2 and x2 < x1 + w1 and y1 < y2 + h2 and y2 < y1 + h1
end

-- helper methods for incrementing/decrementing counters while avoiding the integer limit
function increment_counter(n)
  return ternary(n>32000, 20000, n+1)
end
function increment_counter_prop(obj, key)
  obj[key] = increment_counter(obj[key])
end
function decrement_counter(n)
  return max(0, n-1)
end
function decrement_counter_prop(obj, key)
  local initial_value = obj[key]
  obj[key] = decrement_counter(initial_value)
  return initial_value > 0 and initial_value <= 1
end

-- random number generators
function rnd_int(min_val, max_val)
  return flr(min_val + rnd(1 + max_val - min_val))
end
function rnd_num(min_val, max_val)
  return min_val + rnd(max_val - min_val)
end

-- finds the distance between two points
function calc_distance(x1, y1, x2, y2)
  local dx = mid(-100, x2 - x1, 100)
  local dy = mid(-100, y2 - y1, 100)
  return sqrt(dx * dx + dy * dy), dx, dy
end

-- wrappers for drawing functions
function pset2(x, y, ...)
  pset(x + 0.5, y + 0.5, ...)
end
function print2(text, x, y, ...)
  print(text, x + 0.5, y + 0.5, ...)
end
function print2_center(text, x, y, ...)
  print(text, x - 2 * #("" .. text) + 0.5, y + 0.5, ...)
end
function spr2(sprite, x, y, ...)
  spr(sprite, x + 0.5, y + 0.5, 1, 1, ...)
end
function sspr2(sx, sy, sw, sh, x, y, flip_h, flip_y, sw2, sh2)
  sspr(sx, sy, sw, sh, x + 0.5, y + 0.5, sw2 or sw, sh2 or sh, flip_h, flip_y)
end
function rect2(x, y, width, height, ...)
  rect(x + 0.5, y + 0.5, x + width - 0.5, y + height - 0.5, ...)
end
function rectfill2(x, y, width, height, ...)
  rectfill(x + 0.5, y + 0.5, x + width - 0.5, y + height - 0.5, ...)
end

__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000222220123
00000033300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000222224567
000003333000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002222289ab
0000033330000000000000000333300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022222cdef
00000333300000000000000033333300000000000000000000000000000000000000000000000000000000000000000000000000000003330000000222222222
00003bbbb30000000000000bb3333300000000000000000000000000000333000000000000000000000000000000000000000000000003333000000222222222
00003bbbb30000000000003bbb333000000000000333000000000000003333000000000000000000000000000000000000000000000003333000000222222222
000333333300000000000333bbb3000000000003333bb33300000000003333000000000000000000000000000000000000000000000033333000000222222222
0003333333000000000003333b33000000000033333bb333300000003b333300000000000000000000000000000000330000000000033bbbb300000222222222
0003333333000000000033333330000000000033333bb333300000003bbbbb30000000000000333300000000000003333000000000333bbb3300000222222222
00033333330000000000333333300000000003333333b3333000000333bbb33300000000003b3333300000000003b33330000000003377333300000222222222
000333333300000000003333333000000000033333333000000000033333333330000000033b3333300000000033b33333000000003377333300000222222222
000333333300000000003333333000000000033333330000000000033333333330000000033bb333300000000033bbbb33000000000333333300000222222222
0003333333000000000033333330000000000333333300000000000333333330000000003333bb333000000003333bb333300000003333333300000222222222
00003333336600000000033333366000000000333333660000000003333333360000000033333333330000000333333333300000003333333360000222222222
06063336666000000060633366660000000606333666600000006063336666600000060633333333330000606333333377300006063333033360000222222222
00666666000000000006666660000000000066666600000000000666666000000000006666333303336000066666333377360000666666033000000222222222
00000000000000000000000000000000000000000000000000000000000000000000000000033360660000000000063333600000000000666000000222222222
00377000000000000000000000000000000000000000000000000000033330000000000000000000000000000000000000000000000000033300000002222222
00377003330000000000000333000000000000000333000000003000033330000000000000000330000000000000333000000000000000333300000002222222
00330033330000000030003333000000000003003333000000037700033330000000000000333330000000000003333000000000000000333300000002222222
00330033330000000377003333000000000037703333000000037730033330000000000000333300000000000003333000000000000333333300000002222222
003330333300000003770033330000000000377333330000000333333bbbb3300000000000333330000000000033333000000000003333bbb333333002222222
003333bbbb330000033033bbbb333333330033333bbb3003330033333bbb33300000000003333333000000000033bbb000000000003303bb3333333332222222
0003333bbb333033033333bbbb3333333000033333bb33333000003333333330000000003333b33300000000003bbb3330000000000003333330003302222222
00003333333333330333333333330000000000033333333300000000333333000000000033bbbb33000000000333333330000000000033333300000002222222
00000333333033300000033333300000000000033333333000000033333333000000000033333300000000000333333300000000000033333300000002222222
00000333333000000000033333300000000000033333300000000033333333000000000033333300000000000333333000000000000333333300000002222222
00000333333000000000033333300000000000033333300000000000333333000000000033333300000000000333333000000000000333333000000002222222
00000333333000000000033333330000000000033333330000000000333333000000000033333330000000000333333300000000003333333000000002222222
00003333333300000000033333330000000000033333330000000000333333300000000033333330000000000333333300000000003330333000000002222222
00003333033300000000033303333000000000333303330000000003330333300000000033303333000000000333033300000000033330333600000002222222
00003330033360000000033300333600000000333303336000000003330033360000000033300333600000000333033360000060633360666600000002222222
06063336066660000060633360666600000606333606666000006063336066660000060633360666600000606333666606000006666660000000000002222222
00666666000000000006666660000000000066666600000000000666666000000000006666660000000000066666600000000022222222222222222222222222
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022222222222222222222222222
00000bb0000000000000000000000000000000000011111000111110000001111111100011111111111111111110000001111100011110011111001111111112
000bb77bbb00000000bb000000000000000000000177777100177710000001777777710017777777771177777771000017777710017771017771017777777712
00b6777777b00000bb77bbb00000000bb000000017d711d71017d710000001d7d117d7101d7d7d7d7d11d7d117d710017d717d71017d7101d7d117d7d7d7d712
0b667777777b000b6677777b000000b77bb000017d71017d711d7d100000017d71017d711111d7d111117d71017d7117d71017d711d7dd117d711d7d11111112
0b6777777777b00b6777777b00000b67777b0001ddd101ddd11ddd10000001ddd101ddd10001ddd10001ddd101ddd11ddd101ddd11dddd11ddd11ddddd111002
0b6777777777b0b667777777b000b6777777b001ddd101ddd11ddd10000001ddd101ddd10001ddd10001ddd111ddd11ddd111ddd11ddddd1ddd101ddddddd102
b66777777777b0b667777777b000b6777777b001ddd101ddd11ddd10000001ddd101ddd10001ddd10001dddddddd101ddddddddd11ddd1ddddd100111ddddd12
b6667777777b00b66777777b0000b6676777b001ddd101ddd11ddd11111111ddd101ddd10001ddd10001ddddddd1001ddddddddd11ddd11dddd11111111ddd12
0b667777777b00b66767777b0000b66676bb00001dd11ddd101ddddddddd11ddd11ddd100001ddd10001ddd11ddd101ddd111ddd11ddd11dddd11ddddddddd12
0b66676777b0000b667677b000000bb66b00000001ddddd1001ddddddddd11ddddddd1000001ddd10001ddd101ddd11ddd101ddd11ddd101ddd11dddddddd102
00b6667677b00000b6666b000000000bb00000000011111000111111111111111111100000011111000111110011111111101111111111001111111111111002
000bbb666b0000000bbbb0000000000000000001111111100011111011111111110001111111111bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb222222222222222
000000bbb00000000000000000000000000000017777777100177710177711777100017771177710000000000000000000000000000000000222222222222222
000000bb00000000000000000000000000000001d7d117d71017d7101d7d11d7d100017d7117d71bbbbb00bbbbbb00bbbb00bbbbb00bb000b222222222222222
000bbb77b0000000000bb00000000000000000017d71017d101d7d1117d7117d710001d7d11d7d1bb000b0bb00000bb000b0bb000b0bb000b222222222222222
00b677777b000000bbb77b0000000000bb000001ddd111d1001ddddddddd11ddd10101ddd11ddd1bb000b0bb00000bb000b0bb000b00bb0b0222222222222222
0b67777777b0000b677777b000000bbb77b00001dddddddd101ddddddddd11ddd11d11ddd11ddd1bbbbb00bbbbb00bbbbbb0bb000b00bbbb0222222222222222
0b677777777b00b66777777b0000b677777b0001ddd111ddd11ddd111ddd11ddd1ddd1ddd11ddd1bb000b0bb00000bb000b0bb000b000bb00222222222222222
b66677777777b0b667777777b000b6677777b001ddd1001dd11ddd101ddd11ddddd1ddddd11ddd1bb000b0bb00000bb000b0bb000b000bb00222222222222222
b66767777777b0b666777777b000b6767777b001ddd111ddd11ddd101ddd11dddd101dddd11ddd1bb000b0bbbbbb0bb000b0bbbbb0000bb00222222222222222
b66677777777b0b667677777b000b6677777b001dddddddd101ddd101ddd101dd10001dd101ddd10000000000000000000000000000000000222222222222222
b6667777777b000b6677777b00000b66777b0001111111110011111011111001100000110011111bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb222222222222222
0b666777777b000b6667777b000000b666b00002222222222222222222222222222222222222222bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb222222222222222
0b6666777bb00000b6666bb00000000bbb0000022222222222222222222222222222222222222220000000000000000000000000000000000222222222222222
00bbb666b00000000bbbb00000000000000000022222222222222222222222222222222222222220000000bb000b0bbbbb000bbbb00000000222222222222222
00000bbb000000000000000000000000000000022222222222222222222222222222222222222220000000bbb00b0bb000b0bb000b0000000222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222220000000bbb00b0bb000b0bb00000000000222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222220000000bb0b0b0bbbbb00bb00000000000222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222220000000bb0b0b0bb00000bb00000000000222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222220000000bb00bb0bb00000bb000b0000000222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222220000000bb00bb0bb000000bbbb00000000222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222220000000000000000000000000000000000222222222222222
2222222222222222222222222222222222222222222222222222222222222222222222222222222bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb222222222222222
2222222222222222222222222222222222222222222222222222200d000000002222222222222222222222222222222222222222222222222222222222222222
2222222222222222222222222222222222222222222222222222200dd00000002222222222222222222222222222222222222222222222222222222222222222
222222222222222222222222222222222222222222222222222220ddd000000044dddddddddddddddddddddddddddd2444444444444444444444444444444444
22222222222222222222222222222222222200003770000000b000d7d000000044dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
22222222222222222222222222222222222200003770000000bb00dd7d00000044dddddddddddddd6dddddddddddddddddddddddddddddddddddddddddddddd6
22222222222222222222222222222222222200003330000000bb00ddddd0000044ddddddddddddddddddddddddddd6dddddddddddddddddddddddddddddddddd
22222222222222222222222222222222222200003300000000bb00dddd00000044dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
22222222222222222222222222222222222200003333300000bbb07ddddd000044ddd6dddddddddddddddddddddddddddddddddddd6ddddddddddd6ddddddddd
22222222222222222222222222222222222200003333300000bbb0dddd00000044ddddddddd6ddddddddddd6ddddddddddd6dddddddddddddddddddddddddddd
22222222222222222222222222222222222200003333300000bbb0ddddd0000044dddddddddddddddddddddddddddddddddddddd6ddd6ddd6ddd6ddd6ddd6dd6
22222222222222222222222222222222222200003333300000bbb0d77ddd000044ddddddd6ddd6ddd6ddd6ddd6ddd6ddd6dddd6ddd6ddd6ddd6ddd6ddd6ddd6d
222b000b000b000b000b0022222222222222000033bbbb0000bbb0dd77d00000446ddd6dddd6ddd6ddd6ddd6ddd6ddd6ddd6d6d6d6d6d6d6d6d6d6d6d6d6d6d6
222bb00bb00bb00bb00bb0222222222222220000333bb33000bbb0dddd7d000044dd6ddd6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d
222bbb0bbb0bbb0bbb0bbb2222222222222200003333333033bbb0ddddddd00044d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d666d6666666d6666666d66666
222bb00bb00bb00bb00bb07777777777777700003333333333bbb0dddddddd00446d6d6d666d6666666d6666666d6666666d666d666666d6666666d66666666d
222b000b000b000b000b000000007777777700003333333330bbb0dddddd0000446666666666666d6666666d6666666d66666666666666666666666666666666
22222211110000110000111011111010000000003333330000bbb0dd6dddd0004466d66666666666666666666666666666666666666666666666666666666666
20000010001001001001000010000010000000003333333000bbbdddd66dddd044666666666666666666666666666666666666666666d66666666666666d6666
20000010000110000110000010000010000000003333333000bbbddddd7d000044666666666666666d66666666666d6666666666666666666666666666666666
2bbbbb10000110000110011111100010000000033330333000bbbddddddd77d04d6666d666666666666666666666666666666666666666666666666666666666
20bbb0100001100001100001100000100000000333003336000bbddddddddddd46666666666666666666666666666666666666666666666666d6666666666666
200b00100010010010010001100000000000606333606666000bbddd000000004666666666666666666666666666666666666666666666666666666666666666
20b0001111000011000011101111101000000666666000000000b7d0000000004666666666666666666666666666666666666666666666666666666666666666
20bb000000000d000000000000000004444444444444444444444444444444444666666666666666666666666666666666666666666666666666666666666666
20bbb00700000dd00044444444444444444444444444444444444444444444444666666666666d66666666666666666666666666666666666666666666666666
20bbbb000000ddd000444444444444444449aaaaaaaaaaa9a9999999999999444666666666666666666666666666666666666666666666666666666666666666
20000007000ddd7d004499999999aaa9aaaaaaaaaaaaaaaaaaaaaa9a9a9999444666666666666666666666666666666666666666666666666666666666666666
200b00777000d6d7d044999aa9aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9a9994446666666666666666666666666666d6666666666666666666666666666666666
20bb000700dd6ddd004499a9aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9a99444666666666666666666666666666666666666666666666666666666666666666
2bbb0070700d7dddd0449a9aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa999a9444666666666666666666666666666666666666666666666666666666666666666
20bb000700d7ddddd04499a9aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9a99444666666666666666666666666666666666666666666666666666666666666666
200b0070777d7d7d7d449aaaaaaaaaaaaaaaaabbbbbbbbaaaaaaaaaaaaaaa9444666666666666666666666666666666666666666666666666666666666666666
220000000000000d00449aaaaaaaaaaaaaaabbbbbbbbbbbbaaaaaaaaaaaaa9444666666666666666666666666666666666666666666666666666666666666666
220000000000000dd0449aaaaaaaaaaaaaabbbbbbbbbbbbbbaaaaaaaaaaaa9444666666666666666666666666666666666666666666666666666666666666666
22000000000000d7d0449aaaaaaaaaaaaabbbbbbbbbbbbbbbbaaaaaaaaaaaa444666666666666666666666666666666666666666666666666666666666666666
2200000000000d76d0449aaaaaaaaaaaabbbbbb777777bbbbbbaaaaaaaaaa9444666666666666666666666666666666666666666666666666666666666666666
22000000000000ddd0449aaaaaaaaaaabbbbb7777777777bbbbbaaaaaaaaaa444666666666666666666666666666666666666666666666666666666666666666
2200000000000dddd044aaaaaaaaaaaabbbb777777777777bbbbaaaaaaaaaa444666666666666666766666666666666666666666666666666666666666666666
220000000000d77dd0449aaaaaaaaaabbbbb777777777777bbbbbaaaaaaaaa444666666666666666666666666666676666666666666666666666666666666666
22000000000d77ddd044aaaaaaaaaaabbbb77777777777777bbbbaaaaaaaaa44d666666666666666666666666666666666666666666666666666666666666667
2200000000ddd67dd044aaaaaaaaaaabbbb77777777777777bbbbaaaaaaaaa446666676666666666666666666666666666666666666666666666666666666666
220000000000ddddd044aaaaaaaaaaabbbb77777777777777bbbbaaaaaaaaa446666666666676666666666676666666666666666666666666666666666666666
2200000000ddddddd044aaaaaaaaaaabbbb77777777777777bbbbaaaaaaaaa446666666666666666666666666666666666666666667666666666667666666666
220000000d7dddd7d000aaaaaaaaaaabbbb67777777777777bbbbaaaaaaaaa906666666667666766676667666766676667676666666666666666666666666666
2200000d77dddd77d000aaaaaaaaaaabbbb67777777777777bbbbaaaaaaaaaa06676667666676667666766676667666766666666766676667666766676667667
22000000dddddd7dd000aaaaaaaaaaabbbbb677777777777bbbbbaaaaaaaaaa07666766676767676767676767676767676766676667666766676667666766676
220000dd0dddd7ddd000aaaaaaaaaaaabbbb666777777777bbbbaaaaaaaaaaa07777777777777767676767676767676767676767676767676767676767676767
22000dd0dddd6dddd000aaaaaaaaaaaabbbbb6667777777bbbbbaaaaaaaaaa907777777777777777777777777777777777767676767676767676767676767676
220000d7dd6dddddd000aaaaaaaaaaaaabbbbbb666677bbbbbbaaaaaaaaaaaa07777777777777777777777777777777777777777777777777777777777777777
22000d7dddddd7ddd000aaaaaaaaaaaaaabbbbbbbbbbbbbbbbaaaaaaaaaaa9907777777777777777777777777777777777777777777777777777777777777777
2200dddddddd77ddd0009aaaaaaaaaaaaaabbbbbbbbbbbbbbaaaaaaaaaaa9a907777777777777777777777777777777777777777777777777777777777777777
2200000d7ddd7dddd000aaaaaaaaaaaaaaaabbbbbbbbbbbbaaaaaaaaaaaaa9907777777777777777777777777777777777777777777777777777777777777777
220000d7ddddddddd0009aaaaaaaaaaaaaaaaabbbbbbbbaaaaaaaaaaaaaaa9907777777777777777777777777777777777777777777777777777777777777777
2200d77d77dddddddd009aa9aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9a907777777777777777777777777777777777777777777777777777777777777777
220d77dd7ddddddddd009a999aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9a9907777777777777777777777777777777777777777777777777777777777777777
22dddd0ddddddddddd0099a9aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9a9a99907777777777777777777777777777777777777777777777777777777777777777
220000000ddddddddd009a9a9aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9999999907777777777777777777777777666666666666666666666666666666666666666
220000000000000ddd0099a9a9aaaaaaaaaaaaaaaaaaaaaaaaaaa900000000006666666666666666666666666666666666666d44444444444444444444444444
220000000000000ddd0099999999aaaaaaa9000000000000000000000000000066666666666d4444444444444444444444444444444444444444444444444444
__sfx__
010300000061000631006110060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600
010300000461004631046110060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600
010300000761007631076110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00040000207451c745197351873500700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700
0003000018135191351c1452014500105001050010500105001050010500105001050010500105001050010500105001050010500105001050010500105001050010500105001050010500105001050010500105
0001000018010120100e0100c0100b0100a0100a0100a010090100901009010090100a0100b0100c0100d0100f0101001012010140101501017010190101c0101f01022010260102a0102e01032010370103d010
0001000016010110100d0100b0100a0100901009010090100801008010080100801008010090100a0100b0100c0100d0100f010100101201014010170101a0101d0102001024010280102c01030010350103b010
010200002a61225632216321e6321962215622106220e6220a622096120861207612221221912213122101220f1220d1220c1220a122091220811208112121120c11209112051120311202112011120111201112
010700001855018541185311852118511185111850100500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000000
000400001d0101d01121021270212c021300313002130021300113001130021300113001130021300113000130001300013000130001300013000130001300013000130001300013000130001300010000000000
010200002475024741247412473124731247312473124731247212472124721247212472124721247112471124711247112471124711247112471124711247112470111701007010070100701007010070100701
0103000000620006410062100611180201802118011000000000018000180201802118021180211f0201f0211f0211f0212402024021240212402224022240222402224012240112401124011240112401124001
010400001870000700007000000000000187100000000000000000000000000000000000018710000000000000000000000000003710037110371103711047110671107721097210c7210e71113711187111c701
010200000b5130b5130c5130e52313523195231251312523135231553319533205331b5231b5231d5332153328541215212153122531265412a54126531285312a5312d541305413053130511305030050300503
00080000056100a621086210361101601086100c62109621036110360100601006010060100601006010060100601006010060100601006010060100601006010060100601006010060100601006010060100601
000a00000000000700007000070000000000000000000700000001871000700007000000000700187100000000000000000000000000000000000000000000000000018710000000000000000000001871000000
010500000170001701017010170101701017110171101711017110171101711017110171101711027110271102721027210372103721037210472104721047210572105721077210772109721097310b7310d731
011400002174021721247402d7402d721247402b7402b7412874026740267212474028740007002b7400070000700307503073130721307010070000700007000070000700007000070000700007000070000700
011600002133021311243302833028311243302733027331263302433024311213301f3321f312000001b3321b312000000000000300183121832218312183121830100300003000030000300003000030000300
01100000181100010000100001001a1100010000100001001c1200010000100001001d1220010000100001001f2321f2120010000100212422123221212212022325221232232222122223202001000010000100
010c00000060100611016110061100601006010060100601006010060100601006010060100601006010060100601006010060100601006010060100601006010060100601006010060100601006010060100000
011000000060100611016210162101621006110060100601006010060100601006010060100601006010060100601006010060100601006010060100601006010060100601006010060100601006010060100601
011200000060100611016210261104631036210061100601006010060100601006010060100601006010060100601006010060100601006010060100601006010060100601006010060100601006010060100601
01140000006010061103621066110962107631096410b631066210061100601006010060100601006010060100601006010060100601006010060100601006010060100601006010060100601006010060100601
001000000060100611076210e611106210d6310964113651196311b64115631136410b63107621006110060100601006010060100601006010060100601006010060100601006010060100601006010060100601
010d00000970009711087110771107711077110671105711057110571104711047110472103721037210272102721027210272102721027210173101731017510000000000000000000000000000000000000000
00040000376522c642236521964215652116320d6220c6220b6220b6220a6120a6122c142251321d13218132151222213219132121220e1220c1120a1121a132131320c12208122061120e122091220511202112
00030000326422a6321f6421b63214632106220e6220b62209622076120761207612281321e13216132121220f1220e1121c132161320e1220a12207122061120511205112111220a12206122041120111201112
000200002a63225632216321e6221962215622106220e6220a622096120861207612221221912213122101220f1220d1220c1220a122091220811208112121120c11209112051120311202112011120111201112
__music__
04 51424311
00 41424344
00 41424344
00 41424344
04 52424312


pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

--[[
render layers:
  9: ...
  ~black out everything outside of the view pane~
  10: ...
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
  stand = { 1 },
  pause = { { -1, 10 } },
  bow = { { 2, 10 }, { 3, 30 }, { 2, 10 }, 1 },
  drop = { { 4, 9 }, { 5, 8 } },
  pack_snow = { { 5, 14 }, { 6, 14 } },
  show_snowball = { { 7, 8 }, { 15, 30 } },
  aim = { { 8, 12 }, 9 },
  throw = { { 10, 3 }, 14 },
  dodge = { { 11, 20 } },
  block = { { 12, 30 }, { 13, 20 } }
}

-- effect vars
local game_frames
local freeze_frames
local screen_shake_frames

-- input vars
local buttons
local button_presses

-- entity vars
local entities
local entity_classes = {
  player = {
    sprite = 1,
    animation_queue = nil,
    animation_frames = -1,
    on_animation_done = nil,
    init = function(self)
      self.animation_queue = {}
      self.pane = spawn_entity("snowball_pane", ternary(self.is_first_player, 31, 95), 103, {
        player = self,
        is_visible = true
      })
      self.score = spawn_entity("score", ternary(self.is_first_player, 31, 95), 20, {
        player = self,
        is_visible = true
      })
    end,
    update = function(self)
      -- apply animation
      self:apply_animation()
      local has_pressed_button = btnp2(4, self.player_num, true) or btnp2(5, self.player_num, true)
      if has_pressed_button then
        -- self:animate({ "stand", "pause", "drop", "pack_snow", "pack_snow", "pack_snow", "show_snowball", "aim", "pause", "pause", "block", "stand", "pause", "pause", "aim", "pause", "pause", "throw" })
        self.pane:activate()
      end
    end,
    draw = function(self, x, y)
      -- colorize
      pal(3, ternary(self.is_first_player, 1, 2))
      pal(11, ternary(self.is_first_player, 12, 8))
      -- draw player sprite
      if self.sprite == 14 then
        sspr2(102, 18, 19, 16, x - ternary(self.is_first_player, 7, 11), y + 1, not self.is_first_player)
      elseif self.sprite == 15 then
        sspr2(36, 72, 14, 20, x - ternary(self.is_first_player, 7, 6), y - 3, not self.is_first_player)
      else
        sspr2(17 * ((self.sprite - 1) % 7), 18 * flr((self.sprite - 1) / 7), 17, 18, x - 8, y, not self.is_first_player)
      end
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
        -- set the player's sprite based on the animation data
        local animation = self.animation_queue[1]
        local animation_data = player_animations[animation]
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
  snowball_pane = {
    render_layer = 10,
    cursor_angle = 0,
    init = function(self)
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
    update = function(self)
      self.cursor_angle = (self.cursor_angle + 8 * ternary(self.player.is_first_player, 1, -1)) % 360
      if self.cursor_angle < 0 then
        self.cursor_angle += 360
      end
    end,
    activate = function(self)
      local lump_index = flr((self.cursor_angle + 30) / 60) % 6 + 1
      local lump = self.lumps[lump_index]
      if lump.size > 0 then
        lump.size -= 1
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
      pal()
      pal(11, ternary(is_first, 12, 8))
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
    end,
    draw_color = function(self, x, y, color)
      local is_first = self.player.is_first_player
      pal()
      pal(11, ternary(is_first, 12, 8))
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
  score = {
    wins = 0,
    render_layer = 10,
    draw = function(self, x, y)
      pal(11, 12)
      local i
      for i = 1, 3 do
        if self.wins >= ternary(self.player.is_first_player, i, 4 - i) then
          pal(11, ternary(self.player.is_first_player, 12, 8))
        else
          pal(11, ternary(self.player.is_first_player, 1, 2))
        end
        sspr2(50, 72, 3, 20, x - 13 + 6 * i, y - 10)
      end
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
      if rnd() < self.spawn_rate then
        self:spawn_snowflake()
      end
      -- update all snowflakes
      local i
      for i = 1, #self.snowflakes do
        local snowflake = self.snowflakes[i]
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
        x = rnd_int(-5, 131),
        y = 29,
        sprite = sprite,
        distance_from_camera = distance_from_camera
      })
    end
  },
  title = {
    render_layer = 11,
    draw = function(self, x, y)
      rectfill2(0, 0, 127, 65, 0)
      rectfill2(0, 74, 127, 127)
      draw_bubble_letters_with_shadow({ 8, 7, 1, 11, 9, 6, 2, 2 }, x + 2, y, 13, 1)
      draw_bubble_letters_with_shadow({ 8, 10, 1, 11, 3, 1, 11, 7 }, x, y + 16, 13, 1)
      print2_center("created by bridgs", 64, 122, 1)
      print2_center("player 1", 21, 80, 12)
      if self.frames_alive % 35 < 25 then
        print2_center("press", 21, 90+4, 1)
        print2_center("button", 21, 96+4)
      end
      print2_center("player 2", 107, 80, 8)
      pal(11, 8)
      sspr2(79, 47, 34, 11, 90, 94)
    end
  }
}

function _init()
  -- init vars
  game_frames = 0
  freeze_frames = 0
  screen_shake_frames = 0
  buttons = { {}, {} }
  button_presses = { {}, {} }
  entities = {}
  -- spawn players
  spawn_entity("player", 20, 65, {
    player_num = 1,
    is_first_player = true
  })
  spawn_entity("player", 106, 65, {
    player_num = 2,
    is_first_player = false
  })
  -- foreground snowfall
  spawn_entity("snowfall", 0, 0, {
    min_dist = 0.0,
    max_dist = 0.4,
    spawn_rate = 0.2,
    render_layer = 9
  })
  -- background snowfall
  spawn_entity("snowfall", 0, 0, {
    min_dist = 0.4,
    max_dist = 0.8,
    spawn_rate = 0.3,
    render_layer = 1
  })
  spawn_entity("title", 14, 23)
end

function _update()
  -- keep track of counters
  local game_is_running = freeze_frames <= 0
  freeze_frames = decrement_counter(freeze_frames)
  if game_is_running then
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
  -- update each entity
  local entity
  for entity in all(entities) do
    if entity.is_freeze_frame_immune or game_is_running then
      if decrement_counter_prop(entity, "frames_to_death") then
        entity:die()
      else
        increment_counter_prop(entity, "frames_alive")
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
  -- draw each entity that's within the main view area
  local entity
  for entity in all(entities) do
    if entity.render_layer < 10 and entity.is_visible and entity.frames_alive >= entity.hidden_frames then
      pal()
      entity:draw(entity.x, entity.y)
    end
  end
  -- black out everything outside of the main view area
  pal()
  palt(6, true)
  palt(7, true)
  palt(13, true)
  pal(4, 0)
  sspr2(64, 71, 64, 57, 0, 32) -- snow drifts
  sspr2(64, 71, 64, 57, 63, 32, true) -- snow drifts
  rectfill2(0, 0, 127, 32, 0)
  rectfill2(0, 89, 127, 39)
  -- draw each entity that's outside of the main view area
  for entity in all(entities) do
    if entity.render_layer >= 10 and entity.is_visible and entity.frames_alive >= entity.hidden_frames then
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
0b666777777b000b6667777b000000b666b000022222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
0b6666777bb00000b6666bb00000000bbb0000022222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
00bbb666b00000000bbbb00000000000000000022222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
00000bbb000000000000000000000000000000022222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
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
222222222222222222222222222222222222000033bbbb0000bbb0dd77d00000446ddd6dddd6ddd6ddd6ddd6ddd6ddd6ddd6d6d6d6d6d6d6d6d6d6d6d6d6d6d6
2222222222222222222222222222222222220000333bb33000bbb0dddd7d000044dd6ddd6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d
22222222222222222222222222222222222200003333333033bbb0ddddddd00044d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d666d6666666d6666666d66666
22222222222222222222222222222222222200003333333333bbb0dddddddd00446d6d6d666d6666666d6666666d6666666d666d666666d6666666d66666666d
22222222222222222222222222222222222200003333333330bbb0dddddd0000446666666666666d6666666d6666666d66666666666666666666666666666666
22222222222111100001100001110111110100003333330000bbb0dd6dddd0004466d66666666666666666666666666666666666666666666666666666666666
20000022222100010010010010000100000100003333333000bbbdddd66dddd044666666666666666666666666666666666666666666d66666666666666d6666
20000022222100001100001100000100000100003333333000bbbddddd7d000044666666666666666d66666666666d6666666666666666666666666666666666
2bbbbb22222100001100001100111111000100033330333000bbbddddddd77d04d6666d666666666666666666666666666666666666666666666666666666666
20bbb0222221000011000011000011000001000333003336000bbddddddddddd46666666666666666666666666666666666666666666666666d6666666666666
200b00222221000100100100100011000000606333606666000bbddd000000004666666666666666666666666666666666666666666666666666666666666666
20b0002222211110000110000111011111010666666000000000b7d0000000004666666666666666666666666666666666666666666666666666666666666666
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

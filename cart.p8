pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

--[[
render layers:
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

-- effect vars
local game_frames
local freeze_frames
local screen_shake_frames

-- input vars
local buttons
local button_presses

-- entity vars
local entities
local entity_classes = {}

function _init()
  -- init vars
  game_frames = 0
  freeze_frames = 0
  screen_shake_frames = 0
  buttons = { {}, {} }
  button_presses = { {}, {} }
  entities = {}
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
  for entity in all(entities) do
    if not entity.is_alive then
      del(entities, entity)
    end
  end
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
  cls(bg_color)
  -- draw each entity
  local entity
  for entity in all(entities) do
    if entity.is_visible and entity.frames_alive >= entity.hidden_frames then
      entity:draw(entity.x, entity.y)
      pal()
      fillp()
    end
  end
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

-- generates a random integer between min_val and max_val, inclusive
function rnd_int(min_val, max_val)
  return flr(min_val + rnd(1 + max_val - min_val))
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

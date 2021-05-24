﻿-- (c) eradicator a.k.a lossycrypt, 2017-2021, not seperately licensable

--------------------------------------------------
-- Localised string search for mods.
--
-- Babelfish is a caching translator for standard prototype localisations.
-- When it detects changes in the locale it starts a background task to 
-- translate all prototype names and descriptions. While this task is running
-- a small status indicator in the upper right corner informs each user of 
-- the current progress. Each language only needs to be translated once,
-- making the process instantaneous to most users even in multiplayer.
--
-- @{Introduction.DevelopmentStatus|Module Status}: Work in progress.
--
-- @module Babelfish
-- @usage
--  -- settings.lua
--  erlib_enable_bablefish()
--  -- control.lua
--  remote.call('er:babelfish-remote-interface','find', player_index, word, options)

--[[ Annecdotes:

  I mean, like...srsly? The whole idea of sending network requests to get
  data that each client already has on disk is quite ridiculous ye know...

  ]]

--[[ Future:

  +Detect non-multiplayer language changes. Needs some fancy
  desync-unsafe voodoo magic (which is fine because SP doesn't desync...).
  I don't want to do regular polling just for this...
  
  ]]
  
-- -------------------------------------------------------------------------- --
-- Built-In                                                                   --
-- -------------------------------------------------------------------------- --
local elroot = (pcall(require,'erlib/empty')) and '' or '__eradicators-library__/'
local say,warn,err,elreq,flag,ercfg=table.unpack(require(elroot..'erlib/shared'))

-- -------------------------------------------------------------------------- --
-- Locals / Init                                                              --
-- (Factorio does not allow runtime require!)                                 --
-- -------------------------------------------------------------------------- --
local log         = elreq('erlib/lua/Log'          )().Logger  'Babelfish'
local stop        = elreq('erlib/lua/Error'        )().Stopper 'Babelfish'

local Table       = elreq('erlib/lua/Table'        )()
local Setting     = elreq('erlib/factorio/Setting')()

local Verificate  = elreq('erlib/lua/Verificate'   )()
local verify      = Verificate.verify

local Setting     = elreq('erlib/factorio/Setting' )()
local Locale      = elreq('erlib/factorio/Locale'  )()
local ntuples     = elreq('erlib/lua/Iter/ntuples' )()

-- -------------------------------------------------------------------------- --
-- Constants                                                                  --
-- -------------------------------------------------------------------------- --
local script = EventManager .get_managed_script    'babelfish'
local import = PluginManager.make_relative_require 'babelfish'
local const  = import '/const'
local ident  = serpent.line

-- -------------------------------------------------------------------------- --
-- Module                                                                     --
-- -------------------------------------------------------------------------- --
local Babelfish = {}
local Dictionary = import 'methods/Dictionary'

local StatusIndicator = import 'methods/StatusIndicator'

-- -------------------------------------------------------------------------- --
-- Savedata                                                                   --
-- -------------------------------------------------------------------------- --
local Savedata, DefaultSavedata = nil, {
  players = {}, dicts = {}
  }
PluginManager.manage_savedata  ('babelfish', function(_) Savedata = _ end, DefaultSavedata)
PluginManager.manage_garbage   ('babelfish')
PluginManager.classify_savedata('babelfish', {

  get_pdata = function(self, e, pindex)
    return assert(self.players[pindex or e.player_index])
    end,

  sget_pdata = function(self, e, pindex)
    local pdata = self.players[pindex or e.player_index]
            or self:init_pdata(pindex or e.player_index)
    return pdata, pdata.p end,
  
  init_pdata = function(self, pindex)
    return Table.set(self.players, {pindex}, {
      p = game.players[pindex],
      language_code = nil,
      dict = nil,
      })
    end,
  
  del_pdata = function(self, e, pindex)
    self.players[pindex or e.player_index] = nil
    end,
  
  get_dict = function(self, lcode)
    return assert(self.dicts[lcode]) end,
  
  sget_dict = function(self, lcode)
    return (self.dicts or Table.set(self,{'dicts'},{}))[lcode]
        or Table.set(self.dicts, {lcode}, Dictionary(lcode))
    end,
  
  })
  
-- -------------------------------------------------------------------------- --
-- Conditional Events                                                         --
-- -------------------------------------------------------------------------- --

-- Sometimes an empty event is raised?
-- { migration_applied = false,
--   mod_changes = {},
--   mod_startup_settings_changed = false }
script.on_config(function(e)
  if e and
    ( (table_size(e.mod_changes) > 0)
      or e.migration_applied
      or e.mod_startup_settings_changed )
    then
    -- If any mod changes at all there is no way to know if and how
    -- the locale has changed. Thus we need to start from scratch.
    Table.overwrite(Savedata, Table.dcopy(DefaultSavedata))
    end
  for _, pdata in pairs(Savedata.players) do
    pdata.language_code = nil
    end
  Babelfish.on_player_language_changed()
  end)
  
script.on_load(function(e)
  for _, dict in ntuples(2, Savedata.dicts) do
    Dictionary.reclassify(dict)
    end
  Babelfish.update_handlers()
  end)

-- Manages ALL event de/registration
-- must be ON_LOAD compatible!
Babelfish.update_handlers = function()
  local string_event   = defines.events.on_string_translated
  --
  local update_players = (not not Savedata.changed_players) or nil
  local update_dicts   = (not not Savedata.incomplete_dictionaries) or nil
  --
  if update_players then
    log:info('Translation suspended while waiting for language codes.')
    script.on_event   (string_event  , Babelfish.on_recieve_language_code)
    script.on_nth_tick(            60, Babelfish.on_player_language_changed)
    script.on_nth_tick(             1, nil)
  elseif update_dicts then
    log:info('Translation started.')
    -- Send out translation requests.
    script.on_event   (string_event  , Babelfish.on_recieve_translation)
    script.on_nth_tick(            60, Babelfish.update_status_indicators)
    script.on_nth_tick(             1, Babelfish.request_translations)
  else
    log:info('All translations finished.')
    -- Sleep while nothing is happening.
    script.on_event   (string_event  , nil)
    script.on_nth_tick(            60, nil)
    script.on_nth_tick(             1, nil)
    end
  end
  
  
-- -------------------------------------------------------------------------- --
-- Player Language                                                            --
-- -------------------------------------------------------------------------- --
Babelfish.on_player_language_changed = script.on_event({
  -- Always watch for potential language changes.
  defines.events. on_player_left_game  ,
  defines.events. on_player_created    ,
  defines.events. on_player_joined_game,
  defines.events. on_player_removed    ,
  }, function()
  local changed_players         = {}
  local incomplete_dictionaries = {}
  --
  for pindex, p in pairs(game.players) do
    if not p.connected then
      -- language must be re-evaluated on re-join
      Savedata:del_pdata(nil, pindex)
    else
      local pdata = Savedata:sget_pdata(nil, pindex)
      if (not pdata.language_code) then
        if ((pdata.next_request_tick or 0) <= game.tick) then
          assert(p.request_translation(const.lstring.language_code))
          pdata.next_request_tick = game.tick + const.network.rerequest_delay
          table.insert(changed_players, pindex)
          end
      else
        local dict = Savedata:sget_dict(pdata.language_code)
        pdata.dict = dict -- link
        if dict:needs_translation() then
          incomplete_dictionaries[dict] = p -- need a player to request
          end
        end
      end
    end
  --
  Savedata.changed_players         = Table.nil_if_empty(changed_players)
  Savedata.incomplete_dictionaries = Table.nil_if_empty(incomplete_dictionaries)
  --
  Babelfish.update_handlers()
  end)

-- Wait for the requested language codes.  
Babelfish.on_recieve_language_code = 
  (function(f) return function(e) return e.translated and f(e) end end)
  (function(e)
    if (#e.localised_string == 1)
    and (e.localised_string[1] == const.lstring.language_code[1])
    then
      local pdata = Savedata:sget_pdata(e)
      pdata.language_code = e.result
      pdata.next_request_tick = nil
      Babelfish.on_player_language_changed()
      log:debug(("Player %s's language is %s (%s)."):format(
        pdata.p.name, const.native_language_name[pdata.language_code], pdata.language_code))
      end
  end)

-- -------------------------------------------------------------------------- --
-- Request + Recieve                                                          --
-- -------------------------------------------------------------------------- --
  
-- Push event to dictionary.
Babelfish.on_recieve_translation = function(e)
  Savedata:get_pdata(e).dict
    :push_translation(e.localised_string, e.translated and e.result)
  end

-- on_nth_tick(1)
Babelfish.request_translations = function(e)
  -- In Singleplayer all translation is done during the loading screen.
  local allowed_bytes =
    (game.is_multiplayer() or flag.IS_DEV_MODE)
    and (1024 / 60) * Setting.get_value('map', const.setting_name.network_rate)
    or math.huge
  --
  for dict, p in ntuples(2, Savedata.incomplete_dictionaries) do
    allowed_bytes = allowed_bytes - dict:dispatch_requests(p, allowed_bytes)
    if not dict:needs_translation() then
      Savedata.incomplete_dictionaries[dict] = nil
      end
    if allowed_bytes <= 0 then break end
    end
  --
  if 0 == table_size(Savedata.incomplete_dictionaries) then
    StatusIndicator.destroy_all()
    Babelfish.on_player_language_changed()
    -- print(serpent.block(Savedata.players[1].dict.lookup))
    -- print(serpent.block(Savedata.players[1].dict.requests))
    -- print(serpent.block(Savedata.players[1].dict.open_requests))
    end
  end 

-- -------------------------------------------------------------------------- --
-- Status Indicator                                                           --
-- -------------------------------------------------------------------------- --
Babelfish.update_status_indicators = function(e)
  -- Tooltip shows progress for all languages.
  local tooltip = {}
  for dict in pairs(Savedata.incomplete_dictionaries) do
    table.insert(tooltip, 
      ('\n%3s%% %s'):format(dict:get_percentage(), dict.native_language_name))
    end
  tooltip = {
    'babelfish.status-indicator-tooltip-header',
    Locale.merge(table.unpack(tooltip))
    }
  -- Sprite button shows progress for the owning player.
  for _, p in pairs(game.connected_players) do
    local pdata = Savedata:get_pdata(nil, p.index)
    StatusIndicator.update(p, pdata.dict:get_percentage(), tooltip)
    end
  end

--------------------------------------------------------------------------------
-- Startup.  
-- @section
--------------------------------------------------------------------------------

-------
-- Activates babelfish for all mods. Without this babelfish will
-- not be loaded at all. This must be called in __settings.lua__.
--
-- @usage
--   erlib_enable_bablefish()
-- @function erlib_enable_bablefish
  
--------------------------------------------------------------------------------
-- Remote Interface.  
-- @section
--------------------------------------------------------------------------------

local Remote = {}
remote.add_interface(const.remote.interface_name, Remote)

-------
-- What to search. One of the following strings. This is also the
-- order in which translation occurs.
--
--    'recipe_name'    , 'recipe_description'
--    'item_name'      , 'item_description'
--    'fluid_name'     , 'fluid_description'
--    'technology_name', 'technology_description'
--    'equipment_name' , 'equipment_description'
--    'entity_name'    , 'entity_description'
--    'tile_name'      , 'tile_description'
--
-- @table Babelfish.SearchType

-------
-- Given a user input finds prototype names.
-- Can search the localised name and description of all common prototypes
-- to deliver a native search experience.
--
-- Translation is granular per @{Babelfish.SearchType|SearchType},
-- so users can start searching for i.e. recipe names even if item names
-- are still being translated.
--
-- @tparam NaturalNumber pindex A @{FOBJ LuaPlayer.index}.
-- @tparam string|DenseArray types One or more @{Babelfish.SearchType|SearchTypes}.
-- @tparam string word The user input.
-- @param options (@{table})
-- @tparam[opt=inf] Integer options.limit Search will abort after this many
-- hits and return the (partial) result.
-- @tparam[opt=plain] string options.mode `'plain'`, `'fuzzy'` or `'lua'`.
-- Fuzzy and lua modes both use lua pattern matching, thus if "word" is
-- not a @{string.find} compatible pattern the search result will be empty.
-- 
-- @usage
-- 
--   -- First lets make a shortcut.
--   local babelfind = (function(c) return function(...)
--     return c('er:babelfish-remote-interface','find_prototype_names',...)
--     end end)(remote.call)
--   
--   -- Now lets try something. For demonstration purposes I'm using a player
--   -- with a German locale.
--   local ok, results
--     = babelfind(game.player.index, {'item_name','recipe_name'},'Kupfer')
--   if ok then print(serpent.block(results)) end
--   
--   > {
--   >   item_name = {
--   >     ["copper-cable"] = true,
--   >     ["copper-ore"] = true,
--   >     ["copper-plate"] = true
--   >   },
--   >   recipe_name = {
--   >     ["copper-cable"] = true,
--   >     ["copper-plate"] = true
--   >   }
--   > }
-- 
-- @treturn boolean If Babelfish has not finished translating all of the
-- given types yet this will be false and the result will be nil. Even if some
-- of the given types are already fully translated.
--
-- @treturn table A table mapping each requested type to a @{Types.set|set} of
-- prototype names.
--
-- @function Babelfish.find_prototype_names
function Remote.find_prototype_names(pindex, types, word, options)
  -- Other mod might send index of offline player!
  local pdata = Savedata:sget_pdata(
    nil, verify(pindex, 'NaturalNumber', 'Babelfish: Invalid player index.'))
  if not pdata.dict then return false, nil end
  return pdata.dict:find(Table.plural(types), word, options or {}) end

-- -------------------------------------------------------------------------- --
-- Draft                                                                      --
-- -------------------------------------------------------------------------- --


function Remote.get_player_language(pindex)
  -- For multi-language find()
  error('Not Implemented')
  end

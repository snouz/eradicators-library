-- (c) eradicator a.k.a lossycrypt, 2017-2020, not seperately licensable

--------------------------------------------------
-- Description
--
-- @{Introduction.DevelopmentStatus|Module Status}: Polishing.
--
-- @module Remote
-- @usage
--  local Remote = require('__eradicators-library__/erlib/factorio/Remote')()
  
-- -------------------------------------------------------------------------- --
-- Built-In                                                                   --
-- -------------------------------------------------------------------------- --
local elroot = (pcall(require,'erlib/empty')) and '' or '__eradicators-library__/'
local say,warn,err,elreq,flag,ercfg=table.unpack(require(elroot..'erlib/shared'))

-- -------------------------------------------------------------------------- --
-- Locals / Init                                                              --
-- (Factorio does not allow runtime require!)                                 --
-- -------------------------------------------------------------------------- --

local Hydra = elreq('erlib/lua/Coding/Hydra')()

local log  = elreq('erlib/lua/Log'  )().Logger  'Remote'
local stop = elreq('erlib/lua/Error')().Stopper 'Remote'

local Verificate = elreq('erlib/lua/Verificate')()
local Verify           , Verify_Or
    = Verificate.verify, Verificate.verify_or

local filter_pairs = elreq('erlib/lua/Iter/filter_pairs')()

local Set   = elreq('erlib/lua/Set'  )()
local Table = elreq('erlib/lua/Table')()

local Replicate = elreq('erlib/lua/Replicate')()
local Class     = elreq('erlib/lua/Class'    )()

local Lambda    = elreq('erlib/lua/Lambda'   )()

local Filter    = elreq('erlib/lua/Filter'   )()

-- -------------------------------------------------------------------------- --
-- Module                                                                     --
-- -------------------------------------------------------------------------- --

local Remote,_Remote,_uLocale = {},{},{}



--------------------------------------------------------------------------------
-- PackedInterfaceGroup.
-- @section
--------------------------------------------------------------------------------

----------
-- __Concept.__ A table distributed in parts accross multiple remote interfaces.
--
-- A PackedInterfaceGroup encodes static data into the method names of
-- multiple remote interfaces. One @{key->value} pair is encoded per method.
-- Keys are unique within the group. They can only be written once and can never
-- be removed. The methods themselfs are No-Op dummies.
--
-- A PackedInterfaceGroup object provides read access to the data
-- of an arbitary number of sequentially numbered remote interfaces.
-- Each instance has write access to a single such numbered interface.
--
-- Used to transfer static data between mods before on\_load. For example
-- event names generated by script.generate\_event\_name().
-- 
-- This allows all mods using the same PackedInterfaceGroup name to
-- transparently access each others constants without having to know
-- which mods are installed.
--
-- However you can only read data from mods that were loaded before yours.
-- So if you want to read data from a particular mod you must 
-- __declare an (optional) dependency__ on that mod.
--
-- @table PackedInterfaceGroup



-- -------------------------------------------------------------------------- --
-- PIG Private Api                                                            --
-- -------------------------------------------------------------------------- --

-- Encodes "{key=value}" into a serialized one-key-table.
-- @treturn string data
  local _hydra_opts = {compact=true,nocode=true}
local function _encode (key,value)
  return Hydra.line({[key] = value},_hydra_opts)
  end


-- Decodes a "{key=data}" serialized one-key-table.
-- @return key
-- @return value
local function _decode(data)
  local k, v = next(Hydra.decode(data) or {})
  if (k == nil) or (v == nil) then
    -- Protect from incorrectly formatted garbage.
    stop('Failed to decode PackedInterfaceGroup data:\n',data)
    end
  return k, v
  end

  
-- Decodes and merges all data in a single interface instance.
-- @tparam[opt] string iname Interface Name
-- @tparam[opt] table The interface
-- @treturn table 
local function _decode_interface (iname, interface)
  interface = interface or remote.interfaces[iname]
  Verify(interface, 'NotNil', 'No interface found with that name: "', iname, '".')
  local r = {}
  for data in pairs(interface) do
    rawset(r, _decode(data));
    end
  return r
  end
  

-- Creates a filter_pairs compatible interface name filter.
local function iname_filterer (prefix, ignore_list)
  return Lambda(
    '_, iname -> A(iname) and B(iname)'
    , Filter.false_object_array(ignore_list or  { }  ) -- faster filter first
    , Filter.string_pattern    ('%-%d+$', #prefix + 1) -- ends with "-number"
    )    
  end

  
-- Traverses all interfaces and collects the data into a table.
-- 
-- @tparam string prefix The name prefix of a PackedInterfaceGroup.
-- @tparam DenseArray ignore_list A list of names of interfaces of which
-- no data will be collected even if they exist.
--
-- @treturn MixedTable A table containing the decoded key -> value mappings.
-- 
local function pull_pig_data(prefix, ignore_list)
  local r = {}
  -- do not rely on interface names being properly sequentially numbered
  for iname, interface in filter_pairs(
    remote.interfaces, iname_filterer(prefix, ignore_list)
  ) do
    -- log:debug('PIG <',iname,'>:pull().') -- too verbose
    for k, v in pairs(_decode_interface(nil, interface)) do
      Verify(r[k], 'nil',
        'PIG data has a duplicate key:'
        ,'\n  name= ', iname
        ,'\n  key = ', k
        ,'\n  val1= ', r[k]
        ,'\n  val2= ', v
        )
      r[k] = v
      end
    end
  return r
  end

  
  
-- -------------------------------------------------------------------------- --
-- PIG Public Api                                                             --
-- -------------------------------------------------------------------------- --

----------
-- Create a new PackedInterfaceGroup object instance.
--
-- @tparam string name The name of this group. The same name must be used
-- by all mods that intend to share data.
--
-- @treturn PackedInterfaceGroup
--
-- @function PackedInterfaceGroup
local PackedInterfaceGroup = {}

local _pig_mt = {
  -- read/write is redirected to self.cached_data
  __index = function(self,key)
    return PackedInterfaceGroup[key] --local method overshadows
        or PackedInterfaceGroup.get(self,key)
    end,
  __newindex = function(self,key,value)
    return PackedInterfaceGroup.set(self,key,value)
    end,
  __pairs = function(self)
    return pairs(PackedInterfaceGroup.get_all(self))
    end
  }

setmetatable(PackedInterfaceGroup,{__call=function(_,name)
  -- object
  local pig = {
    prefix      = name, -- The shared prefix of this interface group.
    interface   = {}  , -- The public interface table for this PIG instance.
    cached_data = {}  , -- A local copy of the last seen public data.
                        -- As all keys are write-once-only this is guaranteed
                        -- to never contain outdated data, though it won't
                        -- contain data published after the last update.
    }
  -- find first available name + remember name + register
  local i = 0; repeat i = i + 1
    pig.iname = name .. '-' .. i
    until remote.interfaces[pig.iname] == nil
  remote.add_interface(pig.iname, pig.interface)
  --
  log:debug('PIG <', pig.iname, '> created.')
  return setmetatable(pig,_pig_mt)
  end});


-- Hidden method for internal use only.
function PackedInterfaceGroup:update_cache()
  self.cached_data = pull_pig_data(self.prefix)
  end
  

----------
-- Decodes and returns the value of a key.
-- 
-- @tparam string|number key
-- 
-- @treturn string|number|table|nil Returns nil if there is no such key.
-- 
-- @function PackedInterfaceGroup:get
function PackedInterfaceGroup:get(key,silent)
  -- @tparam boolean silent Hidden internal setting to skip logging nil.
  Verify(key,'NotNil')
  local value = self.cached_data[key]
  -- check remote data if local doesn't know key (yet)
  if value == nil then
    self:update_cache()
    value = self.cached_data[key]
    end
  -- if it's *still* nil at least log it...
  if value == nil and silent ~= true then
    log:debug('PIG <',self.prefix,'>:get("',key,'") returned nil.')
  else
    return Table.dcopy(value) -- don't need to copy nil
    end
  end


----------
-- Decodes and returns all @{key -> value} pairs.
-- 
-- @treturn table
-- 
function PackedInterfaceGroup:get_all()
  self:update_cache()
  return Table.dcopy(self.cached_data)
  end
  
  
----------
-- Encodes the given @{key -> value} mapping and makes it publically accessible.
-- All keys are __writeable only once__. Keys that already have a value
-- can not be altered or deleted.
--
-- Writing the exact same value that the key already maps will be silently ignored.
--
-- @tparam string|number key
-- @tparam string|number|table value 
--
function PackedInterfaceGroup:set(key,value)
  -- Functions in table values are deleted by Hydra.encode().
  -- @future: Should more limits be imposed on value type?
  Verify(key  ,'str|num','Unsupported key data type.'  )
  Verify(value,'str|num|tbl','Unsupported value data type.')
  -- _pig_mt.__index priorizes PIG keys, so proper reading would not be guaranteed.
  Verify(PackedInterfaceGroup[key],'nil','PIG method names can not be used as keys.')
  -- data *must* be up-to-date before checking if value already exists
  self:update_cache()
  -- ignore writing of identical value
  -- error on different value
  -- table value identity is conveniently destroyed by Hydra during update_cache()
  if self.cached_data[key] == nil then
    log:debug('PIG <',self.prefix,'>:set("',key,'",',value,')')
    self.cached_data[key               ] = value
    self.interface  [_encode(key,value)] = ercfg.SKIP
  elseif self.cached_data[key] ~= value then
    stop(
      'PIG key is already in use (by another mod?):'
      ,'\n  name    = ', self.prefix
      ,'\n  key     = ', key
      ,'\n  old_val = ', self.cached_data[key]
      ,'\n  new_val = ', value
      )
  else -- key == value
    log:debug('PIG <',self.prefix,'>:set("',key,'",',value,') skipped, same value already present.')
    end
  end
  

--------------------------------------------------------------------------------
-- Wrapper.
-- @section
--------------------------------------------------------------------------------

--[[------
  Imports a @{FOBJ LuaRemote } interface as a local module.
  Behaves identical to calling the interface manually.
  
  __Syntactic sugar__ for candy lovers.

  @usage
    local Freeplay = Remote.get_interface('freeplay')
  
    -- Native syntax.
    for method_name in pairs(remote.interfaces['freeplay']) do
      print(method_name)
      end
    
    -- Sugar coated syntax.
    for method_name in pairs(Freeplay) do
      print(method_name)
      end
  
    > get_created_items
    > set_created_items
    > get_respawn_items
    > set_respawn_items
    > set_skip_intro
    > set_chart_distance
    > set_disable_crashsite
    > get_ship_items
    > set_ship_items
    > get_debris_items
    > set_debris_items
  
    print(Hydra.lines(Freeplay.get_created_items()))
  
    > {
    >   ["wood"] = 1
    >   ["pistol"] = 1,
    >   ["iron-plate"] = 8,
    >   ["stone-furnace"] = 1,
    >   ["firearm-magazine"] = 10,
    >   ["burner-mining-drill"] = 1,
    >   }

  @tparam string interface_name The name of any remote interface.

  @treturn table The pseudo-module wrapper.
  
]]
function Remote.get_interface(interface_name)
  local remote_call = assert(remote.call)
  return setmetatable({},{
    __index = function(self, key)
      local f = function(...) return remote_call(interface_name, key, ...) end
      rawset(self, key, f)
      return f end,
    __newindex = function(self, key)
      stop(('Can not add method "%s" to remote interface "%s".')
        :format(key, interface_name))
      end,
    __pairs = function()
      return pairs(remote.interfaces[interface_name])
      end,
    })
  end



  

-- -------------------------------------------------------------------------- --
-- Export                                                                     --
-- -------------------------------------------------------------------------- --

Remote.PackedInterfaceGroup = PackedInterfaceGroup

-- -------------------------------------------------------------------------- --
-- End                                                                        --
-- -------------------------------------------------------------------------- --
do (STDOUT or log or print)('  Loaded → erlib.Remote') end
return function() return Remote,_Remote,_uLocale end

-- (c) eradicator a.k.a lossycrypt, 2017-2021, not seperately licensable

--------------------------------------------------
-- Documents some of factorios built-in data-stage functions.
--
-- @{Introduction.DevelopmentStatus|Module Status}: Work in progress.
--
-- @module Wube
-- @usage
--  local Wube = require('__eradicators-library__/erlib/factorio/Wube')()
  
-- -------------------------------------------------------------------------- --
-- Built-In                                                                   --
-- -------------------------------------------------------------------------- --
local elroot = (pcall(require,'erlib/empty')) and '' or '__eradicators-library__/'
local say,warn,err,elreq,flag,ercfg=table.unpack(require(elroot..'erlib/shared'))

-- -------------------------------------------------------------------------- --
-- Eradicators Library                                                        --
-- (Factorio does not allow runtime require!)                                 --
-- -------------------------------------------------------------------------- --

-- -------------------------------------------------------------------------- --
-- Module                                                                     --
-- -------------------------------------------------------------------------- --

local Wube = {
  Util = assert(_ENV.util),
  }

-- -------
-- Nothing.
-- @within Todo
-- @field todo1

--------------------------------------------------------------------------------
-- Circuit.
-- @section
--------------------------------------------------------------------------------

----------
-- (@{number}).
-- @field Wube.default_circuit_wire_max_distance
Wube.default_circuit_wire_max_distance
  = assert(_ENV .default_circuit_wire_max_distance)

----------
-- (@{table}).  
-- The template graphics are in:  
-- `base/graphics/entity/circuit-connector/hr-ccm-universal-04a-base-sequence.png`
-- @table Wube.universal_connector_template
Wube.universal_connector_template
  = assert(_ENV .universal_connector_template)
  
----------
-- (@{table}).
-- Contains the sprites and points generated by base factorio in:  
-- `core/lualib/circuit-connector-generated-definitions.lua`
-- @table Wube.circuit_connector_definitions
Wube.circuit_connector_definitions
  = assert(_ENV .circuit_connector_definitions)
  
----------
-- (@{function}).
-- @tparam table connector_template For examples @{Wube.universal_connector_template}.
-- @tparam table definitions
-- @treturn table A table with two subtables:  
--   `sprites` (@{table}) @{FWIKI Prototype Entity.circuit_connector_sprites}  
--   `points` (@{table}) @{FWIKI Prototype Entity.circuit_wire_connection_point}  
-- @function circuit_connector_definitions.create
do end

----------
-- (@{function}). Erlib Syntactic Sugar.  
-- Calls [circuit\_connector\_definitions.create](./Wube.html#circuit_connector_definitions.create)
-- using the @{Wube.universal_connector_template}, and unpacks the results.
--
-- Variation number is based on the sequence in the template graphics file.
-- Starting at 1 in the upper left corner and incrementing left-to-right, top-to-bottom.
--
-- @usage
--  
--  local sprites, points = Wube.make_universal_circuit_connectors{{
--    variation     = 26,
--    main_offset   = Wube.Util.by_pixel(7, 15.5),
--    shadow_offset = Wube.Util.by_pixel(7, 15.5),
--    show_shadow   = false,                  
--    }}
--
--  local my_prototype = {}
--  my_prototype.circuit_connector_sprites     = sprites
--  my_prototype.circuit_wire_connection_point = points
--
-- @tparam table definitions
-- @treturn table @{FWIKI Prototype Entity.circuit_connector_sprites}  
-- @treturn table @{FWIKI Prototype Entity.circuit_wire_connection_point} 
--   
function Wube.make_universal_circuit_connectors(definitions)
  local r = Wube.circuit_connector_definitions.create(
    Wube.universal_connector_template, definitions)
  return r.sprites, r.points end


--------------------------------------------------------------------------------
-- Pixel.  
-- @section
--------------------------------------------------------------------------------

----------
-- Converts pixels to tiles (32 pixels per tile).
-- @tparam number x in pixels
-- @tparam number y in pixels
-- @treturn table `{x,y}` in tiles
-- @function Util.by_pixel
do end


----------
-- Converts pixels to tiles (64 pixels per tile).
-- @tparam number x in pixels
-- @tparam number y in pixels
-- @treturn table `{x,y}` in tiles
-- @function Util.by_pixel_hr
do end



-- -------------------------------------------------------------------------- --
-- End                                                                        --
-- -------------------------------------------------------------------------- --
do (STDOUT or log or print)('  Loaded → erlib.Wube') end
return function() return Wube,nil,nil end
﻿
local apply_formatting --scoping

local String = require('__eradicators-library__/erlib/lua/String')()

-- localised templates
local lt = {
   
  power_user_setting_description_header = {
    en = 'This is an advanced setting. Be careful when changing it.',
    ja = 'こちらはヘビーユーザー専用の設定です。\\n変更時はご注意ください。',
    de = 'Dies ist eine Power-User Einstellung. Vorsicht beim Ändern.',
    },

  default_value = {
    en = 'Default Value:',
    de = 'Standardwert:',
    ja = 'デフォルト値→',
    }
    
  }
  
local function is_description(entry)
  return entry.header:match('%-?([^%-]+)%]$') == 'description'
  end
  
local function get_description_header(entry)
  return entry.header:gsub('%-name%]',']'):gsub('%]','-description]')
  end
  
local function find_description(entry, db)
  -- [controls] and [controls-description] but
  -- [mod-setting-name] and [mod-setting-description]
  local desc_header = get_description_header(entry)
  --
  for _, dbentry in pairs(db) do
    if  (dbentry.header == desc_header)
    and (dbentry.key    == entry.key  )
    then return dbentry end end
  end
  
-- Takes a string and puts it into the description of the corresponding
-- entry. Generates a new description if there was none.
local function add_description_header(entry, db, msg)
  local desc = find_description(entry, db)
  
  if desc then
  
    local desc_value = String.split(desc.value, '_UL:ENDOFHEADER_')
    assert(#desc_value <= 2, 'Too many headers?!')
    assert(#desc_value >  0, 'No string content?')
    
    -- insert as second-last
    table.insert(desc_value, #desc_value, msg)
    table.insert(desc_value, #desc_value, '_UL:ENDOFHEADER_')
    desc.value = table.concat(desc_value, '')
  
  else
    -- don't forget to format newly generated entries!
    db[#db+1] = apply_formatting({
      header    = get_description_header(entry),
      mod_name  = entry.mod_name ,
      file_name = entry.file_name,
      language  = entry.language ,
      key       = entry.key      ,
      value     = msg .. '_UL:ENDOFHEADER_'
      }, db)
    end  
  end
  
local pattern_functions = {
  -- Array of *ordered* patterns. Can influence each other.


  -- _UL:PowerUserSetting_
  function(entry, db)
  
    local count
    entry.value, count = entry.value:gsub('%s*_UL:PowerUserSetting_%s*','')
    if count > 0 then
      --
      assert(not is_description(entry), 'Power user flag must be in name not description')
      -- Put an icon at the end of the name.
      entry.value = entry.value .. ' _UL:ICON_TOOLTIP_ _UL:ICON_DEV_'
      
      -- Put a warning at the beginning of the description.
      add_description_header(entry, db,
         '_UL:ICON_DEV_[color=blue] '
        .. assert(lt.power_user_setting_description_header[entry.language])
        ..'[/color]\\n')
      
      end
    end,
    
    
  
  -- Inject mod setting default value description.
  function(entry, db)
    if entry.header == '[mod-setting-name]' then
      add_description_header(entry, db, 
        ("_UL:ICON_TOOLTIP_ [color=orange]%s[/color] [color=acid]%s[/color]\\n")
        :format(
          lt.default_value[entry.language],
          -- serpent automatically puts quotes on strings! ;)
          serpent.line(game.mod_setting_prototypes[entry.key].default_value)
          )
        )
      end
    end,

    
    
  -- Fix newline escapes
  -- function(entry, db)
    -- any slash count to one slash in the final output
    -- entry.value = entry.value:gsub('\\+n','\\\\n')
    -- end,

-- -------------------------------------------------------------------------- --
-- !FINAL FIXES!
    
  -- Remove trailing newlines.
  function(entry, db)
    entry.value = entry.value:gsub('_UL:ENDOFHEADER_$',''):gsub('\\n+$','')
    end,
    
  }
  
  
  
local pattern_strings = {

  {'_UL:ICON_DEV_'    , '[img=developer]'},
  {'_UL:ICON_TOOLTIP_', '[img=info]'     },

  --internal use
  {'_UL:ENDOFHEADER_','\\n'},
  
  }


function apply_formatting(entry, db)
  for j=1, #pattern_functions do
    -- Functions may create new locale entries!
    pattern_functions[j](entry, db)
    end
  for j=1, #pattern_strings do
    entry.value = entry.value:gsub(table.unpack(pattern_strings[j]))
    end
  return entry end
  
  
-- All manipulation is in-place.
return function(db)
  
  for i=1, #db do
    apply_formatting(db[i], db)
    end
  
  end
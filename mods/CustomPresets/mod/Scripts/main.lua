local config = require('config')
require('CustomPresets.I18n').configure(config.Language)
if config.Enabled then require('CustomPresets.UI').start(config) end

#!/usr/bin/env bash
set -euo pipefail
plugin_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
# Evaluate the titlebar template while hyprbars is not loaded, as at login
# before HyprPM ran or while the separate hyprpm package is missing.
lua - "$plugin_dir/contrib/hyprbars.lua" <<'LUA'
local configs, rules = {}, 0
hl = {
  plugin = { load = function() end },
  config = function(c) table.insert(configs, c) end,
  window_rule = function(spec)
    for key in pairs(spec) do assert(not key:match('^hyprbars:'), 'hyprbars rule without plugin') end
    rules = rules + 1
    return { set_enabled = function() end }
  end,
}
io.open = function() return {close = function() end} end
dofile(arg[1])
for _, c in ipairs(configs) do
  assert(not (c.plugin and c.plugin.hyprbars), 'hyprbars config without plugin')
end
assert(rules > 0)
omarchy_floating_mode_set_workspace_enabled(1, true, false, false, false, "rgba(00000000)")
omarchy_floating_mode_disable_all_workspace_rules()
LUA
printf 'PASS: template loads without hyprbars and skips titlebar config, rules and buttons\n'

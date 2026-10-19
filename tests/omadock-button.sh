#!/usr/bin/env bash
set -euo pipefail
plugin_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf -- "$test_dir"' EXIT
config_home="$test_dir/config"
state_dir="$test_dir/state"
dock_button_marker="$state_dir/omadock-button"
mkdir -p "$config_home/omarchy/plugins/omadock" "$state_dir"
printf '{}\n' > "$config_home/omarchy/plugins/omadock/manifest.json"
# Exercise the production synchronizer with compositor IPC mocked.
eval "$(sed -n '/^sync_dock_button() {$/,/^}$/p' "$plugin_dir/bin/floating-mode")"
state_file_exists() { [[ -f "$1" ]]; }
truncate_state_file() { : > "$1"; }
hyprctl() { printf '%s\n' "$*" >> "$test_dir/reloads"; [[ ${fail_reload:-false} == false ]]; }
write_config() { printf '%s\n' "$1" > "$config_home/omarchy/shell.json"; }
write_config '{"plugins":[]}'
sync_dock_button
[[ ! -e "$dock_button_marker" && ! -e "$test_dir/reloads" ]]
write_config '{"plugins":[{"id":"omadock"}]}'
sync_dock_button
[[ -f "$dock_button_marker" ]]
sync_dock_button
[[ $(wc -l < "$test_dir/reloads") == 1 ]]
write_config '{broken'
sync_dock_button 2>/dev/null
[[ -f "$dock_button_marker" ]]
write_config '{"plugins":[{"id":"omadock","enabled":false}]}'
sync_dock_button
[[ ! -e "$dock_button_marker" ]]
write_config '{"plugins":[{"id":"omadock"}]}'
fail_reload=true
if sync_dock_button; then echo 'Expected reload failure' >&2; exit 1; fi
[[ ! -e "$dock_button_marker" ]]
fail_reload=false
sync_dock_button
[[ -f "$dock_button_marker" ]]
rm "$config_home/omarchy/plugins/omadock/manifest.json"
sync_dock_button
[[ ! -e "$dock_button_marker" ]]
# Evaluate the complete titlebar template with a mock compositor API.
for enabled in false true; do
  lua - "$plugin_dir/contrib/hyprbars.lua" "$enabled" <<'LUA'
local buttons = {}
hl = {
  plugin = { load = function() end, hyprbars = { add_button = function(b) table.insert(buttons, b) end } },
  config = function() end,
  window_rule = function() return { set_enabled = function() end } end,
}
io.open = function(path)
  assert(path:match('/omarchy%-floating%-mode/omadock%-button$'))
  if arg[2] == 'true' then return {close = function() end} end
end
dofile(arg[1])
assert(#buttons == (arg[2] == 'true' and 3 or 2))
assert(buttons[1].icon == 'X' and buttons[2].icon == '□')
if arg[2] == 'true' then
  assert(buttons[3].icon == '−')
  assert(buttons[3].action == 'omarchy-shell omadock minimizeActive')
end
LUA
done
printf 'PASS: enable/disable, unchanged state, invalid config, missing plugin, reload rollback, button order and action\n'

-- Native titlebars and snapping for Floating Mode. Loaded after Omarchy defaults.
hl.plugin.load([====[@SNAP_PLUGIN_PATH@]====])

hl.config({
  general = {
    -- Native directional resizing for floating windows: sides change only
    -- their matching axis, while corners change width and height together.
    -- The extended grab area keeps thin themed borders easy to hit, and
    -- Hyprland supplies the matching horizontal, vertical or diagonal cursor.
    resize_on_border = true,
    extend_border_grab_area = 12,
    hover_icon_on_border = true,
    resize_corner = 0, -- never force a corner when a side was grabbed

    -- Hyprland's native magnetic snap keeps freely placed windows aligned to
    -- nearby windows and monitor edges without changing their size.
    snap = {
      enabled = true,
      window_gap = 10,
      monitor_gap = 10,
      respect_gaps = true,
    },
  },

  plugin = {
    hyprbars = {
      enabled = false,
      -- Slightly opaque while retaining a hint of the background beneath it.
      bar_color = "rgba(333333c0)",
      bar_height = 30,
      bar_title_enabled = true,
      bar_text_size = 14,
      bar_text_weight = 600,
      bar_text_font = "Sans",
      bar_text_align = "left",
      bar_buttons_alignment = "right",
      bar_part_of_window = true,
      -- Let Hyprland draw one continuous window border around both the
      -- native titlebar decoration and the application surface.
      bar_precedence_over_border = true,
      bar_padding = 8,
      bar_button_padding = 6,
      icon_on_hover = false,
      button_hover_bg_color = "rgba(ffffff24)",
      close_button_hover_bg_color = "rgba(ff4d4d48)",
    },

    -- Aero-style edge and corner zones are implemented in the compositor so
    -- titlebar drags and Super+drag share the same scale-aware geometry.
    omarchy_windows_snap = {
      enabled = true,
      floating_mode_only = true,
      -- "auto" uses three full-height columns above 16:9 and two otherwise.
      -- Set this to "2" or "3" to force the same layout on every monitor.
      columns = "auto",
      edge_threshold = 12,
      corner_ratio = 0.25,
      preview_color = "rgba(1e3a8a33)",
      preview_border_color = "rgba(1d4ed8bd)",
      preview_border_size = 2,
      preview_rounding = 8,
      preview_blur = true,
      preview_animation_duration = 200,
    },
  },
})

-- Apply the final floating geometry while a new tiled window is being mapped,
-- before Hyprland can present a full-work-area tiled frame. The shell helper
-- enables this named rule only while Floating Mode is active. The tag lets the
-- helper retain ownership of these windows and tile only those windows again.
omarchy_floating_mode_open_rule = hl.window_rule({
  name = "floating-mode-open-small",
  match = {
    -- Omarchy's screensaver has its own fullscreen rule. Excluding it keeps
    -- Floating Mode from clearing fullscreen and shrinking it to 70%.
    class = "negative:^org\\.omarchy\\.screensaver$",
    float = false,
  },
  tag = "+floating-mode-managed",
  float = true,
  fullscreen_state = "0 0",
  size = { "monitor_w*0.7", "monitor_h*0.7" },
  center = true,
})
omarchy_floating_mode_open_rule:set_enabled(false)
omarchy_floating_mode_open_no_focus_rule = nil


-- Omarchy deliberately tiles Chromium-based browsers through a dynamic tag
-- rule. While Floating Mode is active, remove that tag so the later tile=true
-- effect cannot undo the initial floating placement. Disabling this rule lets
-- Omarchy restore its normal browser behavior automatically.
omarchy_floating_mode_browser_rule = hl.window_rule({
  name = "floating-mode-disable-browser-tiling",
  match = {
    class = "((google-)?[cC]hrom(e|ium)|[bB]rave-browser|[mM]icrosoft-edge|Vivaldi-stable|helium)",
  },
  tag = "-chromium-based-browser",
})
omarchy_floating_mode_browser_rule:set_enabled(false)

-- Keep newly mapped windows from briefly inheriting the normal active border
-- when the Floating Mode focus border preference is disabled. Match before
-- the managed tag is attached: rules that depend on that tag can only take
-- effect after the first mapping pass and allow one active-border frame.
omarchy_floating_mode_no_focus_rule = nil

function omarchy_floating_mode_set_global_focus_border(enabled, inactive_color)
  if omarchy_floating_mode_no_focus_rule == nil then
    omarchy_floating_mode_no_focus_rule = hl.window_rule({
      name = "floating-mode-no-focus-border",
      match = { class = "negative:^org\\.omarchy\\.screensaver$" },
      tag = "+floating-mode-no-focus",
      border_color = inactive_color,
    })
  end
  omarchy_floating_mode_no_focus_rule:set_enabled(not enabled)
end

function omarchy_floating_mode_set_global_enabled(enabled, focus_border_enabled, inactive_color)
  if omarchy_floating_mode_open_no_focus_rule == nil then
    omarchy_floating_mode_open_no_focus_rule = hl.window_rule({
      name = "floating-mode-open-small-no-focus",
      match = {
        class = "negative:^org\\.omarchy\\.screensaver$",
        float = false,
      },
      tag = "+floating-mode-managed",
      float = true,
      fullscreen_state = "0 0",
      size = { "monitor_w*0.7", "monitor_h*0.7" },
      center = true,
      border_color = inactive_color,
    })
  end
  omarchy_floating_mode_open_rule:set_enabled(enabled and focus_border_enabled)
  omarchy_floating_mode_open_no_focus_rule:set_enabled(enabled and not focus_border_enabled)
  omarchy_floating_mode_browser_rule:set_enabled(enabled)
  omarchy_floating_mode_set_global_focus_border(not enabled or focus_border_enabled, inactive_color)
end

-- Current-workspace scope needs creation-time rules as well. A polling
-- service cannot reliably catch the short interval in which a new window is
-- mapped and tiled. These handles are created lazily for each enabled
-- workspace and make new windows floating before their first frame.
omarchy_floating_mode_workspace_rules = {}

function omarchy_floating_mode_set_workspace_enabled(workspace_id, enabled, focus_border_enabled, transparency_enabled, titlebar_transparency_enabled, inactive_color)
  workspace_id = tonumber(workspace_id)
  if workspace_id == nil or workspace_id ~= math.floor(workspace_id) then return end
  local key = tostring(workspace_id)
  local rules = omarchy_floating_mode_workspace_rules[key]
  if rules == nil then
    local label = key:gsub("%-", "minus")
    rules = {
      open = hl.window_rule({
        name = "floating-mode-open-workspace-" .. label,
        match = {
          class = "negative:^org\\.omarchy\\.screensaver$",
          workspace = key,
          float = false,
        },
        tag = "+floating-mode-managed",
        float = true,
        fullscreen_state = "0 0",
        size = { "monitor_w*0.7", "monitor_h*0.7" },
        center = true,
      }),
      open_no_focus = hl.window_rule({
        name = "floating-mode-open-no-focus-workspace-" .. label,
        match = {
          class = "negative:^org\\.omarchy\\.screensaver$",
          workspace = key,
          float = false,
        },
        tag = "+floating-mode-managed",
        float = true,
        fullscreen_state = "0 0",
        size = { "monitor_w*0.7", "monitor_h*0.7" },
        center = true,
        border_color = inactive_color,
      }),
      browser = hl.window_rule({
        name = "floating-mode-browser-workspace-" .. label,
        match = {
          class = "((google-)?[cC]hrom(e|ium)|[bB]rave-browser|[mM]icrosoft-edge|Vivaldi-stable|helium)",
          workspace = key,
        },
        tag = "-chromium-based-browser",
      }),
      no_focus = hl.window_rule({
        name = "floating-mode-no-focus-border-workspace-" .. label,
        match = {
          class = "negative:^org\\.omarchy\\.screensaver$",
          workspace = key,
        },
        tag = "+floating-mode-no-focus",
        border_color = inactive_color,
      }),
      opaque = hl.window_rule({
        name = "floating-mode-opaque-workspace-" .. label,
        match = {
          tag = "floating-mode-managed",
          workspace = key,
        },
        opacity = "1.0 override 1.0 override",
      }),
      titlebar_transparent = hl.window_rule({
        name = "floating-mode-titlebar-transparent-workspace-" .. label,
        match = {
          tag = "floating-mode-managed",
          workspace = key,
        },
        ["hyprbars:bar_color"] = "rgba(333333c0)",
      }),
      titlebar_opaque = hl.window_rule({
        name = "floating-mode-titlebar-opaque-workspace-" .. label,
        match = {
          tag = "floating-mode-managed",
          workspace = key,
        },
        ["hyprbars:bar_color"] = "rgba(333333ff)",
      }),
    }
    omarchy_floating_mode_workspace_rules[key] = rules
  end
  rules.open:set_enabled(enabled and focus_border_enabled)
  rules.open_no_focus:set_enabled(enabled and not focus_border_enabled)
  rules.browser:set_enabled(enabled)
  rules.no_focus:set_enabled(enabled and not focus_border_enabled)
  rules.opaque:set_enabled(enabled and not transparency_enabled)
  rules.titlebar_transparent:set_enabled(enabled and titlebar_transparency_enabled)
  rules.titlebar_opaque:set_enabled(enabled and not titlebar_transparency_enabled)
end

function omarchy_floating_mode_disable_all_workspace_rules()
  for _, rules in pairs(omarchy_floating_mode_workspace_rules) do
    rules.open:set_enabled(false)
    rules.open_no_focus:set_enabled(false)
    rules.browser:set_enabled(false)
    rules.no_focus:set_enabled(false)
    rules.opaque:set_enabled(false)
    rules.titlebar_transparent:set_enabled(false)
    rules.titlebar_opaque:set_enabled(false)
  end
end

function omarchy_floating_mode_disable_workspace_rules(workspace_id)
  workspace_id = tonumber(workspace_id)
  if workspace_id == nil or workspace_id ~= math.floor(workspace_id) then return end
  local rules = omarchy_floating_mode_workspace_rules[tostring(workspace_id)]
  if rules == nil then return end
  rules.open:set_enabled(false)
  rules.open_no_focus:set_enabled(false)
  rules.browser:set_enabled(false)
  rules.no_focus:set_enabled(false)
  rules.opaque:set_enabled(false)
  rules.titlebar_transparent:set_enabled(false)
  rules.titlebar_opaque:set_enabled(false)
end

-- Optional fully opaque rendering for every window while Floating Mode is on.
omarchy_floating_mode_opaque_rule = hl.window_rule({
  name = "floating-mode-opaque-windows",
  -- Limit the override to windows owned by Floating Mode. In per-workspace
  -- scope, tiled windows on other workspaces keep their normal opacity.
  match = { tag = "floating-mode-managed" },
  opacity = "1.0 override 1.0 override",
})
omarchy_floating_mode_opaque_rule:set_enabled(false)

-- Dynamic tags added by mapping rules otherwise survive after a window is
-- restored to tiling. Remove both ownership and focus-suppression state so
-- Hyprland falls back to the current theme's complete border gradient.
hl.window_rule({
  name = "floating-mode-clear-managed-tag-on-tiled-windows",
  match = { float = false },
  tag = "-floating-mode-managed",
})
hl.window_rule({
  name = "floating-mode-clear-no-focus-tag-on-tiled-windows",
  match = { float = false },
  tag = "-floating-mode-no-focus",
})

-- Buttons are declared right-to-left: close, then maximize.
hl.plugin.hyprbars.add_button({
  bg_color = "rgba(00000000)",
  fg_color = "rgba(ffffffff)",
  size = 21,
  icon = "X",
  action = [[hyprctl dispatch 'hl.dsp.window.close({})']],
})

-- A maximized floating window fills the work area, so its decorative border
-- adds no useful separation. This dynamic rule restores the normal themed
-- border automatically as soon as the window leaves maximized state.
hl.window_rule({
  name = "floating-mode-maximized-no-border",
  match = {
    float = true,
    fullscreen_state_internal = 1,
  },
  border_size = 0,
})

hl.plugin.hyprbars.add_button({
  bg_color = "rgba(00000000)",
  fg_color = "rgba(ffffffff)",
  size = 21,
  icon = "□",
  action = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
})

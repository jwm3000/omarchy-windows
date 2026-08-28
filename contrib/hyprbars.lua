-- Native titlebars and snapping for Floating Mode. Loaded after Omarchy defaults.
hl.plugin.load([====[@SNAP_PLUGIN_PATH@]====])

hl.config({
  general = {
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

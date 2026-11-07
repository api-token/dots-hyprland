-- Minimal config for the nested Hyprland that bench/run starts. It only hosts the shell under
-- test, so keep it free of user settings: results must not depend on ~/.config/hypr.
hl.config({
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
    },
})

-- Minimal Hyprland used only as the compositor for the Kairos greeter.
-- Runs as the "greeter" user; nothing from the desktop session is loaded.

hl.config({
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        force_default_wallpaper = 0,
        background_color = "rgb(000000)",
    },
    animations = {
        enabled = false,
    },
})

-- Start the greeter. When it exits (after handing the login to greetd), close this
-- compositor so greetd can start the real session.
hl.on("hyprland.start", function()
    hl.exec_cmd("qs -p /usr/share/kairos-greeter; hyprctl dispatch exit || pkill -x -u greeter Hyprland")
end)

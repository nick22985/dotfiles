require("theme.mocha")
require("conf.env")
require("conf.monitor")
require("conf.autostart")
require("conf.windowrule")
require("conf.looknfeel")
require("conf.input")
require("conf.bindings")
require("conf.apps")

hl.config({
	debug = {
		disable_logs = true,
		enable_stdout_logs = false,
	},
})

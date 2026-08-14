-- Monitors + workspace-to-monitor bindings.
-- Converted from conf/monitor.conf.

hl.monitor({ output = "desc:Samsung Electric Company Odyssey G95NC HNTX400116", mode = "7680x2160@60", position = "0x0",      scale = 1 })
hl.monitor({ output = "desc:LG Electronics LG ULTRAGEAR 107NTQD1V116",          mode = "2560x1440@60", position = "0x-1440",   scale = 1 }) -- left
hl.monitor({ output = "desc:LG Electronics LG ULTRAGEAR 106NTGYDZ367",          mode = "2560x1440@60", position = "2560x-1440", scale = 1 }) -- middle
hl.monitor({ output = "desc:LG Electronics LG ULTRAGEAR 107NTNH1W367",          mode = "2560x1440@60", position = "5120x-1440", scale = 1 }) -- right
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

hl.workspace_rule({ workspace = "10", monitor = "desc:LG Electronics LG ULTRAGEAR 107NTNH1W367", default = true })  -- Slack
hl.workspace_rule({ workspace = "9",  monitor = "desc:LG Electronics LG ULTRAGEAR 107NTNH1W367", default = false }) -- Discord
hl.workspace_rule({ workspace = "1",  monitor = "desc:Samsung Electric Company Odyssey G95NC HNTX400116", default = true })
hl.workspace_rule({ workspace = "2",  monitor = "desc:LG Electronics LG ULTRAGEAR 107NTQD1V116", default = true })
hl.workspace_rule({ workspace = "3",  monitor = "desc:LG Electronics LG ULTRAGEAR 106NTGYDZ367", default = true })
hl.workspace_rule({ workspace = "4",  monitor = "desc:LG Electronics LG ULTRAGEAR 107NTNH1W367", default = true })

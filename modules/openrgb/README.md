# OpenRGB

`openrgb.service` (a user unit) runs `openrgb --server` and holds every lighting controller: the Commander Core, Commander PRO, Mystic Light and the RAM. hypridle calls `rgb-lights off` when it dims the display and `rgb-lights on` when it comes back; `rgb-lights` loads the OpenRGB profile of that name through the server.

## Profiles

`rgb-lights setup` saves both, and the module runs it when either is missing: `off` puts every device in black in Static or Direct mode, or in mode Off (the Sapphire GPU ignores Off), and `on` in its first rainbow mode (Rainbow Wave, Spectrum Cycle, ...). A device without one (the Commander Core, keyboard, mouse) gets a static rainbow across its LEDs in Direct mode; one without Direct either is left out of `on` and listed with the modes it has.

For other lighting, set it in the OpenRGB GUI (stop the server first: `systemctl --user stop openrgb`) and save it as `on`; apply won't overwrite it.

OpenRGB 1.x saves them as `~/.config/OpenRGB/profiles/on.json` and `off.json`, and takes the bare name (`--profile off`); a name ending in `.orp` gets saved as `off.orp.json`. The server loads `on` when it starts.

## Motherboard ignores everything

OpenRGB detects the MSI Z790 Carbon (MS-7D89, Mystic Light 185-byte) but no mode or colour reaches it, with or without the server, and nothing is logged. Its LEDs stay on through `off`; turn them off with EZ LED Control in the BIOS instead.

## RAM not detected

The RAM is on the SMBus, which needs the `i2c-dev` module (`/etc/modules-load.d/i2c-dev.conf`):
```
ls -l /dev/i2c-*                 # should exist and grant you access through the OpenRGB udev rules
sudo i2cdetect -l                # the SMBus I801 adapter should be listed
```
A cold boot sometimes helps the first detection. Then restart the server.

## Check it

```
rgb-lights off; sleep 3; rgb-lights on
journalctl --user -u openrgb     # what the server detected
```

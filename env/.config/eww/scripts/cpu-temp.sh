#!/bin/bash
# CPU package temperature in whole °C, from hwmon (k10temp/coretemp/zenpower),
# falling back to the ACPI thermal zone.

for hwmon in /sys/class/hwmon/hwmon*; do
    case "$(cat "$hwmon/name" 2>/dev/null)" in
        k10temp|coretemp|zenpower)
            if [[ -r "$hwmon/temp1_input" ]]; then
                echo $(( $(cat "$hwmon/temp1_input") / 1000 ))
                exit 0
            fi
            ;;
    esac
done

for zone in /sys/class/thermal/thermal_zone*; do
    if [[ "$(cat "$zone/type" 2>/dev/null)" == "acpitz" ]]; then
        echo $(( $(cat "$zone/temp") / 1000 ))
        exit 0
    fi
done

echo 0

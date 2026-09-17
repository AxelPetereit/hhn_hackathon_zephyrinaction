#!/bin/bash
YAML=~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/hss-payload.yaml
sed -i 's|/home/administrator/|/home/m77107/|g' "$YAML"
echo "Updated YAML:"
grep "zephyr.elf" "$YAML"

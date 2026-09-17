#!/bin/bash
source ~/.zephyrenv/bin/activate
pip install -r ~/zephyr/zephyr/scripts/requirements.txt 2>&1 | grep -E "error|Error|Failed|Collecting|Installing" | head -30
echo "EXIT: $?"

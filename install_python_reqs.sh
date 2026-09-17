#!/bin/bash
set -e

source ~/.zephyrenv/bin/activate

echo "Installing Zephyr Python requirements..."
pip install -r ~/zephyr/zephyr/scripts/requirements.txt
echo "PYTHON_REQS_OK"

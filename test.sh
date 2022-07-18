#!/usr/bin/env bash
resty --shdict 'test 1m' -e "require 'busted.runner' ({ standalone = false })"

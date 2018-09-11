#!/bin/bash

set -e

iptables-save | grep 'default/kubernetes:https'

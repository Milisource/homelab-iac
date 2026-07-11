#!/bin/bash
# DNS health check for Keepalived VRRP failover
# Tests if local DNS resolver (AdGuard/Unbound) is responding
dig +short @127.0.0.1 localhost A >/dev/null 2>&1

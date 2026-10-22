#!/bin/zsh
# Fails if the binary links or calls any networking API. Snug has no reason to touch the network.
set -euo pipefail
bin=$1
if otool -L "$bin" | grep -Ei 'Network.framework|CFNetwork'; then
    echo "FAIL: networking framework linked"; exit 1
fi
if nm -u "$bin" | grep -Ei 'URLSession|NSURLConnection|NSURLRequest|CFSocket|CFStream|_socket$|_connect$|_nw_|_getaddrinfo$|WebKit'; then
    echo "FAIL: networking symbol referenced"; exit 1
fi
echo "no-network check passed"

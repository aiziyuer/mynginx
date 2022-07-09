


local socks5 = require('resty.socks5')


-- original:
-- curl -kv --socks5 127.0.0.1:1080 https://8.8.8.8

-- test:
-- curl -kv https://127.0.0.1 -H 'Host: 8.8.8.8'

-- ngx.req.set_header("Host", '8.8.8.8')


-- curl --http1.1 -kv --socks5-hostname 127.0.0.1:1080 https://dns.google.com
-- curl -kv https://127.0.0.1 -H 'Host: dns.google.com'

socks5.handle_request("127.0.0.1", 1080)

return
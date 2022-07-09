


local socks5 = require('resty.socks5')


-- original:
-- curl -kv --socks5 127.0.0.1:7890 https://8.8.8.8

-- test:
-- curl -kv https://127.0.0.1 -H 'Host: 8.8.8.8'

-- ngx.req.set_header("Host", '8.8.8.8')

socks5.handle_request("127.0.0.1", 7890)

return
万能网关
---


``` bash

# 自颁发证书
mkdir -p conf/cert.d
openssl genrsa -out conf/cert.d/server.key 1024
openssl req -new -x509 -days 3650 -key conf/cert.d/server.key \
                                  -out conf/cert.d/server.crt \
                                  -subj '//C=CN/C=CN/ST=ZJ/L=HZ/O=Aiziyuer/OU=dev/CN=moyi-lc.com/emailAddress=ziyu0123456789@gmail.com'

```
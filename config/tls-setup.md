# TLS & Certificate Authority Setup (Task E)

Commands executed on Mac 2 to create the private Certificate Authority (CA) and issue the SSL/TLS server certificate for `app.admv.test` and `api.admv.test`.

## 1. Directory and Tool Setup
```bash
OSSL=$(brew --prefix openssl@3)/bin/openssl
mkdir -p ~/team1-pki && cd ~/team1-pki
```

## 2. Step 1: Root Certificate Authority (CA)
```bash
$OSSL genrsa -out ca.key 4096
$OSSL req -x509 -new -key ca.key -sha256 -days 365 -out ca.crt \
  -subj "/CN=admv Local CA" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"
```

## 3. Step 2: Server Key and Certificate Signing Request (CSR)
```bash
$OSSL genrsa -out server.key 2048
$OSSL req -new -key server.key -out server.csr -subj "/CN=app.admv.test"
```

## 4. Step 3: Extensions File (SAN)
```bash
cat > server.ext <<'EOT'
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:app.admv.test,DNS:api.admv.test
EOT
```

## 5. Step 4: CA Signs Server Certificate
```bash
$OSSL x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out server.crt -days 365 -sha256 -extfile server.ext
```

## 6. Step 5: Verification
```bash
$OSSL verify -CAfile ca.crt server.crt
$OSSL x509 -in server.crt -noout -subject -issuer -dates -ext subjectAltName
```

## 7. Step 6: Deploy to Nginx
```bash
mkdir -p $(brew --prefix)/etc/nginx/certs
cp server.crt server.key $(brew --prefix)/etc/nginx/certs/
chmod 600 $(brew --prefix)/etc/nginx/certs/server.key
```

## 8. Client Trust (Task E.2)
```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain ca.crt
```

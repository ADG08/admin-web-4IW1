#!/bin/bash

BASEDIR="$(cd "$(dirname "$0")" && pwd)"

apt update
apt install -y apache2 mariadb-server php php-{gd,zip,curl,xml,mysql,mbstring} unzip openssl

unzip -d /var/www/ "$BASEDIR/dolibarr.zip"
unzip -d /var/www/ "$BASEDIR/glpi.zip"

mv /var/www/dolibarr-* /var/www/dolibarr 2>/dev/null
mv /var/www/glpi-* /var/www/glpi 2>/dev/null

chown -R www-data:www-data /var/www/dolibarr /var/www/glpi

mysql_secure_installation

mysql <<EOF
CREATE DATABASE dolibarr;
CREATE USER 'dolibarr'@'localhost' IDENTIFIED BY 'doli';
GRANT ALL PRIVILEGES ON dolibarr.* TO 'dolibarr'@'localhost';

CREATE DATABASE glpi;
CREATE USER 'glpi'@'localhost' IDENTIFIED BY 'glpi';
GRANT ALL PRIVILEGES ON glpi.* TO 'glpi'@'localhost';

FLUSH PRIVILEGES;
EOF

mkdir -p /etc/ssl/myCA && cd /etc/ssl/myCA

# CA KEY
openssl genpkey -algorithm RSA -out root_ca.key -pkeyopt rsa_keygen_bits:4096 -aes256

# CA CERT
openssl req -x509 -new -key root_ca.key -sha256 -days 120 -out root_ca.pem

# GLPI : Private key
openssl genpkey -algorithm RSA -out glpi.key -pkeyopt rsa_keygen_bits:2048 -aes256
openssl req -new -key glpi.key -out glpi.csr
openssl x509 -req -in glpi.csr -CA root_ca.pem -CAkey root_ca.key -CAcreateserial -out glpi.crt -days 365 -sha256

# DOLIBARR : Private key
openssl genpkey -algorithm RSA -out dolibarr.key -pkeyopt rsa_keygen_bits:2048 -aes256
openssl req -new -key dolibarr.key -out dolibarr.csr
openssl x509 -req -in dolibarr.csr -CA root_ca.pem -CAkey root_ca.key -CAcreateserial -out dolibarr.crt -days 365 -sha256

a2enmod ssl

# GLPI CONF
cp /etc/apache2/sites-available/default-ssl.conf /etc/apache2/sites-available/glpi.conf
sed -i "s|DocumentRoot .*|DocumentRoot /var/www/glpi|" /etc/apache2/sites-available/glpi.conf
sed -i "s|SSLCertificateFile .*|SSLCertificateFile /etc/ssl/myCA/glpi.crt|" /etc/apache2/sites-available/glpi.conf
sed -i "s|SSLCertificateKeyFile .*|SSLCertificateKeyFile /etc/ssl/myCA/glpi.key|" /etc/apache2/sites-available/glpi.conf
sed -i "s|#ServerName .*|ServerName glpi.local|" /etc/apache2/sites-available/glpi.conf

# DOLIBARR CONF
cp /etc/apache2/sites-available/default-ssl.conf /etc/apache2/sites-available/dolibarr.conf
sed -i "s|DocumentRoot .*|DocumentRoot /var/www/dolibarr/htdocs|" /etc/apache2/sites-available/dolibarr.conf
sed -i "s|SSLCertificateFile .*|SSLCertificateFile /etc/ssl/myCA/dolibarr.crt|" /etc/apache2/sites-available/dolibarr.conf
sed -i "s|SSLCertificateKeyFile .*|SSLCertificateKeyFile /etc/ssl/myCA/dolibarr.key|" /etc/apache2/sites-available/dolibarr.conf
sed -i "s|#ServerName .*|ServerName dolibarr.local|" /etc/apache2/sites-available/dolibarr.conf

a2ensite glpi.conf
a2ensite dolibarr.conf

htpasswd -cb /etc/apache2/.htpasswd admin admin

cat >> /etc/apache2/apache2.conf <<EOF

<Directory /var/www/html>
    AuthType Basic
    AuthName "Restricted Access"
    AuthBasicProvider file
    AuthUserFile /etc/apache2/.htpasswd
    Require valid-user
</Directory>
EOF

systemctl reload apache2

echo -e "\e[32m✅ Déploiement terminé !\e[0m"
echo "➡️  https://glpi.local"
echo "➡️  https://dolibarr.local"

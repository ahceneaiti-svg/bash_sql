FROM mysql:8.4

ENV MYSQL_DATABASE=ecommerce

COPY init.sql /docker-entrypoint-initdb.d/init.sql
COPY sql/ /usr/local/share/sql/
COPY update_abandonnes.sh /usr/local/bin/update_abandonnes.sh
RUN chmod +x /usr/local/bin/update_abandonnes.sh

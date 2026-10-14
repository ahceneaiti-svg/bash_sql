FROM mysql:8.4

ENV MYSQL_DATABASE=ecommerce

COPY init.sql /docker-entrypoint-initdb.d/init.sql
COPY sql/ /usr/local/share/sql/
COPY select_update.sh /usr/local/bin/select_update.sh
RUN chmod +x /usr/local/bin/select_update.sh

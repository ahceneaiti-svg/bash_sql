FROM mysql:8.4

ENV MYSQL_DATABASE=ecommerce

COPY init.sql /docker-entrypoint-initdb.d/init.sql
COPY init_user.sh /docker-entrypoint-initdb.d/init_user.sh
COPY sql/ /usr/local/share/sql/
COPY select_update.sh /usr/local/bin/select_update.sh
RUN chmod +x /usr/local/bin/select_update.sh

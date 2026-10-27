FROM redmine:7.0.2

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential pkg-config libsqlite3-dev libyaml-dev libxml2-dev libxslt1-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/redmine

RUN printf 'development:\n  adapter: sqlite3\n  database: sqlite/development.sqlite3\ntest:\n  adapter: sqlite3\n  database: sqlite/test.sqlite3\n' > config/database.yml \
 && bundle config unset without \
 && bundle install --jobs 4

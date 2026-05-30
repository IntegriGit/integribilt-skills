# db-check

Database health, query analysis, and schema review.

## What I do
I connect to the IntegriBilt databases and run health checks: connection counts, slow queries, index usage, table sizes, replication lag, and schema drift. I support PostgreSQL, MySQL, MongoDB, Redis, and SQLite.

## How to use me
Name the database or connection string you want checked. I will run diagnostics and report any issues with recommended fixes.

## Tools I use
- postgres MCP for PostgreSQL (integribilt DB at postgres:5432)
- mysql MCP for MySQL/MariaDB
- mongodb MCP for MongoDB
- redis MCP for Redis cache health
- sqlite MCP for SQLite files

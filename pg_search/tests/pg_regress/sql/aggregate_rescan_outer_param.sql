-- Tests that the Tantivy Aggregate Scan declares the Params of its search query, so a
-- Hash Join above it rebuilds its hash table when an outer value changes (#6639).
CREATE EXTENSION IF NOT EXISTS pg_search;

SET max_parallel_workers_per_gather = 0;
SET paradedb.enable_aggregate_custom_scan = on;
-- Make the planner hash the Aggregate Scan inside the correlated subquery.
SET enable_nestloop = off;

DROP TABLE IF EXISTS rescan_items;
CREATE TABLE rescan_items (id INT PRIMARY KEY, account INT, rating INT);
-- Account 1 has three rows, account 2 has one row.
INSERT INTO rescan_items VALUES (1, 1, 4), (2, 1, 5), (3, 1, 5), (4, 2, 5);
CREATE INDEX rescan_items_idx ON rescan_items USING paradedb (id, account, rating);

-- The outer value is in a heap filter of the search query.
EXPLAIN (COSTS OFF)
SELECT o.a,
       (SELECT SUM(g.n)
        FROM (VALUES (4), (5)) AS t (rating)
        JOIN (SELECT rating, COUNT(*) AS n
              FROM rescan_items
              WHERE account = o.a AND id @@@ paradedb.all()
              GROUP BY rating) AS g USING (rating)) AS n
FROM (VALUES (1), (2), (99)) AS o (a)
ORDER BY o.a;

SELECT o.a,
       (SELECT SUM(g.n)
        FROM (VALUES (4), (5)) AS t (rating)
        JOIN (SELECT rating, COUNT(*) AS n
              FROM rescan_items
              WHERE account = o.a AND id @@@ paradedb.all()
              GROUP BY rating) AS g USING (rating)) AS n
FROM (VALUES (1), (2), (99)) AS o (a)
ORDER BY o.a;

-- The outer value is an argument of a search function.
SELECT o.a,
       (SELECT SUM(g.n)
        FROM (VALUES (4), (5)) AS t (rating)
        JOIN (SELECT rating, COUNT(*) AS n
              FROM rescan_items
              WHERE account @@@ paradedb.term('account', o.a)
              GROUP BY rating) AS g USING (rating)) AS n
FROM (VALUES (1), (2), (99)) AS o (a)
ORDER BY o.a;

-- The outer value is only in the FILTER of an aggregate. Without GROUP BY, the plan
-- replaces its Aggrefs, so the plan's target list no longer shows the FILTER.
EXPLAIN (COSTS OFF)
SELECT o.a,
       (SELECT t.n
        FROM (VALUES (1), (2), (3)) AS t (n)
        JOIN (SELECT COUNT(*) FILTER (WHERE account = o.a) AS n
              FROM rescan_items
              WHERE id @@@ paradedb.all()) AS g USING (n)) AS n
FROM (VALUES (1), (2), (99)) AS o (a)
ORDER BY o.a;

SELECT o.a,
       (SELECT t.n
        FROM (VALUES (1), (2), (3)) AS t (n)
        JOIN (SELECT COUNT(*) FILTER (WHERE account = o.a) AS n
              FROM rescan_items
              WHERE id @@@ paradedb.all()) AS g USING (n)) AS n
FROM (VALUES (1), (2), (99)) AS o (a)
ORDER BY o.a;

-- Postgres gives the same results without the Aggregate Scan.
SET paradedb.enable_aggregate_custom_scan = off;
SELECT o.a,
       (SELECT SUM(g.n)
        FROM (VALUES (4), (5)) AS t (rating)
        JOIN (SELECT rating, COUNT(*) AS n
              FROM rescan_items
              WHERE account = o.a AND id @@@ paradedb.all()
              GROUP BY rating) AS g USING (rating)) AS n
FROM (VALUES (1), (2), (99)) AS o (a)
ORDER BY o.a;

RESET paradedb.enable_aggregate_custom_scan;
RESET enable_nestloop;
RESET max_parallel_workers_per_gather;
DROP TABLE rescan_items;

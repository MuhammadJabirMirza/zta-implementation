-- Run on BOTH source and target; outputs must match exactly (Day 12 evidence).
USE legacyapp;
SELECT "customers" AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL
SELECT "orders", COUNT(*) FROM orders;
CHECKSUM TABLE customers, orders;

-- =========================================
-- 01_load_bronze.sql
-- Load raw CSVs into Bronze tables (all columns as text, no cleaning)
-- =========================================

CREATE SCHEMA IF NOT EXISTS workspace.bronze;

-- Customers
CREATE OR REPLACE TABLE workspace.bronze.customers AS
SELECT *
FROM read_files(
  '/Volumes/workspace/bronze/raw_files/customers(in).csv',
  format => 'csv', sep => ';', header => true, inferColumnTypes => false
);

-- Orders
CREATE OR REPLACE TABLE workspace.bronze.orders AS
SELECT *
FROM read_files(
  '/Volumes/workspace/bronze/raw_files/orders(in).csv',
  format => 'csv', sep => ';', header => true, inferColumnTypes => false
);

-- Subscriptions
CREATE OR REPLACE TABLE workspace.bronze.subscriptions AS
SELECT *
FROM read_files(
  '/Volumes/workspace/bronze/raw_files/subscriptions(in).csv',
  format => 'csv', sep => ';', header => true, inferColumnTypes => false
);

-- Products (column mapping allows the broken header "product_cat_desc,,,,")
CREATE OR REPLACE TABLE workspace.bronze.products
TBLPROPERTIES ('delta.columnMapping.mode' = 'name') AS
SELECT *
FROM read_files(
  '/Volumes/workspace/bronze/raw_files/products(in).csv',
  format => 'csv', sep => ';', header => true, inferColumnTypes => false
);

-- =========================================
-- Checks: expected 92,042 / 210,000 / 170,245 / 1,462
-- =========================================
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM workspace.bronze.customers
UNION ALL SELECT 'orders',        COUNT(*) FROM workspace.bronze.orders
UNION ALL SELECT 'subscriptions', COUNT(*) FROM workspace.bronze.subscriptions
UNION ALL SELECT 'products',      COUNT(*) FROM workspace.bronze.products;

-- Check column names (look for a hidden BOM character on the first column)
DESCRIBE workspace.bronze.orders;
DESCRIBE workspace.bronze.products;
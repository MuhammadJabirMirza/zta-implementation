-- Seed data for the "legacy" source database (Day 12).
CREATE DATABASE IF NOT EXISTS legacyapp;
USE legacyapp;

CREATE TABLE customers (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  email VARCHAR(150) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE orders (
  id INT AUTO_INCREMENT PRIMARY KEY,
  customer_id INT NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  status VARCHAR(20) DEFAULT "pending",
  FOREIGN KEY (customer_id) REFERENCES customers(id)
);

INSERT INTO customers (name, email)
SELECT CONCAT("Customer ", n), CONCAT("user", n, "@example.com")
FROM (SELECT @row := @row + 1 AS n
      FROM information_schema.columns a,
           information_schema.columns b,
           (SELECT @row := 0) r LIMIT 5000) t;

INSERT INTO orders (customer_id, amount, status)
SELECT FLOOR(1 + RAND() * 5000), ROUND(RAND() * 500, 2),
       ELT(FLOOR(1 + RAND() * 3), "pending", "paid", "shipped")
FROM (SELECT @r := @r + 1 FROM information_schema.columns a,
      information_schema.columns b, (SELECT @r := 0) x LIMIT 20000) t;

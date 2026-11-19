/* ==========================================================================
   E-COMMERCE ANALYTICS  -  MySQL 8.0  -  schema: portfolio
   Satu program, 8 analisis:
     1. Data Profiling        5. Category Analysis
     2. Sales KPIs            6. Customer Analysis
     3. Time Analysis         7. Geography Analysis
     4. Product Analysis      8. Profitability Analysis

   Tabel: customers, orders, order_items, products, returns

   ATURAN PENJUALAN (berlaku untuk semua analisis)
   - Populasi penjualan : order_status IN ('delivered', 'returned'); cancelled dikeluarkan
   - Returned           : order berstatus 'returned' (tabel returns hanya dipakai
                          untuk alasan retur dan pengecekan konsistensi)
   - Net sales after returns = penjualan order 'delivered' saja
   - discount_rate dianggap pecahan 0-1 (dicek di Bagian 1)

   CARA PAKAI
   - Jalankan SETUP dulu (4 view), lalu bagian lain satu per satu
     (seleksi blok, Ctrl+Enter). Hasil tiap query dirancang <= 25 baris.
   ========================================================================== */

USE portfolio;
/* ==========================================================================
   1. DATA PROFILING
   ========================================================================== */

-- 1a. Jumlah baris per tabel (tabel kosong = import gagal)
SELECT 'customers' AS table_name, COUNT(*) AS total_rows, IF(COUNT(*) > 0, 'OK', 'KOSONG') AS status FROM customers
UNION ALL SELECT 'orders',      COUNT(*), IF(COUNT(*) > 0, 'OK', 'KOSONG') FROM orders
UNION ALL SELECT 'order_items', COUNT(*), IF(COUNT(*) > 0, 'OK', 'KOSONG') FROM order_items
UNION ALL SELECT 'products',    COUNT(*), IF(COUNT(*) > 0, 'OK', 'KOSONG') FROM products
UNION ALL SELECT 'returns',     COUNT(*), IF(COUNT(*) > 0, 'OK', 'KOSONG') FROM returns;

-- 1b. Pemeriksaan kualitas data. issues = jumlah baris bermasalah.
SELECT 'Duplicate primary keys (4 tabel)' AS check_name, n AS issues, IF(n = 0, 'OK', 'CHECK') AS status
FROM (SELECT (SELECT COUNT(*) - COUNT(DISTINCT customer_id) FROM customers)
           + (SELECT COUNT(*) - COUNT(DISTINCT order_id)    FROM orders)
           + (SELECT COUNT(*) - COUNT(DISTINCT product_id)  FROM products)
           + (SELECT COUNT(*) - COUNT(DISTINCT return_id)   FROM `returns`) AS n) t
UNION ALL SELECT 'NULL pada kolom id/kunci', n, IF(n = 0, 'OK', 'CHECK')
FROM (SELECT (SELECT COUNT(*) FROM customers   WHERE customer_id IS NULL)
           + (SELECT COUNT(*) FROM orders      WHERE order_id IS NULL OR customer_id IS NULL)
           + (SELECT COUNT(*) FROM order_items WHERE order_id IS NULL OR product_id IS NULL)
           + (SELECT COUNT(*) FROM products    WHERE product_id IS NULL)
           + (SELECT COUNT(*) FROM `returns`   WHERE return_id IS NULL OR order_id IS NULL) AS n) t
UNION ALL SELECT 'Orders tanpa customer', n, IF(n = 0, 'OK', 'CHECK')
FROM (SELECT COUNT(*) AS n FROM orders o LEFT JOIN customers c ON c.customer_id = o.customer_id WHERE c.customer_id IS NULL) t
UNION ALL SELECT 'Order items tanpa order', n, IF(n = 0, 'OK', 'CHECK')
FROM (SELECT COUNT(*) AS n FROM order_items oi LEFT JOIN orders o ON o.order_id = oi.order_id WHERE o.order_id IS NULL) t
UNION ALL SELECT 'Order items tanpa produk', n, IF(n = 0, 'OK', 'CHECK')
FROM (SELECT COUNT(*) AS n FROM order_items oi LEFT JOIN products p ON p.product_id = oi.product_id WHERE p.product_id IS NULL) t
UNION ALL SELECT 'Returns tanpa order', n, IF(n = 0, 'OK', 'CHECK')
FROM (SELECT COUNT(*) AS n FROM `returns` r LEFT JOIN orders o ON o.order_id = r.order_id WHERE o.order_id IS NULL) t
UNION ALL SELECT 'Orders tanpa order items', n, IF(n = 0, 'OK', 'CHECK')
FROM (SELECT COUNT(*) AS n FROM orders o LEFT JOIN order_items oi ON oi.order_id = o.order_id WHERE oi.order_id IS NULL) t
UNION ALL SELECT 'Usia di luar 0-100', n, IF(n = 0, 'OK', 'CHECK')
FROM (SELECT COUNT(*) AS n FROM customers WHERE age < 0 OR age > 100) t
UNION ALL SELECT 'Quantity <= 0', n, IF(n = 0, 'OK', 'CHECK')
FROM (SELECT COUNT(*) AS n FROM order_items WHERE quantity <= 0) t
UNION ALL SELECT 'Harga/biaya negatif (items + products)', n, IF(n = 0, 'OK', 'CHECK')
FROM (SELECT (SELECT COUNT(*) FROM order_items WHERE unit_price_idr < 0 OR unit_cost_idr < 0)
           + (SELECT COUNT(*) FROM products    WHERE list_price_idr < 0 OR unit_cost_idr < 0) AS n) t
UNION ALL SELECT 'Discount rate di luar 0-1', n, IF(n = 0, 'OK', 'CHECK')
FROM (SELECT COUNT(*) AS n FROM order_items WHERE discount_rate < 0 OR discount_rate > 1) t
UNION ALL SELECT 'Item dengan HPP di atas harga jual (info)', n, 'INFO'
FROM (SELECT COUNT(*) AS n FROM order_items WHERE unit_cost_idr > unit_price_idr) t
UNION ALL SELECT 'Tanggal kirim sebelum tanggal order', n, IF(n = 0, 'OK', 'CHECK')
FROM (SELECT COUNT(*) AS n FROM orders WHERE shipped_date < order_date) t
UNION ALL SELECT 'Tanggal terima sebelum tanggal kirim', n, IF(n = 0, 'OK', 'CHECK')
FROM (SELECT COUNT(*) AS n FROM orders WHERE delivered_date < shipped_date) t
UNION ALL SELECT 'Tanggal retur sebelum tanggal order', n, IF(n = 0, 'OK', 'CHECK')
FROM (SELECT COUNT(*) AS n FROM `returns` r JOIN orders o ON o.order_id = r.order_id WHERE r.return_date < o.order_date) t
UNION ALL SELECT 'Customers dengan atribut kosong', n, IF(n = 0, 'OK', 'CHECK')
FROM (SELECT COUNT(*) AS n FROM customers
      WHERE age IS NULL OR signup_date IS NULL
         OR TRIM(COALESCE(gender, '')) = '' OR TRIM(COALESCE(city, '')) = ''
         OR TRIM(COALESCE(province, '')) = '' OR TRIM(COALESCE(region, '')) = ''
         OR TRIM(COALESCE(initial_membership_tier, '')) = '') t
UNION ALL SELECT 'Orders dengan atribut kosong', n, IF(n = 0, 'OK', 'CHECK')
FROM (SELECT COUNT(*) AS n FROM orders
      WHERE order_date IS NULL OR TRIM(COALESCE(order_status, '')) = ''
         OR TRIM(COALESCE(payment_method, '')) = '' OR TRIM(COALESCE(sales_channel, '')) = ''
         OR TRIM(COALESCE(region, '')) = '' OR TRIM(COALESCE(shipping_city, '')) = ''
         OR TRIM(COALESCE(shipping_method, '')) = '') t
UNION ALL SELECT 'Products dengan atribut kosong', n, IF(n = 0, 'OK', 'CHECK')
FROM (SELECT COUNT(*) AS n FROM products
      WHERE list_price_idr IS NULL OR unit_cost_idr IS NULL
         OR TRIM(COALESCE(category, '')) = '' OR TRIM(COALESCE(subcategory, '')) = ''
         OR TRIM(COALESCE(product_status, '')) = '') t
UNION ALL SELECT 'Order berstatus returned tanpa catatan di returns', n, IF(n = 0, 'OK', 'CHECK')
FROM (SELECT COUNT(*) AS n FROM orders o
      WHERE LOWER(TRIM(o.order_status)) = 'returned'
        AND NOT EXISTS (SELECT 1 FROM `returns` r WHERE r.order_id = o.order_id)) t
UNION ALL SELECT 'Catatan returns pada order yang bukan returned', n, IF(n = 0, 'OK', 'CHECK')
FROM (SELECT COUNT(DISTINCT r.order_id) AS n FROM `returns` r
      JOIN orders o ON o.order_id = r.order_id WHERE LOWER(TRIM(o.order_status)) <> 'returned') t
UNION ALL SELECT 'Customers yang belum pernah order (info)', n, 'INFO'
FROM (SELECT COUNT(*) AS n FROM customers c LEFT JOIN orders o ON o.customer_id = c.customer_id WHERE o.customer_id IS NULL) t
UNION ALL SELECT 'Kolom bertipe TEXT di 5 tabel (info)', n, IF(n = 0, 'OK', 'INFO')
FROM (SELECT COUNT(*) AS n FROM information_schema.columns
      WHERE table_schema = DATABASE()
        AND table_name IN ('customers', 'orders', 'order_items', 'products', 'returns')
        AND data_type IN ('tinytext', 'text', 'mediumtext', 'longtext')) t;

-- 1c. Nilai unik kolom kategorikal (cek ejaan, huruf besar/kecil, status yang dipakai)
SELECT 'orders.order_status' AS column_name, COUNT(DISTINCT LOWER(TRIM(order_status))) AS distinct_values,
       GROUP_CONCAT(DISTINCT LOWER(TRIM(order_status)) ORDER BY LOWER(TRIM(order_status)) SEPARATOR ' | ') AS values_found FROM orders
UNION ALL SELECT 'orders.payment_method', COUNT(DISTINCT LOWER(TRIM(payment_method))),
       GROUP_CONCAT(DISTINCT LOWER(TRIM(payment_method)) ORDER BY LOWER(TRIM(payment_method)) SEPARATOR ' | ') FROM orders
UNION ALL SELECT 'orders.sales_channel', COUNT(DISTINCT LOWER(TRIM(sales_channel))),
       GROUP_CONCAT(DISTINCT LOWER(TRIM(sales_channel)) ORDER BY LOWER(TRIM(sales_channel)) SEPARATOR ' | ') FROM orders
UNION ALL SELECT 'orders.shipping_method', COUNT(DISTINCT LOWER(TRIM(shipping_method))),
       GROUP_CONCAT(DISTINCT LOWER(TRIM(shipping_method)) ORDER BY LOWER(TRIM(shipping_method)) SEPARATOR ' | ') FROM orders
UNION ALL SELECT 'orders.region', COUNT(DISTINCT LOWER(TRIM(region))),
       GROUP_CONCAT(DISTINCT LOWER(TRIM(region)) ORDER BY LOWER(TRIM(region)) SEPARATOR ' | ') FROM orders
UNION ALL SELECT 'products.category', COUNT(DISTINCT LOWER(TRIM(category))),
       GROUP_CONCAT(DISTINCT LOWER(TRIM(category)) ORDER BY LOWER(TRIM(category)) SEPARATOR ' | ') FROM products
UNION ALL SELECT 'products.product_status', COUNT(DISTINCT LOWER(TRIM(product_status))),
       GROUP_CONCAT(DISTINCT LOWER(TRIM(product_status)) ORDER BY LOWER(TRIM(product_status)) SEPARATOR ' | ') FROM products
UNION ALL SELECT 'products.product_origin', COUNT(DISTINCT LOWER(TRIM(product_origin))),
       GROUP_CONCAT(DISTINCT LOWER(TRIM(product_origin)) ORDER BY LOWER(TRIM(product_origin)) SEPARATOR ' | ') FROM products
UNION ALL SELECT 'customers.gender', COUNT(DISTINCT LOWER(TRIM(gender))),
       GROUP_CONCAT(DISTINCT LOWER(TRIM(gender)) ORDER BY LOWER(TRIM(gender)) SEPARATOR ' | ') FROM customers
UNION ALL SELECT 'customers.initial_membership_tier', COUNT(DISTINCT LOWER(TRIM(initial_membership_tier))),
       GROUP_CONCAT(DISTINCT LOWER(TRIM(initial_membership_tier)) ORDER BY LOWER(TRIM(initial_membership_tier)) SEPARATOR ' | ') FROM customers
UNION ALL SELECT 'returns.return_reason', COUNT(DISTINCT LOWER(TRIM(return_reason))),
       GROUP_CONCAT(DISTINCT LOWER(TRIM(return_reason)) ORDER BY LOWER(TRIM(return_reason)) SEPARATOR ' | ') FROM `returns`
UNION ALL SELECT 'returns.resolution', COUNT(DISTINCT LOWER(TRIM(resolution))),
       GROUP_CONCAT(DISTINCT LOWER(TRIM(resolution)) ORDER BY LOWER(TRIM(resolution)) SEPARATOR ' | ') FROM `returns`;

-- 1d. Rentang nilai numerik dan tanggal
SELECT 'customers.age' AS item, CAST(MIN(age) AS CHAR) AS min_value, CAST(MAX(age) AS CHAR) AS max_value, CAST(ROUND(AVG(age), 2) AS CHAR) AS avg_value FROM customers
UNION ALL SELECT 'order_items.quantity',       CAST(MIN(quantity) AS CHAR),       CAST(MAX(quantity) AS CHAR),       CAST(ROUND(AVG(quantity), 2) AS CHAR)       FROM order_items
UNION ALL SELECT 'order_items.unit_price_idr', CAST(MIN(unit_price_idr) AS CHAR), CAST(MAX(unit_price_idr) AS CHAR), CAST(ROUND(AVG(unit_price_idr), 0) AS CHAR) FROM order_items
UNION ALL SELECT 'order_items.unit_cost_idr',  CAST(MIN(unit_cost_idr) AS CHAR),  CAST(MAX(unit_cost_idr) AS CHAR),  CAST(ROUND(AVG(unit_cost_idr), 0) AS CHAR)  FROM order_items
UNION ALL SELECT 'order_items.discount_rate',  CAST(MIN(discount_rate) AS CHAR),  CAST(MAX(discount_rate) AS CHAR),  CAST(ROUND(AVG(discount_rate), 4) AS CHAR)  FROM order_items
UNION ALL SELECT 'products.list_price_idr',    CAST(MIN(list_price_idr) AS CHAR), CAST(MAX(list_price_idr) AS CHAR), CAST(ROUND(AVG(list_price_idr), 0) AS CHAR) FROM products
UNION ALL SELECT 'products.unit_cost_idr',     CAST(MIN(unit_cost_idr) AS CHAR),  CAST(MAX(unit_cost_idr) AS CHAR),  CAST(ROUND(AVG(unit_cost_idr), 0) AS CHAR)  FROM products
UNION ALL SELECT 'customers.signup_date',  CAST(MIN(signup_date) AS CHAR),  CAST(MAX(signup_date) AS CHAR),  NULL FROM customers
UNION ALL SELECT 'orders.order_date',      CAST(MIN(order_date) AS CHAR),   CAST(MAX(order_date) AS CHAR),   NULL FROM orders
UNION ALL SELECT 'orders.shipped_date',    CAST(MIN(shipped_date) AS CHAR), CAST(MAX(shipped_date) AS CHAR), NULL FROM orders
UNION ALL SELECT 'orders.delivered_date',  CAST(MIN(delivered_date) AS CHAR), CAST(MAX(delivered_date) AS CHAR), NULL FROM orders
UNION ALL SELECT 'returns.return_date',    CAST(MIN(return_date) AS CHAR),  CAST(MAX(return_date) AS CHAR),  NULL FROM `returns`;


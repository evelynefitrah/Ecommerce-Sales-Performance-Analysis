/* ==========================================================================
   E-COMMERCE ANALYTICS  -  MySQL 8.0  -  schema: portfolio
   Satu program, 8 analisis (ringkas, siap portofolio):
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
   SETUP: VIEW DASAR
   ========================================================================== */

/* Satu baris per item order (delivered + returned). Semua metrik penjualan
   dihitung di sini sekali, lalu cukup di-SUM oleh analisis lain. */
CREATE OR REPLACE VIEW vw_item_sales AS
SELECT
    b.*,
    b.net_sales * b.is_returned                  AS returned_sales,
    b.net_sales * (1 - b.is_returned)            AS net_sales_after_returns,
    b.cogs      * (1 - b.is_returned)            AS cogs_after_returns,
    (b.net_sales - b.cogs) * (1 - b.is_returned) AS gross_profit,
    b.quantity * b.is_returned                   AS units_returned,
    b.quantity * (1 - b.is_returned)             AS units_net
FROM (
    SELECT
        o.order_id,
        o.customer_id,
        COALESCE(STR_TO_DATE(LEFT(TRIM(o.order_date), 10), '%Y-%m-%d'),
                 STR_TO_DATE(LEFT(TRIM(o.order_date), 10), '%d/%m/%Y'))   AS order_dt,
        LOWER(TRIM(o.order_status))                                       AS order_status,
        IF(LOWER(TRIM(o.order_status)) = 'returned', 1, 0)                AS is_returned,
        COALESCE(NULLIF(TRIM(o.sales_channel), ''), 'Unknown')            AS sales_channel,
        COALESCE(NULLIF(TRIM(o.payment_method), ''), 'Unknown')           AS payment_method,
        COALESCE(NULLIF(TRIM(o.region), ''), 'Unknown')                   AS region,
        COALESCE(NULLIF(TRIM(o.shipping_city), ''), 'Unknown')            AS shipping_city,
        oi.product_id,
        COALESCE(NULLIF(TRIM(p.category), ''), 'Unknown')                 AS category,
        COALESCE(NULLIF(TRIM(p.subcategory), ''), 'Unknown')              AS subcategory,
        COALESCE(NULLIF(TRIM(p.product_status), ''), 'Unknown')           AS product_status,
        oi.quantity,
        oi.quantity * oi.unit_price_idr                                   AS gross,
        oi.quantity * oi.unit_price_idr * COALESCE(oi.discount_rate, 0)   AS discount_amount,
        oi.quantity * oi.unit_price_idr * (1 - COALESCE(oi.discount_rate, 0)) AS net_sales,
        oi.quantity * oi.unit_cost_idr                                    AS cogs
    FROM orders o
    JOIN order_items oi ON oi.order_id  = o.order_id
    JOIN products    p  ON p.product_id = oi.product_id
    WHERE LOWER(TRIM(o.order_status)) IN ('delivered', 'returned')
) b;

/* Satu baris per order, semua status (untuk cancel rate dan kecepatan pengiriman) */
CREATE OR REPLACE VIEW vw_order_base AS
SELECT
    x.order_id, x.customer_id, x.order_status, x.region, x.shipping_city, x.shipping_method,
    x.order_dt, x.shipped_dt, x.delivered_dt,
    DATEDIFF(x.shipped_dt, x.order_dt)      AS days_to_ship,
    DATEDIFF(x.delivered_dt, x.shipped_dt)  AS days_in_transit
FROM (
    SELECT
        order_id, customer_id,
        LOWER(TRIM(order_status))                                AS order_status,
        COALESCE(NULLIF(TRIM(region), ''), 'Unknown')            AS region,
        COALESCE(NULLIF(TRIM(shipping_city), ''), 'Unknown')     AS shipping_city,
        COALESCE(NULLIF(TRIM(shipping_method), ''), 'Unknown')   AS shipping_method,
        COALESCE(STR_TO_DATE(LEFT(TRIM(order_date), 10), '%Y-%m-%d'),
                 STR_TO_DATE(LEFT(TRIM(order_date), 10), '%d/%m/%Y'))         AS order_dt,
        COALESCE(STR_TO_DATE(LEFT(TRIM(shipped_date), 10), '%Y-%m-%d'),
                 STR_TO_DATE(LEFT(TRIM(shipped_date), 10), '%d/%m/%Y'))       AS shipped_dt,
        COALESCE(STR_TO_DATE(LEFT(TRIM(delivered_date), 10), '%Y-%m-%d'),
                 STR_TO_DATE(LEFT(TRIM(delivered_date), 10), '%d/%m/%Y'))     AS delivered_dt
    FROM orders
) x;

/* Satu baris per produk yang pernah terjual */
CREATE OR REPLACE VIEW vw_product_base AS
SELECT
    product_id, category, subcategory, product_status,
    COUNT(DISTINCT order_id)                                   AS orders,
    SUM(quantity)                                              AS units_sold,
    SUM(units_returned)                                        AS units_returned,
    SUM(units_net)                                             AS net_units_sold,
    SUM(gross)                                                 AS gross,
    SUM(discount_amount)                                       AS discount_amount,
    SUM(net_sales)                                             AS net_sales,
    SUM(returned_sales)                                        AS returned_sales,
    SUM(net_sales_after_returns)                               AS net_sales_after_returns,
    SUM(gross_profit)                                          AS gross_profit,
    MAX(order_dt)                                              AS last_sale_dt,
    SUM(units_returned) * 100.0 / NULLIF(SUM(quantity), 0)     AS return_rate,
    SUM(discount_amount) * 100.0 / NULLIF(SUM(gross), 0)       AS discount_rate,
    SUM(gross_profit) * 100.0 / NULLIF(SUM(net_sales_after_returns), 0) AS profit_margin
FROM vw_item_sales
GROUP BY product_id, category, subcategory, product_status;

/* Satu baris per pelanggan (termasuk yang belum pernah membeli) */
CREATE OR REPLACE VIEW vw_customer_base AS
SELECT
    c.customer_id, c.customer_name, c.gender, c.age, c.city, c.province, c.region,
    COALESCE(NULLIF(TRIM(c.initial_membership_tier), ''), 'Unknown')  AS membership_tier,
    COALESCE(STR_TO_DATE(LEFT(TRIM(c.signup_date), 10), '%Y-%m-%d'),
             STR_TO_DATE(LEFT(TRIM(c.signup_date), 10), '%d/%m/%Y'))   AS signup_dt,
    COALESCE(s.total_orders, 0)            AS total_orders,
    COALESCE(s.returned_orders, 0)         AS returned_orders,
    s.first_order_dt, s.last_order_dt,
    COALESCE(s.units_sold, 0)              AS units_sold,
    COALESCE(s.units_returned, 0)          AS units_returned,
    COALESCE(s.net_sales_after_returns, 0) AS net_sales_after_returns,
    COALESCE(s.gross_profit, 0)            AS gross_profit,
    DATEDIFF((SELECT MAX(order_dt) FROM vw_item_sales), s.last_order_dt) AS recency
FROM customers c
LEFT JOIN (
    SELECT customer_id,
           COUNT(DISTINCT order_id)                                   AS total_orders,
           COUNT(DISTINCT CASE WHEN is_returned = 1 THEN order_id END) AS returned_orders,
           MIN(order_dt) AS first_order_dt, MAX(order_dt) AS last_order_dt,
           SUM(quantity) AS units_sold, SUM(units_returned) AS units_returned,
           SUM(net_sales_after_returns) AS net_sales_after_returns,
           SUM(gross_profit) AS gross_profit
    FROM vw_item_sales
    GROUP BY customer_id
) s ON s.customer_id = c.customer_id;

/* ==========================================================================
   8. PROFITABILITY ANALYSIS
   Profit per produk/kategori/region/pelanggan: ringkasannya ada di Bagian 4-7.
   Profit dan margin bulanan (MoM) ada di 3b. Bagian ini berisi analisis
   profit yang belum ada di sana.
   gross profit = net sales - HPP; order 'returned' tidak menghasilkan profit.
   ========================================================================== */

-- 8a. Profit waterfall: dari penjualan sampai profit akhir, dan profit yang hilang karena retur
SELECT ROUND(SUM(gross), 0)                                   AS gross_sales,
       ROUND(SUM(discount_amount), 0)                         AS discount_amount,
       ROUND(SUM(net_sales), 0)                               AS net_sales_before_returns,
       ROUND(SUM(cogs), 0)                                    AS cogs_all_shipped_orders,
       ROUND(SUM(net_sales - cogs), 0)                        AS gross_profit_before_returns,
       ROUND(SUM((net_sales - cogs) * is_returned), 0)        AS profit_lost_to_returns,
       ROUND(SUM(gross_profit), 0)                            AS gross_profit_after_returns,
       ROUND(SUM((net_sales - cogs) * is_returned) * 100.0 / NULLIF(SUM(net_sales - cogs), 0), 2) AS pct_profit_lost_to_returns,
       ROUND(SUM(net_sales - cogs) * 100.0 / NULLIF(SUM(net_sales), 0), 2)                        AS margin_before_returns_pct,
       ROUND(SUM(gross_profit) * 100.0 / NULLIF(SUM(net_sales_after_returns), 0), 2)              AS margin_after_returns_pct
FROM vw_item_sales;

-- 8b. 10 produk dengan profit tertinggi dan 10 terendah (loss_making_products_total = jumlah produk rugi)
WITH r AS (
    SELECT product_id, category, subcategory, net_units_sold, net_sales_after_returns, gross_profit, profit_margin,
           gross_profit * 100.0 / SUM(gross_profit) OVER ()                AS profit_share_pct,
           SUM(gross_profit < 0) OVER ()                                   AS loss_making_products_total,
           ROW_NUMBER() OVER (ORDER BY gross_profit DESC, product_id)      AS rank_desc,
           ROW_NUMBER() OVER (ORDER BY gross_profit ASC,  product_id)      AS rank_asc
    FROM vw_product_base
)
SELECT IF(rank_desc <= 10, 'Top 10', 'Bottom 10') AS ranking, product_id, category, subcategory, net_units_sold,
       ROUND(net_sales_after_returns, 0) AS net_sales, ROUND(gross_profit, 0) AS gross_profit,
       ROUND(profit_margin, 2) AS margin_pct, ROUND(profit_share_pct, 2) AS profit_share_pct,
       loss_making_products_total
FROM r
WHERE rank_desc <= 10 OR rank_asc <= 10
ORDER BY gross_profit DESC;

-- 8c. Segmentasi produk: revenue x margin (dibanding rata-rata)
WITH x AS (
    SELECT *, AVG(net_sales_after_returns) OVER () AS avg_sales, AVG(profit_margin) OVER () AS avg_margin
    FROM vw_product_base
)
SELECT CASE WHEN net_sales_after_returns >= avg_sales AND profit_margin >= avg_margin THEN '1. High revenue / High margin'
            WHEN net_sales_after_returns >= avg_sales AND profit_margin <  avg_margin THEN '2. High revenue / Low margin'
            WHEN net_sales_after_returns <  avg_sales AND profit_margin >= avg_margin THEN '3. Low revenue / High margin'
            ELSE '4. Low revenue / Low margin' END AS segment,
       COUNT(*) AS products, ROUND(SUM(net_sales_after_returns), 0) AS net_sales,
       ROUND(SUM(gross_profit), 0) AS gross_profit,
       ROUND(SUM(gross_profit) * 100.0 / SUM(SUM(gross_profit)) OVER (), 2) AS pct_of_profit,
       ROUND(SUM(gross_profit) * 100.0 / NULLIF(SUM(net_sales_after_returns), 0), 2) AS margin_pct
FROM x
GROUP BY segment
ORDER BY segment;

-- 8d. Kontribusi profit per kategori dibanding kontribusi penjualannya
--     (poin positif = kategori menyumbang profit lebih besar dari porsi penjualannya)
SELECT category,
       ROUND(SUM(net_sales_after_returns), 0) AS net_sales,
       ROUND(SUM(cogs_after_returns), 0)      AS cogs,
       ROUND(SUM(gross_profit), 0)            AS gross_profit,
       ROUND(SUM(gross_profit) * 100.0 / NULLIF(SUM(net_sales_after_returns), 0), 2) AS margin_pct,
       ROUND(SUM(net_sales_after_returns) * 100.0 / SUM(SUM(net_sales_after_returns)) OVER (), 2) AS sales_share_pct,
       ROUND(SUM(gross_profit) * 100.0 / SUM(SUM(gross_profit)) OVER (), 2)                       AS profit_share_pct,
       ROUND(SUM(gross_profit) * 100.0 / SUM(SUM(gross_profit)) OVER ()
             - SUM(net_sales_after_returns) * 100.0 / SUM(SUM(net_sales_after_returns)) OVER (), 2) AS profit_vs_sales_share_points,
       ROUND(SUM((net_sales - cogs) * is_returned), 0) AS profit_lost_to_returns
FROM vw_item_sales
GROUP BY category
ORDER BY SUM(gross_profit) DESC;

-- 8e. Efektivitas diskon (order delivered): apakah diskon besar masih menguntungkan?
SELECT CASE WHEN discount_amount = 0                         THEN '0%'
            WHEN discount_amount / NULLIF(gross, 0) <= 0.10  THEN '>0-10%'
            WHEN discount_amount / NULLIF(gross, 0) <= 0.20  THEN '>10-20%'
            ELSE '>20%' END AS discount_bucket,
       COUNT(DISTINCT order_id) AS orders, SUM(quantity) AS units_sold,
       ROUND(SUM(net_sales), 0) AS net_sales, ROUND(SUM(net_sales - cogs), 0) AS gross_profit,
       ROUND(SUM(net_sales - cogs) * 100.0 / NULLIF(SUM(net_sales), 0), 2) AS margin_pct,
       ROUND(SUM(net_sales - cogs) / SUM(quantity), 0) AS profit_per_unit
FROM vw_item_sales
WHERE is_returned = 0
GROUP BY discount_bucket
ORDER BY MIN(discount_amount / NULLIF(gross, 0));

-- 8f. Margin per sales channel dan metode pembayaran
WITH l AS (
    SELECT 'sales_channel' AS dimension, sales_channel AS group_value, net_sales_after_returns, gross_profit,
           quantity, units_returned, gross, discount_amount
    FROM vw_item_sales
    UNION ALL
    SELECT 'payment_method', payment_method, net_sales_after_returns, gross_profit,
           quantity, units_returned, gross, discount_amount
    FROM vw_item_sales
)
SELECT dimension, group_value, ROUND(SUM(net_sales_after_returns), 0) AS net_sales,
       ROUND(SUM(net_sales_after_returns) * 100.0 / SUM(SUM(net_sales_after_returns)) OVER (PARTITION BY dimension), 2) AS share_pct,
       ROUND(SUM(gross_profit) * 100.0 / NULLIF(SUM(net_sales_after_returns), 0), 2) AS margin_pct,
       ROUND(SUM(units_returned) * 100.0 / NULLIF(SUM(quantity), 0), 2) AS return_rate_pct,
       ROUND(SUM(discount_amount) * 100.0 / NULLIF(SUM(gross), 0), 2) AS discount_rate_pct
FROM l
GROUP BY dimension, group_value
ORDER BY dimension, net_sales DESC;

-- 8g. Profit bridge: kenapa profit 90 hari terakhir berbeda dari 90 hari sebelumnya?
--     volume + harga + diskon + biaya = perubahan profit produk yang dijual di kedua periode;
--     sisanya (new_or_dropped) berasal dari produk yang hanya dijual di salah satu periode.
WITH a AS (
    SELECT MAX(order_dt) AS max_dt FROM vw_item_sales
),
p AS (
    SELECT s.product_id,
           IF(s.order_dt > DATE_SUB(a.max_dt, INTERVAL 90 DAY), 'cur', 'prev') AS period_flag,
           SUM(s.quantity)                           AS qty,
           SUM(s.gross) / SUM(s.quantity)            AS price,
           SUM(s.discount_amount) / SUM(s.quantity)  AS disc,
           SUM(s.cogs) / SUM(s.quantity)             AS cost,
           SUM(s.net_sales - s.cogs)                 AS profit
    FROM vw_item_sales s CROSS JOIN a
    WHERE s.is_returned = 0 AND s.order_dt > DATE_SUB(a.max_dt, INTERVAL 180 DAY)
    GROUP BY s.product_id, period_flag
),
j AS (
    SELECT c.qty AS q1, c.price AS p1, c.disc AS d1, c.cost AS c1, c.profit AS pr1,
           v.qty AS q0, v.price AS p0, v.disc AS d0, v.cost AS c0, v.profit AS pr0
    FROM p c
    JOIN p v ON v.product_id = c.product_id AND c.period_flag = 'cur' AND v.period_flag = 'prev'
)
SELECT ROUND((SELECT SUM(profit) FROM p WHERE period_flag = 'prev'), 0) AS profit_prev_90d,
       ROUND((SELECT SUM(profit) FROM p WHERE period_flag = 'cur'), 0)  AS profit_last_90d,
       ROUND((SELECT SUM(profit) FROM p WHERE period_flag = 'cur')
             - (SELECT SUM(profit) FROM p WHERE period_flag = 'prev'), 0) AS total_change,
       ROUND(SUM((q1 - q0) * (p0 - d0 - c0)), 0) AS volume_effect,
       ROUND(SUM((p1 - p0) * q1), 0)             AS price_effect,
       ROUND(SUM((d0 - d1) * q1), 0)             AS discount_effect,
       ROUND(SUM((c0 - c1) * q1), 0)             AS cost_effect,
       ROUND((SELECT SUM(profit) FROM p WHERE period_flag = 'cur')
             - (SELECT SUM(profit) FROM p WHERE period_flag = 'prev')
             - SUM(pr1 - pr0), 0)                AS new_or_dropped_products_effect
FROM j;

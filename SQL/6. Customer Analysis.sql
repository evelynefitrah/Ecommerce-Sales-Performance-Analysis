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
   6. CUSTOMER ANALYSIS
   ========================================================================== */

-- 6a. Ringkasan pelanggan (satu baris)
SELECT COUNT(*)                                                   AS total_customers,
       SUM(total_orders > 0)                                      AS buying_customers,
       SUM(total_orders = 0)                                      AS never_bought,
       ROUND(SUM(total_orders > 0) * 100.0 / COUNT(*), 2)         AS conversion_pct,
       SUM(total_orders >= 2)                                     AS repeat_customers,
       ROUND(SUM(total_orders >= 2) * 100.0 / NULLIF(SUM(total_orders > 0), 0), 2) AS repeat_rate_pct,
       ROUND(AVG(CASE WHEN total_orders > 0 THEN total_orders END), 2)             AS avg_orders_per_buyer,
       ROUND(SUM(net_sales_after_returns) / NULLIF(SUM(total_orders > 0), 0), 0)   AS sales_per_buyer,
       ROUND(SUM(returned_orders > 0) * 100.0 / NULLIF(SUM(total_orders > 0), 0), 2) AS buyers_with_returns_pct
FROM vw_customer_base;

-- 6b. Profil pelanggan: membership, gender, kelompok usia
WITH d AS (
    SELECT total_orders, net_sales_after_returns, units_sold, units_returned, membership_tier,
           COALESCE(NULLIF(TRIM(gender), ''), 'Unknown') AS gender,
           CASE WHEN age IS NULL OR TRIM(age) = '' THEN 'Unknown'
                WHEN CAST(age AS UNSIGNED) < 25 THEN '< 25'
                WHEN CAST(age AS UNSIGNED) < 35 THEN '25-34'
                WHEN CAST(age AS UNSIGNED) < 45 THEN '35-44'
                WHEN CAST(age AS UNSIGNED) < 55 THEN '45-54'
                ELSE '55+' END AS age_group
    FROM vw_customer_base
),
l AS (
    SELECT 'membership_tier' AS dimension, membership_tier AS group_value, total_orders, net_sales_after_returns, units_sold, units_returned FROM d
    UNION ALL SELECT 'gender',    gender,    total_orders, net_sales_after_returns, units_sold, units_returned FROM d
    UNION ALL SELECT 'age_group', age_group, total_orders, net_sales_after_returns, units_sold, units_returned FROM d
)
SELECT dimension, group_value, COUNT(*) AS customers, SUM(total_orders > 0) AS buyers,
       ROUND(SUM(net_sales_after_returns), 0) AS net_sales,
       ROUND(SUM(net_sales_after_returns) / NULLIF(SUM(total_orders > 0), 0), 0) AS sales_per_buyer,
       ROUND(AVG(CASE WHEN total_orders > 0 THEN total_orders END), 2) AS avg_orders_per_buyer,
       ROUND(SUM(units_returned) * 100.0 / NULLIF(SUM(units_sold), 0), 2) AS return_rate_pct
FROM l
GROUP BY dimension, group_value
ORDER BY dimension, net_sales DESC;

-- 6c. Distribusi frekuensi pembelian
SELECT CASE WHEN total_orders = 0 THEN '0 (belum pernah beli)' WHEN total_orders = 1 THEN '1' WHEN total_orders = 2 THEN '2'
            WHEN total_orders <= 4 THEN '3-4' WHEN total_orders <= 9 THEN '5-9' ELSE '10+' END AS orders_per_customer,
       COUNT(*) AS customers, ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_customers,
       ROUND(SUM(net_sales_after_returns), 0) AS net_sales,
       ROUND(SUM(net_sales_after_returns) * 100.0 / SUM(SUM(net_sales_after_returns)) OVER (), 2) AS pct_sales
FROM vw_customer_base
GROUP BY orders_per_customer
ORDER BY MIN(total_orders);

-- 6d. Konsentrasi penjualan: berapa pelanggan yang menyumbang 80% penjualan
WITH b AS (
    SELECT net_sales_after_returns AS sales,
           ROW_NUMBER() OVER (ORDER BY net_sales_after_returns DESC, customer_id) AS rn,
           SUM(net_sales_after_returns) OVER (ORDER BY net_sales_after_returns DESC, customer_id
                                               ROWS UNBOUNDED PRECEDING) AS running,
           SUM(net_sales_after_returns) OVER () AS total, COUNT(*) OVER () AS n
    FROM vw_customer_base
    WHERE total_orders > 0
)
SELECT MAX(n) AS buyers,
       MIN(CASE WHEN running * 100.0 / total >= 80 THEN rn END) AS customers_for_80pct_sales,
       ROUND(MIN(CASE WHEN running * 100.0 / total >= 80 THEN rn END) * 100.0 / MAX(n), 2) AS pct_of_buyers,
       ROUND(SUM(CASE WHEN rn <= CEIL(n * 0.1) THEN sales ELSE 0 END) * 100.0 / MAX(total), 2) AS top10pct_buyers_sales_share
FROM b;

-- 6e. 10 pelanggan terbaik
SELECT customer_id, customer_name, membership_tier, city, total_orders,
       ROUND(net_sales_after_returns, 0) AS net_sales,
       ROUND(gross_profit * 100.0 / NULLIF(net_sales_after_returns, 0), 2) AS margin_pct,
       ROUND(units_returned * 100.0 / NULLIF(units_sold, 0), 2) AS return_rate_pct, recency AS days_since_last_order
FROM vw_customer_base
ORDER BY net_sales_after_returns DESC
LIMIT 10;

-- 6f. Segmentasi RFM (skor 5 = terbaik; skor memakai CUME_DIST sehingga nilai kembar mendapat skor sama)
WITH b AS (
    SELECT customer_id, recency, total_orders AS frequency, net_sales_after_returns AS monetary
    FROM vw_customer_base
    WHERE total_orders > 0
),
s AS (
    SELECT *, CEIL(5 * CUME_DIST() OVER (ORDER BY recency DESC))  AS r_score,
              CEIL(5 * CUME_DIST() OVER (ORDER BY frequency ASC)) AS f_score,
              CEIL(5 * CUME_DIST() OVER (ORDER BY monetary ASC))  AS m_score
    FROM b
),
g AS (
    SELECT *, CASE WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
                   WHEN r_score >= 4 AND f_score >= 3 AND m_score >= 3 THEN 'Loyal Customers'
                   WHEN r_score >= 4 AND f_score <= 2                  THEN 'New / Potential'
                   WHEN r_score <= 2 AND f_score >= 4 AND m_score >= 4 THEN 'At Risk - High Value'
                   WHEN r_score <= 2 AND f_score >= 3                  THEN 'At Risk'
                   WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 2 THEN 'Lost / Low Value'
                   ELSE 'Regular' END AS rfm_segment
    FROM s
)
SELECT rfm_segment, COUNT(*) AS customers, ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_customers,
       ROUND(AVG(recency), 0) AS avg_days_since_last_order, ROUND(AVG(frequency), 2) AS avg_orders,
       ROUND(SUM(monetary), 0) AS net_sales,
       ROUND(SUM(monetary) * 100.0 / SUM(SUM(monetary)) OVER (), 2) AS pct_sales
FROM g
GROUP BY rfm_segment
ORDER BY SUM(monetary) DESC;

-- 6g. Retensi kohort per kuartal pembelian pertama (persen pembeli yang aktif tepat di bulan ke-N).
--     NULL = kohort belum cukup umur.
WITH a AS (
    SELECT DISTINCT customer_id, YEAR(order_dt) * 12 + MONTH(order_dt) AS mi
    FROM vw_item_sales
    WHERE order_dt IS NOT NULL
),
f AS (SELECT customer_id, MIN(mi) AS first_mi FROM a GROUP BY customer_id),
j AS (SELECT f.customer_id, f.first_mi, a.mi - f.first_mi AS month_no FROM f JOIN a ON a.customer_id = f.customer_id),
c AS (
    SELECT CONCAT(FLOOR((first_mi - 1) / 12), '-Q', FLOOR(MOD(first_mi - 1, 12) / 3) + 1) AS cohort_quarter,
           MAX(first_mi) AS last_first_mi,
           COUNT(DISTINCT customer_id) AS cohort_size,
           COUNT(DISTINCT CASE WHEN month_no = 1 THEN customer_id END) AS m1,
           COUNT(DISTINCT CASE WHEN month_no = 3 THEN customer_id END) AS m3,
           COUNT(DISTINCT CASE WHEN month_no = 6 THEN customer_id END) AS m6
    FROM j
    GROUP BY 1
)
SELECT cohort_quarter, cohort_size,
       CASE WHEN last_first_mi + 1 <= x.mx THEN ROUND(m1 * 100.0 / cohort_size, 1) END AS month1_pct,
       CASE WHEN last_first_mi + 3 <= x.mx THEN ROUND(m3 * 100.0 / cohort_size, 1) END AS month3_pct,
       CASE WHEN last_first_mi + 6 <= x.mx THEN ROUND(m6 * 100.0 / cohort_size, 1) END AS month6_pct
FROM c CROSS JOIN (SELECT MAX(mi) AS mx FROM a) x
ORDER BY cohort_quarter;

-- 6h. Konversi pelanggan berdasarkan tahun pendaftaran
SELECT YEAR(signup_dt) AS signup_year, COUNT(*) AS customers, SUM(total_orders > 0) AS buyers,
       ROUND(SUM(total_orders > 0) * 100.0 / COUNT(*), 2) AS conversion_pct,
       ROUND(SUM(net_sales_after_returns), 0) AS net_sales
FROM vw_customer_base
WHERE signup_dt IS NOT NULL
GROUP BY 1
ORDER BY 1;
/* ==========================================================================
   7. GEOGRAPHY ANALYSIS  (region dan kota pengiriman dari tabel orders)
   ========================================================================== */

-- 7a. Scorecard region: penjualan, nilai pelanggan, margin, retur, cancel, kecepatan kirim, segmen
WITH s AS (
    SELECT region, COUNT(DISTINCT customer_id) AS customers, COUNT(DISTINCT order_id) AS orders,
           COUNT(DISTINCT CASE WHEN is_returned = 0 THEN order_id END) AS delivered_orders,
           SUM(net_sales_after_returns) AS net_sales, SUM(gross_profit) AS gross_profit,
           SUM(units_returned) * 100.0 / NULLIF(SUM(quantity), 0) AS return_rate,
           SUM(discount_amount) * 100.0 / NULLIF(SUM(gross), 0)   AS discount_rate
    FROM vw_item_sales
    GROUP BY region
),
o AS (
    SELECT region, ROUND(SUM(order_status = 'cancelled') * 100.0 / COUNT(*), 2) AS cancel_rate_pct,
           ROUND(AVG(days_to_ship), 1) AS avg_days_to_ship, ROUND(AVG(days_in_transit), 1) AS avg_days_in_transit
    FROM vw_order_base
    GROUP BY region
),
k AS (
    SELECT s.*, o.cancel_rate_pct, o.avg_days_to_ship, o.avg_days_in_transit,
           s.net_sales / NULLIF(s.customers, 0)      AS sales_per_customer,
           s.orders * 1.0 / NULLIF(s.customers, 0)   AS orders_per_customer
    FROM s LEFT JOIN o ON o.region = s.region
)
SELECT region, customers, orders, ROUND(net_sales, 0) AS net_sales,
       ROUND(net_sales * 100.0 / SUM(net_sales) OVER (), 2) AS share_pct,
       ROUND(net_sales / NULLIF(delivered_orders, 0), 0) AS avg_order_value,
       ROUND(sales_per_customer, 0) AS sales_per_customer, ROUND(orders_per_customer, 2) AS orders_per_customer,
       ROUND(gross_profit * 100.0 / NULLIF(net_sales, 0), 2) AS margin_pct,
       ROUND(return_rate, 2) AS return_rate_pct, ROUND(discount_rate, 2) AS discount_rate_pct,
       cancel_rate_pct, avg_days_to_ship, avg_days_in_transit,
       CASE WHEN sales_per_customer >= AVG(sales_per_customer) OVER () AND orders_per_customer >= AVG(orders_per_customer) OVER () THEN 'High value / High frequency'
            WHEN sales_per_customer >= AVG(sales_per_customer) OVER () THEN 'High value / Low frequency'
            WHEN orders_per_customer >= AVG(orders_per_customer) OVER () THEN 'Low value / High frequency'
            ELSE 'Low value / Low frequency' END AS segment
FROM k
ORDER BY net_sales DESC;

-- 7b. 10 kota terbesar dan 5 kota terkecil
WITH c AS (
    SELECT shipping_city, MIN(region) AS region, COUNT(DISTINCT customer_id) AS customers, COUNT(DISTINCT order_id) AS orders,
           SUM(net_sales_after_returns) AS net_sales, SUM(gross_profit) AS gross_profit,
           SUM(units_returned) * 100.0 / NULLIF(SUM(quantity), 0) AS return_rate,
           COUNT(DISTINCT CASE WHEN is_returned = 0 THEN order_id END) AS delivered_orders
    FROM vw_item_sales
    GROUP BY shipping_city
),
r AS (
    SELECT *, net_sales * 100.0 / SUM(net_sales) OVER () AS share_pct,
           ROW_NUMBER() OVER (ORDER BY net_sales DESC, shipping_city) AS rank_desc,
           ROW_NUMBER() OVER (ORDER BY net_sales ASC,  shipping_city) AS rank_asc
    FROM c
)
SELECT IF(rank_desc <= 10, 'Top 10', 'Bottom 5') AS ranking, shipping_city, region, customers, orders,
       ROUND(net_sales, 0) AS net_sales, ROUND(share_pct, 2) AS share_pct,
       ROUND(net_sales / NULLIF(delivered_orders, 0), 0) AS avg_order_value,
       ROUND(gross_profit * 100.0 / NULLIF(net_sales, 0), 2) AS margin_pct, ROUND(return_rate, 2) AS return_rate_pct
FROM r
WHERE rank_desc <= 10 OR rank_asc <= 5
ORDER BY net_sales DESC;

-- 7c. Pertumbuhan region: tahun berjalan vs tahun lalu (periode setara) dan momentum 90 hari
WITH a AS (
    SELECT MAX(order_dt) AS max_dt, YEAR(MAX(order_dt)) AS cy,
           IF(MAX(order_dt) < LAST_DAY(MAX(order_dt)), MONTH(MAX(order_dt)) - 1, MONTH(MAX(order_dt))) AS cm
    FROM vw_item_sales
),
g AS (
    SELECT s.region,
           SUM(CASE WHEN YEAR(s.order_dt) = a.cy - 1 AND MONTH(s.order_dt) <= a.cm THEN s.net_sales_after_returns ELSE 0 END) AS prev_year_ytd,
           SUM(CASE WHEN YEAR(s.order_dt) = a.cy     AND MONTH(s.order_dt) <= a.cm THEN s.net_sales_after_returns ELSE 0 END) AS curr_year_ytd,
           SUM(CASE WHEN s.order_dt >  DATE_SUB(a.max_dt, INTERVAL 90 DAY) THEN s.net_sales_after_returns ELSE 0 END) AS last_90d,
           SUM(CASE WHEN s.order_dt >  DATE_SUB(a.max_dt, INTERVAL 180 DAY)
                     AND s.order_dt <= DATE_SUB(a.max_dt, INTERVAL 90 DAY) THEN s.net_sales_after_returns ELSE 0 END) AS prev_90d
    FROM vw_item_sales s CROSS JOIN a
    WHERE s.order_dt IS NOT NULL
    GROUP BY s.region
)
SELECT region, ROUND(prev_year_ytd, 0) AS prev_year_same_period, ROUND(curr_year_ytd, 0) AS curr_year_same_period,
       ROUND((curr_year_ytd - prev_year_ytd) * 100.0 / NULLIF(prev_year_ytd, 0), 2) AS yoy_same_period_pct,
       ROUND((last_90d - prev_90d) * 100.0 / NULLIF(prev_90d, 0), 2) AS momentum_90d_pct
FROM g
ORDER BY curr_year_ytd DESC;

-- 7d. Kinerja metode pengiriman
SELECT shipping_method, COUNT(*) AS orders, ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS share_pct,
       ROUND(SUM(order_status = 'cancelled') * 100.0 / COUNT(*), 2) AS cancel_rate_pct,
       ROUND(SUM(order_status = 'returned') * 100.0
             / NULLIF(SUM(order_status IN ('delivered', 'returned')), 0), 2) AS return_rate_pct,
       ROUND(AVG(days_to_ship), 1) AS avg_days_to_ship, ROUND(AVG(days_in_transit), 1) AS avg_days_in_transit,
       ROUND(AVG(days_to_ship + days_in_transit), 1) AS avg_total_days, MAX(days_to_ship + days_in_transit) AS max_total_days
FROM vw_order_base
GROUP BY shipping_method
ORDER BY orders DESC;
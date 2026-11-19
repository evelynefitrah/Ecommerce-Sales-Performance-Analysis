/* ==========================================================================
   5. CATEGORY ANALYSIS
   ========================================================================== */

-- 5a. Scorecard kategori (kontribusi, kumulatif Pareto, margin, retur, diskon, profil)
WITH c AS (
    SELECT category,
           COUNT(DISTINCT product_id) AS products, COUNT(DISTINCT order_id) AS orders,
           SUM(units_net) AS net_units, SUM(net_sales_after_returns) AS net_sales, SUM(gross_profit) AS gross_profit,
           SUM(units_returned) * 100.0 / NULLIF(SUM(quantity), 0) AS return_rate,
           SUM(discount_amount) * 100.0 / NULLIF(SUM(gross), 0)   AS discount_rate
    FROM vw_item_sales
    GROUP BY category
),
k AS (
    SELECT *, gross_profit * 100.0 / NULLIF(net_sales, 0) AS margin,
           AVG(net_sales) OVER () AS avg_sales, AVG(gross_profit * 100.0 / NULLIF(net_sales, 0)) OVER () AS avg_margin,
           AVG(return_rate) OVER () AS avg_return
    FROM c
)
SELECT category, products, orders, net_units, ROUND(net_sales, 0) AS net_sales,
       ROUND(net_sales * 100.0 / SUM(net_sales) OVER (), 2) AS share_pct,
       ROUND(SUM(net_sales) OVER (ORDER BY net_sales DESC, category ROWS UNBOUNDED PRECEDING) * 100.0
             / SUM(net_sales) OVER (), 2) AS cumulative_share_pct,
       ROUND(margin, 2) AS margin_pct, ROUND(return_rate, 2) AS return_rate_pct,
       ROUND(discount_rate, 2) AS discount_rate_pct, ROUND(net_sales / NULLIF(products, 0), 0) AS sales_per_product,
       CASE WHEN net_sales >= avg_sales AND margin >= avg_margin AND return_rate <= avg_return THEN 'Bintang'
            WHEN net_sales >= avg_sales AND margin <  avg_margin THEN 'Besar, margin tipis'
            WHEN net_sales >= avg_sales AND return_rate >  avg_return THEN 'Besar, retur tinggi'
            WHEN net_sales <  avg_sales AND margin >= avg_margin THEN 'Kecil, sehat'
            ELSE 'Kecil, lemah' END AS category_profile
FROM k
ORDER BY net_sales DESC;

-- 5b. 10 subkategori terbesar
SELECT category, subcategory, COUNT(DISTINCT product_id) AS products,
       ROUND(SUM(net_sales_after_returns), 0) AS net_sales,
       ROUND(SUM(net_sales_after_returns) * 100.0 / SUM(SUM(net_sales_after_returns)) OVER (), 2) AS share_pct,
       ROUND(SUM(gross_profit) * 100.0 / NULLIF(SUM(net_sales_after_returns), 0), 2) AS margin_pct,
       ROUND(SUM(units_returned) * 100.0 / NULLIF(SUM(quantity), 0), 2) AS return_rate_pct
FROM vw_item_sales
GROUP BY category, subcategory
ORDER BY SUM(net_sales_after_returns) DESC
LIMIT 10;

-- 5c. Pertumbuhan kategori: tahun berjalan vs tahun lalu (periode setara) dan momentum 90 hari
WITH a AS (
    SELECT MAX(order_dt) AS max_dt, YEAR(MAX(order_dt)) AS cy,
           IF(MAX(order_dt) < LAST_DAY(MAX(order_dt)), MONTH(MAX(order_dt)) - 1, MONTH(MAX(order_dt))) AS cm
    FROM vw_item_sales
),
g AS (
    SELECT s.category,
           SUM(CASE WHEN YEAR(s.order_dt) = a.cy - 1 AND MONTH(s.order_dt) <= a.cm THEN s.net_sales_after_returns ELSE 0 END) AS prev_year_ytd,
           SUM(CASE WHEN YEAR(s.order_dt) = a.cy     AND MONTH(s.order_dt) <= a.cm THEN s.net_sales_after_returns ELSE 0 END) AS curr_year_ytd,
           SUM(CASE WHEN s.order_dt >  DATE_SUB(a.max_dt, INTERVAL 90 DAY) THEN s.net_sales_after_returns ELSE 0 END) AS last_90d,
           SUM(CASE WHEN s.order_dt >  DATE_SUB(a.max_dt, INTERVAL 180 DAY)
                     AND s.order_dt <= DATE_SUB(a.max_dt, INTERVAL 90 DAY) THEN s.net_sales_after_returns ELSE 0 END) AS prev_90d
    FROM vw_item_sales s CROSS JOIN a
    WHERE s.order_dt IS NOT NULL
    GROUP BY s.category
)
SELECT category, ROUND(prev_year_ytd, 0) AS prev_year_same_period, ROUND(curr_year_ytd, 0) AS curr_year_same_period,
       ROUND((curr_year_ytd - prev_year_ytd) * 100.0 / NULLIF(prev_year_ytd, 0), 2) AS yoy_same_period_pct,
       ROUND(prev_90d, 0) AS prev_90d_sales, ROUND(last_90d, 0) AS last_90d_sales,
       ROUND((last_90d - prev_90d) * 100.0 / NULLIF(prev_90d, 0), 2) AS momentum_90d_pct
FROM g
ORDER BY curr_year_ytd DESC;

-- 5d. Alasan retur terbanyak per kategori (catatan retur dihitung untuk setiap kategori dalam order itu)
WITH rr AS (
    SELECT s.category, LOWER(TRIM(COALESCE(NULLIF(r.return_reason, ''), 'unknown'))) AS reason,
           COUNT(DISTINCT r.return_id) AS return_records
    FROM `returns` r
    JOIN (SELECT DISTINCT order_id, category FROM vw_item_sales) s ON s.order_id = r.order_id
    GROUP BY 1, 2
),
k AS (
    SELECT *, RANK() OVER (PARTITION BY category ORDER BY return_records DESC) AS rnk,
           SUM(return_records) OVER (PARTITION BY category) AS total_records
    FROM rr
)
SELECT category, reason AS top_return_reason, return_records,
       ROUND(return_records * 100.0 / total_records, 1) AS share_in_category_pct
FROM k
WHERE rnk = 1
ORDER BY return_records DESC;
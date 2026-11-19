/* ==========================================================================
   3. TIME ANALYSIS
   ========================================================================== */

-- 3a. Tahunan. YoY penuh hanya dihitung bila jumlah bulan data kedua tahun sama;
--     YoY periode setara membandingkan Januari s.d. bulan terakhir yang sudah selesai.
WITH m AS (
    SELECT YEAR(order_dt) AS yr, MONTH(order_dt) AS mo,
           COUNT(DISTINCT order_id) AS orders,
           SUM(net_sales_after_returns) AS net_sales,
           SUM(gross_profit) AS gross_profit
    FROM vw_item_sales
    WHERE order_dt IS NOT NULL
    GROUP BY 1, 2
),
cut AS (
    SELECT IF(MAX(order_dt) < LAST_DAY(MAX(order_dt)), MONTH(MAX(order_dt)) - 1, MONTH(MAX(order_dt))) AS cm
    FROM vw_item_sales
),
y AS (
    SELECT m.yr, c.cm,
           COUNT(*)												AS months_in_data,
           SUM(m.orders)										AS orders,
           SUM(m.net_sales)										AS net_sales,
           SUM(m.gross_profit)									AS gross_profit,
           SUM(CASE WHEN m.mo <= c.cm THEN 1 ELSE 0 END)		AS ytd_months,
           SUM(CASE WHEN m.mo <= c.cm THEN m.net_sales ELSE 0 END)	AS ytd_sales
    FROM m CROSS JOIN cut c
    GROUP BY m.yr, c.cm
)
SELECT yr AS sales_year, months_in_data, orders, ROUND(net_sales, 0) AS net_sales,
       ROUND(gross_profit * 100 / NULLIF(net_sales, 0), 2) AS gross_margin_pct,
       CASE WHEN months_in_data = LAG(months_in_data) OVER w
            THEN ROUND((net_sales - LAG(net_sales) OVER w) * 100 / NULLIF(LAG(net_sales) OVER w, 0), 2) END AS yoy_full_year_pct,
       CONCAT('Jan-', cm) AS same_period, ROUND(ytd_sales, 0) AS same_period_sales,
       CASE WHEN ytd_months = LAG(ytd_months) OVER w
            THEN ROUND((ytd_sales - LAG(ytd_sales) OVER w) * 100 / NULLIF(LAG(ytd_sales) OVER w, 0), 2) END AS yoy_same_period_pct
FROM y
WINDOW w AS (ORDER BY yr)
ORDER BY yr;

-- 3b. 12 bulan terakhir + MoM (MoM hanya dihitung jika bulan sebelumnya benar-benar berurutan)
WITH m AS (
    SELECT YEAR(order_dt) * 12 + MONTH(order_dt) AS mi, DATE_FORMAT(order_dt, '%Y-%m') AS ym,
           COUNT(DISTINCT order_id) AS orders, SUM(units_net) AS net_units,
           SUM(net_sales_after_returns) AS net_sales, SUM(gross_profit) AS gross_profit,
           COUNT(DISTINCT CASE WHEN is_returned = 0 THEN order_id END) AS delivered_orders
    FROM vw_item_sales
    WHERE order_dt IS NOT NULL
    GROUP BY 1, 2
),
l AS (
    SELECT m.*, LAG(mi) OVER w AS prev_mi, LAG(orders) OVER w AS prev_orders,
           LAG(net_sales) OVER w AS prev_sales, LAG(gross_profit) OVER w AS prev_profit,
           LAG(gross_profit * 100.0 / NULLIF(net_sales, 0)) OVER w AS prev_margin
    FROM m
    WINDOW w AS (ORDER BY mi)
)
SELECT ym AS year_month_key, orders, net_units, ROUND(net_sales, 0) AS net_sales,
       ROUND(net_sales / NULLIF(delivered_orders, 0), 0) AS avg_order_value,
       ROUND(gross_profit * 100 / NULLIF(net_sales, 0), 2) AS gross_margin_pct,
       CASE WHEN mi - prev_mi = 1 THEN ROUND(gross_profit * 100.0 / NULLIF(net_sales, 0) - prev_margin, 2) END AS margin_change_points,
       CASE WHEN mi - prev_mi = 1 THEN ROUND((orders - prev_orders) * 100 / NULLIF(prev_orders, 0), 2) END     AS mom_orders_pct,
       CASE WHEN mi - prev_mi = 1 THEN ROUND((net_sales - prev_sales) * 100 / NULLIF(prev_sales, 0), 2) END    AS mom_sales_pct,
       CASE WHEN mi - prev_mi = 1 THEN ROUND((gross_profit - prev_profit) * 100 / NULLIF(prev_profit, 0), 2) END AS mom_profit_pct
FROM l
ORDER BY mi DESC
LIMIT 12;

-- 3c. Pola musiman: rata-rata penjualan tiap bulan kalender (indeks 1.00 = rata-rata)
WITH m AS (
    SELECT YEAR(order_dt) AS yr, MONTH(order_dt) AS mo, SUM(net_sales_after_returns) AS net_sales
    FROM vw_item_sales
    WHERE order_dt IS NOT NULL
    GROUP BY 1, 2
)
SELECT mo AS month_no, ELT(mo, 'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec') AS month_name,
       COUNT(*) AS years_covered, ROUND(AVG(net_sales), 0) AS avg_net_sales,
       ROUND(AVG(net_sales) / AVG(AVG(net_sales)) OVER (), 2) AS seasonality_index
FROM m
GROUP BY mo
ORDER BY mo;
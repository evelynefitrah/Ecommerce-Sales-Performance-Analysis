/* ==========================================================================
   4. PRODUCT ANALYSIS
   ========================================================================== */

-- 4a. Kesehatan katalog (satu baris)
SELECT (SELECT COUNT(*) FROM products)                       AS catalog_products,
       COUNT(*)                                              AS products_sold,
       (SELECT COUNT(*) FROM products) - COUNT(*)            AS never_sold,
       SUM(DATEDIFF(a.max_dt, v.last_sale_dt) >= 90)         AS not_sold_last_90d,
       SUM(v.gross_profit < 0)                               AS loss_making_products
FROM vw_product_base v
CROSS JOIN (SELECT MAX(order_dt) AS max_dt FROM vw_item_sales) a;

-- 4b. 10 produk terbaik dan 10 terburuk berdasarkan net sales setelah retur
WITH r AS (
    SELECT product_id, category, subcategory, net_units_sold, net_sales_after_returns, profit_margin, return_rate,
           net_sales_after_returns * 100.0 / SUM(net_sales_after_returns) OVER () AS share_pct,
           ROW_NUMBER() OVER (ORDER BY net_sales_after_returns DESC, product_id) AS rank_desc,
           ROW_NUMBER() OVER (ORDER BY net_sales_after_returns ASC,  product_id) AS rank_asc
    FROM vw_product_base
)
SELECT IF(rank_desc <= 10, 'Top 10', 'Bottom 10') AS ranking, product_id, category, subcategory,
       net_units_sold, ROUND(net_sales_after_returns, 0) AS net_sales, ROUND(share_pct, 2) AS share_pct,
       ROUND(profit_margin, 2) AS margin_pct, ROUND(return_rate, 2) AS return_rate_pct
FROM r
WHERE rank_desc <= 10 OR rank_asc <= 10
ORDER BY net_sales_after_returns DESC;

-- 4c. Klasifikasi ABC (A = 80% penjualan pertama, B = 15% berikutnya, C = 5% terakhir)
WITH r AS (
    SELECT product_id, net_sales_after_returns AS sales, gross_profit,
           SUM(net_sales_after_returns) OVER (ORDER BY net_sales_after_returns DESC, product_id
                                               ROWS UNBOUNDED PRECEDING) AS running_sales,
           SUM(net_sales_after_returns) OVER () AS total_sales
    FROM vw_product_base
),
t AS (
    SELECT *, CASE WHEN (running_sales - sales) * 100.0 / total_sales < 80 THEN 'A'
                   WHEN (running_sales - sales) * 100.0 / total_sales < 95 THEN 'B'
                   ELSE 'C' END AS abc_class
    FROM r
)
SELECT abc_class, COUNT(*) AS products,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_of_products,
       ROUND(SUM(sales), 0) AS net_sales,
       ROUND(SUM(sales) * 100.0 / SUM(SUM(sales)) OVER (), 2) AS pct_of_sales,
       ROUND(SUM(gross_profit) * 100.0 / NULLIF(SUM(sales), 0), 2) AS margin_pct
FROM t
GROUP BY abc_class
ORDER BY abc_class;

-- 4d. Segmentasi produk: penjualan x return rate (dibanding rata-rata)
WITH x AS (
    SELECT *, AVG(net_sales_after_returns) OVER () AS avg_sales, AVG(return_rate) OVER () AS avg_return
    FROM vw_product_base
)
SELECT CASE WHEN net_sales_after_returns >  avg_sales AND return_rate >  avg_return THEN '1. High sales / High returns'
            WHEN net_sales_after_returns >  avg_sales AND return_rate <= avg_return THEN '2. High sales / Low returns'
            WHEN net_sales_after_returns <= avg_sales AND return_rate >  avg_return THEN '3. Low sales / High returns'
            ELSE '4. Low sales / Low returns' END AS segment,
       COUNT(*) AS products, ROUND(SUM(net_sales_after_returns), 0) AS net_sales,
       ROUND(SUM(net_sales_after_returns) * 100.0 / SUM(SUM(net_sales_after_returns)) OVER (), 2) AS pct_of_sales,
       ROUND(AVG(return_rate), 2) AS avg_return_rate_pct
FROM x
GROUP BY segment
ORDER BY segment;

-- 4e. 10 produk dengan return rate tertinggi (hanya produk dengan volume di atas rata-rata)
SELECT product_id, category, subcategory, units_sold, units_returned,
       ROUND(return_rate, 2) AS return_rate_pct, ROUND(net_sales_after_returns, 0) AS net_sales
FROM vw_product_base
WHERE units_sold >= (SELECT AVG(units_sold) FROM vw_product_base)
ORDER BY return_rate DESC
LIMIT 10;
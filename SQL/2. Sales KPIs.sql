/* ==========================================================================
   SETUP: VIEW DASAR
   ========================================================================== */
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

/* ==========================================================================
   2. SALES KPIs
   ========================================================================== */
-- 2a. Ringkasan KPI (satu baris)
SELECT
    COUNT(DISTINCT order_id)									AS sales_orders,
    COUNT(DISTINCT customer_id)									AS purchasing_customers,
    SUM(quantity)												AS units_sold,
    SUM(units_returned)											AS units_returned,
    SUM(units_net)												AS net_units_sold,
    ROUND(SUM(gross), 0)										AS gross_sales,
    ROUND(SUM(discount_amount), 0)								AS discount_amount,
    ROUND(SUM(net_sales), 0)									AS net_sales_before_returns,
    ROUND(SUM(returned_sales), 0)								AS returned_sales,
    ROUND(SUM(net_sales_after_returns), 0)						AS net_sales_after_returns,
    ROUND(SUM(cogs_after_returns), 0)							AS cogs_after_returns,
    ROUND(SUM(gross_profit), 0)									AS gross_profit,
    ROUND(SUM(gross_profit) * 100 / NULLIF(SUM(net_sales_after_returns), 0), 2)	AS gross_margin_pct,
    ROUND(SUM(discount_amount) * 100 / NULLIF(SUM(gross), 0), 2)                AS discount_rate_pct,
    ROUND(SUM(returned_sales) * 100 / NULLIF(SUM(net_sales), 0), 2)             AS sales_return_rate_pct,
    ROUND(SUM(net_sales_after_returns)
          / NULLIF(COUNT(DISTINCT CASE WHEN is_returned = 0 THEN order_id END), 0), 0)	AS avg_order_value,
    ROUND(COUNT(DISTINCT order_id) / NULLIF(COUNT(DISTINCT customer_id), 0), 2)			AS orders_per_customer
FROM vw_item_sales;

-- 2b. Status order: berapa yang menjadi penjualan, berapa yang hilang (cancelled)
SELECT LOWER(TRIM(o.order_status))                       AS order_status,
	COUNT(DISTINCT o.order_id)                        AS orders,
	ROUND(COUNT(DISTINCT o.order_id) * 100.0
             / SUM(COUNT(DISTINCT o.order_id)) OVER (), 2) AS pct_of_orders,
	ROUND(SUM(oi.quantity * oi.unit_price_idr * (1 - COALESCE(oi.discount_rate, 0))), 0) AS order_value
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY 1
ORDER BY orders DESC;


-- 2c. Revenue leakage per metode pembayaran: nilai order batal (cancelled) dan diretur (returned)
SELECT * FROM (
    SELECT COALESCE(NULLIF(TRIM(o.payment_method), ''), 'Unknown') AS payment_method,
           COUNT(DISTINCT o.order_id) AS total_orders,
           COUNT(DISTINCT CASE WHEN LOWER(TRIM(o.order_status)) = 'cancelled' THEN o.order_id END) AS cancelled_orders,
           ROUND(COUNT(DISTINCT CASE WHEN LOWER(TRIM(o.order_status)) = 'cancelled' THEN o.order_id END) * 100.0
                 / COUNT(DISTINCT o.order_id), 2) AS cancel_rate_pct,
           COUNT(DISTINCT CASE WHEN LOWER(TRIM(o.order_status)) = 'returned' THEN o.order_id END) AS returned_orders,
           ROUND(COUNT(DISTINCT CASE WHEN LOWER(TRIM(o.order_status)) = 'returned' THEN o.order_id END) * 100.0
                 / COUNT(DISTINCT o.order_id), 2) AS return_rate_pct,
           ROUND(SUM(CASE WHEN LOWER(TRIM(o.order_status)) = 'cancelled'
                          THEN oi.quantity * oi.unit_price_idr * (1 - COALESCE(oi.discount_rate, 0)) ELSE 0 END), 0) AS cancelled_value,
           ROUND(SUM(CASE WHEN LOWER(TRIM(o.order_status)) = 'returned'
                          THEN oi.quantity * oi.unit_price_idr * (1 - COALESCE(oi.discount_rate, 0)) ELSE 0 END), 0)  AS returned_value
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    GROUP BY 1
) t
ORDER BY cancelled_value + returned_value DESC;



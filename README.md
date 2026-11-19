# E-Commerce Sales Analysis
## About the Project
This project explores an e-commerce dataset to understand sales performance, customer purchasing behavior, product performance, and business profitability.
The analysis was conducted using MySQL for data processing and exploration, followed by Power BI to present the main findings through an interactive dashboard.

## Tools Used
- MySQL 8.0 – Data profiling, data analysis, and KPI calculations.
- Power BI– Dashboard development and data visualization.

## Dataset
The dataset consists of five related tables:
- Customers – Customer details, including demographics, location, and membership information.
- Orders – Order dates, status, payment methods, sales channels, and shipping details.
- Order Items – Products purchased, quantities, selling prices, costs, and discount rates.
- Products – Product categories, subcategories, pricing, and product status.
- Returns – Return dates, reasons, and resolutions.

## Analysis
The SQL analysis covers eight areas:
1. Data Profiling  – Checking data quality, completeness, and consistency.
2. Sales KPIs – Reviewing sales, orders, discounts, returns, and profitability metrics.
3. Time Analysis – Examining monthly sales trends and growth.
4. Product Analysis – Identifying product performance.
5. Category Analysis – Comparing sales and profit across categories.
6. Customer Analysis – Understanding customer purchasing patterns.
7. Geography Analysis – Exploring sales distribution by region and city.
8. Profitability Analysis – Evaluating COGS, gross profit, and profit margin.

Each analysis is documented in the SQL files included in this repository.

## Power BI Dashboard
The dashboard brings together selected results from the SQL analysis, focusing on the metrics and visualizations most relevant to monitoring business performance.
Not every SQL analysis is presented as a separate dashboard visual. SQL is used for deeper exploration, while Power BI provides a concise overview of the main results.

## Calculation Notes
The analysis uses the following order status definitions:
- Delivered: included in realized sales and profitability.
- Returned: included in sales before returns, but excluded from realized sales after returns.
- Cancelled: excluded from sales performance calculations.

Key metrics include Net Sales, COGS, Gross Profit, Gross Margin, Average Order Value (AOV), and Sales Return Rate.

Returned sales are calculated from the net value of orders marked as returned. Actual refund amounts and item-level returned quantities are not available in the dataset.

## Repository Structure

```text
e-commerce-sales-analysis/
├── sql/
│   └── SQL analysis files
├── power-bi/
│   └── ecommerce-sales-dashboard.pbix
└── README.md
```

## Project Outcome

This project provided hands-on experience in working with relational datasets, writing SQL queries, calculating business metrics, and building an interactive Power BI dashboard to communicate the results.

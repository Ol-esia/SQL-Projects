--- SET PRIMARY KEYS

ALTER TABLE orders 
ADD PRIMARY KEY ("Row ID");

ALTER TABLE returns 
ADD PRIMARY KEY ("Order ID");

ALTER TABLE people 
ADD PRIMARY KEY ("Region");

--- SET FOREIGN KEYs

ALTER TABLE orders
ADD CONSTRAINT orders_people_fk
FOREIGN KEY ("Region")
REFERENCES people ("Region");

ALTER TABLE orders
ADD CONSTRAINT orders_returns_fk
FOREIGN KEY ("Order ID")
REFERENCES returns ("Order ID");

--- REPLACE commas

UPDATE orders 
SET
	"Sales" = replace("Sales", ',', '.'),
	"Profit" = replace("Profit", ',', '.'),
	"Discount" = replace("Discount", ',', '.');

--- CHANGE DATA TYPES (for "Order Date" and "Ship Date" to DATE data type and for "Sales", "Discount", "Profit" to NUMERIC data type)

ALTER TABLE orders
ALTER COLUMN "Order Date" TYPE date USING "Order Date"::date;

ALTER TABLE orders
ALTER COLUMN "Ship Date" TYPE date USING "Ship Date"::date;

ALTER TABLE orders
ALTER COLUMN "Sales" TYPE numeric USING "Sales"::numeric;

ALTER TABLE orders
ALTER COLUMN "Discount" TYPE numeric USING "Discount"::numeric;

ALTER TABLE orders
ALTER COLUMN "Profit" TYPE numeric USING "Profit"::numeric;

--- How many disticnt items across all the orders were ordered and how many orders were made? (ANSWER: 9994 order items across 5009 unique orders)

SELECT
	COUNT(*) AS items_ordered, 
	COUNT(DISTINCT "Order ID") num_of_orders
FROM orders

--- How many orders per customer? (ANSWER: Most of the orders (17) were made by Emily Phan (the customer with ID EP-13915))

SELECT 
	"Customer ID", 
	"Customer Name", 
	COUNT(DISTINCT "Order ID") AS num_of_orders
FROM orders
GROUP BY "Customer ID", "Customer Name"
ORDER BY COUNT(DISTINCT "Order ID") DESC

--- How many orders per state?

SELECT 
	"State", 
	COUNT(DISTINCT "Order ID") AS num_of_orders
FROM orders
GROUP BY "State"
ORDER BY COUNT(DISTINCT "Order ID") DESC


--- Key Performance Indicators

SELECT DISTINCT 
	DATE_PART('YEAR', "Order Date") AS year_of_order,
	DATE_PART('MONTH', "Order Date") AS month_of_order,
	SUM("Sales") AS total_sales,
	SUM("Profit") AS total_profit, 
	SUM("Quantity") AS total_quantity
FROM orders
GROUP BY 
	DATE_PART('YEAR', "Order Date"),
	DATE_PART('MONTH', "Order Date")
ORDER BY 1, 2

--- Forecasting Sales and Profit for 2018

WITH monthly_data AS (
	SELECT
		date_trunc('month', "Order Date") AS year_and_month,
		SUM("Sales") AS sales, 
		SUM("Profit") AS profit
	FROM orders
	GROUP BY date_trunc('month', "Order Date")
),


monthly_ranking AS (
SELECT
	year_and_month,
	sales, 
	profit,
	ROW_NUMBER() OVER (ORDER BY year_and_month) AS n,
	EXTRACT(MONTH FROM year_and_month)::int AS mo
FROM monthly_data
),

linear_regression AS (
SELECT 
	regr_slope(sales, n) AS slope_sales, 
	regr_intercept(sales, n) AS intersept_sales, 
	regr_slope(profit, n) AS slope_profit, 
	regr_intercept(profit, n) AS intersept_profit
FROM monthly_ranking
),

seasonality AS (
  SELECT mo,
         AVG(sales - (intersept_sales + slope_sales * n))  AS seasonal_sales,
         AVG(profit - (intersept_profit + slope_profit * n)) AS seasonal_profit
  FROM monthly_ranking, linear_regression
  GROUP BY mo
),

future AS (
  SELECT gen_ser::date AS month,
         ROW_NUMBER() OVER (ORDER BY gen_ser) + (SELECT MAX(n) FROM monthly_ranking) AS t,
         EXTRACT(MONTH FROM gen_ser)::int AS mo
  FROM generate_series(
         (SELECT (MAX(year_and_month) + interval '1 month') FROM monthly_ranking),
         (SELECT (MAX(year_and_month) + interval '12 months') FROM monthly_ranking),
         interval '1 month'
       ) AS gen_ser
)

SELECT
  f.month::date,
  (intersept_sales  + slope_sales  * f.t + COALESCE(s.seasonal_sales, 0))  AS forecast_sales,
  (intersept_profit + slope_profit * f.t + COALESCE(s.seasonal_profit, 0)) AS forecast_profit
FROM future f
CROSS JOIN linear_regression
LEFT JOIN seasonality s USING (mo)
ORDER BY f.month;

--- Sales per Category

SELECT 
	"Category", 
	sum("Profit") AS total_profit
FROM orders
GROUP BY "Category"

--- 3 most purchased items from each category

WITH product_summary AS (
	SELECT 
		"Category", 
		"Product Name",
		SUM("Quantity") AS items_sold
	FROM orders
	GROUP BY 
		"Category", 
		"Sub-Category",
		"Product Name"
	), 
	
ranking AS (
SELECT
		"Category", 
		"Product Name",
		items_sold,
		ROW_NUMBER() OVER(PARTITION BY "Category" ORDER BY items_sold DESC) AS category_rank
FROM product_summary)

SELECT *
FROM ranking
WHERE category_rank IN (1,2,3)

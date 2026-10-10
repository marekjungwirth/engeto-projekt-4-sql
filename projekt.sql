-- =====================================================================
-- Engeto SQL project: affordability of basic foods vs. average wages
-- Author: Marek Jungwirth
-- Database: PostgreSQL
-- Source tables are NOT modified; all transformations happen in the
-- newly created tables / queries below.
-- =====================================================================


-- =====================================================================
-- 1. PRIMARY TABLE: wages + food prices in Czechia (common years only)
-- =====================================================================
-- Granularity: one row = year x industry x food category.
-- Because wages and prices are joined on year only, every wage value is
-- repeated once per food category (and every price once per industry).
-- Analytical queries below therefore de-duplicate or aggregate first.
DROP TABLE IF EXISTS t_marek_jungwirth_project_SQL_primary_final;

CREATE TABLE t_marek_jungwirth_project_SQL_primary_final AS
WITH wages AS (
    SELECT
        cp.payroll_year AS year,
        cpib.name AS industry_name,
        AVG(cp.value) AS average_wage          -- average over quarters
    FROM czechia_payroll cp
    JOIN czechia_payroll_industry_branch cpib
        ON cp.industry_branch_code = cpib.code -- inner join drops rows without industry
    WHERE cp.value_type_code = '5958'          -- 5958 = average gross wage per employee
      AND cp.calculation_code = '200'          -- 200 = recalculated (FTE) figure
      AND cp.industry_branch_code IS NOT NULL  -- explicit for readability
    GROUP BY cp.payroll_year, cpib.name
),
prices AS (
    SELECT
        EXTRACT(YEAR FROM cp.date_from) AS year,
        cpc.name AS food_category,
        AVG(cp.value) AS average_price,        -- average over weeks and regions
        cpc.price_value,
        cpc.price_unit
    FROM czechia_price cp
    JOIN czechia_price_category cpc
        ON cp.category_code = cpc.code
    GROUP BY EXTRACT(YEAR FROM cp.date_from), cpc.name, cpc.price_value, cpc.price_unit
)
SELECT
    w.year,
    w.industry_name,
    w.average_wage,
    p.food_category,
    p.average_price,
    p.price_value,
    p.price_unit
FROM wages w
JOIN prices p
    ON w.year = p.year;                        -- keeps only years present in both sources


-- =====================================================================
-- 2. SECONDARY TABLE: GDP, GINI and population of European countries
--    for the same period as the primary table
-- =====================================================================
DROP TABLE IF EXISTS t_marek_jungwirth_project_SQL_secondary_final;

CREATE TABLE t_marek_jungwirth_project_SQL_secondary_final AS
SELECT
    c.country,
    e.year,
    e.gdp,
    e.gini,
    e.population
FROM countries c
JOIN economies e
    ON c.country = e.country
WHERE c.continent = 'Europe'
  AND e.year BETWEEN (SELECT MIN(year) FROM t_marek_jungwirth_project_SQL_primary_final)
                 AND (SELECT MAX(year) FROM t_marek_jungwirth_project_SQL_primary_final);


-- =====================================================================
-- DATA QUALITY CHECKS (supporting the "missing values" section of README)
-- =====================================================================

-- DQ1: how many years of data does each food category have?
-- (categories with fewer years distort the average price across categories)
SELECT
    food_category,
    MIN(year) AS first_year,
    MAX(year) AS last_year,
    COUNT(DISTINCT year) AS years_available
FROM t_marek_jungwirth_project_SQL_primary_final
GROUP BY food_category
ORDER BY years_available, food_category;

-- DQ2: how many years of data does each industry have?
SELECT
    industry_name,
    MIN(year) AS first_year,
    MAX(year) AS last_year,
    COUNT(DISTINCT year) AS years_available
FROM t_marek_jungwirth_project_SQL_primary_final
GROUP BY industry_name
ORDER BY years_available, industry_name;

-- DQ3: source rows that were excluded because of a missing industry code
SELECT COUNT(*) AS wage_rows_without_industry
FROM czechia_payroll
WHERE value_type_code = '5958'
  AND calculation_code = '200'
  AND industry_branch_code IS NULL;

-- DQ4: price rows without a region (check whether they can distort the average)
SELECT
    COUNT(*) FILTER (WHERE region_code IS NULL) AS price_rows_without_region,
    COUNT(*) AS price_rows_total
FROM czechia_price;

-- DQ5: completeness of the secondary table
-- (values are copied from the source as they are; missing values stay NULL)
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT country) AS countries,
    COUNT(*) FILTER (WHERE gdp IS NULL) AS rows_without_gdp,
    COUNT(*) FILTER (WHERE gini IS NULL) AS rows_without_gini,
    COUNT(*) FILTER (WHERE population IS NULL) AS rows_without_population
FROM t_marek_jungwirth_project_SQL_secondary_final;

-- DQ6: do price rows without a region (probably a national-level series)
-- change the annual average prices? Per category and year, the average over
-- ALL rows is compared with the average over regional rows only.
WITH category_year AS (
    SELECT
        category_code,
        EXTRACT(YEAR FROM date_from) AS year,
        AVG(value) AS avg_all_rows,
        AVG(value) FILTER (WHERE region_code IS NOT NULL) AS avg_regional_only,
        AVG(value) FILTER (WHERE region_code IS NULL) AS avg_no_region
    FROM czechia_price
    GROUP BY category_code, EXTRACT(YEAR FROM date_from)
)
SELECT
    COUNT(*) AS category_year_pairs,
    ROUND(AVG(ABS(avg_all_rows / avg_regional_only - 1) * 100)::numeric, 3) AS avg_abs_diff_pct,
    ROUND(MAX(ABS(avg_all_rows / avg_regional_only - 1) * 100)::numeric, 3) AS max_abs_diff_pct,
    ROUND(MAX(ABS(avg_no_region / avg_regional_only - 1) * 100)::numeric, 3) AS max_no_region_vs_regional_pct,
    (SELECT COUNT(DISTINCT region_code) FROM czechia_price) AS distinct_regions
FROM category_year;


-- =====================================================================
-- QUESTION 1: Do wages grow in all industries, or do some of them fall?
-- Output: every industry/year where the wage fell compared to the
-- previous year. (Covers only years present in the primary table.)
-- =====================================================================
WITH wage_growth AS (
    SELECT
        year,
        industry_name,
        average_wage,
        LAG(average_wage) OVER (PARTITION BY industry_name ORDER BY year) AS prev_year_wage
    FROM (
        SELECT DISTINCT year, industry_name, average_wage
        FROM t_marek_jungwirth_project_SQL_primary_final
    ) distinct_wages
)
SELECT
    industry_name,
    year,
    average_wage,
    prev_year_wage,
    ROUND(((average_wage - prev_year_wage) / prev_year_wage * 100)::numeric, 2) AS growth_percentage
FROM wage_growth
WHERE prev_year_wage IS NOT NULL
  AND average_wage < prev_year_wage
ORDER BY year, growth_percentage;


-- =====================================================================
-- QUESTION 2: How many litres of milk and kg of bread can be bought for
-- the average wage in the first and last comparable period?
-- Note: wage = monthly gross wage, simple (unweighted) average over
-- industries. affordable_amount is expressed in price_unit (kg / l).
-- =====================================================================
WITH first_last_year AS (
    SELECT MIN(year) AS min_year, MAX(year) AS max_year
    FROM t_marek_jungwirth_project_SQL_primary_final
)
SELECT
    p.year,
    p.food_category,
    p.price_value,
    p.price_unit,
    ROUND(AVG(p.average_wage)::numeric, 2) AS avg_overall_wage,
    ROUND(AVG(p.average_price)::numeric, 2) AS avg_food_price,
    FLOOR(AVG(p.average_wage) / AVG(p.average_price)) AS affordable_amount
FROM t_marek_jungwirth_project_SQL_primary_final p
JOIN first_last_year fl
    ON p.year IN (fl.min_year, fl.max_year)
WHERE p.food_category IN ('Mléko polotučné pasterované', 'Chléb konzumní kmínový')
GROUP BY p.year, p.food_category, p.price_value, p.price_unit
ORDER BY p.food_category, p.year;


-- =====================================================================
-- QUESTION 3: Which food category gets more expensive the slowest?
-- Top 3 are shown on purpose: a negative value means the category
-- actually became cheaper on average.
-- Only consecutive years are compared (guards against gaps in the data).
-- =====================================================================
WITH price_growth AS (
    SELECT
        year,
        food_category,
        average_price,
        LAG(average_price) OVER (PARTITION BY food_category ORDER BY year) AS prev_year_price,
        LAG(year) OVER (PARTITION BY food_category ORDER BY year) AS prev_year
    FROM (
        SELECT DISTINCT year, food_category, average_price
        FROM t_marek_jungwirth_project_SQL_primary_final
    ) distinct_prices
),
year_over_year AS (
    SELECT
        food_category,
        ROUND(((average_price - prev_year_price) / prev_year_price * 100)::numeric, 2) AS yoy_growth
    FROM price_growth
    WHERE prev_year_price IS NOT NULL
      AND prev_year = year - 1
)
SELECT
    food_category,
    ROUND(AVG(yoy_growth), 2) AS avg_yoy_growth
FROM year_over_year
GROUP BY food_category
ORDER BY avg_yoy_growth ASC
LIMIT 3;


-- =====================================================================
-- QUESTION 4: Is there a year in which food prices grew by significantly
-- more than wages (difference > 10 percentage points)?
-- Output: ALL years sorted by the difference, with a flag column, so the
-- answer (and the largest observed difference) is visible in the result.
-- =====================================================================
WITH avg_yearly_data AS (
    SELECT
        year,
        AVG(average_wage) AS avg_wage,
        AVG(average_price) AS avg_price
    FROM t_marek_jungwirth_project_SQL_primary_final
    GROUP BY year
),
growth_data AS (
    SELECT
        year,
        (avg_wage - LAG(avg_wage) OVER (ORDER BY year))
            / LAG(avg_wage) OVER (ORDER BY year) * 100 AS wage_growth,
        (avg_price - LAG(avg_price) OVER (ORDER BY year))
            / LAG(avg_price) OVER (ORDER BY year) * 100 AS price_growth
    FROM avg_yearly_data
)
SELECT
    year,
    ROUND(wage_growth::numeric, 2) AS wage_growth_pct,
    ROUND(price_growth::numeric, 2) AS price_growth_pct,
    ROUND((price_growth - wage_growth)::numeric, 2) AS difference_pct,
    (price_growth - wage_growth) > 10 AS exceeds_10_pp
FROM growth_data
WHERE wage_growth IS NOT NULL
  AND price_growth IS NOT NULL
ORDER BY difference_pct DESC;


-- ---------------------------------------------------------------------
-- 4b) Sensitivity check: composition effect of the wine category.
-- DQ1 showed that 'Jakostní víno bílé' has data only for 2015-2018, so
-- from 2015 on it enters the all-category price average and can distort
-- the 2015 growth rate. Compare growth with and without that category.
-- ---------------------------------------------------------------------
WITH yearly AS (
    SELECT
        year,
        AVG(average_price) AS avg_price_all,
        AVG(average_price) FILTER (WHERE food_category <> 'Jakostní víno bílé') AS avg_price_like_for_like
    FROM t_marek_jungwirth_project_SQL_primary_final
    GROUP BY year
)
SELECT
    year,
    ROUND(((avg_price_all - LAG(avg_price_all) OVER w)
        / LAG(avg_price_all) OVER w * 100)::numeric, 2) AS price_growth_all_categories_pct,
    ROUND(((avg_price_like_for_like - LAG(avg_price_like_for_like) OVER w)
        / LAG(avg_price_like_for_like) OVER w * 100)::numeric, 2) AS price_growth_like_for_like_pct
FROM yearly
WINDOW w AS (ORDER BY year)
ORDER BY year;




-- =====================================================================
-- QUESTION 5: Does GDP growth affect wage and food price growth in the
-- same year or in the following year?
-- Price growth is shown twice: for all categories and "like-for-like"
-- (without 'Jakostní víno bílé', which only exists from 2015; see DQ1/4b).
-- 5a) yearly growth rates incl. next-year wage / price growth
-- =====================================================================
WITH metrics AS (
    SELECT
        p.year,
        AVG(p.average_wage) AS avg_wage,
        AVG(p.average_price) AS avg_price,
        AVG(p.average_price) FILTER (WHERE p.food_category <> 'Jakostní víno bílé') AS avg_price_lfl,
        MAX(s.gdp) AS gdp
    FROM t_marek_jungwirth_project_SQL_primary_final p
    JOIN t_marek_jungwirth_project_SQL_secondary_final s
        ON p.year = s.year AND s.country = 'Czech Republic'
    GROUP BY p.year
),
growth AS (
    SELECT
        year,
        (gdp - LAG(gdp) OVER w) / LAG(gdp) OVER w * 100 AS gdp_growth,
        (avg_wage - LAG(avg_wage) OVER w) / LAG(avg_wage) OVER w * 100 AS wage_growth,
        (avg_price - LAG(avg_price) OVER w) / LAG(avg_price) OVER w * 100 AS price_growth,
        (avg_price_lfl - LAG(avg_price_lfl) OVER w) / LAG(avg_price_lfl) OVER w * 100 AS price_growth_lfl
    FROM metrics
    WINDOW w AS (ORDER BY year)
),
growth_with_next AS (
    SELECT
        year,
        gdp_growth,
        wage_growth,
        price_growth,
        price_growth_lfl,
        LEAD(wage_growth) OVER (ORDER BY year) AS wage_growth_next,
        LEAD(price_growth) OVER (ORDER BY year) AS price_growth_next,
        LEAD(price_growth_lfl) OVER (ORDER BY year) AS price_growth_lfl_next
    FROM growth
)
SELECT
    year,
    ROUND(gdp_growth::numeric, 2) AS gdp_growth_pct,
    ROUND(wage_growth::numeric, 2) AS wage_growth_pct,
    ROUND(price_growth::numeric, 2) AS price_growth_pct,
    ROUND(price_growth_lfl::numeric, 2) AS price_growth_lfl_pct,
    ROUND(wage_growth_next::numeric, 2) AS wage_growth_next_year_pct,
    ROUND(price_growth_next::numeric, 2) AS price_growth_next_year_pct,
    ROUND(price_growth_lfl_next::numeric, 2) AS price_growth_lfl_next_year_pct
FROM growth_with_next
WHERE gdp_growth IS NOT NULL
ORDER BY year;


-- 5b) Pearson correlation of GDP growth with wage / price growth
-- (same year and following year). Only ~11-12 observations, so treat the
-- numbers as indicative, not as statistical proof.
-- (The last CTE is named differently from 5a on purpose: DBeaver names
-- exported files after the table in FROM, and equal names overwrite.)
WITH metrics AS (
    SELECT
        p.year,
        AVG(p.average_wage) AS avg_wage,
        AVG(p.average_price) AS avg_price,
        AVG(p.average_price) FILTER (WHERE p.food_category <> 'Jakostní víno bílé') AS avg_price_lfl,
        MAX(s.gdp) AS gdp
    FROM t_marek_jungwirth_project_SQL_primary_final p
    JOIN t_marek_jungwirth_project_SQL_secondary_final s
        ON p.year = s.year AND s.country = 'Czech Republic'
    GROUP BY p.year
),
growth AS (
    SELECT
        year,
        (gdp - LAG(gdp) OVER w) / LAG(gdp) OVER w * 100 AS gdp_growth,
        (avg_wage - LAG(avg_wage) OVER w) / LAG(avg_wage) OVER w * 100 AS wage_growth,
        (avg_price - LAG(avg_price) OVER w) / LAG(avg_price) OVER w * 100 AS price_growth,
        (avg_price_lfl - LAG(avg_price_lfl) OVER w) / LAG(avg_price_lfl) OVER w * 100 AS price_growth_lfl
    FROM metrics
    WINDOW w AS (ORDER BY year)
),
correlation_input AS (
    SELECT
        year,
        gdp_growth,
        wage_growth,
        price_growth,
        price_growth_lfl,
        LEAD(wage_growth) OVER (ORDER BY year) AS wage_growth_next,
        LEAD(price_growth) OVER (ORDER BY year) AS price_growth_next,
        LEAD(price_growth_lfl) OVER (ORDER BY year) AS price_growth_lfl_next
    FROM growth
)
SELECT
    ROUND(CORR(gdp_growth, wage_growth)::numeric, 2) AS corr_gdp_wage_same_year,
    ROUND(CORR(gdp_growth, wage_growth_next)::numeric, 2) AS corr_gdp_wage_next_year,
    ROUND(CORR(gdp_growth, price_growth)::numeric, 2) AS corr_gdp_price_same_year,
    ROUND(CORR(gdp_growth, price_growth_next)::numeric, 2) AS corr_gdp_price_next_year,
    ROUND(CORR(gdp_growth, price_growth_lfl)::numeric, 2) AS corr_gdp_price_lfl_same_year,
    ROUND(CORR(gdp_growth, price_growth_lfl_next)::numeric, 2) AS corr_gdp_price_lfl_next_year
FROM correlation_input;

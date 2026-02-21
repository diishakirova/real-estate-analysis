* Проект «Анализ данных для агентства недвижимости»
 * Цель проекта: изучить рынок недвижимости Санкт-Петербурга и Ленинградской области, сезонность и время активности
 объявлений о продаже недвижимости.
 * Автор: Шакирова Динара Гумеровна
 * Дата: 07.08.2025

 
 --Задача 1. Время активности объявлений--
WITH
--с помощью перцентилей берем выбросы (анамально большие и анамалтно маленькие данные)
limits AS (
    SELECT
        PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY a.last_price) AS p01_price,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY a.last_price) AS p99_price,
        PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY f.total_area) AS p01_area,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY f.total_area) AS p99_area,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY f.rooms) AS p99_rooms,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY f.floors_total) AS p99_floors
    FROM real_estate.advertisement a
    JOIN real_estate.flats f ON a.id = f.id
    JOIN real_estate.type  t ON f.type_id = t.type_id
    WHERE t.type ='город'
),

--данные после проверок и отсечения выбросов
filtered_ids AS (
    SELECT a.id
    FROM real_estate.advertisement a
    JOIN real_estate.flats f ON a.id = f.id
    JOIN real_estate.type t ON f.type_id = t.type_id
    CROSS JOIN limits l
    WHERE t.type = 'город'
      AND a.last_price IS NOT NULL AND a.last_price > 0
      AND f.total_area IS NOT NULL AND f.total_area > 0
      AND f.rooms IS NOT NULL AND f.rooms > 0
      AND f.floors_total IS NOT NULL AND f.floors_total > 0
      AND a.last_price BETWEEN l.p01_price AND l.p99_price
      AND f.total_area BETWEEN l.p01_area AND l.p99_area
      AND f.rooms <= l.p99_rooms
      AND f.floors_total <= l.p99_floors
),
--данные по отфильтрованным объектам
base AS (
    SELECT
        a.id,
        a.days_exposition,
        a.last_price,
        f.total_area,
        f.rooms,
        f.balcony,         
        f.floors_total,
        c.city,
        CASE WHEN c.city = 'Санкт-Петербург' THEN 'Санкт-Петербург' ELSE 'ЛенОбл' END AS region
    FROM filtered_ids fi
    JOIN real_estate.advertisement a ON a.id = fi.id
    JOIN real_estate.flats f ON f.id = fi.id
    JOIN real_estate.city c ON f.city_id = c.city_id
),

--добавим категории по времени активности
categorized AS (
    SELECT
        region,
        CASE
            WHEN days_exposition IS NULL THEN 'активно'
            WHEN days_exposition <= 30 THEN 'до месяца'
            WHEN days_exposition <= 90 THEN 'до трёх месяцев'
            WHEN days_exposition <= 180 THEN 'до полугода'
            else 'более полугода'
        END AS activity_segment,
        (last_price / NULLIF(total_area, 0)) AS price_per_m2,
        total_area,
        rooms,
        balcony,
        floors_total
    FROM base
)

--финальные данные
SELECT
    region AS "Регион",
    activity_segment AS "Сегмент активности",
    COUNT(*) AS "Кол-во объявлений",
    --доля внутри рынка
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY region), 1) AS "Доля сегмента, %",
    ROUND(AVG(price_per_m2)) AS "Средняя стоимость кв. метра",
    ROUND(AVG(total_area)) AS "Средняя площадь",
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY rooms) AS "Медиана кол-ва комнат",
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY balcony)
        FILTER (WHERE balcony IS NOT NULL) AS "Медиана кол-ва балконов",
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY floors_total) AS "Медиана этажности"
FROM categorized
GROUP BY region, activity_segment
ORDER BY
    CASE region WHEN 'Санкт-Петербург' THEN 1 ELSE 2 END,
    CASE activity_segment
        WHEN 'активно' THEN 0
        WHEN 'до месяца' THEN 1
        WHEN 'до трёх месяцев' THEN 2
        WHEN 'до полугода' THEN 3
        ELSE 4
    END;


--Задача 2. Сезонность объявлений--

--с помощью перцентилей берем выбросы (анамально большие и анамалтно маленькие данные)
WITH limits AS (
    SELECT
        PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY a.last_price) AS p01_price,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY a.last_price) AS p99_price,
        PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY f.total_area) AS p01_area,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY f.total_area) AS p99_area,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY f.rooms)      AS p99_rooms,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY f.floors_total) AS p99_floors
    FROM real_estate.advertisement a
    JOIN real_estate.flats f ON a.id = f.id
    JOIN real_estate.type  t ON f.type_id = t.type_id
    WHERE t.type = 'город'
),
--фиьтрации обьявлений
filtered_ids AS (
    SELECT a.id
    FROM real_estate.advertisement a
    JOIN real_estate.flats f ON a.id = f.id
    JOIN real_estate.type  t ON f.type_id = t.type_id
    CROSS JOIN limits l
    WHERE t.type = 'город'
      AND a.first_day_exposition IS NOT NULL
      AND a.days_exposition IS NOT NULL
      AND a.last_price IS NOT NULL AND a.last_price > 0
      AND f.total_area IS NOT NULL AND f.total_area > 0
      AND f.rooms IS NOT NULL AND f.rooms > 0
      AND f.floors_total IS NOT NULL AND f.floors_total > 0
      AND a.last_price BETWEEN l.p01_price AND l.p99_price
      AND f.total_area BETWEEN l.p01_area  AND l.p99_area
      AND f.rooms <= l.p99_rooms
      AND f.floors_total <= l.p99_floors
),
--убираем не полные года
ads AS (
    SELECT 
        a.id,
        a.first_day_exposition,
        (a.first_day_exposition + a.days_exposition * INTERVAL '1 day')::date AS close_date,
        a.last_price,
        f.total_area
    FROM filtered_ids fi
    JOIN real_estate.advertisement a ON fi.id = a.id
    JOIN real_estate.flats f ON fi.id = f.id
    WHERE EXTRACT(YEAR FROM a.first_day_exposition) BETWEEN 2015 AND 2018
      AND EXTRACT(YEAR FROM (a.first_day_exposition + a.days_exposition * INTERVAL '1 day')) BETWEEN 2015 AND 2018
)

SELECT 
    pub.month_num,
    pub.month_name,
    pub.season,
    pub.num_published,
    clo.num_closed,
    ROUND(pub.avg_price_per_sqm::numeric, 2) AS avg_price_per_sqm_published,
    ROUND(pub.avg_area::numeric, 1) AS avg_area_published,
    ROUND(clo.avg_price_per_sqm::numeric, 2) AS avg_price_per_sqm_closed,
    ROUND(clo.avg_area::numeric, 1) AS avg_area_closed
FROM (
    SELECT
        EXTRACT(MONTH FROM first_day_exposition) AS month_num,
        TO_CHAR(first_day_exposition, 'Month') AS month_name,
        CASE 
            WHEN EXTRACT(MONTH FROM first_day_exposition) IN (12, 1, 2) THEN 'Зима'
            WHEN EXTRACT(MONTH FROM first_day_exposition) IN (3, 4, 5) THEN 'Весна'
            WHEN EXTRACT(MONTH FROM first_day_exposition) IN (6, 7, 8) THEN 'Лето'
            WHEN EXTRACT(MONTH FROM first_day_exposition) IN (9, 10, 11) THEN 'Осень'
        END AS season,
        COUNT(*) AS num_published,
        AVG(last_price / NULLIF(total_area, 0)) AS avg_price_per_sqm,
        AVG(total_area) AS avg_area
    FROM ads
    GROUP BY month_num, month_name, season
) pub
JOIN (
    SELECT
        EXTRACT(MONTH FROM close_date) AS month_num,
        TO_CHAR(close_date, 'Month') AS month_name,
        COUNT(*) AS num_closed,
        AVG(last_price / NULLIF(total_area, 0)) AS avg_price_per_sqm,
        AVG(total_area) AS avg_area
    FROM ads
    GROUP BY month_num, month_name
) clo USING (month_num, month_name)
ORDER BY month_num;


--Задача 3. Анализ рынка недвижимости Ленобласти--

--с помощью перцентилей берем выбросы (анамально большие и анамалтно маленькие данные)
WITH limits AS (
    SELECT
        PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY a.last_price) AS p01_price,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY a.last_price) AS p99_price,
        PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY f.total_area) AS p01_area,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY f.total_area) AS p99_area,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY f.rooms) AS p99_rooms,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY f.floors_total) AS p99_floors
    FROM real_estate.advertisement a
    JOIN real_estate.flats f ON a.id = f.id
    JOIN real_estate.city c ON f.city_id = c.city_id
    WHERE c.city <> 'Санкт-Петербург'
),

--фильтрации обьявлений
filtered_ids AS (
    SELECT a.id
    FROM real_estate.advertisement a
    JOIN real_estate.flats f ON a.id = f.id
    JOIN real_estate.city c ON f.city_id = c.city_id
    CROSS JOIN limits l
    WHERE c.city <> 'Санкт-Петербург'
      AND a.last_price IS NOT NULL AND a.last_price > 0
      AND f.total_area IS NOT NULL AND f.total_area > 0
      AND f.rooms IS NOT NULL AND f.rooms > 0
      AND f.floors_total IS NOT NULL AND f.floors_total > 0
      AND a.last_price BETWEEN l.p01_price AND l.p99_price
      AND f.total_area BETWEEN l.p01_area  AND l.p99_area
      AND f.rooms <= l.p99_rooms
      AND f.floors_total <= l.p99_floors
),

--данные только по Ленобласти
valid_data AS (
    SELECT
        a.id,
        a.last_price,
        a.days_exposition,
        f.total_area,
        f.city_id,
        c.city
    FROM filtered_ids fi
    JOIN real_estate.advertisement a ON fi.id = a.id
    JOIN real_estate.flats f ON fi.id = f.id
    JOIN real_estate.city c ON f.city_id = c.city_id
),

-- считаем количество, средние значения и долю снятых обьявлений
aggregated AS (
    SELECT
        city,
        COUNT(*) AS total_ads,  
        COUNT(days_exposition) AS removed_ads, 
        ROUND(AVG(days_exposition)::numeric, 1) AS avg_days_exposition, 
        ROUND(AVG((last_price / total_area)::numeric)) AS avg_price_per_m2, 
        ROUND(AVG(total_area)::numeric, 1) AS avg_area,
        ROUND(100.0 * COUNT(days_exposition) / COUNT(*)::numeric, 1) AS removed_share 
    FROM valid_data
    GROUP BY city
),

--фильтруем только крупные населенные пункты с >= 50 объявлений
filtered AS (
    SELECT *
    FROM aggregated
    WHERE total_ads >= 50
)

--выводим топ-15 по количеству объявлений
SELECT *
FROM filtered
ORDER BY total_ads DESC
LIMIT 15;
